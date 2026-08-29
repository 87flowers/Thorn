attack_set: [2][16]SquareSet,

masked_attack_set: [16]SquareSet,
danger: SquareSet,
pinned: SquareSet,
checkers: SquareSet,

piece_mailbox: [64]Piece,
id_mailbox: [64]PieceId,

color_set: [2]SquareSet,
ptype_set: [6]SquareSet,

piece_list_sq: [2][16]Square,
piece_list_ptype: [2][16]PieceType,

enpassant: Square,
fifty_move_clock: u16,
ply_since_null: u16,
ply: u16,

castling: Castling,

pub const startpos = blk: {
    @setEvalBranchQuota(100_000);
    break :blk parse("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1") catch unreachable;
};
pub const kiwipete = blk: {
    @setEvalBranchQuota(100_000);
    break :blk parse("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1") catch unreachable;
};

pub fn colorSet(self: *const Position, color: Color) SquareSet {
    return self.color_set[color.toIndex()];
}

pub fn ptypeSet(self: *const Position, ptype: PieceType) SquareSet {
    return self.ptype_set[ptype.toIndex()];
}

pub fn coloredPtypeSet(self: *const Position, color: Color, ptype: PieceType) SquareSet {
    return self.color_set[color.toIndex()].bitAnd(self.ptype_set[ptype.toIndex()]);
}

pub fn sideToMove(self: *const Position) Color {
    return @enumFromInt(self.ply % 2);
}

pub fn turnClock(self: *const Position) u16 {
    return self.ply / 2 + 1;
}

pub fn kingSq(self: *const Position, color: Color) Square {
    return self.piece_list_sq[color.toIndex()][0];
}

pub fn occupiedSet(self: *const Position) SquareSet {
    return self.color_set[0].bitOr(self.color_set[1]);
}

// Naming convention:
// *At: takes a Square
// *Is/*Are: takes a (Color, PieceId)
// what*: returns Piece/PieceType
// which*: returns PieceId/PieceSet

pub fn whatAt(self: *const Position, sq: Square) Piece {
    return self.piece_mailbox[sq.toIndex()];
}

pub fn ptypeAt(self: *const Position, sq: Square) PieceType {
    return self.whatAt(sq).ptype();
}

pub fn colorAt(self: *const Position, sq: Square) Color {
    return self.whatAt(sq).color();
}

pub fn whichAt(self: *const Position, sq: Square) PieceId {
    return self.id_mailbox[sq.toIndex()];
}

pub fn whatIs(self: *const Position, color: Color, id: PieceId) PieceType {
    return self.piece_list_ptype[color.toIndex()][id.toIndex()];
}

pub fn whereIs(self: *const Position, color: Color, id: PieceId) Square {
    return self.piece_list_sq[color.toIndex()][id.toIndex()];
}

pub fn whichAre(self: *const Position, color: Color, ptype: PieceType) PieceSet {
    const v: @Vector(16, u8) = @bitCast(self.piece_list_ptype[color.toIndex()]);
    return PieceSet.make(@bitCast(v == ptype.splat(16)));
}

pub fn whichAreSlider(self: *const Position, color: Color) PieceSet {
    const v: @Vector(16, u8) = @bitCast(self.piece_list_ptype[color.toIndex()]);
    const needle: @Vector(16, u8) = @splat(PieceType.slider);
    const zero: @Vector(16, u8) = @splat(0);
    return PieceSet.make(@bitCast((v & needle) != zero));
}

pub fn whichAttackTo(self: *const Position, color: Color, dst: SquareSet) PieceSet {
    const v: @Vector(16, u64) = @bitCast(self.attack_set[color.toIndex()]);
    const bb: @Vector(16, u64) = @splat(dst.raw);
    const zero: @Vector(16, u64) = @splat(0);
    return PieceSet.make(@bitCast((v & bb) != zero));
}

pub fn whichMaskedAttackTo(self: *const Position, dst: SquareSet) PieceSet {
    const v: @Vector(16, u64) = @bitCast(self.masked_attack_set);
    const bb: @Vector(16, u64) = @splat(dst.raw);
    const zero: @Vector(16, u64) = @splat(0);
    return PieceSet.make(@bitCast((v & bb) != zero));
}

