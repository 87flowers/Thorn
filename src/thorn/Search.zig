io: std.Io,
searches: []Search,
channel: Broadcast(Engine.Message).Receiver,
index: usize,
thread: std.Thread,

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
            .go => {
                self.channel.done(self.io);
                std.debug.print("go received by thread {}\n", .{self.index});
            },
        }
    }
}

const Search = @This();
const std = @import("std");
const thorn = @import("../thorn.zig");
const Broadcast = thorn.util.Broadcast;
const Engine = thorn.Engine;
