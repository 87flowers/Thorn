pub const SquareSet = packed struct {
    raw: u64,

    pub const empty = make(0);
    pub const all = make(0xFFFFFFFFFFFFFFFF);
    pub const promo_zone = make(0xFF000000000000FF);

    pub fn make(raw: u64) SquareSet {
        return SquareSet{ .raw = raw };
    }

    pub fn set(args: anytype) SquareSet {
        const ArgsType = @TypeOf(args);
        const args_type_info = @typeInfo(ArgsType);
        if (args_type_info != .@"struct") @compileError("expected tuple argument, found " ++ @typeName(ArgsType));

        var result: SquareSet = .empty;

        inline for (args_type_info.@"struct".fields) |field| {
            if (field.type != Square) @compileError("expected Square, found " ++ @typeName(field.type));
            const arg: Square = @field(args, field.name);
            result.insert(arg.toSet());
        }

        return result;
    }

    pub fn fileMask(file: File) SquareSet {
        return make(@as(u64, 0x0101010101010101) << @intFromEnum(file));
    }

    pub fn rankMask(rank: u8) SquareSet {
        assert(rank >= 0 and rank <= 7);
        return make(@as(u64, 0xFF) << @intCast(rank * 8));
    }

    pub fn rayMask(start: Square, dir: Dir) SquareSet {
        assert(start.isSome());
        var bb = start.toSet();
        var result = SquareSet.empty;
        while (!bb.isEmpty()) {
            bb = bb.shift(dir);
            result = result.bitOr(bb);
        }
        return result;
    }

    // (a, b)
    pub fn rayBetween(a: Square, b: Square) SquareSet {
        assert(a.isSome() and b.isSome());
        return ray_between_table[a.toIndex()][b.toIndex()];
    }

    // [a, b)
    pub fn rayExclusiveInclusive(a: Square, b: Square) SquareSet {
        assert(a.isSome() and b.isSome());
        return ray_exclusive_inclusive_table[a.toIndex()][b.toIndex()];
    }

    // [a, b]
    pub fn rayInclusive(a: Square, b: Square) SquareSet {
        assert(a.isSome() and b.isSome());
        return ray_inclusive_table[a.toIndex()][b.toIndex()];
    }

    // (a, b] and every square past b
    pub fn rayPast(from: Square, to: Square) SquareSet {
        assert(from.isSome() and to.isSome());
        return ray_past_table[from.toIndex()][to.toIndex()];
    }

    pub fn isEmpty(self: SquareSet) bool {
        return self.raw == 0;
    }

    pub fn lsb(self: SquareSet) Square {
        assert(!self.isEmpty());
        return Square.fromIndex(@ctz(self.raw));
    }

    pub fn popLsb(self: *SquareSet) void {
        self.raw &= self.raw - 1;
    }

    pub fn popcount(self: SquareSet) i32 {
        return @popCount(self.raw);
    }

    pub fn read(self: SquareSet, sq: Square) bool {
        assert(sq.isSome());
        return (self.raw & sq.toSet().raw) != 0;
    }

    pub fn readRank(self: SquareSet, rank: u8) u8 {
        return @truncate(self.raw >> @intCast(8 * rank));
    }

    pub fn write(self: *SquareSet, sq: Square, value: bool) void {
        assert(sq.isSome());
        if (value) {
            self.raw |= sq.toSet().raw;
        } else {
            self.raw &= sq.toSet().bitNot().raw;
        }
    }

    pub fn bitAnd(self: SquareSet, other: SquareSet) SquareSet {
        return SquareSet.make(self.raw & other.raw);
    }

    pub fn bitAndNot(self: SquareSet, other: SquareSet) SquareSet {
        return SquareSet.make(self.raw & ~other.raw);
    }

    pub fn bitOr(self: SquareSet, other: SquareSet) SquareSet {
        return SquareSet.make(self.raw | other.raw);
    }

    pub fn bitNot(self: SquareSet) SquareSet {
        return SquareSet.make(~self.raw);
    }

    pub fn insert(self: *SquareSet, other: SquareSet) void {
        self.raw |= other.raw;
    }

    pub fn applyMask(self: *SquareSet, other: SquareSet) void {
        self.raw &= other.raw;
    }

    pub fn shift(self: SquareSet, dir: Dir) SquareSet {
        const file_a = fileMask(.a);
        const file_h = fileMask(.h);
        return switch (dir) {
            .n => SquareSet.make(self.raw << 8),
            .ne => SquareSet.make((self.raw & ~file_h.raw) << 9),
            .e => SquareSet.make((self.raw & ~file_h.raw) << 1),
            .se => SquareSet.make((self.raw & ~file_h.raw) >> 7),
            .s => SquareSet.make(self.raw >> 8),
            .sw => SquareSet.make((self.raw & ~file_a.raw) >> 9),
            .w => SquareSet.make((self.raw & ~file_a.raw) >> 1),
            .nw => SquareSet.make((self.raw & ~file_a.raw) << 7),
        };
    }

    pub fn iter(self: SquareSet) struct {
        remaining: SquareSet,

        pub fn next(i: *@This()) ?Square {
            if (i.remaining.isEmpty()) return null;
            const result = i.remaining.lsb();
            i.remaining.popLsb();
            return result;
        }
    } {
        return .{ .remaining = self };
    }
};