pub fn isCastleLegal(self: *const Position, comptime side: Castling.Side) bool {
    switch (self.sideToMove()) {
        inline else => |stm| {
            const rook = self.castling.read(stm, side);
            return rook.isSome() and self.checkers.isEmpty() and switch (side) {
                .a => self.isCastleLegalHelper(rook, .d, .c),
                .h => self.isCastleLegalHelper(rook, .f, .g),
            };
        },
    }
}

fn isCastleLegalHelper(self: *const Position, rook: Square, rook_dst: File, king_dst: File) bool {
    const stm = self.sideToMove();
    const king = self.kingSq(stm);

    const rook_ray = SquareSet.rayExclusiveInclusive(rook, Square.fromFileAndRank(rook_dst, king.rank()));
    const king_ray = SquareSet.rayExclusiveInclusive(king, Square.fromFileAndRank(king_dst, king.rank()));

    const empty = self.occupiedSet().bitNot();
    const danger = self.danger;
    const clear = empty.bitOr(rook.toSet()).bitOr(king.toSet());

    return rook_ray.bitAndNot(clear).isEmpty() and king_ray.bitAndNot(clear).isEmpty() and king_ray.bitAnd(danger).isEmpty() and !self.pinned.read(rook);
}

pub fn move(self: *const Position, m: Move) Position {
    var new_pos = self.*;
    new_pos.masked_attack_set = @splat(.empty);
    new_pos.danger = .empty;
    new_pos.pinned = .empty;
    new_pos.checkers = .empty;

    new_pos.enpassant = .none;

    const stm = self.sideToMove();
    const from = m.from();
    const to = m.to();
    const src_piece = self.whatAt(from);
    const dst_piece = self.whatAt(to);
    const src_id = self.whichAt(from);
    const dst_id = self.whichAt(to);

    switch (m.flags()) {
        .normal => {
            new_pos.removePiece(from, src_piece, src_id);
            new_pos.addPiece(to, src_piece, src_id);
            new_pos.castling.unset(from);
            if (src_piece.ptype() == .k) new_pos.castling.clear(stm);
            new_pos.fifty_move_clock = if (src_piece.ptype() == .p) 0 else new_pos.fifty_move_clock + 1;

            new_pos.updateAttacks(stm, src_id, src_piece.ptype(), to);
            new_pos.updateSliderAttacks(.white, self.whichAttackTo(.white, .set(.{ from, to })));
            new_pos.updateSliderAttacks(.black, self.whichAttackTo(.black, .set(.{ from, to })));
        },
        .cap_normal => {
            new_pos.removePiece(from, src_piece, src_id);
            new_pos.removePiece(to, dst_piece, dst_id);
            new_pos.addPiece(to, src_piece, src_id);
            new_pos.castling.unset(from);
            new_pos.castling.unset(to);
            if (src_piece.ptype() == .k) new_pos.castling.clear(stm);
            new_pos.fifty_move_clock = 0;

            new_pos.updateAttacks(stm, src_id, src_piece.ptype(), to);
            new_pos.removeAttacks(stm.invert(), dst_id);
            new_pos.updateSliderAttacks(.white, self.whichAttackTo(.white, .set(.{ from, to })));
            new_pos.updateSliderAttacks(.black, self.whichAttackTo(.black, .set(.{ from, to })));
        },
        .double_push => {
            new_pos.removePiece(from, src_piece, src_id);
            new_pos.addPiece(to, src_piece, src_id);
            new_pos.enpassant = to.toggleRankLsb();
            new_pos.fifty_move_clock = 0;

            new_pos.updateAttacks(stm, src_id, src_piece.ptype(), to);
            new_pos.updateSliderAttacks(.white, self.whichAttackTo(.white, .set(.{ from, to })));
            new_pos.updateSliderAttacks(.black, self.whichAttackTo(.black, .set(.{ from, to })));
        },
        .enpassant => {
            const victim = to.toggleRankLsb();
            const victim_id = self.whichAt(victim);
            new_pos.removePiece(from, src_piece, src_id);
            new_pos.removePiece(victim, Piece.make(stm.invert(), .p), victim_id);
            new_pos.addPiece(to, src_piece, src_id);
            new_pos.fifty_move_clock = 0;

            new_pos.updateAttacks(stm, src_id, src_piece.ptype(), to);
            new_pos.removeAttacks(stm.invert(), victim_id);
            new_pos.updateSliderAttacks(.white, self.whichAttackTo(.white, .set(.{ from, to, victim })));
            new_pos.updateSliderAttacks(.black, self.whichAttackTo(.black, .set(.{ from, to, victim })));
        },
        .castle_aside => {
            const king_src = from;
            const rook_src = to;
            const king_id = PieceId.king;
            const rook_id = dst_id;
            const king_dst = Square.fromFileAndRank(.c, king_src.rank());
            const rook_dst = Square.fromFileAndRank(.d, rook_src.rank());
            new_pos.removePiece(king_src, Piece.make(stm, .k), king_id);
            new_pos.removePiece(rook_src, Piece.make(stm, .r), rook_id);
            new_pos.addPiece(king_dst, Piece.make(stm, .k), king_id);
            new_pos.addPiece(rook_dst, Piece.make(stm, .r), rook_id);
            new_pos.castling.clear(stm);
            new_pos.fifty_move_clock += 1;

            new_pos.updateAttacks(stm, king_id, .k, king_dst);
            new_pos.updateAttacks(stm, rook_id, .r, rook_dst);
            new_pos.updateSliderAttacks(.white, self.whichAttackTo(.white, .set(.{ king_src, rook_src, king_dst, rook_dst })));
            new_pos.updateSliderAttacks(.black, self.whichAttackTo(.black, .set(.{ king_src, rook_src, king_dst, rook_dst })));
        },
        .castle_hside => {
            const king_src = from;
            const rook_src = to;
            const king_id = PieceId.king;
            const rook_id = dst_id;
            const king_dst = Square.fromFileAndRank(.g, king_src.rank());
            const rook_dst = Square.fromFileAndRank(.f, rook_src.rank());
            new_pos.removePiece(king_src, Piece.make(stm, .k), king_id);
            new_pos.removePiece(rook_src, Piece.make(stm, .r), rook_id);
            new_pos.addPiece(king_dst, Piece.make(stm, .k), king_id);
            new_pos.addPiece(rook_dst, Piece.make(stm, .r), rook_id);
            new_pos.castling.clear(stm);
            new_pos.fifty_move_clock += 1;

            new_pos.updateAttacks(stm, king_id, .k, king_dst);
            new_pos.updateAttacks(stm, rook_id, .r, rook_dst);
            new_pos.updateSliderAttacks(.white, self.whichAttackTo(.white, .set(.{ king_src, rook_src, king_dst, rook_dst })));
            new_pos.updateSliderAttacks(.black, self.whichAttackTo(.black, .set(.{ king_src, rook_src, king_dst, rook_dst })));
        },
        .promo_n => {
            new_pos.removePiece(from, src_piece, src_id);
            new_pos.addPiece(to, Piece.make(stm, .n), src_id);
            new_pos.fifty_move_clock = 0;

            new_pos.updateAttacks(stm, src_id, .n, to);
            new_pos.updateSliderAttacks(.white, self.whichAttackTo(.white, .set(.{ from, to })));
            new_pos.updateSliderAttacks(.black, self.whichAttackTo(.black, .set(.{ from, to })));
        },
        .promo_b => {
            new_pos.removePiece(from, src_piece, src_id);
            new_pos.addPiece(to, Piece.make(stm, .b), src_id);
            new_pos.fifty_move_clock = 0;

            new_pos.updateAttacks(stm, src_id, .b, to);
            new_pos.updateSliderAttacks(.white, self.whichAttackTo(.white, .set(.{ from, to })));
            new_pos.updateSliderAttacks(.black, self.whichAttackTo(.black, .set(.{ from, to })));
        },
        .promo_r => {
            new_pos.removePiece(from, src_piece, src_id);
            new_pos.addPiece(to, Piece.make(stm, .r), src_id);
            new_pos.fifty_move_clock = 0;

            new_pos.updateAttacks(stm, src_id, .r, to);
            new_pos.updateSliderAttacks(.white, self.whichAttackTo(.white, .set(.{ from, to })));
            new_pos.updateSliderAttacks(.black, self.whichAttackTo(.black, .set(.{ from, to })));
        },
        .promo_q => {
            new_pos.removePiece(from, src_piece, src_id);
            new_pos.addPiece(to, Piece.make(stm, .q), src_id);
            new_pos.fifty_move_clock = 0;

            new_pos.updateAttacks(stm, src_id, .q, to);
            new_pos.updateSliderAttacks(.white, self.whichAttackTo(.white, .set(.{ from, to })));
            new_pos.updateSliderAttacks(.black, self.whichAttackTo(.black, .set(.{ from, to })));
        },
        .cap_promo_n => {
            new_pos.removePiece(from, src_piece, src_id);
            new_pos.removePiece(to, dst_piece, dst_id);
            new_pos.addPiece(to, Piece.make(stm, .n), src_id);
            new_pos.castling.unset(to);
            new_pos.fifty_move_clock = 0;

            new_pos.updateAttacks(stm, src_id, .n, to);
            new_pos.removeAttacks(stm.invert(), dst_id);
            new_pos.updateSliderAttacks(.white, self.whichAttackTo(.white, .set(.{ from, to })));
            new_pos.updateSliderAttacks(.black, self.whichAttackTo(.black, .set(.{ from, to })));
        },
        .cap_promo_b => {
            new_pos.removePiece(from, src_piece, src_id);
            new_pos.removePiece(to, dst_piece, dst_id);
            new_pos.addPiece(to, Piece.make(stm, .b), src_id);
            new_pos.castling.unset(to);
            new_pos.fifty_move_clock = 0;

            new_pos.updateAttacks(stm, src_id, .b, to);
            new_pos.removeAttacks(stm.invert(), dst_id);
            new_pos.updateSliderAttacks(.white, self.whichAttackTo(.white, .set(.{ from, to })));
            new_pos.updateSliderAttacks(.black, self.whichAttackTo(.black, .set(.{ from, to })));
        },
        .cap_promo_r => {
            new_pos.removePiece(from, src_piece, src_id);
            new_pos.removePiece(to, dst_piece, dst_id);
            new_pos.addPiece(to, Piece.make(stm, .r), src_id);
            new_pos.castling.unset(to);
            new_pos.fifty_move_clock = 0;

            new_pos.updateAttacks(stm, src_id, .r, to);
            new_pos.removeAttacks(stm.invert(), dst_id);
            new_pos.updateSliderAttacks(.white, self.whichAttackTo(.white, .set(.{ from, to })));
            new_pos.updateSliderAttacks(.black, self.whichAttackTo(.black, .set(.{ from, to })));
        },
        .cap_promo_q => {
            new_pos.removePiece(from, src_piece, src_id);
            new_pos.removePiece(to, dst_piece, dst_id);
            new_pos.addPiece(to, Piece.make(stm, .q), src_id);
            new_pos.castling.unset(to);
            new_pos.fifty_move_clock = 0;

            new_pos.updateAttacks(stm, src_id, .q, to);
            new_pos.removeAttacks(stm.invert(), dst_id);
            new_pos.updateSliderAttacks(.white, self.whichAttackTo(.white, .set(.{ from, to })));
            new_pos.updateSliderAttacks(.black, self.whichAttackTo(.black, .set(.{ from, to })));
        },
    }

    new_pos.ply += 1;

    new_pos.recalculateDanger();

    return new_pos;
}

