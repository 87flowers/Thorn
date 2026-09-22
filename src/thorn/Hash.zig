pub const Hash = enum(u64) {
    empty = 0,
    _,

    pub fn fromPosition(position: *const Position) Hash {
        var hash: Hash = .empty;
        for (0..64) |i| {
            const sq: Square = .fromIndex(@intCast(i));
            const piece = position.whatAt(sq);
            if (piece.isSome()) hash.togglePiece(piece, sq);
        }
        if (position.enpassant.isSome()) hash.toggleEnpassant(position.enpassant);
        if (position.sideToMove() == .black) hash.toggleStm();
        hash.toggleCastling(position.castling.toIndex());
        return hash;
    }

    pub fn move(self: Hash, position: *const Position, m: Move) Hash {
        var new_hash = self;
        var new_castling = position.castling;

        if (position.enpassant.isSome()) new_hash.toggleEnpassant(position.enpassant);

        const stm = position.sideToMove();
        const from = m.from();
        const to = m.to();
        const src_piece = position.whatAt(from);
        const dst_piece = position.whatAt(to);

        switch (m.flags()) {
            .normal => {
                new_hash.togglePiece(src_piece, from);
                new_hash.togglePiece(src_piece, to);
                new_castling.unset(from);
                if (src_piece.ptype() == .k) new_castling.clear(stm);
            },
            .cap_normal => {
                new_hash.togglePiece(src_piece, from);
                new_hash.togglePiece(src_piece, to);
                new_hash.togglePiece(dst_piece, to);
                new_castling.unset(from);
                new_castling.unset(to);
                if (src_piece.ptype() == .k) new_castling.clear(stm);
            },
            .double_push => {
                new_hash.togglePtype(stm, .p, from);
                new_hash.togglePtype(stm, .p, to);
                new_hash.toggleEnpassant(to.toggleRankLsb());
            },
            .enpassant => {
                new_hash.togglePtype(stm, .p, from);
                new_hash.togglePtype(stm, .p, to);
                new_hash.togglePtype(stm.invert(), .p, to.toggleRankLsb());
            },
            .castle_aside => {
                const king_src = from;
                const rook_src = to;
                const king_dst = Square.fromFileAndRank(.c, king_src.rank());
                const rook_dst = Square.fromFileAndRank(.d, rook_src.rank());
                new_hash.togglePtype(stm, .k, king_src);
                new_hash.togglePtype(stm, .r, rook_src);
                new_hash.togglePtype(stm, .k, king_dst);
                new_hash.togglePtype(stm, .r, rook_dst);
                new_castling.clear(stm);
            },
            .castle_hside => {
                const king_src = from;
                const rook_src = to;
                const king_dst = Square.fromFileAndRank(.g, king_src.rank());
                const rook_dst = Square.fromFileAndRank(.f, rook_src.rank());
                new_hash.togglePtype(stm, .k, king_src);
                new_hash.togglePtype(stm, .r, rook_src);
                new_hash.togglePtype(stm, .k, king_dst);
                new_hash.togglePtype(stm, .r, rook_dst);
                new_castling.clear(stm);
            },
            .promo_n => {
                new_hash.togglePtype(stm, .p, from);
                new_hash.togglePtype(stm, .n, to);
            },
            .promo_b => {
                new_hash.togglePtype(stm, .p, from);
                new_hash.togglePtype(stm, .b, to);
            },
            .promo_r => {
                new_hash.togglePtype(stm, .p, from);
                new_hash.togglePtype(stm, .r, to);
            },
            .promo_q => {
                new_hash.togglePtype(stm, .p, from);
                new_hash.togglePtype(stm, .q, to);
            },
            .cap_promo_n => {
                new_hash.togglePtype(stm, .p, from);
                new_hash.togglePtype(stm, .n, to);
                new_hash.togglePiece(dst_piece, to);
                new_castling.unset(to);
            },
            .cap_promo_b => {
                new_hash.togglePtype(stm, .p, from);
                new_hash.togglePtype(stm, .b, to);
                new_hash.togglePiece(dst_piece, to);
                new_castling.unset(to);
            },
            .cap_promo_r => {
                new_hash.togglePtype(stm, .p, from);
                new_hash.togglePtype(stm, .r, to);
                new_hash.togglePiece(dst_piece, to);
                new_castling.unset(to);
            },
            .cap_promo_q => {
                new_hash.togglePtype(stm, .p, from);
                new_hash.togglePtype(stm, .q, to);
                new_hash.togglePiece(dst_piece, to);
                new_castling.unset(to);
            },
        }

        new_hash.toggleCastling(position.castling.toIndex());
        new_hash.toggleCastling(new_castling.toIndex());
        new_hash.toggleStm();

        return new_hash;
    }

    pub fn togglePiece(self: *Hash, piece: Piece, sq: Square) void {
        self.togglePtype(piece.color(), piece.ptype(), sq);
    }

    pub fn togglePtype(self: *Hash, color: Color, ptype: PieceType, sq: Square) void {
        self.toggle(@enumFromInt(hash_tables.piece[color.toIndex()][ptype.toIndex()][sq.toIndex()]));
    }

    pub fn toggleEnpassant(self: *Hash, sq: Square) void {
        self.toggle(@enumFromInt(hash_tables.enpassant[sq.toIndex()]));
    }

    pub fn toggleCastling(self: *Hash, index: u4) void {
        assert(index < hash_tables.castle.len);
        self.toggle(@enumFromInt(hash_tables.castle[index]));
    }

    pub fn toggleStm(self: *Hash) void {
        self.toggle(@enumFromInt(hash_tables.stm));
    }

    fn toggle(self: *Hash, other: Hash) void {
        self.* = @enumFromInt(@intFromEnum(self.*) ^ @intFromEnum(other));
    }
};

const std = @import("std");
const assert = std.debug.assert;
const hash_tables = @import("hash_tables");
const thorn = @import("../thorn.zig");
const Color = thorn.Color;
const Move = thorn.Move;
const Piece = thorn.Piece;
const PieceType = thorn.PieceType;
const Position = thorn.Position;
const Square = thorn.Square;
