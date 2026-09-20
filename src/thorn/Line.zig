pub const max_len: usize = 256;

len: usize = 0,
storage: [max_len]Move = undefined,

pub fn copyFrom(self: *Line, other: *const Line) void {
    self.len = other.len;
    @memcpy(self.storage[0..other.len], other.storage[0..other.len]);
}

pub fn writeLine(self: *Line, first: Move, rest: *const Line) void {
    self.len = rest.len + 1;
    self.storage[0] = first;
    @memcpy(self.storage[1..self.len], rest.storage[0..rest.len]);
}

const Line = @This();
const thorn = @import("../thorn.zig");
const Move = thorn.Move;
