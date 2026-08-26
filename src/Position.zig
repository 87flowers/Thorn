attack_set: [2][16]SquareSet,
danger: SquareSet,
pinned: SquareSet,
checkers: SquareSet,

piece_mailbox: [64]Piece,
id_mailbox: [64]PieceId,

color_set: [2]SquareSet,
ptype_set: [6]SquareSet,

piece_list_sq: [2][16]Square,
piece_list_ptype: [2][16]PieceType,

enpassant: Square,
fifty_move_clock: u16,
ply_since_null: u16,
ply: u16,

castling: Castling,

pub fn colorSet(self: *const Position, color: Color) SquareSet {
    return self.color_set[color.toIndex()];
}

pub fn ptypeSet(self: *const Position, ptype: PieceType) SquareSet {
    return self.ptype_set[ptype.toIndex()];
}

pub fn sideToMove(self: *const Position) Color {
    return @enumFromInt(self.ply % 2);
}

pub fn turnClock(self: *const Position) u16 {
    return self.ply / 2 + 1;
}

pub fn kingSq(self: *const Position, color: Color) Square {
    return self.piece_list_sq[color.toIndex()][0];
}

pub fn occupiedSet(self: *const Position) SquareSet {
    return self.color_set[0].bitOr(self.color_set[1]);
}

// Caller has ownership of string
pub fn parse(str: []const u8) !Position {
    var it = std.mem.tokenizeAny(u8, str, " \t\r\n");
    const board_str = it.next() orelse return ParseError.InvalidLength;
    const color_str = it.next() orelse return ParseError.InvalidLength;
    const castle_str = it.next() orelse return ParseError.InvalidLength;
    const enpassant_str = it.next() orelse return ParseError.InvalidLength;
    const fifty_move_clock_str = it.next() orelse return ParseError.InvalidLength;
    const turns_str = it.next() orelse return ParseError.InvalidLength;
    if (it.next() != null) return ParseError.InvalidLength;
    return parseParts(board_str, color_str, castle_str, enpassant_str, fifty_move_clock_str, turns_str);
}

