pub const bench = @import("cmd/bench.zig");
pub const display = @import("cmd/display.zig");
pub const perft = @import("cmd/perft.zig");

pub const ShouldQuit = enum {
    next,
    quit,
};

pub fn processLine(
    io: std.Io,
    _: std.mem.Allocator,
    out: *std.Io.Writer,
    engine: *Engine,
    game: *Game,
    line: []const u8,
) !ShouldQuit {
    var it = std.mem.tokenizeAny(u8, line, " \t\r\n");
    const cmd = it.next() orelse return .next;
    if (std.ascii.eqlIgnoreCase(cmd, "position")) {
        const pos_type = it.next() orelse return .next;
        if (std.mem.eql(u8, pos_type, "startpos")) {
            game.setPosition(.startpos);
        } else if (std.mem.eql(u8, pos_type, "kiwipete")) {
            game.setPosition(.kiwipete);
        } else if (std.mem.eql(u8, pos_type, "fen")) {
            const board_str = it.next() orelse "";
            const color = it.next() orelse "";
            const castling = it.next() orelse "";
            const enpassant = it.next() orelse "";
            const no_capture_clock = it.next() orelse "";
            const turn = it.next() orelse "";
            game.setPosition(Position.parseParts(board_str, color, castling, enpassant, no_capture_clock, turn) catch return .next);
        } else {
            return .next;
        }

        if (std.ascii.eqlIgnoreCase(it.next() orelse "", "moves")) {
            while (it.next()) |move_str| {
                const m = Move.parse(move_str, &game.position) catch break;
                game.move(m);
            }
        }
    } else if (std.ascii.eqlIgnoreCase(cmd, "go")) {
        engine.go(io, out, game);
    } else if (std.ascii.eqlIgnoreCase(cmd, "uci")) {
        try out.print(
            \\id name Thorn 0.0
            \\id author 87 (87flowers.com)
            \\uciok
            \\
        , .{});
        try out.flush();
    } else if (std.ascii.eqlIgnoreCase(cmd, "isready")) {
        try out.print("readyok\n", .{});
        try out.flush();
    } else if (std.ascii.eqlIgnoreCase(cmd, "d")) {
        try display.run(io, out, &game.position);
    } else if (std.ascii.eqlIgnoreCase(cmd, "perft")) {
        const depth_str = it.next() orelse "1";
        const depth = std.fmt.parseUnsigned(usize, depth_str, 10) catch return .next;
        const bulk_str = it.next() orelse "bulk";
        const bulk = if (std.ascii.eqlIgnoreCase(bulk_str, "bulk"))
            true
        else if (std.ascii.eqlIgnoreCase(bulk_str, "nonbulk") or std.ascii.eqlIgnoreCase(bulk_str, "nobulk"))
            false
        else
            return .next;
        switch (bulk) {
            inline else => |b| try perft.run(io, out, &game.position, depth, b),
        }
    } else if (std.ascii.eqlIgnoreCase(cmd, "bench")) {
        engine.setOutputMode(io, .none);
        try bench.run(io, out, engine);
        return .quit;
    } else if (std.ascii.eqlIgnoreCase(cmd, "quit")) {
        return .quit;
    }
    return .next;
}

const std = @import("std");
const thorn = @import("../thorn.zig");
const Engine = thorn.Engine;
const Game = thorn.Game;
const Move = thorn.Move;
const Position = thorn.Position;
