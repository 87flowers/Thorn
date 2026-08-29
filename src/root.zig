pub const attacks = @import("attacks.zig");
pub const movegen = @import("movegen.zig");
pub const util = @import("util.zig");
pub const Move = @import("Move.zig");
pub const MoveList = @import("MoveList.zig");
pub const PieceSet = @import("PieceSet.zig");
pub const Position = @import("Position.zig");
pub const SquareSet = @import("SquareSet.zig").SquareSet;

pub const ParseError = error{
    InvalidChar,
    InvalidLength,
    ColorViolation,
    OutOfRange,
    InvalidBoard,
    TooManyKings,
    TooManyPieces,
};

pub const MoveFormat = enum {
    classical,
    frc,
};

pub const Color = enum(u1) {
    white = 0,
    black = 1,

    pub fn invert(self: Color) Color {
        return @enumFromInt(@intFromEnum(self) ^ 1);
    }

    pub fn homeRank(self: Color) Rank {
        return switch (self) {
            .white => .first,
            .black => .eighth,
        };
    }

    pub fn toIndex(self: Color) usize {
        return @intFromEnum(self);
    }

    pub fn toChar(self: Color) u8 {
        return "wb"[self.toIndex()];
    }

    pub fn parse(ch: u8) ParseError!Color {
        return switch (ch) {
            'w' => .white,
            'b' => .black,
            else => ParseError.InvalidChar,
        };
    }

    pub fn format(self: Color, writer: *std.Io.Writer) !void {
        try writer.print("{c}", .{self.toChar()});
    }
};

pub const PieceType = enum(u8) {
    none = 0,
    p = 0b000001,
    n = 0b000010,
    b = 0b000100,
    r = 0b001000,
    q = 0b010000,
    k = 0b100000,

    pub fn isSome(self: PieceType) bool {
        return self != .none;
    }

    pub fn isNone(self: PieceType) bool {
        return self == .none;
    }

    pub fn toIndex(self: PieceType) usize {
        assert(self.isSome());
        return @ctz(@intFromEnum(self));
    }

    pub fn isSlider(self: PieceType) bool {
        return (@intFromEnum(self) & 0b011100) != 0;
    }

    pub fn toChar(self: PieceType) u8 {
        if (self.isNone()) {
            return '.';
        }
        return "pnbrqk"[self.toIndex()];
    }

    pub fn splat(self: PieceType, comptime size: usize) @Vector(size, u8) {
        return @splat(@intFromEnum(self));
    }

    pub fn format(self: PieceType, writer: *std.Io.Writer) !void {
        try writer.print("{c}", .{self.toChar()});
    }
};

pub const Piece = enum(u8) {
    none = 0,
    wp = 0b00000001,
    wn = 0b00000010,
    wb = 0b00000100,
    wr = 0b00001000,
    wq = 0b00010000,
    wk = 0b00100000,
    bp = 0b10000001,
    bn = 0b10000010,
    bb = 0b10000100,
    br = 0b10001000,
    bq = 0b10010000,
    bk = 0b10100000,

    pub fn make(c: Color, pt: PieceType) Piece {
        const color_bit = @as(u8, @intFromEnum(c)) << 7;
        return @enumFromInt(color_bit | @intFromEnum(pt));
    }

    pub fn isSome(self: Piece) bool {
        return self != .none;
    }

    pub fn isNone(self: Piece) bool {
        return self == .none;
    }

    pub fn color(self: Piece) Color {
        return @enumFromInt(@intFromBool((@intFromEnum(self) & 0x80) != 0));
    }

    pub fn ptype(self: Piece) PieceType {
        return @enumFromInt(@intFromEnum(self) & 0x7F);
    }

    pub fn toChar(self: Piece) u8 {
        if (self.isNone()) {
            return '.';
        }
        return switch (self.color()) {
            .white => "PNBRQK",
            .black => "pnbrqk",
        }[self.ptype().toIndex()];
    }

    pub fn parse(ch: u8) ParseError!Piece {
        return switch (ch) {
            'P' => .wp,
            'N' => .wn,
            'B' => .wb,
            'R' => .wr,
            'Q' => .wq,
            'K' => .wk,
            'p' => .bp,
            'n' => .bn,
            'b' => .bb,
            'r' => .br,
            'q' => .bq,
            'k' => .bk,
            else => ParseError.InvalidChar,
        };
    }

    pub fn format(self: Piece, writer: *std.Io.Writer) !void {
        try writer.print("{c}", .{self.toChar()});
    }
};

pub const Dir = enum(u8) {
    n = 0,
    ne = 1,
    e = 2,
    se = 3,
    s = 4,
    sw = 5,
    w = 6,
    nw = 7,

    pub fn flip(self: Dir) Dir {
        return @enumFromInt((@intFromEnum(self) + 4) % 8);
    }
};

