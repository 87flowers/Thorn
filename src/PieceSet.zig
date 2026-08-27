raw: u16,

pub const empty = make(0);
pub const king = make(0x0001);

pub fn make(raw: u16) PieceSet {
    return .{ .raw = raw };
}

pub fn fromVector(v: @Vector(16, bool)) PieceSet {
    return make(@bitCast(v));
}

pub fn isEmpty(self: PieceSet) bool {
    return self.raw == 0;
}

pub fn popcount(self: PieceSet) i32 {
    return @popCount(self.raw);
}

pub fn lsb(self: PieceSet) PieceId {
    return @enumFromInt(@ctz(self.raw));
}

pub fn popLsb(self: *PieceSet) void {
    self.raw &= self.raw - 1;
}

pub fn read(self: PieceSet, id: PieceId) bool {
    return (self.raw & id.toSet().raw) != 0;
}

pub fn bitAnd(self: PieceSet, other: PieceSet) PieceSet {
    return PieceSet.make(self.raw & other.raw);
}

pub fn bitAndNot(self: PieceSet, other: PieceSet) PieceSet {
    return PieceSet.make(self.raw & ~other.raw);
}

pub fn bitOr(self: PieceSet, other: PieceSet) PieceSet {
    return PieceSet.make(self.raw | other.raw);
}

pub fn bitNot(self: PieceSet) PieceSet {
    return PieceSet.make(~self.raw);
}

pub fn insert(self: *PieceSet, other: PieceSet) void {
    self.raw |= other.raw;
}

pub fn applyMask(self: *PieceSet, other: PieceSet) void {
    self.raw &= other.raw;
}

pub fn iter(self: PieceSet) struct {
    remaining: PieceSet,

    pub fn next(i: *@This()) ?PieceId {
        if (i.remaining.isEmpty()) return null;
        const result = i.remaining.lsb();
        i.remaining.popLsb();
        return result;
    }
} {
    return .{ .remaining = self };
}

const PieceSet = @This();
const thorn = @import("root.zig");
const PieceId = thorn.PieceId;
