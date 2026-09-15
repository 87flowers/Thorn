pub fn run(_: std.Io, writer: *std.Io.Writer, position: *const Position) !void {
    try writer.print("   +------------------------+\n", .{});
    for (0..8) |rev_rank| {
        const rank: Rank = .fromIndex(@intCast(7 - rev_rank));
        try writer.print(" {c} |", .{rank.toChar()});
        for (0..8) |f| {
            const file: File = .fromIndex(@intCast(f));
            const sq: Square = .fromFileAndRank(file, rank);
            const piece = position.whatAt(sq);
            try writer.print(" {f} ", .{piece});
        }
        try writer.print("|\n", .{});
    }
    try writer.print("   +------------------------+\n", .{});
    try writer.print("     a  b  c  d  e  f  g  h  \n", .{});
    try writer.print("\n", .{});
    try writer.print("fen: {f}\n", .{position});
    try writer.print("hash: 0x{X:016}\n", .{@intFromEnum(Hash.fromPosition(position))});
    try writer.flush();
}

const std = @import("std");
const thorn = @import("../../thorn.zig");
const File = thorn.File;
const Hash = thorn.Hash;
const Position = thorn.Position;
const Rank = thorn.Rank;
const Square = thorn.Square;
