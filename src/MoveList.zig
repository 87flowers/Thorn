pub const capacity: usize = 256;

len: usize,
storage: [capacity]Move,

pub fn new() MoveList {
    return .{
        .len = 0,
        .storage = undefined,
    };
}

pub fn constSlice(self: *const MoveList) []const Move {
    return self.storage[0..self.len];
}

pub fn push(self: *MoveList, from: Square, to: Square, flags: Move.Flags) void {
    self.storage[self.len] = Move.make(from, to, flags);
    self.len += 1;
}

pub fn pushSet(self: *MoveList, from: Square, to: SquareSet, flags: Move.Flags) void {
    var iter = to.iter();
    while (iter.next()) |sq| self.push(from, sq, flags);
}

pub fn pushPawnRank(self: *MoveList, base: Square, from: u8, offset: i8, flags: Move.Flags) void {
    var set = from;
    while (set != 0) : (set &= set - 1) {
        const f: i32 = @intFromEnum(base) + @as(i32, @ctz(set));
        const t: i32 = f + offset;
        self.push(Square.fromIndex(@intCast(f)), Square.fromIndex(@intCast(t)), flags);
    }
}

pub fn pushPawnBody(self: *MoveList, from: u32, offset: i8) void {
    var set = from;
    while (set != 0) : (set &= set - 1) {
        const f: i32 = 16 + @as(i32, @ctz(set));
        const t: i32 = f + offset;
        self.push(Square.fromIndex(@intCast(f)), Square.fromIndex(@intCast(t)), .normal);
    }
}

const MoveList = @This();
const thorn = @import("root.zig");
const Move = thorn.Move;
const Square = thorn.Square;
const SquareSet = thorn.SquareSet;
