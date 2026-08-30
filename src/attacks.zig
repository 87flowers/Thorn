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

pub fn bishop(occ: SquareSet, sq: Square) SquareSet {
    const e = bishop_table[0][sq.toIndex()];
    return bishop_table[1][e.offset + intrin.pext(occ.raw, e.mask.raw)];
}

pub fn rook(occ: SquareSet, sq: Square) SquareSet {
    const e = rook_table[0][sq.toIndex()];
    return rook_table[1][e.offset + intrin.pext(occ.raw, e.mask.raw)];
}

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

fn bishopHq(occ: SquareSet, sq: Square) SquareSet {
    assert(sq.isSome());
    const m = hq_masks_table[sq.toIndex()];
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

fn rookHq(occ: SquareSet, sq: Square) SquareSet {
    assert(sq.isSome());
    const m = hq_masks_table[sq.toIndex()];
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

const hq_masks_table = blk: {
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

const bishop_table = blk: {
    @setEvalBranchQuota(100_000_000);

    var table: [64]SliderTable = @splat(.{ .mask = .empty, .offset = undefined });
    var entry_count: [64]usize = undefined;
    var total_entry_count: usize = 0;
    for (0..64) |i| {
        const sq: Square = .fromIndex(i);
        table[i].mask.insert(.rayMaskExceptLast(sq, .ne));
        table[i].mask.insert(.rayMaskExceptLast(sq, .nw));
        table[i].mask.insert(.rayMaskExceptLast(sq, .se));
        table[i].mask.insert(.rayMaskExceptLast(sq, .sw));
        entry_count[i] = @as(usize, 1) << @intCast(table[i].mask.popcount());
        table[i].offset = total_entry_count;
        total_entry_count += entry_count[i];
    }

    var result_table: [total_entry_count]SquareSet = @splat(.empty);
    for (0..64) |i| {
        const sq: Square = .fromIndex(i);
        const mask: SquareSet = table[i].mask;
        for (0..entry_count[i]) |j| {
            const occ: SquareSet = .make(intrin.pdep(j, mask.raw));
            result_table[table[i].offset + j] = bishopHq(occ, sq);
        }
    }

    break :blk .{ table, result_table };
};

const rook_table = blk: {
    @setEvalBranchQuota(100_000_000);

    var table: [64]SliderTable = @splat(.{ .mask = .empty, .offset = undefined });
    var entry_count: [64]usize = undefined;
    var total_entry_count: usize = 0;
    for (0..64) |i| {
        const sq: Square = .fromIndex(i);
        table[i].mask.insert(.rayMaskExceptLast(sq, .n));
        table[i].mask.insert(.rayMaskExceptLast(sq, .e));
        table[i].mask.insert(.rayMaskExceptLast(sq, .s));
        table[i].mask.insert(.rayMaskExceptLast(sq, .w));
        entry_count[i] = @as(usize, 1) << @intCast(table[i].mask.popcount());
        table[i].offset = total_entry_count;
        total_entry_count += entry_count[i];
    }

    var result_table: [total_entry_count]SquareSet = @splat(.empty);
    for (0..64) |i| {
        const sq: Square = .fromIndex(i);
        const mask: SquareSet = table[i].mask;
        for (0..entry_count[i]) |j| {
            const occ: SquareSet = .make(intrin.pdep(j, mask.raw));
            result_table[table[i].offset + j] = rookHq(occ, sq);
        }
    }

    break :blk .{ table, result_table };
};

const SliderTable = struct {
    mask: SquareSet,
    offset: usize,
};

const std = @import("std");
const assert = std.debug.assert;
const thorn = @import("root.zig");
const intrin = thorn.util.intrin;
const Color = thorn.Color;
const PieceType = thorn.PieceType;
const Square = thorn.Square;
const SquareSet = thorn.SquareSet;