fn removePiece(self: *Position, sq: Square, piece: Piece, id: PieceId) void {
    const s = sq.toIndex();
    const c = piece.color().toIndex();
    const pt = piece.ptype().toIndex();
    const i = id.toIndex();
    self.piece_mailbox[s] = .none;
    self.id_mailbox[s] = .none;
    self.color_set[c].write(sq, false);
    self.ptype_set[pt].write(sq, false);
    self.piece_list_sq[c][i] = .none;
    self.piece_list_ptype[c][i] = .none;
}

fn addPiece(self: *Position, sq: Square, piece: Piece, id: PieceId) void {
    const s = sq.toIndex();
    const c = piece.color().toIndex();
    const pt = piece.ptype().toIndex();
    const i = id.toIndex();
    self.piece_mailbox[s] = piece;
    self.id_mailbox[s] = id;
    self.color_set[c].write(sq, true);
    self.ptype_set[pt].write(sq, true);
    self.piece_list_sq[c][i] = sq;
    self.piece_list_ptype[c][i] = piece.ptype();
}

fn updateAttacks(self: *Position, color: Color, id: PieceId, ptype: PieceType, sq: Square) void {
    self.attack_set[color.toIndex()][id.toIndex()] = attacks.ptype(ptype, self.occupiedSet(), sq, color);
}

