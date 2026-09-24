stack: StaticVec(Stack, Search.max_depth + 3) = .new(),

pub fn reset(self: *Eval, position: *const Position) void {
    self.stack.clear();

    self.stack.push(rebuild(position));
}

pub fn push(self: *Eval, parent_position: *const Position, m: Move) void {
    var psqt_delta: Pair = .{ 0, 0 };
    var phase_delta: i32 = 0;

    const stm = parent_position.sideToMove();
    const from = m.from();
    const to = m.to();

    const src_piece = parent_position.whatAt(from).ptype().toIndex();

    const my_from = if (stm == .white) from else from.flipColor();
    const my_to = if (stm == .white) to else to.flipColor();
    const their_to = if (stm == .white) to.flipColor() else to;

    switch (m.flags()) {
        .normal => {
            psqt_delta -= psqt_table[src_piece][my_from.toIndex()];
            psqt_delta += psqt_table[src_piece][my_to.toIndex()];
        },
        .cap_normal => {
            const dst_piece = parent_position.whatAt(to).ptype().toIndex();
            psqt_delta -= psqt_table[src_piece][my_from.toIndex()];
            psqt_delta += psqt_table[src_piece][my_to.toIndex()];
            psqt_delta += psqt_table[dst_piece][their_to.toIndex()];
            phase_delta -= phase_table[dst_piece];
        },
        .double_push => {
            psqt_delta -= psqt_table[PieceType.p.toIndex()][my_from.toIndex()];
            psqt_delta += psqt_table[PieceType.p.toIndex()][my_to.toIndex()];
        },
        .enpassant => {
            psqt_delta -= psqt_table[PieceType.p.toIndex()][my_from.toIndex()];
            psqt_delta += psqt_table[PieceType.p.toIndex()][my_to.toIndex()];
            psqt_delta += psqt_table[PieceType.p.toIndex()][their_to.toggleRankLsb().toIndex()];
            phase_delta -= phase_table[PieceType.p.toIndex()];
        },
        .castle_aside => {
            const king_src = my_from;
            const rook_src = my_to;
            const king_dst = Square.fromFileAndRank(.c, king_src.rank());
            const rook_dst = Square.fromFileAndRank(.d, rook_src.rank());
            psqt_delta -= psqt_table[PieceType.k.toIndex()][king_src.toIndex()];
            psqt_delta -= psqt_table[PieceType.r.toIndex()][rook_src.toIndex()];
            psqt_delta += psqt_table[PieceType.k.toIndex()][king_dst.toIndex()];
            psqt_delta += psqt_table[PieceType.r.toIndex()][rook_dst.toIndex()];
        },
        .castle_hside => {
            const king_src = my_from;
            const rook_src = my_to;
            const king_dst = Square.fromFileAndRank(.g, king_src.rank());
            const rook_dst = Square.fromFileAndRank(.f, rook_src.rank());
            psqt_delta -= psqt_table[PieceType.k.toIndex()][king_src.toIndex()];
            psqt_delta -= psqt_table[PieceType.r.toIndex()][rook_src.toIndex()];
            psqt_delta += psqt_table[PieceType.k.toIndex()][king_dst.toIndex()];
            psqt_delta += psqt_table[PieceType.r.toIndex()][rook_dst.toIndex()];
        },
        .promo_n => {
            psqt_delta -= psqt_table[PieceType.p.toIndex()][my_from.toIndex()];
            psqt_delta += psqt_table[PieceType.n.toIndex()][my_to.toIndex()];
            phase_delta += phase_table[PieceType.n.toIndex()];
        },
        .promo_b => {
            psqt_delta -= psqt_table[PieceType.p.toIndex()][my_from.toIndex()];
            psqt_delta += psqt_table[PieceType.b.toIndex()][my_to.toIndex()];
            phase_delta += phase_table[PieceType.b.toIndex()];
        },
        .promo_r => {
            psqt_delta -= psqt_table[PieceType.p.toIndex()][my_from.toIndex()];
            psqt_delta += psqt_table[PieceType.r.toIndex()][my_to.toIndex()];
            phase_delta += phase_table[PieceType.r.toIndex()];
        },
        .promo_q => {
            psqt_delta -= psqt_table[PieceType.p.toIndex()][my_from.toIndex()];
            psqt_delta += psqt_table[PieceType.q.toIndex()][my_to.toIndex()];
            phase_delta += phase_table[PieceType.q.toIndex()];
        },
        .cap_promo_n => {
            const dst_piece = parent_position.whatAt(to).ptype().toIndex();
            psqt_delta -= psqt_table[PieceType.p.toIndex()][my_from.toIndex()];
            psqt_delta += psqt_table[PieceType.n.toIndex()][my_to.toIndex()];
            psqt_delta += psqt_table[dst_piece][their_to.toIndex()];
            phase_delta += phase_table[PieceType.n.toIndex()];
            phase_delta -= phase_table[dst_piece];
        },
        .cap_promo_b => {
            const dst_piece = parent_position.whatAt(to).ptype().toIndex();
            psqt_delta -= psqt_table[PieceType.p.toIndex()][my_from.toIndex()];
            psqt_delta += psqt_table[PieceType.b.toIndex()][my_to.toIndex()];
            psqt_delta += psqt_table[dst_piece][their_to.toIndex()];
            phase_delta += phase_table[PieceType.b.toIndex()];
            phase_delta -= phase_table[dst_piece];
        },
        .cap_promo_r => {
            const dst_piece = parent_position.whatAt(to).ptype().toIndex();
            psqt_delta -= psqt_table[PieceType.p.toIndex()][my_from.toIndex()];
            psqt_delta += psqt_table[PieceType.r.toIndex()][my_to.toIndex()];
            psqt_delta += psqt_table[dst_piece][their_to.toIndex()];
            phase_delta += phase_table[PieceType.r.toIndex()];
            phase_delta -= phase_table[dst_piece];
        },
        .cap_promo_q => {
            const dst_piece = parent_position.whatAt(to).ptype().toIndex();
            psqt_delta -= psqt_table[PieceType.p.toIndex()][my_from.toIndex()];
            psqt_delta += psqt_table[PieceType.q.toIndex()][my_to.toIndex()];
            psqt_delta += psqt_table[dst_piece][their_to.toIndex()];
            phase_delta += phase_table[PieceType.q.toIndex()];
            phase_delta -= phase_table[dst_piece];
        },
    }

    const psqt = self.stack.back().psqt + if (stm == .white) psqt_delta else -psqt_delta;
    const phase = self.stack.back().phase + phase_delta;
    var value = lerp(psqt, phase);
    if (parent_position.sideToMove() == .white) value = -value;
    self.stack.push(.{
        .psqt = psqt,
        .phase = phase,
        .value = value,
    });
}

