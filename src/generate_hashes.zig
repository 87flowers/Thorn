/// represents polynomial of size 2^n
pub fn gf2(comptime n: u4) type {
    const T = @Int(.unsigned, n);
    const PP = @Int(.unsigned, n + 1);
    const primitive_polynomial: PP = switch (n) {
        3 => (1 << 3) + (1 << 1) + 1,
        4 => (1 << 4) + (1 << 1) + 1,
        5 => (1 << 5) + (1 << 2) + 1,
        6 => (1 << 6) + (1 << 1) + 1,
        7 => (1 << 7) + (1 << 1) + 1,
        8 => (1 << 8) + (1 << 4) + (1 << 3) + (1 << 2) + 1,
        9 => (1 << 9) + (1 << 4) + 1,
        10 => (1 << 10) + (1 << 3) + 1,
        11 => (1 << 11) + (1 << 2) + 1,
        12 => (1 << 12) + (1 << 6) + (1 << 4) + (1 << 1) + 1,
        13 => (1 << 13) + (1 << 4) + (1 << 3) + (1 << 1) + 1,
        14 => (1 << 14) + (1 << 8) + (1 << 6) + (1 << 1) + 1,
        15 => (1 << 15) + (1 << 1) + 1,
        else => unreachable,
    };
    const trunc_pp: T = @truncate(primitive_polynomial);
    return struct {
        const bit_count = n;
        value: T = 0,

        pub fn init(value: T) @This() {
            return .{ .value = value };
        }

        pub fn msb(a: @This()) u1 {
            return @truncate(a.value >> (n - 1));
        }

        pub fn add(a: @This(), b: @This()) @This() {
            return .{ .value = a.value ^ b.value };
        }

        pub fn double(a: @This()) @This() {
            return .{ .value = (a.value << 1) ^ (a.msb() * trunc_pp) };
        }

        pub fn mul(a: @This(), b: @This()) @This() {
            var result: @This() = .{};
            for (0..n) |i| {
                result = result.double();
                const bit: u1 = @truncate(b.value >> @truncate(n - i - 1));
                if (bit == 1) {
                    result = result.add(a);
                }
            }
            return result;
        }

        pub fn pow(a: @This(), e: usize) @This() {
            var result = @This().init(1);
            for (0..e) |_| {
                result = result.mul(a);
            }
            return result;
        }

        pub fn evalWithPoly(x: @This(), poly: anytype) @This() {
            comptime assert(@typeInfo(@TypeOf(poly)) == .int and @typeInfo(@TypeOf(poly)).int.signedness == .unsigned);

            var result = @This().init(0);
            var term = @This().init(1);
            var p = poly;
            while (p != 0) : (p >>= 1) {
                const bit: u1 = @truncate(p);
                if (bit == 1) {
                    result = result.add(term);
                }
                term = term.mul(x);
            }
            return result;
        }

        pub fn findMinPoly(x: @This()) PP {
            var poly: PP = 1;
            while (true) : (poly += 1) {
                if (x.evalWithPoly(poly).value == 0) {
                    return poly;
                }
            }
        }
    };
}

pub fn MinPoly(comptime n: u4) type {
    return @Int(.unsigned, n + 1);
}

pub fn MinPolys(comptime n: u4) type {
    return std.ArrayList(MinPoly(n));
}

pub fn Generator(comptime n: u4) type {
    return @Int(.unsigned, 1 << n);
}

pub fn Generators(comptime n: u4) type {
    return std.ArrayList(Generator(n));
}

pub fn clmul(comptime T: type, a: T, b: T) T {
    comptime assert(@typeInfo(T) == .int and @typeInfo(T).int.signedness == .unsigned);
    const n = @typeInfo(T).int.bits;
    var result: T = 0;
    for (0..n) |i| {
        result <<= 1;
        const bit: u1 = @truncate(b >> @truncate(n - i - 1));
        if (bit == 1) {
            result ^= a;
        }
    }
    return result;
}

