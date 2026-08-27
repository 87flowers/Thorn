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

    for (moves.constSlice()) |m| try stdout_writer.print("{f} {}\n", .{ m.toString(.frc), moves.len });

    try stdout_writer.flush(); // Don't forget to flush!
}

const std = @import("std");
const Io = std.Io;
const thorn = @import("thorn");