pub fn pop(self: *Eval) void {
    self.stack.pop();
}

pub fn evaluation(self: *Eval) Score {
    const current = &self.stack.back();
    return current.value + lerp(tempo, current.phase);
}

pub fn assertMatchesRebuild(self: *Eval, position: *const Position) void {
    assert(std.meta.eql(self.stack.back(), rebuild(position)));
}

fn rebuild(position: *const Position) Stack {
    var psqt: Pair = .{ 0, 0 };
    var phase: i32 = 0;
    for (0..64) |i| {
        const sq: Square = .fromIndex(@intCast(i));
        const piece = position.whatAt(sq);
        if (piece.isNone()) continue;
        const pt = piece.ptype().toIndex();
        psqt += switch (piece.color()) {
            .white => psqt_table[pt][sq.toIndex()],
            .black => -psqt_table[pt][sq.flipColor().toIndex()],
        };
        phase += phase_table[pt];
    }
    var value = @divFloor(psqt[0] * phase + psqt[1] * (24 - phase), 24);
    if (position.sideToMove() == .black) value = -value;
    return .{
        .psqt = psqt,
        .phase = phase,
        .value = value,
    };
}

fn lerp(x: Pair, phase: i32) i32 {
    return @divFloor(x[0] * phase + x[1] * (max_phase - phase), max_phase);
}