fn removeAttacks(self: *Position, color: Color, id: PieceId) void {
    self.attack_set[color.toIndex()][id.toIndex()] = .empty;
}

fn updateSliderAttacks(self: *Position, color: Color, ids: PieceSet) void {
    const occ = self.occupiedSet();
    var iter = ids.bitAnd(self.whichAreSlider(color)).iter();
    while (iter.next()) |id| {
        const sq = self.whereIs(color, id);
        const ptype = self.whatIs(color, id);
        self.attack_set[color.toIndex()][id.toIndex()] = attacks.ptype(ptype, occ, sq, color);
    }
}

// Caller has ownership of string
pub fn parse(str: []const u8) !Position {
    var it = std.mem.tokenizeAny(u8, str, " \t\r\n");
    const board_str = it.next() orelse return ParseError.InvalidLength;
    const color_str = it.next() orelse return ParseError.InvalidLength;
    const castle_str = it.next() orelse return ParseError.InvalidLength;
    const enpassant_str = it.next() orelse return ParseError.InvalidLength;
    const fifty_move_clock_str = it.next() orelse return ParseError.InvalidLength;
    const turns_str = it.next() orelse return ParseError.InvalidLength;
    if (it.next() != null) return ParseError.InvalidLength;
    return parseParts(board_str, color_str, castle_str, enpassant_str, fifty_move_clock_str, turns_str);
}

