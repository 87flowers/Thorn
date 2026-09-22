pub const capacity: usize = 256;

len: usize,
storage: [capacity]Move,

pub fn new() MoveList {
    return .{
        .len = 0,
        .storage = undefined,
    };
}

pub fn clear(self: *MoveList) void {
    self.len = 0;
}

pub fn constSlice(self: *const MoveList) []const Move {
    return self.storage[0..self.len];
}

pub fn push(self: *MoveList, from: Square, to: Square, flags: Move.Flags) void {
    self.storage[self.len] = Move.make(from, to, flags);
    self.len += 1;
}

pub fn pushSets(self: *MoveList, from: Square, normal_to: SquareSet, cap_to: SquareSet) void {
    const to = normal_to.bitOr(cap_to);

    if (intrin.has_compress) {
        const build_template = struct {
            fn build_template(comptime start: u16, comptime flag: Move.Flags) @Vector(32, u16) {
                var result: @Vector(32, u16) = undefined;
                inline for (0..32) |i| result[i] = (i + start) << 6 | @intFromEnum(flag);
                return result;
            }
        }.build_template;

        const normal_template0 = build_template(0, .normal);
        const normal_template1 = build_template(32, .normal);
        const cap_template0 = build_template(0, .cap_normal);
        const cap_template1 = build_template(32, .cap_normal);

        const cap_m0: @Vector(32, bool) = @bitCast(@as(u32, @truncate(cap_to.raw)));
        const cap_m1: @Vector(32, bool) = @bitCast(@as(u32, @truncate(cap_to.raw >> 32)));

        const v0: @Vector(32, u16) = @select(u16, cap_m0, cap_template0, normal_template0);
        const v1: @Vector(32, u16) = @select(u16, cap_m1, cap_template1, normal_template1);
        const other: @Vector(32, u16) = @splat(@intFromEnum(from));

        const m0: u32 = @truncate(to.raw);
        const m1: u32 = @truncate(to.raw >> 32);

        const c0 = intrin.compress(m0, v0 | other);
        const c1 = intrin.compress(m1, v1 | other);

        if (m0 != 0) {
            @memcpy(self.storage[self.len .. self.len + 32], @as([32]Move, @bitCast(c0))[0..32]);
            self.len += @popCount(m0);
        }
        if (m1 != 0) {
            @memcpy(self.storage[self.len .. self.len + 32], @as([32]Move, @bitCast(c1))[0..32]);
            self.len += @popCount(m1);
        }
    } else {
        var iter = to.iter();
        while (iter.next()) |sq| self.push(from, sq, if (cap_to.read(sq)) .cap_normal else .normal);
    }
}

pub fn pushSet(self: *MoveList, from: Square, to: SquareSet, comptime flag: Move.Flags) void {
    if (intrin.has_compress) {
        const build_template = struct {
            fn build_template(comptime start: u16, comptime f: Move.Flags) @Vector(32, u16) {
                var result: @Vector(32, u16) = undefined;
                inline for (0..32) |i| result[i] = (i + start) << 6 | @intFromEnum(f);
                return result;
            }
        }.build_template;

        const template0 = build_template(0, flag);
        const template1 = build_template(32, flag);

        const other: @Vector(32, u16) = @splat(@intFromEnum(from));

        const m0: u32 = @truncate(to.raw);
        const m1: u32 = @truncate(to.raw >> 32);

        const c0 = intrin.compress(m0, template0 | other);
        const c1 = intrin.compress(m1, template1 | other);

        if (m0 != 0) {
            @memcpy(self.storage[self.len .. self.len + 32], @as([32]Move, @bitCast(c0))[0..32]);
            self.len += @popCount(m0);
        }
        if (m1 != 0) {
            @memcpy(self.storage[self.len .. self.len + 32], @as([32]Move, @bitCast(c1))[0..32]);
            self.len += @popCount(m1);
        }
    } else {
        var iter = to.iter();
        while (iter.next()) |sq| self.push(from, sq, flag);
    }
}

pub fn pushPawnRank(self: *MoveList, base: Square, from: u8, comptime offset: i8, comptime color: Color, comptime flags: Move.Flags) void {
    if (intrin.has_compress) {
        const template = switch (color) {
            .white => comptime blk: {
                var result: @Vector(8, u16) = undefined;
                switch (flags) {
                    .normal => {
                        assert(offset == 8);
                        for (8..16) |i| result[i - 8] = Move.make(.fromIndex(i), .fromIndex(i + 8), .normal).raw;
                    },
                    .double_push => {
                        assert(offset == 16);
                        for (8..16) |i| result[i - 8] = Move.make(.fromIndex(i), .fromIndex(i + 16), .double_push).raw;
                    },
                    .promo_n, .promo_b, .promo_r, .promo_q => |f| {
                        assert(offset == 8);
                        for (48..56) |i| result[i - 48] = Move.make(.fromIndex(i), .fromIndex(i + 8), f).raw;
                    },
                    else => unreachable,
                }
                break :blk result;
            },
            .black => comptime blk: {
                var result: @Vector(8, u16) = undefined;
                switch (flags) {
                    .normal => {
                        assert(offset == -8);
                        for (48..56) |i| result[i - 48] = Move.make(.fromIndex(i), .fromIndex(i - 8), .normal).raw;
                    },
                    .double_push => {
                        assert(offset == -16);
                        for (48..56) |i| result[i - 48] = Move.make(.fromIndex(i), .fromIndex(i - 16), .double_push).raw;
                    },
                    .promo_n, .promo_b, .promo_r, .promo_q => |f| {
                        assert(offset == -8);
                        for (8..16) |i| result[i - 8] = Move.make(.fromIndex(i), .fromIndex(i - 8), f).raw;
                    },
                    else => unreachable,
                }
                break :blk result;
            },
        };
        const c = intrin.compress(from, template);
        @memcpy(self.storage[self.len .. self.len + 8], @as([8]Move, @bitCast(c))[0..8]);
        self.len += @popCount(from);
    } else {
        var set = from;
        while (set != 0) : (set &= set - 1) {
            const f: i32 = @intFromEnum(base) + @as(i32, @ctz(set));
            const t: i32 = f + offset;
            self.push(Square.fromIndex(@intCast(f)), Square.fromIndex(@intCast(t)), flags);
        }
    }
}

