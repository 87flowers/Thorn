stage: enum {
    hint_move,
    movegen_noisy,
    emit_noisy,
    movegen_quiet,
    emit_quiet,
    end,
} = .hint_move,

moves: MoveList = .new(),
position: *const Position,
current: usize = 0,

hint_move: Move,

skip_quiet: bool = false,

pub fn new(position: *const Position, hint_move: Move) MoveSelector {
    return .{
        .position = position,
        .hint_move = hint_move,
    };
}

pub fn skipQuiet(self: *MoveSelector) void {
    self.stage = switch (self.stage) {
        .hint_move => .hint_move,
        .movegen_noisy => .movegen_noisy,
        .emit_noisy => .emit_noisy,
        .movegen_quiet => .end,
        .emit_quiet => .end,
        .end => .end,
    };
    self.skip_quiet = true;
}

pub fn next(self: *MoveSelector) ?Move {
    sw: switch (self.stage) {
        .hint_move => {
            if (self.hint_move.isSome() and self.position.isLegal(self.hint_move)) {
                self.stage = .movegen_noisy;
                return self.hint_move;
            }
            continue :sw .movegen_noisy;
        },
        .movegen_noisy => {
            self.moves.clear();
            movegen.noisy(&self.moves, self.position);
            self.orderNoisyMoves();

            self.current = 0;
            continue :sw .emit_noisy;
        },
        .emit_noisy => {
            self.stage = .emit_noisy;
            if (self.current >= self.moves.len) continue :sw .movegen_quiet;
            const m = self.moves.storage[self.current];
            self.current += 1;
            return m;
        },
        .movegen_quiet => {
            if (self.skip_quiet) continue :sw .end;

            self.moves.clear();
            movegen.quiet(&self.moves, self.position);

            self.current = 0;
            continue :sw .emit_quiet;
        },
        .emit_quiet => {
            self.stage = .emit_quiet;
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

fn orderNoisyMoves(self: *MoveSelector) void {
    var scores: [MoveList.capacity]i32 = undefined;

    for (0..self.moves.len) |i| {
        const m = self.moves.storage[i];
        const src_ptype = self.position.whatAt(m.from()).ptype();
        const dst_ptype = self.position.whatAt(m.to()).ptype();
        scores[i] = mvv_table[dst_ptype.toIndex()] - lva_table[src_ptype.toIndex()];
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