// Caller has ownership of all strings
pub fn parseParts(board_str: []const u8, color_str: []const u8, castle_str: []const u8, enpassant_str: []const u8, fifty_move_clock_str: []const u8, turns_str: []const u8) !Position {
    var position: Position = .{
        .attack_set = @splat(@splat(.empty)),
        .masked_attack_set = @splat(.empty),
        .danger = .empty,
        .pinned = .empty,
        .checkers = .empty,
        .piece_mailbox = @splat(.none),
        .id_mailbox = @splat(.none),
        .color_set = @splat(.empty),
        .ptype_set = @splat(.empty),
        .piece_list_sq = @splat(@splat(.none)),
        .piece_list_ptype = @splat(@splat(.none)),
        .enpassant = .none,
        .fifty_move_clock = 0,
        .ply_since_null = 0,
        .ply = 0,
        .castling = Castling.empty,
    };

    // Parse board
    {
        var next_id: [2]u8 = .{ 1, 1 };
        var i: usize = 0;
        var file: u8 = 0;
        var rank: u8 = 7;
        while (rank >= 0 and i < board_str.len) : (i += 1) {
            switch (board_str[i]) {
                '/' => {
                    if (file != 8 or rank == 0) return ParseError.InvalidBoard;
                    rank -= 1;
                    file = 0;
                },
                '1', '2', '3', '4', '5', '6', '7', '8' => |ch| {
                    file += ch - '0';
                    if (file > 8) return ParseError.InvalidBoard;
                },
                else => |ch| {
                    if (file >= 8) return ParseError.InvalidBoard;

                    const sq = Square.fromFileAndRank(.fromIndex(file), .fromIndex(rank));
                    const piece = try Piece.parse(ch);
                    const color = piece.color();
                    const ptype = piece.ptype();
                    const id = blk: {
                        if (piece.ptype() == .k) {
                            if (position.piece_list_sq[color.toIndex()][0].isSome()) return ParseError.TooManyKings;
                            break :blk 0;
                        }
                        const id = next_id[color.toIndex()];
                        if (id >= 16) return ParseError.TooManyPieces;
                        next_id[color.toIndex()] += 1;
                        break :blk id;
                    };

                    position.piece_mailbox[sq.toIndex()] = piece;
                    position.id_mailbox[sq.toIndex()] = @enumFromInt(id);
                    position.color_set[color.toIndex()].write(sq, true);
                    position.ptype_set[ptype.toIndex()].write(sq, true);
                    position.piece_list_sq[color.toIndex()][id] = sq;
                    position.piece_list_ptype[color.toIndex()][id] = ptype;

                    file += 1;
                },
            }
        }

        if (rank != 0 or file != 8 or i != board_str.len) return ParseError.InvalidLength;
        if (position.piece_list_ptype[0][0] != .k) return ParseError.InvalidBoard;
        if (position.piece_list_ptype[1][0] != .k) return ParseError.InvalidBoard;
    }

    // Parse color
    if (color_str.len != 1) return ParseError.InvalidLength;
    const stm = try Color.parse(color_str[0]);

    // Parse castling
    if (!std.mem.eql(u8, castle_str, "-")) {
        for (castle_str) |ch| {
            const color: Color, const file: File = blk: {
                const color: Color, var f: i8, const dir: i8 = switch (ch) {
                    // Scan required
                    'Q' => .{ .white, 0, 1 },
                    'K' => .{ .white, 7, -1 },
                    'q' => .{ .black, 0, 1 },
                    'k' => .{ .black, 7, -1 },
                    // Scanning not required, location directly specified
                    'A'...'H' => break :blk .{ .white, .fromIndex(ch - 'A') },
                    'a'...'h' => break :blk .{ .black, .fromIndex(ch - 'a') },
                    // Invalid
                    else => return ParseError.InvalidChar,
                };

                // Scan for rook
                while (f >= 0 and f <= 7) : (f += dir) {
                    const file: File = .fromIndex(@intCast(f));
                    const sq = Square.fromFileAndRank(file, color.homeRank());
                    const piece = position.piece_mailbox[sq.toIndex()];
                    if (piece.color() == color and piece.ptype() == .r)
                        break :blk .{ color, file };
                    if (piece.color() == color and piece.ptype() == .k)
                        return ParseError.InvalidBoard;
                }
                return ParseError.InvalidBoard;
            };

            const rook_sq = Square.fromFileAndRank(file, color.homeRank());
            const king_sq = position.piece_list_sq[color.toIndex()][0];

            const maybe_rook = position.piece_mailbox[rook_sq.toIndex()];

            if (maybe_rook.color() != color or maybe_rook.ptype() != .r) return ParseError.InvalidBoard;
            if (king_sq.rank() != color.homeRank()) return ParseError.InvalidBoard;

            if (rook_sq.file().toIndex() < king_sq.file().toIndex()) position.castling.write(color, .a, rook_sq);
            if (rook_sq.file().toIndex() > king_sq.file().toIndex()) position.castling.write(color, .h, rook_sq);
        }
    }

    // Parse enpassant square
    if (!std.mem.eql(u8, enpassant_str, "-"))
        position.enpassant = try Square.parse(enpassant_str);

    // Parse fifty move clock
    position.fifty_move_clock = try std.fmt.parseUnsigned(u8, fifty_move_clock_str, 10);
    if (position.fifty_move_clock > 100) return ParseError.OutOfRange;

    // Parse turns
    const turns = try std.fmt.parseUnsigned(u16, turns_str, 10);
    if (turns == 0 or turns > 10000) return ParseError.OutOfRange;
    position.ply = (turns - 1) * 2 + @as(u16, @intCast(stm.toIndex()));

    position.recalculateAttacks();
    position.recalculateDanger();

    return position;
}

