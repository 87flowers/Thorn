pub const Quiet = struct {
    table: [2][64][64]i16 = @splat(@splat(@splat(0))),

    pub fn reset(self: *Quiet) void {
        self.table = @splat(@splat(@splat(0)));
    }

    pub fn get(self: *const Quiet, stm: Color, mv: Move) i32 {
        return self.table[stm.toIndex()][mv.from().toIndex()][mv.to().toIndex()];
    }

    pub fn update(self: *Quiet, stm: Color, mv: Move, bonus: i32) void {
        gravity(&self.table[stm.toIndex()][mv.from().toIndex()][mv.to().toIndex()], bonus, 8192);
    }
};

fn gravity(value: *i16, bonus: i32, max: i16) void {
    var b: i32 = std.math.clamp(bonus, -max, max);
    b -= @divTrunc(@as(i32, @intCast(@abs(b))) * value.*, max);
    value.* += @intCast(b);
}

const std = @import("std");
const thorn = @import("../../thorn.zig");
const Color = thorn.Color;
const Move = thorn.Move;
