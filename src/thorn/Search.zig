pub const control = @import("./Search/control.zig");
pub const history = @import("./Search/history.zig");
pub const MoveSelector = @import("./Search/MoveSelector.zig");
pub const Stack = @import("./Search/Stack.zig");

io: std.Io,
searches: []Search,
cache: *Cache,
channel: Broadcast(Engine.Message).Receiver,
index: usize,
thread: std.Thread,

output_mode: Engine.OutputMode,
move_format: MoveFormat,

stopping: std.atomic.Value(bool),
nodes: std.atomic.Value(u64),

search_start: std.Io.Timestamp,
root_position: Position,

hash_stack: StaticVec(Hash, 103 + max_depth),
hash_waterline: usize,
stack: [max_depth + stack_offset + 3]Stack,

eval: Eval,

quiet_history: history.Quiet,

pub const max_depth = 240;

pub fn launch(
    self: *Search,
    io: std.Io,
    _: std.mem.Allocator,
    index: usize,
    searches: []Search,
    cache: *Cache,
    channel: Broadcast(Engine.Message).Receiver,
) !void {
    self.io = io;
    self.searches = searches;
    self.cache = cache;
    self.channel = channel;
    self.index = index;
    self.output_mode = .none;
    self.move_format = .frc;
    self.newGame();
    self.thread = try std.Thread.spawn(.{}, threadMain, .{self});
}

fn threadMain(self: *Search) !void {
    while (true) {
        const msg = self.channel.wait(self.io);
        switch (msg.*) {
            .ping => self.channel.done(self.io),
            .new_game => {
                self.newGame();
                self.channel.done(self.io);
            },
            .quit => {
                self.channel.done(self.io);
                return;
            },
            .output_mode => |output_mode| {
                self.output_mode = output_mode;
                self.channel.done(self.io);
            },
            .move_format => |move_format| {
                self.move_format = move_format;
                self.channel.done(self.io);
            },
            .go => |*m| {
                const out = m.out;

                self.search_start = m.search_start;
                self.root_position = m.game.position;
                self.hash_waterline = m.game.hash_stack.len;
                self.hash_stack.len = m.game.hash_stack.len;
                @memcpy(self.hash_stack.storage[0..self.hash_stack.len], m.game.hash_stack.storage[0..self.hash_stack.len]);

                self.nodes.store(0, .monotonic);
                self.stopping.store(false, .monotonic);

                if (self.index == 0) {
                    switch (control.Has{
                        .time = m.limits.hasTime(),
                        .depth = m.limits.hasDepth(),
                        .nodes = m.limits.hasNodes(),
                    }) {
                        inline else => |has| {
                            var ctrl: control.Control(has) = undefined;
                            if (has.time) {
                                const time = calcTimeLimit(&m.limits);
                                ctrl.time_limit.soft = time.soft;
                                ctrl.time_limit.hard = time.hard;
                            }
                            if (has.depth) {
                                ctrl.depth_limit.target_depth = m.limits.depth.?;
                            }
                            if (has.nodes) {
                                ctrl.nodes_limit.soft = m.limits.soft_nodes;
                                ctrl.nodes_limit.hard = m.limits.hard_nodes;
                            }
                            self.channel.done(self.io);
                            try self.go(out, &ctrl);
                        },
                    }
                } else {
                    self.channel.done(self.io);
                    try self.go(out, &control.none);
                }
            },
        }
    }
}

fn calcTimeLimit(limits: *const Engine.SearchLimit) struct { soft: i64, hard: i64 } {
    const margin_ms = 100;

    const move_factor: f64 = if (limits.movestogo) |movestogo| 1.0 / @as(f64, @floatFromInt(movestogo)) else 0.0625;
    const base: f64 = @floatFromInt(limits.base_ms orelse 0);
    const inc: f64 = @floatFromInt(limits.inc_ms orelse 0);

    const hard_limit: i64 = @trunc(base * move_factor * 3.0 + inc * 0.8 - margin_ms);
    const soft_limit: i64 = @trunc(base * move_factor + inc * 0.8 - margin_ms);

    if (limits.movetime_ms) |movetime| {
        const mt: i64 = @intCast(movetime);
        if (limits.base_ms == null and limits.inc_ms == null) return .{ .soft = mt, .hard = mt };
        return .{ .soft = @min(mt, soft_limit), .hard = @min(mt, hard_limit) };
    }

    return .{ .soft = soft_limit, .hard = hard_limit };
}

fn newGame(self: *Search) void {
    self.quiet_history.reset();
}

