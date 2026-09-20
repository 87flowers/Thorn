pub const control = @import("./Search/control.zig");
pub const Stack = @import("./Search/Stack.zig");

io: std.Io,
searches: []Search,
channel: Broadcast(Engine.Message).Receiver,
index: usize,
thread: std.Thread,

output_mode: Engine.OutputMode,
move_format: MoveFormat,

stopping: std.atomic.Value(bool),
nodes: std.atomic.Value(u64),

search_start: std.Io.Timestamp,
root_position: Position,
stack: [max_depth + stack_offset + 3]Stack,

pub fn launch(
    self: *Search,
    io: std.Io,
    _: std.mem.Allocator,
    index: usize,
    searches: []Search,
    channel: Broadcast(Engine.Message).Receiver,
) !void {
    self.io = io;
    self.searches = searches;
    self.channel = channel;
    self.index = index;
    self.thread = try std.Thread.spawn(.{}, threadMain, .{self});
    self.output_mode = .none;
    self.move_format = .frc;
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
                self.search_start = m.search_start;
                self.root_position = m.game.position;
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
                                ctrl.depth_limit.target_depth = m.limits.depth orelse unreachable;
                            }
                            if (has.nodes) {
                                ctrl.nodes_limit.soft = m.limits.soft_nodes;
                                ctrl.nodes_limit.hard = m.limits.hard_nodes;
                            }
                            self.channel.done(self.io);
                            try self.go(m.out, &ctrl);
                        },
                    }
                } else {
                    self.channel.done(self.io);
                    try self.go(m.out, &control.none);
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

fn newGame(_: *Search) void {}

fn go(self: *Search, out: *std.Io.Writer, ctrl: anytype) !void {
    self.stack = @splat(.{});

    var last_pv: Line = .{};
    var last_score: Score = score.none;
    var last_depth: i32 = -1;

    self.ss(0).position = self.root_position;

    var depth: i32 = 1;
    while (depth < max_depth) : (depth += 1) {
        const s = self.searchRoot(ctrl, @intCast(depth)) catch break;

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

fn searchRoot(self: *Search, ctrl: anytype, depth: i32) Abort!Score {
    _ = self.nodes.rmw(.Add, 1, .monotonic);

    return self.searchBody(ctrl, 0, depth);
}

fn search(self: *Search, ctrl: anytype, parent_move: Move, ply: i32, depth: i32) Abort!Score {
    _ = self.nodes.rmw(.Add, 1, .monotonic);

    if (ctrl.checkHardTermination(self) or self.stopping.load(.monotonic)) {
        for (self.searches) |*s| s.stopping.store(true, .monotonic);
        return Abort.Abort;
    }

    if (depth <= 0 or ply >= max_depth) {
        self.ss(ply - 1).position.move(&self.ss(ply).position, parent_move);
        return self.evaluate(ply);
    }

    self.ss(ply - 1).position.move(&self.ss(ply).position, parent_move);

    return self.searchBody(ctrl, ply, depth);
}

fn searchBody(self: *Search, ctrl: anytype, ply: i32, depth: i32) Abort!Score {
    var moves: MoveList = .new();
    movegen.all(&moves, &self.ss(ply).position);

    var best_score: Score = score.none;
    for (moves.constSlice()) |m| {
        const s = -try self.search(ctrl, m, ply + 1, depth - 1);

        if (s > best_score) {
            best_score = s;
            self.ss(ply).pv.writeLine(m, &self.ss(ply + 1).pv);
        }
    }

    if (best_score == score.none) {
        return if (self.ss(ply).position.checkers().isEmpty()) 0 else score.matedIn(ply);
    }
    return best_score;
}

fn evaluate(self: *Search, ply: i32) Score {
    const position: *const Position = &self.ss(ply).position;
    return switch (position.sideToMove()) {
        .white => self.evaluateSide(ply, .white) - self.evaluateSide(ply, .black),
        .black => self.evaluateSide(ply, .black) - self.evaluateSide(ply, .white),
    };
}

fn evaluateSide(self: *Search, ply: i32, color: Color) Score {
    const position: *const Position = &self.ss(ply).position;
    var eval: Score = 0;
    eval += position.coloredPtypeSet(color, .p).popcount() * 100;
    eval += position.coloredPtypeSet(color, .n).popcount() * 300;
    eval += position.coloredPtypeSet(color, .b).popcount() * 300;
    eval += position.coloredPtypeSet(color, .r).popcount() * 500;
    eval += position.coloredPtypeSet(color, .q).popcount() * 900;
    return eval;
}

fn ss(self: *Search, ply: i32) *Stack {
    return &self.stack[@intCast(ply + stack_offset)];
}

const max_depth = 240;
const stack_offset = 7;

const Abort = error{Abort};

const Search = @This();
const std = @import("std");
const thorn = @import("../thorn.zig");
const movegen = thorn.movegen;
const score = thorn.score;
const Broadcast = thorn.util.Broadcast;
const Color = thorn.Color;
const Engine = thorn.Engine;
const Line = thorn.Line;
const Move = thorn.Move;
const MoveFormat = thorn.MoveFormat;
const MoveList = thorn.MoveList;
const Position = thorn.Position;
const Score = thorn.score.Score;
