pub const control = @import("./Search/control.zig");

io: std.Io,
searches: []Search,
channel: Broadcast(Engine.Message).Receiver,
index: usize,
thread: std.Thread,

output_mode: Engine.OutputMode,
move_format: MoveFormat,

nodes: std.atomic.Value(u64),

root_position: Position,

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

pub const Abort = error{Abort};

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
                self.root_position = m.game.position;
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

    const move_factor: f64 = if (limits.movestogo) |movestogo| 1.0 / @as(f64, @floatFromInt(movestogo)) else 0.625;
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

fn go(self: *Search, out: *std.Io.Writer, _: anytype) !void {
    self.nodes.store(0, .seq_cst);

    const rng_source: std.Random.IoSource = .{ .io = self.io };
    const rng = rng_source.interface();

    var moves: MoveList = .new();
    movegen.all(&moves, &self.root_position);

    const index = rng.uintLessThan(usize, moves.len);
    const m = moves.storage[index];

    switch (self.output_mode) {
        .uci => {
            try out.print("info depth 0 nodes 0 score cp 0 pv {f}\n", .{m.toString(self.move_format)});
            try out.print("bestmove {f}\n", .{m.toString(self.move_format)});
            try out.flush();
        },
        .none => {},
    }
}

const Search = @This();
const std = @import("std");
const thorn = @import("../thorn.zig");
const movegen = thorn.movegen;
const Broadcast = thorn.util.Broadcast;
const Engine = thorn.Engine;
const MoveFormat = thorn.MoveFormat;
const MoveList = thorn.MoveList;
const Position = thorn.Position;
