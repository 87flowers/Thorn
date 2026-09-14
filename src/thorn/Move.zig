pub const Move = packed struct {
    raw: u16,

    pub const none = Square{ .raw = 0 };

    pub const Flags = enum(u16) {
        normal = 0x0000,
        double_push = 0x1000,
        castle_aside = 0x2000, // classical: queen-side
        castle_hside = 0x3000, // classical: king-side
        promo_n = 0x4000,
        promo_b = 0x5000,
        promo_r = 0x6000,
        promo_q = 0x7000,
        cap_normal = 0x8000,
        enpassant = 0x9000,
        cap_promo_n = 0xC000,
        cap_promo_b = 0xD000,
        cap_promo_r = 0xE000,
        cap_promo_q = 0xF000,
    };

    pub fn make(f: Square, t: Square, fl: Flags) Move {
        return .{ .raw = @as(u16, @intFromEnum(f)) | @as(u16, @intFromEnum(t)) << 6 | @intFromEnum(fl) };
    }

    pub fn from(self: Move) Square {
        return Square.fromIndex(@intCast(self.raw & 0x3F));
    }

    pub fn to(self: Move) Square {
        return Square.fromIndex(@intCast((self.raw >> 6) & 0x3F));
    }

    pub fn flags(self: Move) Flags {
        return @enumFromInt(self.raw & 0xF000);
    }

    pub fn isNone(self: Move) bool {
        return self.raw == 0;
    }

    pub fn isSome(self: Move) bool {
        return self.raw != 0;
    }

    pub fn isNoisy(self: Move) bool {
        return self.raw >= 0x7000;
    }

    pub fn isQuiet(self: Move) bool {
        return self.raw > 0 and self.raw < 0x7000;
    }

    pub fn isCapture(self: Move) bool {
        return (self.raw & 0x8000) != 0;
    }

    pub fn isPromo(self: Move) bool {
        return (self.raw & 0x4000) != 0;
    }

    pub fn promo(self: Move) PieceType {
        const index = (self.raw & 0x3000) >> 12;
        return @enumFromInt(@intFromEnum(PieceType.n) << @intCast(index));
    }

    pub fn isCastle(self: Move) bool {
        return (self.raw & 0xE000) == 0x2000;
    }

    pub fn isEnpassant(self: Move) bool {
        return self.flags() == .enpassant;
    }

    pub fn isDoublePush(self: Move) bool {
        return self.flags() == .double_push;
    }

    pub fn parse(str: []const u8, context: *const Position) ParseError!Move {
        if (str.len < 4 or str.len > 5) return ParseError.InvalidLength;

        const f = try Square.parse(str[0..2]);
        const t = try Square.parse(str[2..4]);
        const ptype = context.ptypeAt(f);
        const capture = context.whatAt(t).isSome();

        if (str.len == 4) {
            if (ptype == .p) {
                if (context.enpassant == t) return Move.make(f, t, .enpassant);
                if ((f.rank().toIndex() ^ t.rank().toIndex()) == 2) return Move.make(f, t, .double_push);
            }
            if (ptype == .k and context.castling.hasSquare(t)) {
                if (context.castling.read(context.sideToMove(), .a) == t) return Move.make(f, t, .castle_aside);
                if (context.castling.read(context.sideToMove(), .h) == t) return Move.make(f, t, .castle_hside);
                if (f.file() == .e and t.file() == .c) return Move.make(f, t, .castle_aside);
                if (f.file() == .e and t.file() == .g) return Move.make(f, t, .castle_hside);
            }
            return Move.make(f, t, if (capture) .cap_normal else .normal);
        }

        return Move.make(f, t, switch (str[4]) {
            'q' => if (capture) .cap_promo_q else .promo_q,
            'r' => if (capture) .cap_promo_r else .promo_r,
            'b' => if (capture) .cap_promo_b else .promo_b,
            'n' => if (capture) .cap_promo_n else .promo_n,
            else => return ParseError.InvalidChar,
        });
    }

    pub fn toString(self: Move, format: MoveFormat) StaticVec(u8, 5) {
        var result: StaticVec(u8, 5) = .new();

        result.push(self.from().file().toChar());
        result.push(self.from().rank().toChar());
        result.push(blk: {
            const original = self.to().file();
            if (format == .classical and self.isCastle()) {
                if (self.flags() == .castle_aside and original == .a) break :blk 'c';
                if (self.flags() == .castle_hside and original == .h) break :blk 'g';
            }
            break :blk original.toChar();
        });
        result.push(self.to().rank().toChar());
        if (self.isPromo()) result.push(self.promo().toChar());

        return result;
    }

    test {
        try std.testing.expectEqual(PieceType.r, make(try Square.parse("d7"), try Square.parse("d8"), Flags.promo_r).promo());
    }
};

const std = @import("std");
const assert = std.debug.assert;
const thorn = @import("../thorn.zig");
const MoveFormat = thorn.MoveFormat;
const ParseError = thorn.ParseError;
const PieceType = thorn.PieceType;
const Position = thorn.Position;
const Square = thorn.Square;
const StaticVec = thorn.util.StaticVec;
