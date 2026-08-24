raw: u16,

pub const empty = make(0);
pub const king = make(0x0001);

pub fn make(raw: u16) PieceSet {
    return .{ .raw = raw };
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

pub fn popLsb(self: *PieceSet) PieceId {
    self.raw &= self.raw - 1;
}

pub fn read(self: PieceSet, id: PieceId) bool {
    return (self.raw & id.toSet().raw) != 0;
}

const PieceSet = @This();
const thorn = @import("root.zig");
const PieceId = thorn.PieceId;
