pub fn run(io: std.Io, writer: *std.Io.Writer, position: *const Position, depth: usize, comptime semibulk: bool) !void {
    var timer = std.Io.Timestamp.now(io, .awake);
    var result: u64 = 0;
    var moves: thorn.MoveList = .new();
    thorn.movegen.all(&moves, position);
    for (moves.constSlice()) |m| {
        try writer.print("{f}: ", .{m.toString(.frc)});
        try writer.flush();

        var child_position: Position = undefined;
        position.move(&child_position, m);
        const child_result = core(&child_position, depth - 1, semibulk);
        result += child_result;

        try writer.print("{}\n", .{child_result});
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

pub fn core(position: *const Position, depth: usize, comptime semibulk: bool) u64 {
    if (depth == 0) return 1;
    var result: u64 = 0;
    var moves: thorn.MoveList = .new();
    thorn.movegen.all(&moves, position);
    if (depth == 1 and semibulk) return moves.len;
    for (moves.constSlice()) |m| {
        var child_position: Position = undefined;
        position.move(&child_position, m);
        result += core(&child_position, depth - 1, semibulk);
    }
    return result;
}

const std = @import("std");
const thorn = @import("../../thorn.zig");
const Position = thorn.Position;
