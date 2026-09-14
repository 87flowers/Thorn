position: Position,
hash_stack: StaticVec(Hash, 100),

pub const startpos: Game = blk: {
    var result: Game = .{
        .position = .startpos,
        .hash_stack = .new(),
    };
    result.hash_stack.push(.fromPosition(&Position.startpos));
    break :blk result;
};

pub fn setPosition(self: *Game, position: Position) void {
    self.position = position;
    self.hash_stack.clear();
    self.hash_stack.push(.fromPosition(&position));
}

pub fn move(self: *Game, m: Move) void {
    const new_hash = self.hash_stack.back().move(&self.position, m);

    var new_pos: Position = undefined;
    self.position.move(&new_pos, m);
    self.position = new_pos;

    if (new_pos.fifty_move_clock == 0) self.hash_stack.clear();
    self.hash_stack.push(new_hash);
}

const Game = @This();
const thorn = @import("../thorn.zig");
const Hash = thorn.Hash;
const Move = thorn.Move;
const Position = thorn.Position;
const StaticVec = thorn.util.StaticVec;
