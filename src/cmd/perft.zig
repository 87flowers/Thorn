pub fn run(io: std.Io, writer: *std.Io.Writer, position: *const Position, depth: usize) !void {
    var timer = std.Io.Timestamp.now(io, .awake);
    var result: u64 = 0;
    var moves: thorn.MoveList = .new();
    thorn.movegen.all(&moves, position);
    for (moves.constSlice()) |m| {
        const child_position = position.move(m);
        const child_result = core(&child_position, depth - 1);
        result += child_result;

        try writer.print("{f}: {}\n", .{ m.toString(.frc), result });
        try writer.flush();
    }
    const elapsed: f64 = @floatFromInt(timer.untilNow(io, .awake).toNanoseconds());
    try writer.print("total: {}\n", .{result});
    try writer.print("perft to depth {} complete in {d:.1}ms ({d:.1} Mnps)\n", .{
        depth,
        elapsed / std.time.ns_per_ms,
        @as(f64, @floatFromInt(result)) / 1_000_000 / (elapsed / std.time.ns_per_s),
    });
    try writer.flush();
}

pub fn core(position: *const Position, depth: usize) u64 {
    if (depth == 0) return 1;
    var result: u64 = 0;
    var moves: thorn.MoveList = .new();
    thorn.movegen.all(&moves, position);
    if (depth == 1) return moves.len;
    for (moves.constSlice()) |m| {
        const child_position = position.move(m);
        result += core(&child_position, depth - 1);
    }
    return result;
}

const std = @import("std");
const thorn = @import("../root.zig");
const Position = thorn.Position;
