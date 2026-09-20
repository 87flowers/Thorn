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

fn threadMain(self: *Search) !void {
    while (true) {
        const msg = self.channel.wait(self.io);
        switch (msg.*) {
            .ping => self.channel.done(self.io),
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
                self.channel.done(self.io);
                try self.go(m.out);
            },
        }
    }
}

fn go(self: *Search, out: *std.Io.Writer) !void {
    self.nodes.store(1, .seq_cst);

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