pub fn format(self: *const Position, writer: *std.Io.Writer) !void {
    var blanks: u32 = 0;
    for (0..64) |i| {
        const piece = self.piece_mailbox[i ^ 0b111000];

        if (piece.isNone()) {
            blanks += 1;
        } else {
            if (blanks != 0) {
                try writer.print("{}", .{blanks});
                blanks = 0;
            }
            try writer.print("{f}", .{piece});
        }

        if (i % 8 == 7) {
            if (blanks != 0) {
                try writer.print("{}", .{blanks});
                blanks = 0;
            }
            if (i != 63) try writer.print("/", .{});
        }
    }
    try writer.print(" {f}", .{self.sideToMove()});

    try writer.print(" ", .{});
    if (self.castling.isEmpty()) {
        try writer.print("-", .{});
    } else {
        const is_classical = self.castling.maybeClassical() and
            (if (self.castling.hasColor(.white)) self.kingSq(.white) == .e1 else true) and
            (if (self.castling.hasColor(.black)) self.kingSq(.black) == .e8 else true);

        if (is_classical) {
            if (self.castling.read(.white, .h).isSome()) try writer.print("K", .{});
            if (self.castling.read(.white, .a).isSome()) try writer.print("Q", .{});
            if (self.castling.read(.black, .h).isSome()) try writer.print("k", .{});
            if (self.castling.read(.black, .a).isSome()) try writer.print("q", .{});
        } else {
            inline for ([_]Castling.Side{ .h, .a }) |side| {
                const sq = self.castling.read(.white, side);
                if (sq.isSome()) try writer.print("{c}", .{sq.file().toUpperChar()});
            }
            inline for ([_]Castling.Side{ .h, .a }) |side| {
                const sq = self.castling.read(.black, side);
                if (sq.isSome()) try writer.print("{c}", .{sq.file().toLowerChar()});
            }
        }
    }

    try if (self.enpassant.isNone()) writer.print(" -", .{}) else writer.print(" {f}", .{self.enpassant});
    try writer.print(" {}", .{self.fifty_move_clock});
    try writer.print(" {}", .{self.turnClock()});
}

