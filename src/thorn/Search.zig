io: std.Io,
searches: []Search,
channel: Broadcast(Engine.Message).Receiver,
index: usize,
thread: std.Thread,

output_mode: Engine.OutputMode,
move_format: MoveFormat,

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

fn threadMain(self: *Search) void {
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
                std.debug.print("go received by thread {}\n", .{self.index});
                std.debug.print("position: {f}\n", .{m.game.position});
                self.channel.done(self.io);
            },
        }
    }
}

const Search = @This();
const std = @import("std");
const thorn = @import("../thorn.zig");
const Broadcast = thorn.util.Broadcast;
const Engine = thorn.Engine;
const MoveFormat = thorn.MoveFormat;
