pub fn between(a: Square, b: Square) SquareSet {
    assert(a.isSome() and b.isSome());
    return between_table[a.toIndex()][b.toIndex()];
}

pub fn past(from: Square, to: Square) SquareSet {
    assert(from.isSome() and to.isSome());
    return past_table[from.toIndex()][to.toIndex()];
}

const between_table: [64][64]SquareSet = blk: {
    @setEvalBranchQuota(100_000);
    var result: [64][64]SquareSet = @splat(@splat(.empty));
    for (0..64) |origin| {
        for ([_]Dir{ .n, .ne, .e, .se, .s, .sw, .w, .nw }) |dir| {
            var current = Square.fromIndex(origin).toSet().shift(dir);
            var ray = SquareSet.empty;
            while (!current.isEmpty()) {
                const dst = current.lsb().toIndex();
                result[origin][dst] = ray;

                ray = ray.bitOr(current);
                current = current.shift(dir);
            }
        }
    }
    break :blk result;
};

const past_table: [64][64]SquareSet = blk: {
    @setEvalBranchQuota(100_000);
    var result: [64][64]SquareSet = @splat(@splat(.empty));
    for (0..64) |origin| {
        for ([_]Dir{ .n, .ne, .e, .se, .s, .sw, .w, .nw }) |dir| {
            const ray = SquareSet.rayMask(Square.fromIndex(origin), dir);
            var iter = ray.iter();
            while (iter.next()) |dst| {
                result[origin][dst.toIndex()] = ray;
            }
        }
    }
    break :blk result;
};

const std = @import("std");
const assert = std.debug.assert;
const thorn = @import("root.zig");
const Dir = thorn.Dir;
const Square = thorn.Square;
const SquareSet = thorn.SquareSet;