const max_phase = 24;

const tempo: Pair = .{ 20, 8 };

const phase_table: [6]i32 = .{ 0, 1, 1, 2, 4, 0 };

const psqt_table: [6][64]Pair = .{
    // pawn
    .{
        .{ 0, 0 },     .{ 0, 0 },     .{ 0, 0 },     .{ 0, 0 },     .{ 0, 0 },     .{ 0, 0 },     .{ 0, 0 },     .{ 0, 0 },
        .{ 18, 197 },  .{ 53, 197 },  .{ 42, 189 },  .{ 28, 186 },  .{ 38, 183 },  .{ 77, 179 },  .{ 103, 181 }, .{ 37, 164 },
        .{ 28, 189 },  .{ 58, 187 },  .{ 54, 170 },  .{ 50, 173 },  .{ 61, 170 },  .{ 54, 172 },  .{ 95, 178 },  .{ 44, 167 },
        .{ 27, 203 },  .{ 52, 195 },  .{ 57, 173 },  .{ 70, 165 },  .{ 73, 163 },  .{ 61, 165 },  .{ 60, 194 },  .{ 31, 177 },
        .{ 27, 242 },  .{ 63, 221 },  .{ 59, 184 },  .{ 77, 182 },  .{ 84, 160 },  .{ 66, 179 },  .{ 66, 208 },  .{ 27, 207 },
        .{ 33, 314 },  .{ 83, 298 },  .{ 61, 291 },  .{ 99, 252 },  .{ 99, 244 },  .{ 118, 209 }, .{ 34, 329 },  .{ 59, 266 },
        .{ 164, 392 }, .{ 151, 403 }, .{ 135, 376 }, .{ 186, 314 }, .{ 180, 297 }, .{ 102, 368 }, .{ -15, 432 }, .{ 30, 380 },
        .{ 0, 0 },     .{ 0, 0 },     .{ 0, 0 },     .{ 0, 0 },     .{ 0, 0 },     .{ 0, 0 },     .{ 0, 0 },     .{ 0, 0 },
    },
    // knight
    .{
        .{ 191, 379 }, .{ 233, 347 }, .{ 236, 379 }, .{ 230, 406 }, .{ 239, 392 }, .{ 259, 382 }, .{ 239, 359 }, .{ 221, 321 },
        .{ 214, 366 }, .{ 225, 410 }, .{ 250, 419 }, .{ 254, 425 }, .{ 255, 418 }, .{ 266, 395 }, .{ 250, 407 }, .{ 251, 372 },
        .{ 238, 393 }, .{ 259, 418 }, .{ 262, 431 }, .{ 274, 455 }, .{ 274, 466 }, .{ 273, 434 }, .{ 278, 423 }, .{ 236, 388 },
        .{ 253, 402 }, .{ 265, 447 }, .{ 275, 472 }, .{ 276, 474 }, .{ 284, 464 }, .{ 283, 456 }, .{ 284, 441 }, .{ 265, 411 },
        .{ 265, 412 }, .{ 272, 452 }, .{ 296, 474 }, .{ 306, 469 }, .{ 292, 479 }, .{ 326, 457 }, .{ 281, 450 }, .{ 297, 418 },
        .{ 276, 406 }, .{ 297, 434 }, .{ 302, 462 }, .{ 338, 457 }, .{ 354, 445 }, .{ 352, 444 }, .{ 303, 457 }, .{ 259, 408 },
        .{ 233, 397 }, .{ 268, 411 }, .{ 293, 431 }, .{ 318, 440 }, .{ 302, 424 }, .{ 354, 411 }, .{ 237, 383 }, .{ 249, 402 },
        .{ 134, 326 }, .{ 183, 425 }, .{ 168, 445 }, .{ 238, 418 }, .{ 307, 394 }, .{ 70, 453 },  .{ 159, 417 }, .{ 142, 343 },
    },
    // bishop
    .{
        .{ 223, 417 }, .{ 274, 400 }, .{ 257, 383 }, .{ 259, 438 }, .{ 267, 419 }, .{ 246, 408 }, .{ 267, 418 }, .{ 239, 426 },
        .{ 271, 414 }, .{ 275, 420 }, .{ 279, 438 }, .{ 263, 451 }, .{ 271, 453 }, .{ 282, 435 }, .{ 290, 423 }, .{ 269, 419 },
        .{ 268, 432 }, .{ 281, 451 }, .{ 275, 481 }, .{ 280, 481 }, .{ 271, 488 }, .{ 285, 462 }, .{ 282, 447 }, .{ 277, 421 },
        .{ 270, 420 }, .{ 280, 475 }, .{ 286, 490 }, .{ 300, 495 }, .{ 303, 475 }, .{ 283, 481 }, .{ 279, 458 }, .{ 274, 421 },
        .{ 258, 450 }, .{ 279, 477 }, .{ 294, 481 }, .{ 319, 483 }, .{ 314, 483 }, .{ 301, 462 }, .{ 290, 468 }, .{ 276, 456 },
        .{ 273, 452 }, .{ 277, 491 }, .{ 284, 484 }, .{ 318, 478 }, .{ 332, 455 }, .{ 331, 483 }, .{ 294, 479 }, .{ 304, 426 },
        .{ 241, 452 }, .{ 279, 449 }, .{ 274, 475 }, .{ 274, 462 }, .{ 291, 471 }, .{ 282, 465 }, .{ 286, 461 }, .{ 265, 413 },
        .{ 235, 434 }, .{ 242, 460 }, .{ 230, 467 }, .{ 198, 472 }, .{ 208, 495 }, .{ 118, 494 }, .{ 212, 458 }, .{ 265, 454 },
    },
    // rook
    .{
        .{ 321, 747 }, .{ 328, 760 }, .{ 333, 771 }, .{ 339, 771 }, .{ 343, 762 }, .{ 325, 765 }, .{ 303, 767 }, .{ 321, 706 },
        .{ 304, 743 }, .{ 323, 747 }, .{ 311, 760 }, .{ 317, 755 }, .{ 331, 743 }, .{ 344, 755 }, .{ 347, 729 }, .{ 284, 723 },
        .{ 311, 741 }, .{ 308, 760 }, .{ 327, 755 }, .{ 323, 767 }, .{ 330, 752 }, .{ 327, 761 }, .{ 341, 744 }, .{ 321, 731 },
        .{ 317, 772 }, .{ 315, 784 }, .{ 326, 794 }, .{ 334, 784 }, .{ 345, 775 }, .{ 346, 775 }, .{ 343, 769 }, .{ 331, 746 },
        .{ 323, 796 }, .{ 333, 803 }, .{ 356, 802 }, .{ 359, 805 }, .{ 356, 798 }, .{ 354, 803 }, .{ 356, 790 }, .{ 340, 778 },
        .{ 338, 813 }, .{ 363, 808 }, .{ 368, 807 }, .{ 394, 803 }, .{ 423, 794 }, .{ 418, 794 }, .{ 394, 796 }, .{ 374, 787 },
        .{ 368, 806 }, .{ 376, 810 }, .{ 397, 809 }, .{ 423, 801 }, .{ 431, 798 }, .{ 424, 787 }, .{ 374, 803 }, .{ 370, 799 },
        .{ 416, 780 }, .{ 409, 787 }, .{ 427, 782 }, .{ 441, 786 }, .{ 421, 791 }, .{ 416, 792 }, .{ 424, 790 }, .{ 430, 777 },
    },
    // queen
    .{
        .{ 918, 1211 }, .{ 921, 1192 }, .{ 922, 1201 }, .{ 930, 1203 }, .{ 926, 1192 }, .{ 902, 1187 }, .{ 932, 1151 }, .{ 948, 1125 },
        .{ 918, 1163 }, .{ 930, 1238 }, .{ 937, 1224 }, .{ 923, 1245 }, .{ 930, 1236 }, .{ 951, 1193 }, .{ 938, 1181 }, .{ 912, 1200 },
        .{ 916, 1242 }, .{ 933, 1243 }, .{ 928, 1279 }, .{ 921, 1277 }, .{ 917, 1292 }, .{ 929, 1282 }, .{ 930, 1290 }, .{ 926, 1241 },
        .{ 926, 1248 }, .{ 912, 1294 }, .{ 922, 1314 }, .{ 929, 1343 }, .{ 931, 1339 }, .{ 926, 1335 }, .{ 937, 1293 }, .{ 924, 1285 },
        .{ 922, 1265 }, .{ 916, 1312 }, .{ 918, 1352 }, .{ 932, 1344 }, .{ 938, 1381 }, .{ 944, 1350 }, .{ 933, 1372 }, .{ 940, 1304 },
        .{ 917, 1293 }, .{ 920, 1301 }, .{ 930, 1324 }, .{ 952, 1353 }, .{ 972, 1355 }, .{ 975, 1378 }, .{ 956, 1345 }, .{ 956, 1330 },
        .{ 908, 1299 }, .{ 905, 1325 }, .{ 932, 1352 }, .{ 907, 1379 }, .{ 911, 1401 }, .{ 950, 1355 }, .{ 924, 1355 }, .{ 935, 1325 },
        .{ 862, 1356 }, .{ 970, 1277 }, .{ 959, 1322 }, .{ 990, 1331 }, .{ 975, 1329 }, .{ 979, 1320 }, .{ 914, 1356 }, .{ 909, 1353 },
    },
    // king
    .{
        .{ -73, -52 },  .{ 7, -73 },   .{ -17, -58 }, .{ -92, -60 }, .{ -23, -102 }, .{ -59, -68 }, .{ 31, -89 },  .{ 25, -112 },
        .{ 11, -68 },   .{ -23, -43 }, .{ -41, -25 }, .{ -94, -8 },  .{ -92, -17 },  .{ -54, -24 }, .{ -10, -40 }, .{ 10, -68 },
        .{ -37, -37 },  .{ -49, -19 }, .{ -98, -4 },  .{ -125, 17 }, .{ -157, 24 },  .{ -105, 9 },  .{ -66, -14 }, .{ -74, -39 },
        .{ -54, -33 },  .{ 7, -2 },    .{ -97, 24 },  .{ -73, 21 },  .{ -122, 31 },  .{ -132, 32 }, .{ -107, 13 }, .{ -133, -21 },
        .{ -10, -14 },  .{ -58, 20 },  .{ -54, 34 },  .{ -125, 43 }, .{ -77, 40 },   .{ -54, 47 },  .{ -109, 51 }, .{ -154, 23 },
        .{ -7, -7 },    .{ 24, 17 },   .{ -46, 28 },  .{ -1, 27 },   .{ -52, 34 },   .{ -22, 36 },  .{ -52, 56 },  .{ -106, 34 },
        .{ 153, -54 },  .{ 61, 0 },    .{ 33, 17 },   .{ 29, 13 },   .{ -22, 19 },   .{ -64, 54 },  .{ -64, 52 },  .{ -73, 25 },
        .{ 438, -195 }, .{ 171, -44 }, .{ 67, 5 },    .{ 111, -7 },  .{ 92, 21 },    .{ 65, 30 },   .{ 153, -42 }, .{ 118, -52 },
    },
};

const Pair = @Vector(2, i16);

const Stack = struct {
    psqt: Pair,
    phase: i32,
    value: Score,
};

const Eval = @This();
const std = @import("std");
const assert = std.debug.assert;
const thorn = @import("../thorn.zig");
const Move = thorn.Move;
const Piece = thorn.Piece;
const PieceType = thorn.PieceType;
const Position = thorn.Position;
const Score = thorn.score.Score;
const Search = thorn.Search;
const Square = thorn.Square;
const StaticVec = thorn.util.StaticVec;
