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

pub fn toString(self: Move, format: MoveFormat) StaticVec(u8, 5) {
    var result: StaticVec(u8, 5) = .new();

    result.push('a' + self.from().file());
    result.push('1' + self.from().rank());
    result.push(blk: {
        const original = self.to().file();
        if (format == .classical and self.isCastle()) {
            if (self.flags() == .castle_aside and original == 0) break :blk 'c';
            if (self.flags() == .castle_hside and original == 7) break :blk 'g';
        }
        break :blk 'a' + original;
    });
    result.push('1' + self.to().rank());
    if (self.isPromo()) result.push(self.promo().toChar());

    return result;
}

test {
    try std.testing.expectEqual(PieceType.r, make(try Square.parse("d7"), try Square.parse("d8"), Flags.promo_r).promo());
}

const Move = @This();
const std = @import("std");
const assert = std.debug.assert;
const thorn = @import("root.zig");
const MoveFormat = thorn.MoveFormat;
const PieceType = thorn.PieceType;
const Square = thorn.Square;
const StaticVec = thorn.util.StaticVec;
