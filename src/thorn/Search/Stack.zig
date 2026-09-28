position: Position = undefined,
pv: Line = .{},
move: Move = .none,
conthist: ?*Search.history.Continuation.Subtable = null,

const thorn = @import("../../thorn.zig");
const Line = thorn.Line;
const Move = thorn.Move;
const Position = thorn.Position;
const Search = thorn.Search;
const Score = thorn.score.Score;