fn recalculateAttacks(self: *Position) void {
    const occ = self.occupiedSet();
    for ([_]Color{ .white, .black }) |color| {
        for (0..16) |id| {
            const ptype = self.piece_list_ptype[color.toIndex()][id];
            const sq = self.piece_list_sq[color.toIndex()][id];
            self.attack_set[color.toIndex()][id] = attacks.ptype(ptype, occ, sq, color);
        }
    }
}

fn recalculateDanger(self: *Position) void {
    const stm = self.sideToMove();

    const king = self.kingSq(stm);
    const friend = self.colorSet(stm);
    const enemy = self.colorSet(stm.invert());
    const diagonal = enemy.bitAnd(self.ptypeSet(.b).bitOr(self.ptypeSet(.q))).bitAnd(attacks.bishop(enemy, king));
    const orthogonal = enemy.bitAnd(self.ptypeSet(.r).bitOr(self.ptypeSet(.q))).bitAnd(attacks.rook(enemy, king));

    self.pinned = .empty;
    self.checkers = .empty;
    self.masked_attack_set = self.attack_set[stm.toIndex()];

    var potential_pinners = diagonal.bitOr(orthogonal).iter();
    while (potential_pinners.next()) |sq| {
        const pin_ray = SquareSet.rayExclusiveInclusive(king, sq);
        const blockers = pin_ray.bitAnd(friend);
        switch (blockers.popcount()) {
            0 => self.checkers.write(sq, true),
            1 => {
                const id = self.id_mailbox[blockers.lsb().toIndex()];
                self.masked_attack_set[id.toIndex()].applyMask(pin_ray);
                self.pinned.insert(blockers);
            },
            else => {},
        }
    }

    // TODO: Vectorize
    self.danger = .empty;
    for (0..16) |i| {
        self.danger = self.danger.bitOr(self.attack_set[stm.invert().toIndex()][i]);
    }
    var checkers_iter = self.checkers.iter();
    while (checkers_iter.next()) |checker| {
        self.danger = self.danger.bitOr(SquareSet.rayPast(checker, king));
    }

    // TODO: Consider doing checkers as PieceSet instead of SquareSet
    // Alternatively consider implementing isInCheck as a danger read and checkerCount as a count.
    // This is done after the self.danger bit because these checkers are not sliders and thus should not have danger extension.
    self.checkers.insert(attacks.knight(king).bitAnd(self.coloredPtypeSet(stm.invert(), .n)));
    self.checkers.insert(attacks.pawn(king, stm).bitAnd(self.coloredPtypeSet(stm.invert(), .p)));
}