pub fn pushPawnBody(self: *MoveList, from: u32, color: Color) void {
    if (intrin.has_compress) {
        const template = switch (color) {
            .white => comptime blk: {
                var result: @Vector(32, u16) = undefined;
                for (16..48) |i| result[i - 16] = Move.make(.fromIndex(i), .fromIndex(i + 8), .normal).raw;
                break :blk result;
            },
            .black => comptime blk: {
                var result: @Vector(32, u16) = undefined;
                for (16..48) |i| result[i - 16] = Move.make(.fromIndex(i), .fromIndex(i - 8), .normal).raw;
                break :blk result;
            },
        };
        const c = intrin.compress(from, template);
        @memcpy(self.storage[self.len .. self.len + 32], @as([32]Move, @bitCast(c))[0..32]);
        self.len += @popCount(from);
    } else {
        const offset: i32 = switch (color) {
            .white => 8,
            .black => -8,
        };
        var set = from;
        while (set != 0) : (set &= set - 1) {
            const f: i32 = 16 + @as(i32, @ctz(set));
            const t: i32 = f + offset;
            self.push(Square.fromIndex(@intCast(f)), Square.fromIndex(@intCast(t)), .normal);
        }
    }
}

pub fn pushPawnCapture(self: *MoveList, from: SquareSet, comptime dir: Dir) void {
    const offset = switch (dir) {
        .ne => 9,
        .nw => 7,
        .se => -7,
        .sw => -9,
        else => unreachable,
    };
    const mask = switch (dir) {
        .ne, .se => ~SquareSet.fileMask(.h).raw,
        .nw, .sw => ~SquareSet.fileMask(.a).raw,
        else => unreachable,
    };
    var set = from.raw & mask;
    if (intrin.has_compress) {
        const template0 = blk: {
            var result: @Vector(32, u16) = undefined;
            inline for (0..32) |i| result[i] = @as(u16, i) | sqOffset(i, offset) << 6 | @intFromEnum(Move.Flags.cap_normal);
            break :blk result;
        };
        const template1 = blk: {
            var result: @Vector(32, u16) = undefined;
            inline for (32..64) |i| result[i - 32] = @as(u16, i) | sqOffset(i, offset) << 6 | @intFromEnum(Move.Flags.cap_normal);
            break :blk result;
        };
        const m0: u32 = @truncate(set);
        const m1: u32 = @truncate(set >> 32);
        const c0 = intrin.compress(m0, template0);
        const c1 = intrin.compress(m1, template1);
        if (m0 != 0) {
            @memcpy(self.storage[self.len .. self.len + 32], @as([32]Move, @bitCast(c0))[0..32]);
            self.len += @popCount(m0);
        }
        if (m1 != 0) {
            @memcpy(self.storage[self.len .. self.len + 32], @as([32]Move, @bitCast(c1))[0..32]);
            self.len += @popCount(m1);
        }
    } else {
        while (set != 0) : (set &= set - 1) {
            const f: i32 = @as(i32, @ctz(set));
            const t: i32 = f + offset;
            self.push(Square.fromIndex(@intCast(f)), Square.fromIndex(@intCast(t)), .cap_normal);
        }
    }
}

pub fn pushPawnPromoCapture(self: *MoveList, base: Square, from: u8, comptime dir: Dir, comptime flags: Move.Flags) void {
    const offset = switch (dir) {
        .ne => 9,
        .nw => 7,
        .se => -7,
        .sw => -9,
        else => unreachable,
    };
    const mask = switch (dir) {
        .ne, .se => 0b01111111,
        .nw, .sw => 0b11111110,
        else => unreachable,
    };
    var set = from & mask;
    if (intrin.has_compress) {
        const template = comptime blk: {
            var result: @Vector(8, u16) = undefined;
            switch (dir) {
                .ne, .nw => {
                    for (48..56) |i| result[i - 48] = @as(u16, i) | sqOffset(i, offset) << 6 | @intFromEnum(flags);
                },
                .se, .sw => {
                    for (8..16) |i| result[i - 8] = @as(u16, i) | sqOffset(i, offset) << 6 | @intFromEnum(flags);
                },
                else => unreachable,
            }
            break :blk result;
        };
        const c = intrin.compress(from, template);
        @memcpy(self.storage[self.len .. self.len + 8], @as([8]Move, @bitCast(c))[0..8]);
        self.len += @popCount(from);
    } else {
        while (set != 0) : (set &= set - 1) {
            const f: i32 = @intFromEnum(base) + @as(i32, @ctz(set));
            const t: i32 = f + offset;
            self.push(Square.fromIndex(@intCast(f)), Square.fromIndex(@intCast(t)), flags);
        }
    }
}

fn sqOffset(i: u16, offset: i32) u16 {
    const sum = @as(i32, i) + offset;
    const sum_unsigned: u32 = @bitCast(sum);
    return @truncate(sum_unsigned);
}

const MoveList = @This();
const std = @import("std");
const assert = std.debug.assert;
const thorn = @import("../thorn.zig");
const intrin = thorn.util.intrin;
const Color = thorn.Color;
const Dir = thorn.Dir;
const Move = thorn.Move;
const Square = thorn.Square;
const SquareSet = thorn.SquareSet;
