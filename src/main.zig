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

    for (args[1..]) |line| {
        switch (try thorn.cmd.processLine(io, gpa, stdout, &engine, &game, line)) {
            .next => {},
            .quit => break,
        }
    }

    while (try stdin.takeDelimiter('\n')) |line| {
        switch (try thorn.cmd.processLine(io, gpa, stdout, &engine, &game, line)) {
            .next => {},
            .quit => break,
        }
    }

    try stdout.flush();
}

test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
const Io = std.Io;
const thorn = @import("thorn.zig");