pub const Castling = struct {
    raw: @Vector(4, u8),

    pub const empty: Castling = .{ .raw = @splat(@intFromEnum(Square.none)) };

    pub fn isEmpty(self: Castling) bool {
        return @reduce(.And, self.raw == empty.raw);
    }

    // Determine if castleable rooks are in classical starting position.
    pub fn maybeClassical(self: Castling) bool {
        const classical_full = @Vector(4, u8){
            @intFromEnum(Square.a1),
            @intFromEnum(Square.h1),
            @intFromEnum(Square.a8),
            @intFromEnum(Square.h8),
        };
        return @reduce(.And, (self.raw == classical_full) | (self.raw == empty.raw));
    }

    pub fn read(self: Castling, color: Color, side: Side) Square {
        return switch (color.toIndex() * 2 + @intFromEnum(side)) {
            inline 0, 1, 2, 3 => |x| @enumFromInt(self.raw[x]),
            else => unreachable,
        };
    }

    pub fn write(self: *Castling, color: Color, side: Side, sq: Square) void {
        switch (color.toIndex() * 2 + @intFromEnum(side)) {
            inline 0, 1, 2, 3 => |x| self.raw[x] = @intFromEnum(sq),
            else => unreachable,
        }
    }

    pub fn clear(self: *Castling, color: Color) void {
        switch (color.toIndex()) {
            inline 0, 1 => |c| {
                self.raw[c * 2 + 0] = @intFromEnum(Square.none);
                self.raw[c * 2 + 1] = @intFromEnum(Square.none);
            },
            else => unreachable,
        }
    }

    pub fn unset(self: *Castling, sq: Square) void {
        const needle: @Vector(4, u8) = @splat(@intFromEnum(sq));
        self.raw = @select(u8, self.raw == needle, empty.raw, self.raw);
    }

    pub fn hasColor(self: Castling, color: Color) bool {
        assert(@intFromEnum(Square.none) == 0x80);
        const x: [2]u16 = @bitCast(self.raw);
        return x[color.toIndex()] != 0x8080;
    }

    pub fn hasSquare(self: Castling, sq: Square) bool {
        const needle: @Vector(4, u8) = @splat(@intFromEnum(sq));
        return @reduce(.Or, self.raw == needle);
    }

    pub fn toIndex(self: Castling) u4 {
        assert(@intFromEnum(Square.none) == 0x80);
        return @bitCast((self.raw & empty.raw) == empty.raw);
    }

    pub const Side = enum(usize) { a = 0, h = 1 };
};

test "roundtrip fens" {
    const cases = [_][]const u8{
        "7r/3r1p1p/6p1/1p6/2B5/5PP1/1Q5P/1K1k4 b - - 0 38",
        "2n1r1n1/1p1k1p2/6pp/R2pP3/3P4/8/5PPP/2R3K1 b - - 0 30",
        "8/5p2/1kn1r1n1/1p1pP3/6K1/8/4R3/5R2 b - - 9 60",
        "r3k2r/pp1bnpbp/1q3np1/3p4/3N1P2/1PP1Q2P/P1B3P1/RNB1K2R b KQkq - 5 15",
        "7r/3r1p1p/6p1/1p6/2B5/5PP1/1Q5P/1K1k4 b - - 0 38",
        "r3k2r/pp1bnpbp/1q3np1/3p4/3N1P2/1PP1Q2P/P1B3P1/RNB1K2R b KQkq - 5 15",
        "8/5p2/1kn1r1n1/1p1pP3/6K1/8/4R3/5R2 b - - 9 60",
        "r4rk1/1Bp1qppp/2np1n2/1pb1p1B1/4P1b1/P1NP1N2/1PP1QPPP/R4RK1 b - b6 1 11",
        "2r1kr2/8/8/8/8/8/8/1R2K1R1 w GBfc - 0 1",
        "rkr5/8/8/8/8/8/8/5RKR w HFca - 0 1",
        "2r3kr/8/8/8/8/8/8/2KRR3 w h - 3 2",
        "5rkr/8/8/8/8/8/8/RKR5 w CAhf - 0 1",
        "3rkr2/8/8/8/8/8/8/R3K2R w HAfd - 0 1",
        "4k3/8/8/8/8/8/8/4KR2 w F - 0 1",
        "4kr2/8/8/8/8/8/8/4K3 w f - 0 1",
        "4k3/8/8/8/8/8/8/2R1K3 w C - 0 1",
        "2r1k3/8/8/8/8/8/8/4K3 w c - 0 1",
    };
    for (cases) |case| {
        const position = try Position.parse(case);
        var tmp: [128]u8 = undefined;
        const fen = try std.fmt.bufPrint(&tmp, "{f}", .{position});
        try std.testing.expectEqualStrings(case, fen);
    }
}

const Position = @This();
const std = @import("std");
const assert = std.debug.assert;
const thorn = @import("root.zig");
const attacks = thorn.attacks;
const Color = thorn.Color;
const File = thorn.File;
const Move = thorn.Move;
const ParseError = thorn.ParseError;
const Piece = thorn.Piece;
const PieceId = thorn.PieceId;
const PieceSet = thorn.PieceSet;
const PieceType = thorn.PieceType;
const Square = thorn.Square;
const SquareSet = thorn.SquareSet;