const ray_between_table: [64][64]SquareSet = blk: {
    @setEvalBranchQuota(100_000);
    var result: [64][64]SquareSet = @splat(@splat(.empty));
    for (0..64) |origin| {
        for ([_]Dir{ .n, .ne, .e, .se, .s, .sw, .w, .nw }) |dir| {
            var current = Square.fromIndex(origin).toSet().shift(dir);
            var ray = SquareSet.empty;
            while (!current.isEmpty()) {
                const dst = current.lsb().toIndex();
                result[origin][dst] = ray;

                ray.insert(current);
                current = current.shift(dir);
            }
        }
    }
    break :blk result;
};

const ray_exclusive_inclusive_table: [64][64]SquareSet = blk: {
    @setEvalBranchQuota(100_000);
    var result: [64][64]SquareSet = @splat(@splat(.empty));
    for (0..64) |origin| {
        for ([_]Dir{ .n, .ne, .e, .se, .s, .sw, .w, .nw }) |dir| {
            var current = Square.fromIndex(origin).toSet().shift(dir);
            var ray = SquareSet.empty;
            while (!current.isEmpty()) {
                ray.insert(current);

                const dst = current.lsb().toIndex();
                result[origin][dst] = ray;

                current = current.shift(dir);
            }
        }
        // Required for knight moves
        for (0..64) |dst| {
            result[origin][dst].insert(Square.fromIndex(dst).toSet());
        }
    }
    break :blk result;
};

const ray_inclusive_table: [64][64]SquareSet = blk: {
    @setEvalBranchQuota(100_000);
    var result: [64][64]SquareSet = @splat(@splat(.empty));
    for (0..64) |origin| {
        for ([_]Dir{ .n, .ne, .e, .se, .s, .sw, .w, .nw }) |dir| {
            var current = Square.fromIndex(origin).toSet();
            var ray = SquareSet.empty;
            while (!current.isEmpty()) {
                ray.insert(current);

                const dst = current.lsb().toIndex();
                result[origin][dst] = ray;

                current = current.shift(dir);
            }
        }
        // Required for knight moves
        for (0..64) |dst| {
            result[origin][dst].insert(Square.fromIndex(origin).toSet());
            result[origin][dst].insert(Square.fromIndex(dst).toSet());
        }
    }
    break :blk result;
};

const ray_past_table: [64][64]SquareSet = blk: {
    @setEvalBranchQuota(100_000);
    var result: [64][64]SquareSet = @splat(@splat(.empty));
    for (0..64) |origin| {
        for ([_]Dir{ .n, .ne, .e, .se, .s, .sw, .w, .nw }) |dir| {
            const ray = SquareSet.rayMask(Square.fromIndex(origin), dir);
            var i = ray.iter();
            while (i.next()) |dst| {
                result[origin][dst.toIndex()] = ray;
            }
        }
    }
    break :blk result;
};

const std = @import("std");
const assert = std.debug.assert;
const thorn = @import("root.zig");
const Dir = thorn.Dir;
const File = thorn.File;
const Square = thorn.Square;
