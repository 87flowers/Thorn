stage: enum {
    move_gen,
    emit,
    end,
} = .move_gen,

moves: MoveList = .new(),
position: *const Position,
current: usize = 0,

pub fn new(position: *const Position) MoveSelector {
    return .{
        .position = position,
    };
}

pub fn next(self: *MoveSelector) ?Move {
    sw: switch (self.stage) {
        .move_gen => {
            movegen.all(&self.moves, self.position);
            self.orderMoves();

            self.current = 0;
            self.stage = .emit;
            continue :sw .emit;
        },
        .emit => {
            if (self.current >= self.moves.len) continue :sw .end;
            const m = self.moves.storage[self.current];
            self.current += 1;
            return m;
        },
        .end => {
            self.stage = .end;
            return null;
        },
    }
}

fn orderMoves(self: *MoveSelector) void {
    var scores: [MoveList.capacity]i32 = undefined;

    for (0..self.moves.len) |i| {
        const m = self.moves.storage[i];
        const src_ptype = self.position.whatAt(m.from()).ptype();
        const dst_ptype = self.position.whatAt(m.to()).ptype();
        scores[i] = blk: {
            if (m.isCapture())
                break :blk @as(i32, 125 << 24) + mvv_table[dst_ptype.toIndex()] - lva_table[src_ptype.toIndex()];
            break :blk 0;
        };
    }

    self.sort(&scores);
}

fn sort(self: *MoveSelector, scores: []i32) void {
    const Context = struct {
        ml: *MoveList,
        scores: []i32,

        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            return ctx.scores[a] > ctx.scores[b];
        }

        pub fn swap(ctx: @This(), a: usize, b: usize) void {
            std.mem.swap(Move, &ctx.ml.storage[a], &ctx.ml.storage[b]);
            std.mem.swap(i32, &ctx.scores[a], &ctx.scores[b]);
        }
    };
    std.sort.heapContext(0, self.moves.len, Context{ .ml = &self.moves, .scores = scores });
}

const mvv_table: [7]i32 = .{ 800, 2400, 2400, 4000, 7200, 100000, 100 };
const lva_table: [6]i32 = .{ 100, 300, 300, 500, 900, 100000 };

const MoveSelector = @This();
const std = @import("std");
const thorn = @import("../../thorn.zig");
const movegen = thorn.movegen;
const Move = thorn.Move;
const MoveList = thorn.MoveList;
const Position = thorn.Position;
