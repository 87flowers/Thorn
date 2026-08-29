pub fn ptype(pt: PieceType, occ: SquareSet, sq: Square, color: Color) SquareSet {
    return switch (pt) {
        .none => .empty,
        .p => pawn(sq, color),
        .n => knight(sq),
        .b => bishop(occ, sq),
        .r => rook(occ, sq),
        .q => queen(occ, sq),
        .k => king(sq),
    };
}

// TODO: Optimize by vectorizing (take diag_ and anti_ as one 128-bit vector).
pub fn bishop(occ: SquareSet, sq: Square) SquareSet {
    assert(sq.isSome());
    const m = masks_table[sq.toIndex()];
    const bit = sq.toSet();
    var diag_forward = occ.raw & m.diagonal;
    var anti_forward = occ.raw & m.antidiagonal;
    var diag_reverse = @byteSwap(diag_forward);
    var anti_reverse = @byteSwap(anti_forward);
    diag_forward -%= bit.raw;
    anti_forward -%= bit.raw;
    diag_reverse -%= @byteSwap(bit.raw);
    anti_reverse -%= @byteSwap(bit.raw);
    diag_forward ^= @byteSwap(diag_reverse);
    anti_forward ^= @byteSwap(anti_reverse);
    diag_forward &= m.diagonal;
    anti_forward &= m.antidiagonal;
    return SquareSet.make(diag_forward | anti_forward);
}

// TODO: Optimize on AVX-512 by using G2P8AFFINEQB (take f_ and r_ as one 128-bit vector).
pub fn rook(occ: SquareSet, sq: Square) SquareSet {
    assert(sq.isSome());
    const m = masks_table[sq.toIndex()];
    const bit = sq.toSet();
    var f_forward = occ.raw & m.file;
    var r_forward = occ.raw & m.rank;
    var f_reverse = @byteSwap(f_forward);
    var r_reverse = @bitReverse(r_forward);
    f_forward -%= bit.raw;
    r_forward -%= bit.raw;
    f_reverse -%= @byteSwap(bit.raw);
    r_reverse -%= @bitReverse(bit.raw);
    f_forward ^= @byteSwap(f_reverse);
    r_forward ^= @bitReverse(r_reverse);
    f_forward &= m.file;
    r_forward &= m.rank;
    return SquareSet.make(f_forward | r_forward);
}

// TODO: Optimize by vectorizing
pub fn queen(occ: SquareSet, sq: Square) SquareSet {
    return bishop(occ, sq).bitOr(rook(occ, sq));
}

pub fn knight(sq: Square) SquareSet {
    assert(sq.isSome());
    return knight_table[sq.toIndex()];
}

pub fn king(sq: Square) SquareSet {
    assert(sq.isSome());
    return king_table[sq.toIndex()];
}

pub fn pawn(sq: Square, color: Color) SquareSet {
    assert(sq.isSome());
    return pawn_table[color.toIndex()][sq.toIndex()];
}

const masks_table = blk: {
    @setEvalBranchQuota(100_000);
    const Masks = struct {
        diagonal: u64,
        antidiagonal: u64,
        file: u64,
        rank: u64,
    };
    var result: [64]Masks = undefined;
    for (0..64) |i| {
        const sq = Square.fromIndex(i);
        result[i] = .{
            .diagonal = SquareSet.rayMask(sq, .ne).bitOr(SquareSet.rayMask(sq, .sw)).raw,
            .antidiagonal = SquareSet.rayMask(sq, .nw).bitOr(SquareSet.rayMask(sq, .se)).raw,
            .file = SquareSet.rayMask(sq, .n).bitOr(SquareSet.rayMask(sq, .s)).raw,
            .rank = SquareSet.rayMask(sq, .e).bitOr(SquareSet.rayMask(sq, .w)).raw,
        };
    }
    break :blk result;
};

const pawn_table = blk: {
    @setEvalBranchQuota(100_000);
    var result: [2][64]SquareSet = undefined;
    for (0..64) |i| {
        const sq = Square.fromIndex(i);
        var bb = sq.toSet();
        result[0][i] = bb.shift(.ne).bitOr(bb.shift(.nw));
        result[1][i] = bb.shift(.se).bitOr(bb.shift(.sw));
    }
    break :blk result;
};

const knight_table = blk: {
    @setEvalBranchQuota(100_000);
    var result: [64]SquareSet = undefined;
    for (0..64) |i| {
        const sq = Square.fromIndex(i);
        var bb = sq.toSet();
        result[i] = (bb.shift(.n).shift(.ne))
            .bitOr(bb.shift(.n).shift(.nw))
            .bitOr(bb.shift(.s).shift(.se))
            .bitOr(bb.shift(.s).shift(.sw))
            .bitOr(bb.shift(.e).shift(.ne))
            .bitOr(bb.shift(.e).shift(.se))
            .bitOr(bb.shift(.w).shift(.nw))
            .bitOr(bb.shift(.w).shift(.sw));
    }
    break :blk result;
};

const king_table = blk: {
    @setEvalBranchQuota(100_000);
    var result: [64]SquareSet = undefined;
    for (0..64) |i| {
        const sq = Square.fromIndex(i);
        var bb = sq.toSet();
        result[i] = (bb.shift(.n))
            .bitOr(bb.shift(.ne))
            .bitOr(bb.shift(.e))
            .bitOr(bb.shift(.se))
            .bitOr(bb.shift(.s))
            .bitOr(bb.shift(.sw))
            .bitOr(bb.shift(.w))
            .bitOr(bb.shift(.nw));
    }
    break :blk result;
};

const std = @import("std");
const assert = std.debug.assert;
const thorn = @import("root.zig");
const Color = thorn.Color;
const PieceType = thorn.PieceType;
const Square = thorn.Square;
const SquareSet = thorn.SquareSet;