/// Ownership of ArrayList belongs to caller
pub fn generateMinPolys(gpa: std.mem.Allocator, comptime n: u4) std.mem.Allocator.Error!MinPolys(n) {
    const a = gf2(n).init(2);
    var result = try MinPolys(n).initCapacity(gpa, 1 << n - 1);
    for (1..1 << n - 1) |i| {
        const poly = a.pow(i).findMinPoly();
        if (!std.mem.containsAtLeast(@TypeOf(poly), result.items, 1, &.{poly})) {
            try result.append(gpa, poly);
        }
    }
    return result;
}

/// Ownership of ArrayList belongs to caller
pub fn generateGenerators(gpa: std.mem.Allocator, comptime n: u4, min_polys: MinPolys(n)) std.mem.Allocator.Error!Generators(n) {
    var result = try Generators(n).initCapacity(gpa, min_polys.items.len);
    try result.append(gpa, min_polys.items[0]);
    for (1..min_polys.items.len) |i| {
        const prev = result.items[i - 1];
        try result.append(gpa, clmul(Generator(n), prev, min_polys.items[i]));
    }
    return result;
}

pub fn mod(comptime T: type, a: T, b: T) struct { T, T } {
    comptime assert(@typeInfo(T) == .int and @typeInfo(T).int.signedness == .unsigned);
    const n = @typeInfo(T).int.bits;
    const lim = @clz(b);
    var quotient: T = 0;
    var rem = a;
    for (0..lim + 1) |i| {
        const bit: u1 = @truncate(rem >> @truncate(n - i - 1));
        quotient <<= 1;
        if (bit == 1) {
            rem ^= b << @truncate(lim - i);
            quotient |= 1;
        }
    }
    return .{ quotient, rem };
}

pub fn bitWidth(x: anytype) usize {
    const max_bitwidth = @typeInfo(@TypeOf(x)).int.bits;
    return max_bitwidth - @clz(x);
}

pub fn pickGenerator(gpa: std.mem.Allocator, comptime n: u4, min_generator_bitwidth: usize) !Generator(n) {
    const min_polys = try generateMinPolys(gpa, n);
    defer min_polys.deinit();

    const generators = try generateGenerators(n, min_polys);
    defer generators.deinit();

    for (generators.items) |g| {
        if (bitWidth(g) >= min_generator_bitwidth) return g;
    }
    @panic("panic!");
}

pub fn rowBits(comptime n: u4) usize {
    return (1 << n) - 1;
}

pub fn Row(comptime n: u4) type {
    return @Int(.unsigned, rowBits(n));
}

pub fn Matrix(comptime n: u4) type {
    return [rowBits(n)]Row(n);
}

pub fn genBasisMatrix(gpa: std.mem.Allocator, comptime n: u4, m: usize, rot: usize) !Matrix(n) {
    var min_polys = try generateMinPolys(gpa, n);
    defer min_polys.deinit(gpa);

    try min_polys.append(gpa, 0b11);
    std.mem.rotate(MinPoly(n), min_polys.items, rot);

    var generators = try generateGenerators(gpa, n, min_polys);
    defer generators.deinit(gpa);

    var use_gs = try std.ArrayList(Row(n)).initCapacity(gpa, 0);
    defer use_gs.deinit(gpa);

    try use_gs.append(gpa, 0);
    try use_gs.append(gpa, 1);
    for (generators.items) |g| {
        try use_gs.append(gpa, @truncate(g));
        if (bitWidth(g) >= m) {
            break;
        }
    }
    std.mem.reverse(Row(n), use_gs.items);

    var result: Matrix(n) = undefined;
    var g_index: usize = 0;
    for (0..rowBits(n)) |i| {
        while (i > @ctz(@bitReverse(use_gs.items[g_index]))) g_index += 1;
        result[i] = @bitReverse(use_gs.items[g_index]) >> @truncate(i);
    }
    return result;
}

pub fn genParityMatrix(comptime n: u4, bm: Matrix(n)) Matrix(n) {
    var result = bm;
    for (0..rowBits(n)) |j| {
        const i = rowBits(n) - j - 1;
        for (0..j) |k| {
            const mask = @as(Row(n), 1) << @truncate(i);
            const bit = result[k] & mask;
            if (bit != 0) result[k] ^= result[j] & ~mask;
        }
    }
    return result;
}

