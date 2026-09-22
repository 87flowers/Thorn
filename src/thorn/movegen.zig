pub fn all(moves: *MoveList, position: *const Position) void {
    return generateMoves(.all, moves, position);
}

pub fn noisy(moves: *MoveList, position: *const Position) void {
    return generateMoves(.noisy, moves, position);
}

pub fn quiet(moves: *MoveList, position: *const Position) void {
    return generateMoves(.quiet, moves, position);
}

fn generateMoves(comptime subset: Subset, moves: *MoveList, position: *const Position) void {
    @constCast(position).calculateDanger();
    const checkers = position.checkers();
    switch (checkers.popcount()) {
        0 => {
            generateEnpassant(subset, moves, position);
            generateMostMoves(subset, moves, position, SquareSet.all);
            generateCastling(subset, moves, position);
            generateKingMoves(subset, moves, position);
        },
        1 => {
            const checker = checkers.lsb();
            const stm = position.sideToMove();
            const king = position.kingSq(stm);
            if (position.whatIs(stm.invert(), checker) == .p) generateEnpassant(subset, moves, position);
            generateMostMoves(subset, moves, position, SquareSet.rayExclusiveInclusive(king, position.whereIs(stm.invert(), checker)));
            generateKingMoves(subset, moves, position);
        },
        else => generateKingMoves(subset, moves, position),
    }
}

fn generateEnpassant(comptime subset: Subset, moves: *MoveList, position: *const Position) void {
    if (!subset.isNoisy()) return;

    const stm = position.sideToMove();

    const ep = position.enpassant;
    if (ep.isNone()) return;

    const attacker_set = position.whichMaskedAttackTo(ep.toSet()).bitAnd(position.whichAre(stm, .p));
    if (attacker_set.isEmpty()) return;

    if (attacker_set.popcount() == 1) {
        const victim = ep.toggleRankLsb();
        const attacker = position.whereIs(stm, attacker_set.lsb());
        const king = position.kingSq(stm);
        if (king.rank() == victim.rank()) {
            const occ = position.occupiedSet().bitAnd(victim.toSet().bitOr(attacker.toSet()).bitNot());
            const enemy_rooks = position.coloredPtypeSet(stm.invert(), .r).bitOr(position.coloredPtypeSet(stm.invert(), .q));
            // Detect if en passant attacker is clearance pinned
            if (!attacks.rook(occ, king).bitAnd(enemy_rooks).isEmpty()) return;
        }
        moves.push(attacker, ep, .enpassant);
        return;
    }

    var iter = attacker_set.iter();
    while (iter.next()) |id| {
        const attacker = position.whereIs(position.sideToMove(), id);
        moves.push(attacker, ep, .enpassant);
    }
}

fn generateMostMoves(comptime subset: Subset, moves: *MoveList, position: *const Position, valid_destinations: SquareSet) void {
    const stm = position.sideToMove();
    const empty = position.occupiedSet().bitNot();
    const enemy = position.colorSet(stm.invert());
    const valid_empty = empty.bitAnd(valid_destinations);
    const valid_enemy = enemy.bitAnd(valid_destinations);

    const officer_ids = position.whichAreOfficers(stm);
    const movable_ids = position.whichMaskedAttackTo(valid_destinations);

    var iter = officer_ids.bitAnd(movable_ids).iter();
    while (iter.next()) |id| {
        const from = position.whereIs(stm, id);
        const to = position.masked_attack_set[id.toIndex()];
        switch (subset) {
            .all => moves.pushSets(from, to.bitAnd(valid_empty), to.bitAnd(valid_enemy)),
            .noisy => moves.pushSet(from, to.bitAnd(valid_enemy), .cap_normal),
            .quiet => moves.pushSet(from, to.bitAnd(valid_empty), .normal),
        }
    }

    switch (stm) {
        .white => {
            generatePawnCaptures(subset, moves, position, valid_destinations, .white);
            generatePawnPushes(subset, moves, position, valid_destinations, .white);
        },
        .black => {
            generatePawnCaptures(subset, moves, position, valid_destinations, .black);
            generatePawnPushes(subset, moves, position, valid_destinations, .black);
        },
    }
}

fn generatePawnCaptures(comptime subset: Subset, moves: *MoveList, position: *const Position, valid_destinations: SquareSet, comptime stm: Color) void {
    if (!subset.isNoisy()) return;

    const king = position.kingSq(stm);
    const enemy = position.colorSet(stm.invert());
    const valid_enemy = enemy.bitAnd(valid_destinations);

    const pinned = position.pinned;
    const all_pawns = position.coloredPtypeSet(stm, .p);
    const diag_dir, const anti_dir, const promoable_base, const promo_rank = switch (stm) {
        .white => .{ Dir.ne, Dir.nw, Square.a7, 6 },
        .black => .{ Dir.sw, Dir.se, Square.a2, 1 },
    };

    const diag_pawns = all_pawns.bitAndNot(pinned.bitAndNot(.diagonalMask(king))).bitAnd(valid_enemy.shift(diag_dir.flip()));
    const anti_pawns = all_pawns.bitAndNot(pinned.bitAndNot(.antiDiagonalMask(king))).bitAnd(valid_enemy.shift(anti_dir.flip()));

    const diag_cap = diag_pawns.bitAndNot(SquareSet.rankMask(promo_rank));
    const anti_cap = anti_pawns.bitAndNot(SquareSet.rankMask(promo_rank));
    const diag_promo = diag_pawns.readRank(promo_rank);
    const anti_promo = anti_pawns.readRank(promo_rank);

    if (!diag_cap.isEmpty()) moves.pushPawnCapture(diag_cap, diag_dir);
    if (!anti_cap.isEmpty()) moves.pushPawnCapture(anti_cap, anti_dir);
    if (diag_promo != 0) {
        moves.pushPawnPromoCapture(promoable_base, diag_promo, diag_dir, .cap_promo_q);
        moves.pushPawnPromoCapture(promoable_base, diag_promo, diag_dir, .cap_promo_n);
        moves.pushPawnPromoCapture(promoable_base, diag_promo, diag_dir, .cap_promo_r);
        moves.pushPawnPromoCapture(promoable_base, diag_promo, diag_dir, .cap_promo_b);
    }
    if (anti_promo != 0) {
        moves.pushPawnPromoCapture(promoable_base, anti_promo, anti_dir, .cap_promo_q);
        moves.pushPawnPromoCapture(promoable_base, anti_promo, anti_dir, .cap_promo_n);
        moves.pushPawnPromoCapture(promoable_base, anti_promo, anti_dir, .cap_promo_r);
        moves.pushPawnPromoCapture(promoable_base, anti_promo, anti_dir, .cap_promo_b);
    }
}

