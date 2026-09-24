pub const Quiet = struct {
    table: [2][64][64]i16 = @splat(@splat(@splat(0))),

    pub fn reset(self: *Quiet) void {
        self.table = @splat(@splat(@splat(0)));
    }

    pub fn get(self: *const Quiet, stm: Color, m: Move) i32 {
        return self.table[stm.toIndex()][m.from().toIndex()][m.to().toIndex()];
    }

    pub fn update(self: *Quiet, stm: Color, m: Move, bonus: i32) void {
        gravity(&self.table[stm.toIndex()][m.from().toIndex()][m.to().toIndex()], bonus, 8192);
    }
};

pub const Continuation = struct {
    table: [2][6][64]Subtable,

    pub fn reset(self: *Continuation) void {
        self.table = @splat(@splat(@splat(.{})));
    }

    pub fn getSubtable(self: *Continuation, position: *const Position, m: Move) *Subtable {
        const stm = position.sideToMove();
        const ptype = position.whatAt(m.from()).ptype();
        return &self.table[stm.toIndex()][ptype.toIndex()][m.to().toIndex()];
    }

    pub const Subtable = struct {
        table: [2][6][64]i16 = @splat(@splat(@splat(0))),

        pub fn get(self: *const Subtable, position: *const Position, m: Move) i32 {
            const stm = position.sideToMove();
            const ptype = position.whatAt(m.from()).ptype();
            return self.table[stm.toIndex()][ptype.toIndex()][m.to().toIndex()];
        }

        pub fn update(self: *Subtable, position: *const Position, m: Move, bonus: i32) void {
            const stm = position.sideToMove();
            const ptype = position.whatAt(m.from()).ptype();
            gravity(&self.table[stm.toIndex()][ptype.toIndex()][m.to().toIndex()], bonus, 8192);
        }
    };
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
