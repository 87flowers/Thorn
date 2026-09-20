pub fn run(io: std.Io, out: *std.Io.Writer, position: *const Position, depth: usize, comptime semibulk: bool) !void {
    var timer = std.Io.Timestamp.now(io, .awake);
    var result: u64 = 0;
    var moves: thorn.MoveList = .new();
    thorn.movegen.all(&moves, position);
    for (moves.constSlice()) |m| {
        try out.print("{f}: ", .{m.toString(.frc)});
        try out.flush();

        var child_position: Position = undefined;
        position.move(&child_position, m);
        const child_result = core(&child_position, depth - 1, semibulk);
        result += child_result;

        try out.print("{}\n", .{child_result});
        try out.flush();
    }
    const elapsed: f64 = @floatFromInt(timer.untilNow(io, .awake).toNanoseconds());
    try out.print("total: {}\n", .{result});
    try out.print("perft to depth {} complete in {d:.1}ms ({d:.1} Mnps)\n", .{
        depth,
        elapsed / std.time.ns_per_ms,
        @as(f64, @floatFromInt(result)) / 1_000_000 / (elapsed / std.time.ns_per_s),
    });
    try out.flush();
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
