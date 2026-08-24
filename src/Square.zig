raw: u8,

pub const none = Square{ .raw = 0x80 };

pub fn fromFileAndRank(f: u8, r: u8) Square {
    assert(f >= 0 and f <= 7);
    assert(r >= 0 and r <= 7);
    return .{ .raw = @intCast(f + r * 8) };
}

pub fn isSome(self: Square) bool {
    return (self.raw & 0xC0) == 0;
}

pub fn isNone(self: Square) bool {
    return (self.raw & 0xC0) != 0;
}

pub fn file(self: Square) u8 {
    assert(self.isSome());
    return self.raw % 8;
}

pub fn rank(self: Square) u8 {
    assert(self.isSome());
    return self.raw / 8;
}

pub fn toSet(self: Square) SquareSet {
    assert(self.isSome());
    return SquareSet.make(@as(u64, 1) << @intCast(self.raw));
}

// Caller has ownership of string
pub fn parse(str: []const u8) ParseError!Square {
    if (str.len != 2)
        return ParseError.InvalidLength;
    if (str[0] < 'a' or str[0] > 'h')
        return ParseError.InvalidChar;
    const f = str[0] - 'a';
    if (str[1] < '1' or str[1] > '8')
        return ParseError.InvalidChar;
    const r = str[1] - '1';
    return fromFileAndRank(f, r);
}

pub fn format(self: Square, writer: *std.Io.Writer) !void {
    try writer.print("{c}{c}", .{ 'a' + self.file(), '1' + self.rank() });
}

test {
    try std.testing.expect(!none.isSome());
    try std.testing.expect(none.isNone());
    try std.testing.expectEqual(fromFileAndRank(3, 4), parse("d5"));
}

const Square = @This();
const std = @import("std");
const assert = std.debug.assert;
const thorn = @import("root.zig");
const ParseError = thorn.ParseError;
const SquareSet = thorn.SquareSet;
