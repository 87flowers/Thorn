pub const Quiet = struct {
    ft_table: [2][64][64]i16 = @splat(@splat(@splat(0))),
    pt_table: [2][6][64]i16 = @splat(@splat(@splat(0))),

    pub fn reset(self: *Quiet) void {
        self.ft_table = @splat(@splat(@splat(0)));
        self.pt_table = @splat(@splat(@splat(0)));
    }

    pub fn get(self: *const Quiet, position: *const Position, stm: Color, mv: Move) i32 {
        const ptype = position.whatAt(mv.from()).ptype();
        const ft = self.ft_table[stm.toIndex()][mv.from().toIndex()][mv.to().toIndex()];
        const pt = self.pt_table[stm.toIndex()][ptype.toIndex()][mv.to().toIndex()];
        return ft + pt;
    }

    pub fn update(self: *Quiet, position: *const Position, stm: Color, mv: Move, bonus: i32) void {
        const ptype = position.whatAt(mv.from()).ptype();
        gravity(&self.ft_table[stm.toIndex()][mv.from().toIndex()][mv.to().toIndex()], bonus, 8192);
        gravity(&self.pt_table[stm.toIndex()][ptype.toIndex()][mv.to().toIndex()], bonus, 8192);
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
const Position = thorn.Position;
