position: Position,
hash_stack: StaticVec(Hash, 100),

pub const startpos: Game = blk: {
    var result: Game = .{
        .position = .startpos,
        .hash_stack = .new(),
    };
    result.hash_stack.push(.fromPosition(.startpos));
    break :blk result;
};

pub fn move(self: *Game, m: Move) void {
    var new_pos: Position = undefined;
    self.position.move(&new_pos, m);
    self.position.* = new_pos;

    const new_hash = self.hash_stack.back().move(m);
    if (new_pos.fifty_move_clock == 0) self.hash_stack.clear();
    self.hash_stack.push(new_hash);
}

const Game = @This();
const thorn = @import("root.zig");
const Hash = thorn.Hash;
const Move = thorn.Move;
const Position = thorn.Position;
const StaticVec = thorn.util.StaticVec;
