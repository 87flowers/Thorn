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

pub fn newGame(self: *Engine, io: std.Io) void {
    const msg: Message = .new_game;
    self.channel.broadcast(io, &msg);
}

pub fn go(self: *Engine, io: std.Io, out: *std.Io.Writer, game: *Game, search_start: std.Io.Timestamp, limits: SearchLimit) void {
    const msg: Message = .{ .go = .{
        .game = game,
        .out = out,
        .limits = limits,
        .search_start = search_start,
    } };
    self.channel.broadcast(io, &msg);
}

pub fn waitForTotalNodes(self: *Engine, io: std.Io) u64 {
    self.wait(io);
    var total_nodes: u64 = 0;
    for (self.searches) |*search| total_nodes += search.nodes.load(.monotonic);
    return total_nodes;
}

pub fn setOutputMode(self: *Engine, io: std.Io, output_mode: OutputMode) void {
    const msg: Message = .{ .output_mode = output_mode };
    self.channel.broadcast(io, &msg);
}

pub fn setMoveFormat(self: *Engine, io: std.Io, move_format: MoveFormat) void {
    const msg: Message = .{ .move_format = move_format };
    self.channel.broadcast(io, &msg);
}

pub const SearchLimit = struct {
    base_ms: ?u64 = null,
    inc_ms: ?u64 = null,
    movetime_ms: ?u64 = null,
    movestogo: ?u64 = null,
    depth: ?i32 = null,
    hard_nodes: ?u64 = null,
    soft_nodes: ?u64 = null,

    pub fn hasTime(self: *const SearchLimit) bool {
        return self.base_ms != null or self.inc_ms != null or self.movetime_ms != null;
    }

    pub fn hasDepth(self: *const SearchLimit) bool {
        return self.depth != null;
    }

    pub fn hasNodes(self: *const SearchLimit) bool {
        return self.hard_nodes != null or self.soft_nodes != null;
    }
};

pub const OutputMode = enum {
    none,
    uci,
};

pub const MessageKind = enum {
    ping,
    new_game,
    quit,
    output_mode,
    move_format,
    go,
};

pub const Message = union(MessageKind) {
    ping: void,
    new_game: void,
    quit: void,
    output_mode: OutputMode,
    move_format: MoveFormat,
    go: struct {
        game: *Game,
        out: *std.Io.Writer,
        limits: SearchLimit,
        search_start: std.Io.Timestamp,
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
