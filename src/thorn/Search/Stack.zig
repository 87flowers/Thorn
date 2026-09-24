position: Position = undefined,
pv: Line = .{},
conthist: ?*Search.history.Continuation.Subtable = null,

const thorn = @import("../../thorn.zig");
const Line = thorn.Line;
const Position = thorn.Position;
const Score = thorn.score.Score;
const Search = thorn.Search;