// Caller has ownership of all strings
pub fn parseParts(board_str: []const u8, color_str: []const u8, castle_str: []const u8, enpassant_str: []const u8, fifty_move_clock_str: []const u8, turns_str: []const u8) !Position {
    var position: Position = .{
        .attack_set = @splat(@splat(SquareSet.empty)),
        .danger = .empty,
        .pinned = .empty,
        .checkers = .empty,
        .piece_mailbox = @splat(Piece.none),
        .id_mailbox = @splat(PieceId.none),
        .color_set = @splat(SquareSet.empty),
        .ptype_set = @splat(SquareSet.empty),
        .piece_list_sq = @splat(@splat(Square.none)),
        .piece_list_ptype = @splat(@splat(PieceType.none)),
        .enpassant = Square.none,
        .fifty_move_clock = 0,
        .ply_since_null = 0,
        .ply = 0,
        .castling = Castling.empty,
    };

    // Parse board
    {
        var next_id: [2]u8 = .{ 1, 1 };
        var i: usize = 0;
        var file: u8 = 0;
        var rank: u8 = 7;
        while (rank >= 0 and i < board_str.len) : (i += 1) {
            switch (board_str[i]) {
                '/' => {
                    if (file != 8 or rank == 0) return ParseError.InvalidBoard;
                    rank -= 1;
                    file = 0;
                },
                '1', '2', '3', '4', '5', '6', '7', '8' => |ch| {
                    file += ch - '0';
                    if (file > 8) return ParseError.InvalidBoard;
                },
                else => |ch| {
                    if (file >= 8) return ParseError.InvalidBoard;

                    const sq = Square.fromFileAndRank(file, rank);
                    const piece = try Piece.parse(ch);
                    const color = piece.color();
                    const ptype = piece.ptype();
                    const id = blk: {
                        if (piece.ptype() == .k) {
                            if (position.piece_list_sq[color.toIndex()][0].isSome()) return ParseError.TooManyKings;
                            break :blk 0;
                        }
                        const id = next_id[color.toIndex()];
                        if (id >= 16) return ParseError.TooManyPieces;
                        next_id[color.toIndex()] += 1;
                        break :blk id;
                    };

                    position.piece_mailbox[sq.toIndex()] = piece;
                    position.id_mailbox[sq.toIndex()] = @enumFromInt(id);
                    position.color_set[color.toIndex()].write(sq, true);
                    position.ptype_set[ptype.toIndex()].write(sq, true);
                    position.piece_list_sq[color.toIndex()][id] = sq;
                    position.piece_list_ptype[color.toIndex()][id] = ptype;

                    file += 1;
                },
            }
        }

        if (rank != 0 or file != 8 or i != board_str.len) return ParseError.InvalidLength;
        if (position.piece_list_ptype[0][0] != .k) return ParseError.InvalidBoard;
        if (position.piece_list_ptype[1][0] != .k) return ParseError.InvalidBoard;
    }

    // Parse color
    if (color_str.len != 1) return ParseError.InvalidLength;
    const stm = try Color.parse(color_str[0]);

    // Parse castling
    if (!std.mem.eql(u8, castle_str, "-")) {
        for (castle_str) |ch| {
            const color, const file = blk: {
                const color, var f: i8, const dir: i8 = switch (ch) {
                    // Scan required
                    'Q' => .{ Color.white, 0, 1 },
                    'K' => .{ Color.white, 7, -1 },
                    'q' => .{ Color.black, 0, 1 },
                    'k' => .{ Color.black, 7, -1 },
                    // Scanning not required, location directly specified
                    'A'...'H' => break :blk .{ .white, ch - 'A' },
                    'a'...'h' => break :blk .{ .black, ch - 'a' },
                    // Invalid
                    else => return ParseError.InvalidChar,
                };

                // Scan for rook
                while (f >= 0 and f <= 7) : (f += dir) {
                    const file: u8 = @intCast(f);
                    const sq = Square.fromFileAndRank(file, color.homeRank());
                    const piece = position.piece_mailbox[sq.toIndex()];
                    if (piece.color() == color and piece.ptype() == .r)
                        break :blk .{ color, file };
                    if (piece.color() == color and piece.ptype() == .k)
                        return ParseError.InvalidBoard;
                }
                return ParseError.InvalidBoard;
            };

            const rook_sq = Square.fromFileAndRank(file, color.homeRank());
            const king_sq = position.piece_list_sq[color.toIndex()][0];

            const maybe_rook = position.piece_mailbox[rook_sq.toIndex()];

            if (maybe_rook.color() != color or maybe_rook.ptype() != .r) return ParseError.InvalidBoard;
            if (king_sq.rank() != color.homeRank()) return ParseError.InvalidBoard;

            if (rook_sq.file() < king_sq.file()) position.castling.write(color, .a, rook_sq);
            if (rook_sq.file() > king_sq.file()) position.castling.write(color, .h, rook_sq);
        }
    }

    // Parse enpassant square
    if (!std.mem.eql(u8, enpassant_str, "-"))
        position.enpassant = try Square.parse(enpassant_str);

    // Parse fifty move clock
    position.fifty_move_clock = try std.fmt.parseUnsigned(u8, fifty_move_clock_str, 10);
    if (position.fifty_move_clock > 100) return ParseError.OutOfRange;

    // Parse turns
    const turns = try std.fmt.parseUnsigned(u16, turns_str, 10);
    if (turns == 0 or turns > 10000) return ParseError.OutOfRange;
    position.ply = (turns - 1) * 2 + @as(u16, @intCast(stm.toIndex()));

    position.recalculateAttacks();
    position.recalculateDanger();

    return position;
}

