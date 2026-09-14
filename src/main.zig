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

    var engine = try thorn.Engine.init(io, gpa);
    defer engine.deinit(io, gpa);

    var uci: Uci = .{
        .io = io,
        .writer = stdout,
        .game = .startpos,
    };

    engine.wait(io);
    engine.go(io, &uci.game);

    if (args.len > 1) {
        for (args[1..]) |line| {
            try uci.processLine(line);
        }
        try uci.processLine("quit");
    }

    while (try stdin.takeDelimiter('\n')) |line| {
        try uci.processLine(line);
    }

    try stdout.flush();
}

const Uci = struct {
    io: std.Io,
    writer: *std.Io.Writer,
    game: thorn.Game,

    pub fn processLine(self: *Uci, line: []const u8) !void {
        var it = std.mem.tokenizeAny(u8, line, " \t\r\n");
        const cmd = it.next() orelse return;
        if (std.ascii.eqlIgnoreCase(cmd, "position")) {
            const pos_type = it.next() orelse return;
            if (std.mem.eql(u8, pos_type, "startpos")) {
                self.game.setPosition(.startpos);
            } else if (std.mem.eql(u8, pos_type, "kiwipete")) {
                self.game.setPosition(.kiwipete);
            } else if (std.mem.eql(u8, pos_type, "fen")) {
                const board_str = it.next() orelse "";
                const color = it.next() orelse "";
                const castling = it.next() orelse "";
                const enpassant = it.next() orelse "";
                const no_capture_clock = it.next() orelse "";
                const turn = it.next() orelse "";
                self.game.setPosition(thorn.Position.parseParts(board_str, color, castling, enpassant, no_capture_clock, turn) catch return);
            } else {
                return;
            }

            if (std.ascii.eqlIgnoreCase(it.next() orelse "", "moves")) {
                while (it.next()) |move_str| {
                    const m = thorn.Move.parse(move_str, &self.game.position) catch break;
                    self.game.move(m);
                }
            }
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
                inline else => |b| try thorn.cmd.perft.run(self.io, self.writer, &self.game.position, depth, b),
            }
        } else if (std.ascii.eqlIgnoreCase(cmd, "quit")) {
            std.process.exit(0);
        }
    }
};

test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
const Io = std.Io;
const thorn = @import("thorn.zig");
