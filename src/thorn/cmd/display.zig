pub fn run(_: std.Io, out: *std.Io.Writer, position: *const Position) !void {
    switch (position.sideToMove()) {
        .white => try displayBoard(out, position, &mapIdentity, &mapFlip),
        .black => try displayBoard(out, position, &mapFlip, &mapIdentity),
    }
    try out.print("\n", .{});
    try out.print("fen: {f}\n", .{position});
    try out.print("hash: 0x{X:016}\n", .{@intFromEnum(Hash.fromPosition(position))});
    try out.flush();
}

fn displayBoard(out: *std.Io.Writer, position: *const Position, file_map: *const fn (usize) usize, rank_map: *const fn (usize) usize) !void {
    try out.print("   +------------------------+\n", .{});
    for (0..8) |r| {
        const rank: Rank = .fromIndex(@intCast(rank_map(r)));
        try out.print(" {c} |", .{rank.toChar()});
        for (0..8) |f| {
            const file: File = .fromIndex(@intCast(file_map(f)));
            const sq: Square = .fromFileAndRank(file, rank);
            const piece = position.whatAt(sq);
            try out.print(" {f} ", .{piece});
        }
        try out.print("|\n", .{});
    }
    try out.print("   +------------------------+\n", .{});
    try out.print("    ", .{});
    for (0..8) |f| {
        const file: File = .fromIndex(@intCast(file_map(f)));
        try out.print(" {c} ", .{file.toChar()});
    }
    try out.print(" \n", .{});
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
