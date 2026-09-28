channel: *Broadcast(Message),
searches: []Search = &.{},
cache: *Cache,

move_format: MoveFormat = .classical,
output_mode: OutputMode = .none,

pub const max_threads = 1024;

pub fn init(io: std.Io, gpa: std.mem.Allocator) !Engine {
    var self: Engine = .{
        .channel = try gpa.create(Broadcast(Message)),
        .cache = try gpa.create(Cache),
    };
    try self.cache.init(gpa);
    try self.launchSearches(io, gpa, 1);
    return self;
}

pub fn deinit(self: *Engine, io: std.Io, gpa: std.mem.Allocator) void {
    self.quitSearches(io, gpa);
    self.cache.deinit(gpa);
    gpa.destroy(self.cache);
    gpa.destroy(self.channel);
}

pub fn wait(self: *Engine, io: std.Io) void {
    const msg: Message = .ping;
    self.channel.broadcast(io, &msg);
}

pub fn newGame(self: *Engine, io: std.Io) void {
    const msg: Message = .new_game;
    self.channel.broadcast(io, &msg);
    self.cache.clear();
}

pub fn go(self: *Engine, io: std.Io, game: *Game, search_start: std.Io.Timestamp, limits: SearchLimit) void {
    const msg: Message = .{ .go = .{
        .game = game,
        .limits = limits,
        .search_start = search_start,
    } };
    self.channel.broadcast(io, &msg);
}

pub fn stop(self: *Engine, io: std.Io) void {
    for (self.searches) |*se| se.stopping.store(true, .monotonic);
    self.wait(io);
}

pub fn waitForTotalNodes(self: *Engine, io: std.Io) u64 {
    self.wait(io);
    var total_nodes: u64 = 0;
    for (self.searches) |*search| total_nodes += search.nodes.load(.monotonic);
    return total_nodes;
}

pub fn setOutputMode(self: *Engine, io: std.Io, output_mode: OutputMode) void {
    self.output_mode = output_mode;
    const msg: Message = .{ .output_mode = output_mode };
    self.channel.broadcast(io, &msg);
}

pub fn setMoveFormat(self: *Engine, io: std.Io, move_format: MoveFormat) void {
    self.move_format = move_format;
    const msg: Message = .{ .move_format = move_format };
    self.channel.broadcast(io, &msg);
}

pub fn setCacheSize(self: *Engine, io: std.Io, gpa: std.mem.Allocator, mb: usize) !void {
    self.wait(io);
    return self.cache.resize(gpa, mb);
}

pub fn setThreadCount(self: *Engine, io: std.Io, gpa: std.mem.Allocator, count: usize) !void {
    self.quitSearches(io, gpa);
    try self.launchSearches(io, gpa, count);
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
        limits: SearchLimit,
        search_start: std.Io.Timestamp,
    },
};

fn launchSearches(self: *Engine, io: std.Io, gpa: std.mem.Allocator, count: usize) !void {
    assert(self.searches.len == 0);

    self.channel.reset(@intCast(count));
    self.searches = try gpa.alloc(Search, count);
    for (self.searches, 0..) |*se, i|
        try se.launch(io, gpa, i, self.searches, self.cache, self.channel.createReceiver(), self.move_format, self.output_mode);
}

fn quitSearches(self: *Engine, io: std.Io, gpa: std.mem.Allocator) void {
    assert(self.searches.len > 0);

    const msg: Message = .quit;
    self.channel.broadcast(io, &msg);
    for (self.searches) |*se| se.thread.join();

    gpa.free(self.searches);
    self.searches = &.{};
}

const Engine = @This();
const std = @import("std");
const assert = std.debug.assert;
const thorn = @import("../thorn.zig");
const Broadcast = thorn.util.Broadcast;
const Cache = thorn.Cache;
const Game = thorn.Game;
const MoveFormat = thorn.MoveFormat;
const Search = thorn.Search;