pub fn format(self: *const Position, writer: *std.Io.Writer) !void {
    var blanks: u32 = 0;
    for (0..64) |i| {
        const piece = self.piece_mailbox[i ^ 0b111000];

        if (piece.isNone()) {
            blanks += 1;
        } else {
            if (blanks != 0) {
                try writer.print("{}", .{blanks});
                blanks = 0;
            }
            try writer.print("{f}", .{piece});
        }

        if (i % 8 == 7) {
            if (blanks != 0) {
                try writer.print("{}", .{blanks});
                blanks = 0;
            }
            if (i != 63) try writer.print("/", .{});
        }
    }
    try writer.print(" {f}", .{self.sideToMove()});

    try writer.print(" ", .{});
    if (self.castling.isEmpty()) {
        try writer.print("-", .{});
    } else {
        const is_classical = self.castling.maybeClassical() and
            (if (self.castling.hasColor(.white)) self.kingSq(.white) == .e1 else true) and
            (if (self.castling.hasColor(.black)) self.kingSq(.black) == .e8 else true);

        if (is_classical) {
            if (self.castling.read(.white, .h).isSome()) try writer.print("K", .{});
            if (self.castling.read(.white, .a).isSome()) try writer.print("Q", .{});
            if (self.castling.read(.black, .h).isSome()) try writer.print("k", .{});
            if (self.castling.read(.black, .a).isSome()) try writer.print("q", .{});
        } else {
            inline for ([_]Castling.Side{ .h, .a }) |side| {
                const sq = self.castling.read(.white, side);
                if (sq.isSome()) try writer.print("{c}", .{'A' + sq.file()});
            }
            inline for ([_]Castling.Side{ .h, .a }) |side| {
                const sq = self.castling.read(.black, side);
                if (sq.isSome()) try writer.print("{c}", .{'a' + sq.file()});
            }
        }
    }

    try if (self.enpassant.isNone()) writer.print(" -", .{}) else writer.print(" {f}", .{self.enpassant});
    try writer.print(" {}", .{self.fifty_move_clock});
    try writer.print(" {}", .{self.turnClock()});
}

fn recalculateAttacks(self: *Position) void {
    const occ = self.occupiedSet();
    for ([_]Color{ .white, .black }) |color| {
        for (0..16) |id| {
            const ptype = self.piece_list_ptype[color.toIndex()][id];
            const sq = self.piece_list_sq[color.toIndex()][id];
            self.attack_set[color.toIndex()][id] = attacks.ptype(ptype, occ, sq, color);
        }
    }
}

fn recalculateDanger(self: *Position) void {
    const stm = self.sideToMove();

    const king = self.kingSq(stm);
    const friend = self.colorSet(stm);
    const enemy = self.colorSet(stm.invert());
    const diagonal = enemy.bitAnd(self.ptypeSet(.b).bitOr(self.ptypeSet(.q))).bitAnd(attacks.bishop(enemy, king));
    const orthogonal = enemy.bitAnd(self.ptypeSet(.r).bitOr(self.ptypeSet(.q))).bitAnd(attacks.rook(enemy, king));

    self.pinned = .empty;
    self.checkers = .empty;

    var potential_pinners = diagonal.bitOr(orthogonal).iter();
    while (potential_pinners.next()) |sq| {
        const blockers = rays.between(king, sq).bitAnd(friend);
        switch (blockers.popcount()) {
            0 => self.checkers.write(sq, true),
            1 => self.pinned = self.pinned.bitOr(blockers),
            else => {},
        }
    }

    // TODO: Vectorize
    self.danger = .empty;
    for (0..16) |i| {
        self.danger = self.danger.bitOr(self.attack_set[stm.invert().toIndex()][i]);
    }
    var checkers_iter = self.checkers.iter();
    while (checkers_iter.next()) |checker| {
        self.danger = self.danger.bitOr(rays.past(checker, king));
    }
}

