channel: *Broadcast(Message),
searches: []Search,

pub fn init(io: std.Io, gpa: std.mem.Allocator) !Engine {
    var self: Engine = .{
        .channel = try gpa.create(Broadcast(Message)),
        .searches = try gpa.alloc(Search, 1),
    };
    self.channel.reset(1);
    for (self.searches, 0..) |*search, i|
        try search.launch(io, gpa, i, self.searches, self.channel.createReceiver());
    return self;
}

pub fn deinit(self: *Engine, io: std.Io, gpa: std.mem.Allocator) void {
    self.quitSearches(io);
    gpa.free(self.searches);
    gpa.destroy(self.channel);
}

pub fn wait(self: *Engine, io: std.Io) void {
    const msg: Message = .ping;
    self.channel.broadcast(io, &msg);
}

pub fn go(self: *Engine, io: std.Io, out: *std.Io.Writer, game: *Game) void {
    const msg: Message = .{ .go = .{
        .game = game,
        .out = out,
    } };
    self.channel.broadcast(io, &msg);
}

pub fn setOutputMode(self: *Engine, io: std.Io, output_mode: OutputMode) void {
    const msg: Message = .{ .output_mode = output_mode };
    self.channel.broadcast(io, &msg);
}

pub fn setMoveFormat(self: *Engine, io: std.Io, move_format: MoveFormat) void {
    const msg: Message = .{ .move_format = move_format };
    self.channel.broadcast(io, &msg);
}

pub const OutputMode = enum {
    none,
    uci,
};

pub const MessageKind = enum {
    ping,
    quit,
    output_mode,
    move_format,
    go,
};

pub const Message = union(MessageKind) {
    ping: void,
    quit: void,
    output_mode: OutputMode,
    move_format: MoveFormat,
    go: struct {
        game: *Game,
        out: *std.Io.Writer,
    },
};

fn quitSearches(self: *Engine, io: std.Io) void {
    const msg: Message = .quit;
    self.channel.broadcast(io, &msg);
    for (self.searches) |*search| search.thread.join();
}

const Engine = @This();
const std = @import("std");
const thorn = @import("../thorn.zig");
const Broadcast = thorn.util.Broadcast;
const Game = thorn.Game;
const MoveFormat = thorn.MoveFormat;
const Search = thorn.Search;
