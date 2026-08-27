pub fn all(moves: *MoveList, position: *const Position) void {
    return generateMoves(moves, position);
}

fn generateMoves(moves: *MoveList, position: *const Position) void {
    switch (position.checkers.popcount()) {
        0 => {
            generateEnpassant(moves, position);
            generateMostMoves(moves, position, SquareSet.all);
            generateCastling(moves, position);
            generateKingMoves(moves, position);
        },
        1 => {
            const checker = position.checkers.lsb();
            const king = position.kingSq(position.sideToMove());
            if (position.ptypeAt(checker) == .p) generateEnpassant(moves, position);
            generateMostMoves(moves, position, SquareSet.rayBetween(king, checker));
            generateKingMoves(moves, position);
        },
        else => generateKingMoves(moves, position),
    }
}

fn generateEnpassant(moves: *MoveList, position: *const Position) void {
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
            const enemy_rooks = position.coloredPtypeSet(stm.invert(), .r);
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

fn generateMostMoves(moves: *MoveList, position: *const Position, valid_destinations: SquareSet) void {
    const stm = position.sideToMove();
    const empty = position.occupiedSet().bitNot();
    const enemy = position.colorSet(stm.invert());
    const valid_empty = empty.bitAnd(valid_destinations);
    const valid_enemy = enemy.bitAnd(valid_destinations);

    const pawn_ids = position.whichAre(stm, .p);
    const non_pawn_ids = position.whichAre(stm, .none).bitOr(pawn_ids).bitOr(PieceSet.king).bitNot();

    splat(moves, position, pawn_ids, valid_enemy.bitAnd(SquareSet.promo_zone), .cap_promo);
    splat(moves, position, pawn_ids, valid_enemy.bitAndNot(SquareSet.promo_zone), .capture);
    splat(moves, position, non_pawn_ids, valid_enemy, .capture);
    splat(moves, position, non_pawn_ids, valid_empty, .normal);

    switch (stm) {
        .white => generatePawnPushes(moves, position, valid_destinations, .white),
        .black => generatePawnPushes(moves, position, valid_destinations, .black),
    }
}

fn splat(moves: *MoveList, position: *const Position, ids: PieceSet, valid_destinations: SquareSet, kind: enum { normal, capture, cap_promo }) void {
    const stm = position.sideToMove();

    var iter = ids.bitAnd(position.whichMaskedAttackTo(valid_destinations)).iter();
    while (iter.next()) |id| {
        const from = position.whereIs(stm, id);
        const to = position.masked_attack_set[id.toIndex()].bitAnd(valid_destinations);
        switch (kind) {
            .normal => moves.pushSet(from, to, .normal),
            .capture => moves.pushSet(from, to, .cap_normal),
            .cap_promo => {
                moves.pushSet(from, to, .cap_promo_q);
                moves.pushSet(from, to, .cap_promo_n);
                moves.pushSet(from, to, .cap_promo_r);
                moves.pushSet(from, to, .cap_promo_b);
            },
        }
    }
}

fn generatePawnPushes(moves: *MoveList, position: *const Position, valid_destinations: SquareSet, comptime stm: Color) void {
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

    if (home_single != 0) moves.pushPawnRank(home_base, home_single, push, .normal);
    if (home_double != 0) moves.pushPawnRank(home_base, home_double, double_push, .double_push);
    if (body != 0) moves.pushPawnBody(body, push);
    if (promoable != 0) {
        moves.pushPawnRank(promoable_base, promoable, push, .promo_q);
        moves.pushPawnRank(promoable_base, promoable, push, .promo_n);
        moves.pushPawnRank(promoable_base, promoable, push, .promo_r);
        moves.pushPawnRank(promoable_base, promoable, push, .promo_b);
    }
}

fn generateCastling(moves: *MoveList, position: *const Position) void {
    const stm = position.sideToMove();
    if (!position.castling.hasColor(stm)) return;
    if (position.isCastleLegal(.a)) moves.push(position.kingSq(stm), position.castling.read(stm, .a), .castle_aside);
    if (position.isCastleLegal(.h)) moves.push(position.kingSq(stm), position.castling.read(stm, .h), .castle_hside);
}

fn generateKingMoves(moves: *MoveList, position: *const Position) void {
    const stm = position.sideToMove();
    const danger = position.danger;
    const empty = position.occupiedSet().bitNot();
    const enemy = position.colorSet(stm.invert());

    const king = position.kingSq(stm);
    const safe_attacks = position.masked_attack_set[0].bitAndNot(danger);

    moves.pushSet(king, safe_attacks.bitAnd(enemy), .cap_normal);
    moves.pushSet(king, safe_attacks.bitAnd(empty), .normal);
}

const thorn = @import("root.zig");
const attacks = thorn.attacks;
const Color = thorn.Color;
const Dir = thorn.Dir;
const Move = thorn.Move;
const MoveList = thorn.MoveList;
const PieceSet = thorn.PieceSet;
const Position = thorn.Position;
const Square = thorn.Square;
const SquareSet = thorn.SquareSet;
