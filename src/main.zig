pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);

    const io = init.io;
    const gpa = init.gpa;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    const stdin_buffer = try arena.alloc(u8, 1024 * 1024);
    var stdin_file_reader: Io.File.Reader = .init(.stdin(), io, stdin_buffer);
    const stdin = &stdin_file_reader.interface;

    var game: thorn.Game = .startpos;

    var engine = try thorn.Engine.init(io, gpa);
    defer engine.deinit(io, gpa);

    engine.wait(io);
    engine.setOutputMode(io, .uci);
    engine.setMoveFormat(io, .classical);

    if (args.len > 1) for (args[1..]) |line| {
        try processLine(io, gpa, stdout, &engine, &game, line);
    };

    while (try stdin.takeDelimiter('\n')) |line| {
        try processLine(io, gpa, stdout, &engine, &game, line);
    }

    try stdout.flush();
}

pub fn processLine(
    io: std.Io,
    gpa: std.mem.Allocator,
    out: *std.Io.Writer,
    engine: *thorn.Engine,
    game: *thorn.Game,
    line: []const u8,
) !void {
    var it = std.mem.tokenizeAny(u8, line, " \t\r\n");
    const cmd = it.next() orelse return;
    if (std.ascii.eqlIgnoreCase(cmd, "position")) {
        const pos_type = it.next() orelse return;
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
            game.setPosition(thorn.Position.parseParts(board_str, color, castling, enpassant, no_capture_clock, turn) catch return);
        } else {
            return;
        }

        if (std.ascii.eqlIgnoreCase(it.next() orelse "", "moves")) {
            while (it.next()) |move_str| {
                const m = thorn.Move.parse(move_str, &game.position) catch break;
                game.move(m);
            }
        }
    } else if (std.ascii.eqlIgnoreCase(cmd, "go")) {
        engine.go(io, out, game);
    } else if (std.ascii.eqlIgnoreCase(cmd, "d")) {
        try thorn.cmd.display.run(io, out, &game.position);
    } else if (std.ascii.eqlIgnoreCase(cmd, "perft")) {
        const depth_str = it.next() orelse "1";
        const depth = std.fmt.parseUnsigned(usize, depth_str, 10) catch return;
        const bulk_str = it.next() orelse "bulk";
        const bulk = if (std.ascii.eqlIgnoreCase(bulk_str, "bulk"))
            true
        else if (std.ascii.eqlIgnoreCase(bulk_str, "nonbulk") or std.ascii.eqlIgnoreCase(bulk_str, "nobulk"))
            false
        else
            return;
        switch (bulk) {
            inline else => |b| try thorn.cmd.perft.run(io, out, &game.position, depth, b),
        }
    } else if (std.ascii.eqlIgnoreCase(cmd, "quit")) {
        engine.deinit(io, gpa);
        std.process.exit(0);
    }
}

test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
const Io = std.Io;
const thorn = @import("thorn.zig");
