stage: enum {
    hint_move,
    movegen_noisy,
    emit_noisy,
    killer_move,
    movegen_quiet,
    emit_quiet,
    end,
} = .hint_move,

moves: MoveList = .new(),
current: usize = 0,

search: *Search,
ply: i32,
hint_move: Move,
killer_move: Move,

skip_quiet: bool = false,

pub fn new(search: *Search, ply: i32, hint_move: Move) MoveSelector {
    return .{
        .search = search,
        .ply = ply,
        .hint_move = hint_move,
        .killer_move = search.ss(ply).killer,
    };
}

pub fn skipQuiet(self: *MoveSelector) void {
    self.stage = switch (self.stage) {
        .hint_move => .hint_move,
        .movegen_noisy => .movegen_noisy,
        .emit_noisy => .emit_noisy,
        .killer_move => .end,
        .movegen_quiet => .end,
        .emit_quiet => .end,
        .end => .end,
    };
    self.skip_quiet = true;
}

pub fn next(self: *MoveSelector) ?Move {
    const position: *const Position = &self.search.ss(self.ply).position;

    sw: switch (self.stage) {
        .hint_move => {
            if (self.hint_move.isSome() and position.isLegal(self.hint_move)) {
                self.stage = .movegen_noisy;
                return self.hint_move;
            }
            continue :sw .movegen_noisy;
        },
        .movegen_noisy => {
            self.moves.clear();
            movegen.noisy(&self.moves, position);
            self.orderNoisyMoves();

            self.current = 0;
            continue :sw .emit_noisy;
        },
        .emit_noisy => {
            self.stage = .emit_noisy;
            while (self.current < self.moves.len) {
                const m = self.moves.storage[self.current];
                self.current += 1;
                if (m == self.hint_move) continue;
                return m;
            }
            continue :sw .killer_move;
        },
        .killer_move => {
            if (self.skip_quiet) continue :sw .end;

            if (self.killer_move != self.hint_move and
                self.killer_move.isSome() and
                position.isLegal(self.killer_move))
            {
                self.stage = .movegen_quiet;
                return self.killer_move;
            }
            continue :sw .movegen_quiet;
        },
        .movegen_quiet => {
            if (self.skip_quiet) continue :sw .end;

            self.moves.clear();
            movegen.quiet(&self.moves, position);
            self.orderQuietMoves();

            self.current = 0;
            continue :sw .emit_quiet;
        },
        .emit_quiet => {
            self.stage = .emit_quiet;
            while (self.current < self.moves.len) {
                const m = self.moves.storage[self.current];
                self.current += 1;
                if (m == self.hint_move) continue;
                if (m == self.killer_move) continue;
                return m;
            }
            continue :sw .end;
        },
        .end => {
            self.stage = .end;
            return null;
        },
    }
}

fn orderNoisyMoves(self: *MoveSelector) void {
    const position: *const Position = &self.search.ss(self.ply).position;

    var scores: [MoveList.capacity]i32 = undefined;

    for (0..self.moves.len) |i| {
        const m = self.moves.storage[i];
        const src_ptype = position.whatAt(m.from()).ptype();
        const dst_ptype = position.whatAt(m.to()).ptype();
        scores[i] = mvv_table[dst_ptype.toIndex()] - lva_table[src_ptype.toIndex()];
    }

    self.sort(&scores);
}

fn orderQuietMoves(self: *MoveSelector) void {
    const position: *const Position = &self.search.ss(self.ply).position;

    var scores: [MoveList.capacity]i32 = undefined;

    const stm = position.sideToMove();

    for (0..self.moves.len) |i| {
        const m = self.moves.storage[i];
        scores[i] = self.search.quiet_history.get(stm, m);
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
const Search = thorn.Search;
