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
        scores[i] = blk: {
            if (m.isCapture()) break :blk 125 << 24;
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

const MoveSelector = @This();
const std = @import("std");
const thorn = @import("../../thorn.zig");
const movegen = thorn.movegen;
const Move = thorn.Move;
const MoveList = thorn.MoveList;
const Position = thorn.Position;
