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

pub fn pushSet(self: *MoveList, from: Square, to: SquareSet, comptime flags: Move.Flags) void {
    if (has_compress) {
        const template0 = blk: {
            var result: @Vector(32, u16) = undefined;
            inline for (0..32) |i| result[i] = i << 6 | @intFromEnum(flags);
            break :blk result;
        };
        const template1 = blk: {
            var result: @Vector(32, u16) = undefined;
            inline for (32..64) |i| result[i - 32] = i << 6 | @intFromEnum(flags);
            break :blk result;
        };
        const other: @Vector(32, u16) = @splat(@intFromEnum(from));
        const m0: u32 = @truncate(to.raw);
        const m1: u32 = @truncate(to.raw >> 32);
        const c0 = simd.compress(m0, template0 | other);
        const c1 = simd.compress(m1, template1 | other);
        @memcpy(self.storage[self.len .. self.len + 32], @as([32]Move, @bitCast(c0))[0..32]);
        self.len += @popCount(m0);
        @memcpy(self.storage[self.len .. self.len + 32], @as([32]Move, @bitCast(c1))[0..32]);
        self.len += @popCount(m1);
    } else {
        var iter = to.iter();
        while (iter.next()) |sq| self.push(from, sq, flags);
    }
}

pub fn pushPawnRank(self: *MoveList, base: Square, from: u8, comptime offset: i8, comptime color: Color, comptime flags: Move.Flags) void {
    if (has_compress) {
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
        const c = simd.compress(from, template);
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
    if (has_compress) {
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
        const c = simd.compress(from, template);
        @memcpy(self.storage[self.len .. self.len + 32], @as([32]Move, @bitCast(c))[0..32]);
        self.len += @popCount(from);
    } else {
        const offset = switch (color) {
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

const has_compress = @import("builtin").cpu.has(.x86, .avx512vbmi2);

const MoveList = @This();
const std = @import("std");
const assert = std.debug.assert;
const thorn = @import("root.zig");
const simd = thorn.util.simd;
const Color = thorn.Color;
const Move = thorn.Move;
const Square = thorn.Square;
const SquareSet = thorn.SquareSet;
