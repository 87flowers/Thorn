raw: u64,

pub const empty = make(0);

pub fn make(raw: u64) SquareSet {
    return SquareSet{ .raw = raw };
}

pub fn fileMask(file: i8) SquareSet {
    assert(file >= 0 and file <= 7);
    return make(0x0101010101010101 << file);
}

pub fn rankMask(rank: i8) SquareSet {
    assert(rank >= 0 and rank <= 7);
    return make(0xFF << (rank * 8));
}

pub fn rayMask(start: Square, dir: Dir) SquareSet {
    assert(start.isSome());
    var bb = start.toSet();
    var result = SquareSet{};
    while (!bb.isEmpty()) {
        bb = bb.shift(dir);
        result = result.bitOr(bb);
    }
    return result;
}

pub fn isEmpty(self: SquareSet) bool {
    return self.raw == 0;
}

pub fn lsb(self: SquareSet) Square {
    return Square.make(@ctz(self.raw));
}

pub fn popLsb(self: *SquareSet) void {
    self.raw &= self.raw - 1;
}

pub fn popcount(self: SquareSet) i32 {
    return @popCount(self.raw);
}

pub fn read(self: SquareSet, sq: Square) bool {
    assert(sq.isSome());
    return (self.raw >> sq.raw) & 1;
}

pub fn write(self: *SquareSet, sq: Square, value: bool) void {
    assert(sq.isSome());
    if (value) {
        self.raw |= sq.toSet().raw;
    } else {
        self.raw &= sq.toSet().bitNot().raw;
    }
}

pub fn bitOr(self: SquareSet, other: SquareSet) SquareSet {
    return SquareSet.make(self.raw | other.raw);
}

pub fn bitNot(self: SquareSet) SquareSet {
    return SquareSet.make(~self.raw);
}

pub fn shift(self: SquareSet, dir: Dir) SquareSet {
    const file_a = fileMask(0);
    const file_h = fileMask(7);
    return switch (dir) {
        .n => SquareSet.make(self.raw << 8),
        .ne => SquareSet.make((self.raw & ~file_h.raw) << 9),
        .e => SquareSet.make((self.raw & ~file_h.raw) << 1),
        .se => SquareSet.make((self.raw & ~file_h.raw) >> 7),
        .s => SquareSet.make(self.raw >> 8),
        .sw => SquareSet.make((self.raw & ~file_a.raw) >> 9),
        .w => SquareSet.make(self.raw >> 1),
        .nw => SquareSet.make((self.raw & ~file_a.raw) << 7),
    };
}

const SquareSet = @This();
const std = @import("std");
const assert = std.debug.assert;
const thorn = @import("root.zig");
const Dir = thorn.Dir;
const Square = thorn.Square;