pub const Castling = struct {
    raw: @Vector(4, u8),

    pub const empty: Castling = .{ .raw = @splat(@intFromEnum(Square.none)) };

    fn isEmpty(self: Castling) bool {
        return @reduce(.And, self.raw == empty.raw);
    }

    // Determine if castleable rooks are in classical starting position.
    fn maybeClassical(self: Castling) bool {
        const classical_full = @Vector(4, u8){
            @intFromEnum(Square.a1),
            @intFromEnum(Square.h1),
            @intFromEnum(Square.a8),
            @intFromEnum(Square.h8),
        };
        return @reduce(.And, (self.raw == classical_full) | (self.raw == empty.raw));
    }

    fn read(self: Castling, color: Color, side: Side) Square {
        return switch (color.toIndex() * 2 + @intFromEnum(side)) {
            inline 0, 1, 2, 3 => |x| @enumFromInt(self.raw[x]),
            else => unreachable,
        };
    }

    fn write(self: *Castling, color: Color, side: Side, sq: Square) void {
        switch (color.toIndex() * 2 + @intFromEnum(side)) {
            inline 0, 1, 2, 3 => |x| self.raw[x] = @intFromEnum(sq),
            else => unreachable,
        }
    }

    fn clear(self: Castling, color: Color) void {
        self.raw[color.toIndex() * 2 + 0] = .none;
        self.raw[color.toIndex() * 2 + 1] = .none;
    }

    fn unset(self: *Castling, sq: Square) void {
        const needle: @Vector(4, u8) = @splat(sq.raw);
        self.raw = @select(u8, self.raw == needle, empty.raw, self.raw);
    }

    fn hasColor(self: Castling, color: Color) bool {
        assert(@intFromEnum(Square.none) == 0x80);
        const x: [2]u16 = @bitCast(self.raw);
        return x[color.toIndex()] != 0x8080;
    }

    fn hasSquare(self: Castling, sq: Square) void {
        const needle: @Vector(4, u8) = @splat(sq.raw);
        return @reduce(.Or, self.raw == needle);
    }

    fn toIndex(self: Castling) u4 {
        assert(@intFromEnum(Square.none) == 0x80);
        return @bitCast((self.raw & empty.raw) == empty.raw);
    }

    pub const Side = enum(usize) { a = 0, h = 1 };
};

test "roundtrip fens" {
    const cases = [_][]const u8{
        "7r/3r1p1p/6p1/1p6/2B5/5PP1/1Q5P/1K1k4 b - - 0 38",
        "2n1r1n1/1p1k1p2/6pp/R2pP3/3P4/8/5PPP/2R3K1 b - - 0 30",
        "8/5p2/1kn1r1n1/1p1pP3/6K1/8/4R3/5R2 b - - 9 60",
        "r3k2r/pp1bnpbp/1q3np1/3p4/3N1P2/1PP1Q2P/P1B3P1/RNB1K2R b KQkq - 5 15",
        "7r/3r1p1p/6p1/1p6/2B5/5PP1/1Q5P/1K1k4 b - - 0 38",
        "r3k2r/pp1bnpbp/1q3np1/3p4/3N1P2/1PP1Q2P/P1B3P1/RNB1K2R b KQkq - 5 15",
        "8/5p2/1kn1r1n1/1p1pP3/6K1/8/4R3/5R2 b - - 9 60",
        "r4rk1/1Bp1qppp/2np1n2/1pb1p1B1/4P1b1/P1NP1N2/1PP1QPPP/R4RK1 b - b6 1 11",
        "2r1kr2/8/8/8/8/8/8/1R2K1R1 w GBfc - 0 1",
        "rkr5/8/8/8/8/8/8/5RKR w HFca - 0 1",
        "2r3kr/8/8/8/8/8/8/2KRR3 w h - 3 2",
        "5rkr/8/8/8/8/8/8/RKR5 w CAhf - 0 1",
        "3rkr2/8/8/8/8/8/8/R3K2R w HAfd - 0 1",
        "4k3/8/8/8/8/8/8/4KR2 w F - 0 1",
        "4kr2/8/8/8/8/8/8/4K3 w f - 0 1",
        "4k3/8/8/8/8/8/8/2R1K3 w C - 0 1",
        "2r1k3/8/8/8/8/8/8/4K3 w c - 0 1",
    };
    for (cases) |case| {
        const position = try Position.parse(case);
        var tmp: [128]u8 = undefined;
        const fen = try std.fmt.bufPrint(&tmp, "{f}", .{position});
        try std.testing.expectEqualStrings(case, fen);
    }
}

const Position = @This();
const std = @import("std");
const assert = std.debug.assert;
const thorn = @import("root.zig");
const attacks = thorn.attacks;
const rays = thorn.rays;
const Color = thorn.Color;
const ParseError = thorn.ParseError;
const Piece = thorn.Piece;
const PieceId = thorn.PieceId;
const PieceSet = thorn.PieceSet;
const PieceType = thorn.PieceType;
const Square = thorn.Square;
const SquareSet = thorn.SquareSet;