fn go(self: *Search, out: *std.Io.Writer, ctrl: anytype) !void {
    self.stack = @splat(.{});

    var last_pv: Line = .{};
    var last_score: Score = score.none;
    var last_depth: i32 = -1;

    self.ss(0).position = self.root_position;
    self.eval.reset(&self.root_position);

    var depth: i32 = 1;
    while (depth < max_depth) : (depth += 1) {
        const s = self.searchRoot(ctrl, -score.infinity, score.infinity, @intCast(depth)) catch break;

        if (self.stopping.load(.monotonic)) break;

        last_pv.copyFrom(&self.ss(0).pv);
        last_score = s;
        last_depth = depth;

        if (self.index == 0 and ctrl.checkSoftTermination(self, depth)) break;
        if (self.index == 0) try self.printInfoLine(out, last_depth, last_score, &last_pv);
    }

    switch (self.output_mode) {
        .uci => {
            try self.printInfoLine(out, last_depth, last_score, &last_pv);
            try out.print("bestmove {f}\n", .{last_pv.storage[0].toString(self.move_format)});
            try out.flush();
        },
        .none => {},
    }
}

fn printInfoLine(self: *Search, out: *std.Io.Writer, depth: i32, s: Score, pv: *const Line) !void {
    if (self.output_mode == .none) return;

    const elapsed = self.search_start.untilNow(self.io, .awake).toMilliseconds();
    const nodes = self.nodes.load(.monotonic);
    const nps = nodes * 1000 / @as(u64, @intCast(@max(1, elapsed)));

    try out.print("info", .{});
    try out.print(" depth {}", .{depth});
    try out.print(" nodes {}", .{nodes});
    if (score.distanceToMate(s)) |dtm| {
        try out.print(" score mate {}", .{dtm});
    } else {
        try out.print(" score cp {}", .{s});
    }
    try out.print(" time {}", .{elapsed});
    try out.print(" nps {}", .{nps});
    try out.print(" pv", .{});
    for (0..pv.len) |i| try out.print(" {f}", .{pv.storage[i].toString(self.move_format)});
    try out.print("\n", .{});
    try out.flush();
}

fn searchRoot(self: *Search, ctrl: anytype, alpha: Score, beta: Score, depth: i32) Abort!Score {
    const ply = 0;

    _ = self.nodes.rmw(.Add, 1, .monotonic);
    self.ss(ply).pv.clear();

    const cache_entry = self.cache.lookup(self.hash_stack.back(), ply);

    return self.searchBody(.pv, ctrl, cache_entry, alpha, beta, ply, depth);
}

fn search(self: *Search, comptime expected: NodeKind, ctrl: anytype, parent_move: Move, alpha: Score, beta: Score, ply: i32, depth: i32) Abort!Score {
    if (depth <= 0) return self.qsearch(expected, ctrl, parent_move, alpha, beta, ply);

    const parent_position: *const Position = &self.ss(ply - 1).position;

    _ = self.nodes.rmw(.Add, 1, .monotonic);
    self.ss(ply).pv.clear();

    self.hash_stack.push(self.hash_stack.back().move(parent_position, parent_move));
    defer self.hash_stack.pop();

    if (ctrl.checkHardTermination(self) or self.stopping.load(.monotonic)) {
        for (self.searches) |*s| s.stopping.store(true, .monotonic);
        return Abort.Abort;
    }

    const cache_entry = self.cache.lookup(self.hash_stack.back(), ply);
    if (cache_entry) |lr| if (expected != .pv and lr.depth >= depth and switch (lr.kind) {
        .none => false,
        .cut => lr.score >= beta,
        .pv => true,
        .all => lr.score <= alpha,
    }) {
        return lr.score;
    };

    self.eval.push(parent_position, parent_move);
    defer self.eval.pop();

    if (ply >= max_depth) return self.eval.evaluation();

    const new_fifty_move_clock: u16 = if (parent_move.isCapture() or parent_position.ptypeAt(parent_move.from()) == .p)
        0
    else
        parent_position.fifty_move_clock + 1;
    const new_ply_since_null = if (parent_move.isSome()) parent_position.ply_since_null + 1 else 0;
    if (new_fifty_move_clock >= 100 or self.isThreeFoldDraw(@min(new_ply_since_null, new_fifty_move_clock))) return score.draw;

    self.ss(ply - 1).position.move(&self.ss(ply).position, parent_move);

    return self.searchBody(expected, ctrl, cache_entry, alpha, beta, ply, depth);
}