fn generatePawnPushes(comptime subset: Subset, moves: *MoveList, position: *const Position, valid_destinations: SquareSet, comptime stm: Color) void {
    const king = position.kingSq(stm);
    const empty = position.occupiedSet().bitNot();
    const valid_empty = empty.bitAnd(valid_destinations);

    const pinned = position.pinned;
    const pinned_pawns = pinned.bitAnd(SquareSet.fileMask(king.file()).bitNot());
    const pawns = position.coloredPtypeSet(stm, .p).bitAndNot(pinned_pawns);
    const pawns_ok_single, const pawns_ok_double = switch (stm) {
        .white => .{ pawns.bitAnd(valid_empty.shift(.s)), pawns.bitAnd(valid_empty.shift(.s).shift(.s).bitAnd(empty.shift(.s))) },
        .black => .{ pawns.bitAnd(valid_empty.shift(.n)), pawns.bitAnd(valid_empty.shift(.n).shift(.n).bitAnd(empty.shift(.n))) },
    };
    const home_single, const home_base, const home_double, const promoable, const promoable_base, const push, const double_push = switch (stm) {
        .white => .{ pawns_ok_single.readRank(1), Square.a2, pawns_ok_double.readRank(1), pawns_ok_single.readRank(6), Square.a7, 8, 16 },
        .black => .{ pawns_ok_single.readRank(6), Square.a7, pawns_ok_double.readRank(6), pawns_ok_single.readRank(1), Square.a2, -8, -16 },
    };
    const body: u32 = @truncate(pawns_ok_single.raw >> 16);

    if (subset.isQuiet()) if (home_single != 0) moves.pushPawnRank(home_base, home_single, push, stm, .normal);
    if (subset.isQuiet()) if (home_double != 0) moves.pushPawnRank(home_base, home_double, double_push, stm, .double_push);
    if (subset.isQuiet()) if (body != 0) moves.pushPawnBody(body, stm);
    if (promoable != 0) {
        if (subset.isNoisy()) moves.pushPawnRank(promoable_base, promoable, push, stm, .promo_q);
        if (subset.isQuiet()) moves.pushPawnRank(promoable_base, promoable, push, stm, .promo_n);
        if (subset.isQuiet()) moves.pushPawnRank(promoable_base, promoable, push, stm, .promo_r);
        if (subset.isQuiet()) moves.pushPawnRank(promoable_base, promoable, push, stm, .promo_b);
    }
}

fn generateCastling(comptime subset: Subset, moves: *MoveList, position: *const Position) void {
    if (!subset.isQuiet()) return;

    const stm = position.sideToMove();
    if (!position.castling.hasColor(stm)) return;
    if (position.isCastleLegalAssumeNoCheck(.a)) moves.push(position.kingSq(stm), position.castling.read(stm, .a), .castle_aside);
    if (position.isCastleLegalAssumeNoCheck(.h)) moves.push(position.kingSq(stm), position.castling.read(stm, .h), .castle_hside);
}

fn generateKingMoves(comptime subset: Subset, moves: *MoveList, position: *const Position) void {
    const stm = position.sideToMove();
    const danger = position.danger;
    const empty = position.occupiedSet().bitNot();
    const enemy = position.colorSet(stm.invert());

    const king = position.kingSq(stm);
    const safe_attacks = position.masked_attack_set[0].bitAndNot(danger);

    switch (subset) {
        .all => moves.pushSets(king, safe_attacks.bitAnd(empty), safe_attacks.bitAnd(enemy)),
        .noisy => moves.pushSet(king, safe_attacks.bitAnd(enemy), .cap_normal),
        .quiet => moves.pushSet(king, safe_attacks.bitAnd(empty), .normal),
    }
}

const Subset = enum {
    all,
    noisy,
    quiet,

    fn isNoisy(comptime self: Subset) bool {
        return self != .quiet;
    }

    fn isQuiet(comptime self: Subset) bool {
        return self != .noisy;
    }
};

const thorn = @import("../thorn.zig");
const attacks = thorn.attacks;
const Color = thorn.Color;
const Dir = thorn.Dir;
const Move = thorn.Move;
const MoveList = thorn.MoveList;
const PieceSet = thorn.PieceSet;
const Position = thorn.Position;
const Square = thorn.Square;
const SquareSet = thorn.SquareSet;
