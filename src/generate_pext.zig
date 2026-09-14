const IDENT = "    ";

fn generateTable(
    gpa: std.mem.Allocator,
    out: *std.Io.Writer,
    comptime name: []const u8,
    comptime dirs: [4]Dir,
    comptime attack_func: *const fn (SquareSet, Square) SquareSet,
) !void {
    var table: [64]SliderTable = @splat(.{ .mask = .empty, .offset = undefined });
    var entry_count: [64]usize = undefined;
    var total_entry_count: usize = 0;
    for (0..64) |i| {
        const sq: Square = .fromIndex(@intCast(i));
        for (dirs) |dir| {
            table[i].mask.insert(.rayMaskExceptLast(sq, dir));
        }
        entry_count[i] = @as(usize, 1) << @intCast(table[i].mask.popcount());
        table[i].offset = total_entry_count;
        total_entry_count += entry_count[i];
    }

    try out.print("pub const " ++ name ++ ": [64]SliderTable = .{{\n", .{});
    for (0..64) |i| {
        try out.print(IDENT ++ ".{{ .mask = 0x{X:016}, .offset = {} }},\n", .{ table[i].mask.raw, table[i].offset });
    }
    try out.print("}};\n\n", .{});

    const result_table = try gpa.alloc(SquareSet, total_entry_count);
    defer gpa.free(result_table);

    for (0..64) |i| {
        const sq: Square = .fromIndex(@intCast(i));
        const mask: SquareSet = table[i].mask;
        for (0..entry_count[i]) |j| {
            const occ: SquareSet = .make(intrin.pdep(j, mask.raw));
            result_table[table[i].offset + j] = attack_func.*(occ, sq);
        }
    }

    try out.print("pub const " ++ name ++ "_lut: [{}]u64 = .{{\n", .{total_entry_count});
    for (0..total_entry_count) |i| {
        if (i % 8 == 0) try out.print("   ", .{});
        try out.print(" 0x{X:016},", .{result_table[i].raw});
        if (i % 8 == 7) try out.print("\n", .{});
    }
    try out.print("}};\n\n", .{});
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len != 2) {
        std.debug.print("wrong number of arguments\n", .{});
        std.process.exit(1);
    }

    const out_path = args[1];

    var out_file = std.Io.Dir.cwd().createFile(io, out_path, .{}) catch |err| {
        std.debug.print("unable to open '{s}': {s}\n", .{ out_path, @errorName(err) });
        std.process.exit(1);
    };
    defer out_file.close(io);

    var out_buffer: [4096]u8 = undefined;
    var out_writer = out_file.writer(io, &out_buffer);
    const out = &out_writer.interface;
    defer out.flush() catch |err| std.debug.print("failed to flush: {}\n", .{err});

    try generateTable(gpa, out, "bishop", [4]Dir{ .ne, .nw, .se, .sw }, &attacks.bishopHq);
    try generateTable(gpa, out, "rook", [4]Dir{ .n, .e, .s, .w }, &attacks.rookHq);
    try out.print(
        \\const SliderTable = struct {{
        \\    mask: u64,
        \\    offset: usize,
        \\}};
    , .{});

    return std.process.cleanExit(io);
}

const SliderTable = struct {
    mask: SquareSet,
    offset: usize,
};

const std = @import("std");
const assert = std.debug.assert;
const thorn = @import("thorn.zig");
const attacks = thorn.attacks;
const intrin = thorn.util.intrin;
const Dir = thorn.Dir;
const Square = thorn.Square;
const SquareSet = thorn.SquareSet;