fn searchBody(self: *Search, comptime expected: NodeKind, ctrl: anytype, cache_entry: ?Cache.Result, initial_alpha: Score, beta: Score, ply: i32, depth: i32) Abort!Score {
    const position: *const Position = &self.ss(ply).position;
    var alpha = initial_alpha;

    const hint_move: Move = if (cache_entry) |lr| lr.move else .none;

    var moves: MoveSelector = .new(self, &self.ss(ply).position, hint_move);

    var fail_low_quiets: MoveList = .new();

    var searched_moves: usize = 0;
    var best_score: Score = score.none;
    var best_move: Move = .none;
    var actual_kind: NodeKind = .all;
    while (moves.next()) |m| {
        searched_moves += 1;

        var s: Score = undefined;
        if (expected != .pv or searched_moves > 1)
            s = -try self.search(expected.next(), ctrl, m, -alpha - 1, -alpha, ply + 1, depth - 1);
        if (expected == .pv and (searched_moves == 1 or s > alpha))
            s = -try self.search(.pv, ctrl, m, -beta, -alpha, ply + 1, depth - 1);

        if (s > best_score) {
            best_score = s;

            if (s > alpha) {
                if (expected == .pv) self.ss(ply).pv.writeLine(m, &self.ss(ply + 1).pv);
                alpha = s;
                best_move = m;
                actual_kind = .pv;
            }

            if (s >= beta) {
                actual_kind = .cut;
                break;
            }
        }

        if (m != best_move and m.isQuiet()) fail_low_quiets.push(m);
    }

    if (best_score == score.none) {
        return if (position.checkers().isEmpty()) 0 else score.matedIn(ply);
    }

    if (best_move.isSome()) {
        const stm = position.sideToMove();

        const quiet_bonus = 150 * depth - 75;
        const quiet_malus = 75 * depth - 30;

        if (best_move.isQuiet()) {
            self.quiet_history.update(position, stm, best_move, quiet_bonus);
            for (fail_low_quiets.constSlice()) |m| self.quiet_history.update(position, stm, m, -quiet_malus);
        }
    }

    self.cache.update(self.hash_stack.back(), ply, .{
        .depth = depth,
        .kind = actual_kind,
        .score = best_score,
        .move = best_move,
    });

    return best_score;
}

fn qsearch(self: *Search, comptime leaf_expected: NodeKind, ctrl: anytype, parent_move: Move, alpha: Score, beta: Score, ply: i32) Abort!Score {
    const parent_position: *const Position = &self.ss(ply - 1).position;

    _ = self.nodes.rmw(.Add, 1, .monotonic);
    self.ss(ply).pv.clear();

    self.hash_stack.push(self.hash_stack.back().move(parent_position, parent_move));
    defer self.hash_stack.pop();

    if (ctrl.checkHardTermination(self) or self.stopping.load(.monotonic)) {
        for (self.searches) |*s| s.stopping.store(true, .monotonic);
        return Abort.Abort;
    }

    self.eval.push(parent_position, parent_move);
    defer self.eval.pop();

    // Standpat (Part 1)
    const static_eval = self.eval.evaluation();
    if (static_eval >= beta) return static_eval;

    self.ss(ply - 1).position.move(&self.ss(ply).position, parent_move);

    return self.qsearchBody(leaf_expected, ctrl, alpha, beta, ply);
}

fn qsearchBody(self: *Search, comptime leaf_expected: NodeKind, ctrl: anytype, initial_alpha: Score, beta: Score, ply: i32) Abort!Score {
    var alpha = initial_alpha;

    var moves: MoveSelector = .new(self, &self.ss(ply).position, .none);
    moves.skipQuiet();

    var searched_moves: usize = 0;
    var best_score: Score = self.eval.evaluation();

    // Standpat (Part 2)
    alpha = @max(alpha, best_score);

    while (moves.next()) |m| {
        searched_moves += 1;

        const s = -try self.qsearch(leaf_expected, ctrl, m, -beta, -alpha, ply + 1);

        if (s > best_score) {
            best_score = s;

            if (s > alpha) {
                if (leaf_expected == .pv) self.ss(ply).pv.writeLine(m, &self.ss(ply + 1).pv);
                alpha = s;
            }

            if (s >= beta) break;
        }
    }

    return best_score;
}

fn isThreeFoldDraw(self: *Search, end: usize) bool {
    const height = self.hash_stack.len - 1;
    const current_hash = self.hash_stack.storage[height];

    var clones: usize = 0;
    var i: usize = 4;
    while (i <= end) : (i += 2) {
        const h = self.hash_stack.storage[height - i];
        if (h == current_hash) {
            const clone_limit: usize = if ((height - i) < self.hash_waterline) 2 else 1;
            clones += 1;
            if (clones >= clone_limit) return true;
        }
    }
    return false;
}

fn ss(self: *Search, ply: i32) *Stack {
    return &self.stack[@intCast(ply + stack_offset)];
}

const stack_offset = 7;

const Abort = error{Abort};

const Search = @This();
const std = @import("std");
const thorn = @import("../thorn.zig");
const score = thorn.score;
const Broadcast = thorn.util.Broadcast;
const Cache = thorn.Cache;
const Color = thorn.Color;
const Engine = thorn.Engine;
const Eval = thorn.Eval;
const Hash = thorn.Hash;
const Line = thorn.Line;
const Move = thorn.Move;
const MoveFormat = thorn.MoveFormat;
const MoveList = thorn.MoveList;
const NodeKind = thorn.NodeKind;
const Position = thorn.Position;
const Score = thorn.score.Score;
const StaticVec = thorn.util.StaticVec;
