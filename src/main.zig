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
        if (root) try writer.print("{f}: {}\n", .{ m.toString(.classical), child_result });
        try writer.flush();
    }
    return result;
}

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    for (args) |arg| {
        std.log.info("arg: {s}", .{arg});
    }

    const position = try thorn.Position.parse(args[1]);

    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stdout_writer.print("{f}\n", .{position});

    var moves: thorn.MoveList = .new();
    thorn.movegen.all(&moves, &position);

    const depth = try std.fmt.parseUnsigned(usize, args[2], 10);

    const result = try perft(stdout_writer, position, depth, true);
    try stdout_writer.print("Total: {}\n", .{result});

    try stdout_writer.flush(); // Don't forget to flush!
}

const std = @import("std");
const Io = std.Io;
const thorn = @import("thorn");