pub const PieceId = enum(u8) {
    king = 0,
    none = 0x80,
    _,

    pub fn isSome(self: PieceId) bool {
        return self != .none;
    }

    pub fn isNone(self: PieceId) bool {
        return self == .none;
    }

    pub fn toIndex(self: PieceId) usize {
        return @intFromEnum(self);
    }

    pub fn toSet(self: PieceId) PieceSet {
        return PieceSet.make(1 << @intFromEnum(self));
    }
};

pub const File = enum {
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,

    pub fn fromIndex(i: u8) File {
        assert(i < 8);
        return @enumFromInt(i);
    }

    pub fn toIndex(f: File) usize {
        return @intFromEnum(f);
    }

    pub fn toChar(f: File) u8 {
        return 'a' + @as(u8, @intFromEnum(f));
    }

    pub fn toLowerChar(f: File) u8 {
        return 'a' + @as(u8, @intFromEnum(f));
    }

    pub fn toUpperChar(f: File) u8 {
        return 'A' + @as(u8, @intFromEnum(f));
    }
};

pub const Rank = enum {
    first,
    second,
    third,
    fourth,
    fifth,
    sixth,
    seventh,
    eighth,

    pub fn fromIndex(i: u8) Rank {
        assert(i < 8);
        return @enumFromInt(i);
    }

    pub fn toIndex(r: Rank) usize {
        return @intFromEnum(r);
    }

    pub fn toChar(r: Rank) u8 {
        return '1' + @as(u8, @intFromEnum(r));
    }
};

pub const Square = enum(u8) {
    // zig fmt: off
    a1 =  0, b1 =  1, c1 =  2, d1 =  3, e1 =  4, f1 =  5, g1 =  6, h1 =  7,
    a2 =  8, b2 =  9, c2 = 10, d2 = 11, e2 = 12, f2 = 13, g2 = 14, h2 = 15,
    a3 = 16, b3 = 17, c3 = 18, d3 = 19, e3 = 20, f3 = 21, g3 = 22, h3 = 23,
    a4 = 24, b4 = 25, c4 = 26, d4 = 27, e4 = 28, f4 = 29, g4 = 30, h4 = 31,
    a5 = 32, b5 = 33, c5 = 34, d5 = 35, e5 = 36, f5 = 37, g5 = 38, h5 = 39,
    a6 = 40, b6 = 41, c6 = 42, d6 = 43, e6 = 44, f6 = 45, g6 = 46, h6 = 47,
    a7 = 48, b7 = 49, c7 = 50, d7 = 51, e7 = 52, f7 = 53, g7 = 54, h7 = 55,
    a8 = 56, b8 = 57, c8 = 58, d8 = 59, e8 = 60, f8 = 61, g8 = 62, h8 = 63,
    none = 0x80,
    // zig fmt: on

    pub fn fromIndex(i: u8) Square {
        assert(i < 64);
        return @enumFromInt(i);
    }

    pub fn fromFileAndRank(f: File, r: Rank) Square {
        return @enumFromInt(@intFromEnum(f) + @as(u8, @intFromEnum(r)) * 8);
    }

    pub fn isSome(self: Square) bool {
        return (@intFromEnum(self) & 0xC0) == 0;
    }

    pub fn isNone(self: Square) bool {
        return (@intFromEnum(self) & 0xC0) != 0;
    }

    pub fn toIndex(self: Square) usize {
        return @intFromEnum(self);
    }

    pub fn file(self: Square) File {
        assert(self.isSome());
        return @enumFromInt(@intFromEnum(self) % 8);
    }

    pub fn rank(self: Square) Rank {
        assert(self.isSome());
        return @enumFromInt(@intFromEnum(self) / 8);
    }

    pub fn toSet(self: Square) SquareSet {
        assert(self.isSome());
        return SquareSet.make(@as(u64, 1) << @intCast(@intFromEnum(self)));
    }

    pub fn toggleRankLsb(self: Square) Square {
        return @enumFromInt(@intFromEnum(self) ^ 0x08);
    }

    // Caller has ownership of string
    pub fn parse(str: []const u8) ParseError!Square {
        if (str.len != 2) return ParseError.InvalidLength;
        if (str[0] < 'a' or str[0] > 'h') return ParseError.InvalidChar;
        if (str[1] < '1' or str[1] > '8') return ParseError.InvalidChar;
        const f = str[0] - 'a';
        const r = str[1] - '1';
        return fromFileAndRank(.fromIndex(f), .fromIndex(r));
    }

    pub fn format(self: Square, writer: *std.Io.Writer) !void {
        try writer.print("{c}{c}", .{ self.file().toChar(), self.rank().toChar() });
    }

    test {
        try std.testing.expect(!Square.none.isSome());
        try std.testing.expect(Square.none.isNone());
        try std.testing.expectEqual(fromFileAndRank(3, 4), parse("d5"));
    }
};

test {
    std.testing.refAllDecls(@This());
}

test {
    try std.testing.expectEqual(Piece.bq, Piece.parse('q'));
    try std.testing.expectEqual('k', Piece.bk.ptype().toChar());
    try std.testing.expectEqual('w', Color.white.toChar());
}

const std = @import("std");
const assert = std.debug.assert;
