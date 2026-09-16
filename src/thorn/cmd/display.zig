pub fn run(_: std.Io, writer: *std.Io.Writer, position: *const Position) !void {
    switch (position.sideToMove()) {
        .white => try displayBoard(writer, position, &mapIdentity, &mapFlip),
        .black => try displayBoard(writer, position, &mapFlip, &mapIdentity),
    }
    try writer.print("\n", .{});
    try writer.print("fen: {f}\n", .{position});
    try writer.print("hash: 0x{X:016}\n", .{@intFromEnum(Hash.fromPosition(position))});
    try writer.flush();
}

fn displayBoard(writer: *std.Io.Writer, position: *const Position, file_map: *const fn (usize) usize, rank_map: *const fn (usize) usize) !void {
    try writer.print("   +------------------------+\n", .{});
    for (0..8) |r| {
        const rank: Rank = .fromIndex(@intCast(rank_map(r)));
        try writer.print(" {c} |", .{rank.toChar()});
        for (0..8) |f| {
            const file: File = .fromIndex(@intCast(file_map(f)));
            const sq: Square = .fromFileAndRank(file, rank);
            const piece = position.whatAt(sq);
            try writer.print(" {f} ", .{piece});
        }
        try writer.print("|\n", .{});
    }
    try writer.print("   +------------------------+\n", .{});
    try writer.print("    ", .{});
    for (0..8) |f| {
        const file: File = .fromIndex(@intCast(file_map(f)));
        try writer.print(" {c} ", .{file.toChar()});
    }
    try writer.print(" \n", .{});
}

fn mapIdentity(x: usize) usize {
    return x;
}
fn mapFlip(x: usize) usize {
    return 7 - x;
}

const std = @import("std");
const thorn = @import("../../thorn.zig");
const File = thorn.File;
const Hash = thorn.Hash;
const Position = thorn.Position;
const Rank = thorn.Rank;
const Square = thorn.Square;
