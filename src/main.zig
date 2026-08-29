pub fn perft(writer: *Io.Writer, position: thorn.Position, depth: usize, comptime root: bool) !u64 {
    if (depth == 0) return 1;
    var result: u64 = 0;
    var moves: thorn.MoveList = .new();
    thorn.movegen.all(&moves, &position);
    if (depth == 1 and !root) return moves.len;
    for (moves.constSlice()) |m| {
        //try writer.print("{f}: ", .{m.toString(.classical)});
        //try writer.flush();
        const child_position = position.move(m);
        //try writer.print("{f}\n", .{child_position});
        //try writer.flush();
        const child_result = try perft(writer, child_position, depth - 1, false);
        result += child_result;
        if (root) try writer.print("{f}: {}\n", .{ m.toString(.frc), child_result });
        try writer.flush();
    }
    return result;
}

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    // const args = try init.minimal.args.toSlice(arena);

    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    const stdin_buffer = try arena.alloc(u8, 1024 * 1024);
    var stdin_file_reader: Io.File.Reader = .init(.stdin(), io, stdin_buffer);
    const stdin = &stdin_file_reader.interface;

    var position: thorn.Position = undefined;

    while (try stdin.takeDelimiter('\n')) |line| {
        var it = std.mem.tokenizeAny(u8, line, " \t\r\n");
        const cmd = it.next() orelse continue;
        if (std.ascii.eqlIgnoreCase(cmd, "position")) {
            const pos_type = it.next() orelse continue;
            if (std.mem.eql(u8, pos_type, "startpos")) {
                //
            } else if (std.mem.eql(u8, pos_type, "fen")) {
                const board_str = it.next() orelse "";
                const color = it.next() orelse "";
                const castling = it.next() orelse "";
                const enpassant = it.next() orelse "";
                const no_capture_clock = it.next() orelse "";
                const turn = it.next() orelse "";
                position = thorn.Position.parseParts(board_str, color, castling, enpassant, no_capture_clock, turn) catch continue;
            } else {
                continue;
            }

            std.debug.print("{s}\n", .{it.rest()});
            if (std.ascii.eqlIgnoreCase(it.next() orelse "", "moves")) {
                while (it.next()) |move_str| {
                    const m = thorn.Move.parse(move_str, &position) catch break;
                    position = position.move(m);
                }
            }
        } else if (std.ascii.eqlIgnoreCase(cmd, "perft")) {
            const depth_str = it.next() orelse "1";
            const depth = std.fmt.parseUnsigned(usize, depth_str, 10) catch continue;
            const result = try perft(stdout, position, depth, true);
            try stdout.print("total: {}\n", .{result});
            try stdout.flush();
        } else if (std.ascii.eqlIgnoreCase(cmd, "quit")) {
            break;
        }
    }

    try stdout.flush();
}

const std = @import("std");
const Io = std.Io;
const thorn = @import("thorn");
