position: Position = undefined,
hash: Hash = .empty,
pv: Line = .{},
move: Move = .none,
killer: Move = .none,

const thorn = @import("../../thorn.zig");
const Hash = thorn.Hash;
const Line = thorn.Line;
const Move = thorn.Move;
const Position = thorn.Position;
const Score = thorn.score.Score;
