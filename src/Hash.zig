pub const Hash = enum(u64) {
    empty = 0,
    _,

    pub fn fromPosition(position: *const Position) Hash {
        var hash: Hash = .empty;
        for (0..64) |i| {
            const sq: Square = .fromIndex(i);
            const piece = position.whatAt(sq);
            hash.togglePiece(piece, sq);
        }
        if (position.enpassant.isSome()) hash.toggleEnpassant(position.enpassant);
        if (position.sideToMove() == .black) hash.toggleStm();
        hash.toggleCastling(position.castling.toIndex());
        return hash;
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
const thorn = @import("root.zig");
const Color = thorn.Color;
const Piece = thorn.Piece;
const PieceType = thorn.PieceType;
const Position = thorn.Position;
const Square = thorn.Square;