const N = 8;

pub fn get(pm: Matrix(N), i: usize) u64 {
    assert(i < 256);
    assert(pm.len == 255);
    const row = if (i == 255) specialHash(pm) else pm[i];
    const k: u64 = @truncate(row);
    return k;
}

pub fn specialHash(pm: Matrix(N)) Row(N) {
    assert(pm.len == 255);
    var hash: Row(N) = 0;
    for (0..64) |i| {
        for (0..3) |j| {
            hash ^= pm[i + 64 * j];
        }
    }
    return hash;
}

pub fn mungeHash(h: u64) u64 {
    return (@bitReverse(h) << 16) | (h & 0xFFFF);
}

pub fn getHash(pm: Matrix(N), sq: usize, ptype: usize) u64 {
    assert(sq < 64);
    assert(ptype < 16);
    var hash: u64 = 0;
    hash ^= if ((ptype & (1 << 0)) != 0) get(pm, sq + 64 * 0) else 0;
    hash ^= if ((ptype & (1 << 1)) != 0) get(pm, sq + 64 * 1) else 0;
    hash ^= if ((ptype & (1 << 2)) != 0) get(pm, sq + 64 * 2) else 0;
    hash ^= if ((ptype & (1 << 3)) != 0) get(pm, sq + 64 * 3) else 0;
    return mungeHash(hash);
}

pub fn getCastleHash(pm: Matrix(N), castle: usize) u64 {
    var hash: u64 = 0;
    hash ^= if ((castle & (1 << 0)) != 0) getHash(pm, 0, 3 ^ 7) else 0;
    hash ^= if ((castle & (1 << 1)) != 0) getHash(pm, 7, 3 ^ 7) else 0;
    hash ^= if ((castle & (1 << 2)) != 0) getHash(pm, 56, 3 ^ 7) else 0;
    hash ^= if ((castle & (1 << 3)) != 0) getHash(pm, 63, 3 ^ 7) else 0;
    return mungeHash(hash);
}

pub fn getStmHash(pm: Matrix(N)) u64 {
    var hash: u64 = 0;
    for (0..63) |i| {
        hash ^= getHash(pm, i, 8);
    }
    return mungeHash(hash);
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

    const bm = try genBasisMatrix(gpa, N, 64, 0);
    const pm = genParityMatrix(N, bm);

    const IDENT = "    ";

    try out.print("pub const piece: [2][6][64]u64 = .{{\n", .{});
    for (0..2) |c| {
        try out.print(IDENT ++ ".{{\n", .{});
        for (1..7) |p| {
            try out.print(IDENT ++ IDENT ++ ".{{\n", .{});
            for (0..64) |i| {
                if (i % 8 == 0) try out.print(IDENT ++ IDENT ++ "   ", .{});
                const h: u64 = getHash(pm, i, p + c * 8);
                try out.print(" 0x{X:016},", .{h});
                if (i % 8 == 7) try out.print("\n", .{});
            }
            try out.print(IDENT ++ IDENT ++ "}},\n", .{});
        }
        try out.print(IDENT ++ "}},\n", .{});
    }
    try out.print("}};\n\n", .{});

    try out.print("pub const enpassant: [64]u64 = .{{\n", .{});
    for (0..64) |i| {
        if (i % 8 == 0) try out.print("   ", .{});
        const h: u64 = getHash(pm, i, 7);
        try out.print(" 0x{X:016},", .{h});
        if (i % 8 == 7) try out.print("\n", .{});
    }
    try out.print("}};\n\n", .{});

    try out.print("pub const castle: [16]u64 = .{{\n", .{});
    for (0..16) |i| {
        if (i % 8 == 0) try out.print("   ", .{});
        const h: u64 = getCastleHash(pm, i);
        try out.print(" 0x{X:016},", .{h});
        if (i % 8 == 7) try out.print("\n", .{});
    }
    try out.print("}};\n\n", .{});

    try out.print("pub const stm = 0x{X:016};\n\n", .{getStmHash(pm)});

    return std.process.cleanExit(io);
}

const std = @import("std");
const assert = std.debug.assert;
