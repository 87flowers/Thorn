pub const bench = @import("cmd/bench.zig");
pub const display = @import("cmd/display.zig");
pub const perft = @import("cmd/perft.zig");

pub const ShouldQuit = enum {
    next,
    quit,
};

pub fn processLine(
    io: std.Io,
    gpa: std.mem.Allocator,
    out: *std.Io.Writer,
    engine: *Engine,
    game: *Game,
    line: []const u8,
) !ShouldQuit {
    const time_start: std.Io.Timestamp = .now(io, .awake);

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
        var limits: Engine.SearchLimit = .{};
        while (it.next()) |part| {
            if (std.ascii.eqlIgnoreCase(part, "wtime")) {
                const value = std.fmt.parseUnsigned(u64, it.next() orelse break, 10) catch continue;
                if (game.position.sideToMove() == .white) limits.base_ms = value;
            } else if (std.ascii.eqlIgnoreCase(part, "btime")) {
                const value = std.fmt.parseUnsigned(u64, it.next() orelse break, 10) catch continue;
                if (game.position.sideToMove() == .black) limits.base_ms = value;
            } else if (std.ascii.eqlIgnoreCase(part, "winc")) {
                const value = std.fmt.parseUnsigned(u64, it.next() orelse break, 10) catch continue;
                if (game.position.sideToMove() == .white) limits.inc_ms = value;
            } else if (std.ascii.eqlIgnoreCase(part, "binc")) {
                const value = std.fmt.parseUnsigned(u64, it.next() orelse break, 10) catch continue;
                if (game.position.sideToMove() == .black) limits.inc_ms = value;
            } else if (std.ascii.eqlIgnoreCase(part, "movestogo")) {
                limits.movestogo = std.fmt.parseUnsigned(u64, it.next() orelse break, 10) catch continue;
            } else if (std.ascii.eqlIgnoreCase(part, "nodes")) {
                limits.hard_nodes = std.fmt.parseUnsigned(u64, it.next() orelse break, 10) catch continue;
            } else if (std.ascii.eqlIgnoreCase(part, "softnodes")) {
                limits.soft_nodes = std.fmt.parseUnsigned(u64, it.next() orelse break, 10) catch continue;
            } else if (std.ascii.eqlIgnoreCase(part, "depth")) {
                const value: i32 = std.fmt.parseUnsigned(u31, it.next() orelse break, 10) catch continue;
                limits.depth = value;
            }
        }
        engine.go(io, game, time_start, limits);
    } else if (std.ascii.eqlIgnoreCase(cmd, "uci")) {
        try out.print(
            \\id name Thorn {s}
            \\id author 87 (87flowers.com)
            \\option name Hash type spin default {} min 1 max {}
            \\option name Threads type spin default 1 min 1 max {}
            \\option name UCI_Chess960 type check default false
            \\uciok
            \\
        , .{
            @import("../main.zig").thorn_version,
            thorn.Cache.default_size_mb,
            thorn.Cache.max_size_mb,
            thorn.Engine.max_threads,
        });
        try out.flush();
    } else if (std.ascii.eqlIgnoreCase(cmd, "ucinewgame")) {
        engine.newGame(io);
        game.* = .startpos;
    } else if (std.ascii.eqlIgnoreCase(cmd, "setoption")) {
        while (!std.ascii.eqlIgnoreCase(it.next() orelse return .next, "name")) {}
        const name = it.next() orelse return .next;
        while (!std.ascii.eqlIgnoreCase(it.next() orelse return .next, "value")) {}
        const value_str = it.next() orelse return .next;
        if (std.ascii.eqlIgnoreCase(name, "Hash")) {
            const mb = std.fmt.parseUnsigned(usize, value_str, 10) catch return .next;
            try engine.setCacheSize(io, gpa, mb);
        } else if (std.ascii.eqlIgnoreCase(name, "Threads")) {
            const threads = std.fmt.parseUnsigned(usize, value_str, 10) catch return .next;
            try engine.setThreadCount(io, gpa, threads);
        } else if (std.ascii.eqlIgnoreCase(name, "UCI_Chess960")) {
            const move_format: MoveFormat = if (std.ascii.eqlIgnoreCase(name, "true"))
                .frc
            else if (std.ascii.eqlIgnoreCase(name, "false"))
                .classical
            else
                return .next;
            engine.setMoveFormat(io, move_format);
        }
    } else if (std.ascii.eqlIgnoreCase(cmd, "isready")) {
        try out.print("readyok\n", .{});
        try out.flush();
    } else if (std.ascii.eqlIgnoreCase(cmd, "stop")) {
        engine.stop(io);
    } else if (std.ascii.eqlIgnoreCase(cmd, "wait")) {
        engine.wait(io);
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
        try bench.run(io, gpa, out, engine);
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
const MoveFormat = thorn.MoveFormat;
const Position = thorn.Position;
