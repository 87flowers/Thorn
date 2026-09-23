entries: []Entry,

pub const default_size_mb = 16;

pub fn init(gpa: std.mem.Allocator) !Cache {
    return .{
        .entries = try gpa.alloc(Entry, entryCountFromMb(default_size_mb)),
    };
}

pub fn deinit(self: *Cache, gpa: std.mem.Allocator) void {
    gpa.free(self.entries);
}

pub fn resize(self: *Cache, gpa: std.mem.Allocator, mb: usize) !void {
    const n = entryCountFromMb(mb);
    if (self.entries.len == n) return;
    gpa.free(self.entries);
    self.entries = try gpa.alloc(Entry, n);
}

pub fn clear(self: *Cache) void {
    @memset(self.entries, @enumFromInt(0));
}

pub fn partialClear(self: *Cache, i: usize, count: usize) void {
    const part_size = std.math.divCeil(usize, self.entries.len, count);
    const start = @min(part_size * i, self.entries.len);
    const end = @min(start + part_size, self.entries.len);
    @memset(self.entries[start..end], @enumFromInt(0));
}

pub fn lookup(self: *Cache, h: Hash, ply: i32) ?Result {
    const index = self.hashToIndex(h);
    const fragment: Fragment = .fromHash(h);

    const entry = @atomicLoad(Entry, &self.entries[index], .monotonic);
    return if (entry.fragment() == fragment) entry.toResult(ply) else null;
}

pub fn update(self: *Cache, h: Hash, ply: i32, lr: Result) void {
    const index = self.hashToIndex(h);

    @atomicStore(Entry, &self.entries[index], .make(h, ply, lr), .monotonic);
}

fn hashToIndex(self: *Cache, h: Hash) usize {
    return @intCast((@as(u128, @intFromEnum(h)) * self.entries.len) >> 64);
}

fn entryCountFromMb(mb: usize) usize {
    return mb * 1024 * 1024 / @sizeOf(Entry);
}

pub const Result = struct {
    depth: i32 = 0,
    kind: NodeKind = .none,
    score: Score = thorn.score.none,
    move: Move = .none,

    pub fn isNone(self: *Result) bool {
        return self.kind == .none;
    }

    pub fn isSome(self: *Result) bool {
        return self.kind != .none;
    }
};

const Entry = enum(u64) {
    _,

    // MSB -> LSB
    // i16 score
    // u16 move
    // u8 depth
    // u2 kind
    // u6 unused
    // u16 fragment

    const score_shift = 48;
    const move_shift = 32;
    const depth_shift = 24;
    const kind_shift = 22;

    fn make(hash: Hash, ply: i32, lr: Result) Entry {
        const e_score: u32 = @bitCast(thorn.score.adjustPlysToMate(lr.score, -ply));
        const e_depth: u32 = @intCast(std.math.clamp(lr.depth, 0, 255));
        const e_kind: u64 = @intFromEnum(lr.kind);
        const e_fragment: Fragment = .fromHash(hash);

        var raw: u64 = 0;
        raw |= @as(u64, e_score) << score_shift;
        raw |= @as(u64, lr.move.raw) << move_shift;
        raw |= @as(u64, e_depth) << depth_shift;
        raw |= @as(u64, e_kind) << kind_shift;
        raw |= @intFromEnum(e_fragment);
        return @enumFromInt(raw);
    }

    fn score(self: Entry, ply: i32) Score {
        const e_score: Score = @intCast(@as(i64, @bitCast(self)) >> score_shift);
        return thorn.score.adjustPlysToMate(e_score, ply);
    }

    fn move(self: Entry) Move {
        return @bitCast(@as(u16, @truncate(@intFromEnum(self) >> move_shift)));
    }

    fn depth(self: Entry) i32 {
        return @as(u8, @truncate(@intFromEnum(self) >> depth_shift));
    }

    fn kind(self: Entry) NodeKind {
        return @enumFromInt(@as(u2, @truncate(@intFromEnum(self) >> kind_shift)));
    }

    fn fragment(self: Entry) Fragment {
        return @enumFromInt(@as(u16, @truncate(@intFromEnum(self))));
    }

    fn toResult(self: Entry, ply: i32) Result {
        return .{
            .depth = self.depth(),
            .kind = self.kind(),
            .score = self.score(ply),
            .move = self.move(),
        };
    }
};

const Fragment = enum(u16) {
    _,

    fn fromHash(h: Hash) Fragment {
        return @enumFromInt(@as(u16, @truncate(@intFromEnum(h))));
    }
};

const Cache = @This();
const std = @import("std");
const thorn = @import("../thorn.zig");
const Hash = thorn.Hash;
const Move = thorn.Move;
const NodeKind = thorn.NodeKind;
const Score = thorn.score.Score;
