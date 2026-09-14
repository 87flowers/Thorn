pub fn compress(mask: anytype, src: anytype) @TypeOf(src) {
    const V = @TypeOf(src);
    const name = std.fmt.comptimePrint("llvm.x86.avx512.mask.compress.{s}.{}", .{
        switch (@bitSizeOf(@typeInfo(V).vector.child)) {
            8 => "b",
            16 => "w",
            32 => "d",
            64 => "q",
            else => unreachable,
        },
        @bitSizeOf(@TypeOf(src)),
    });
    return @extern(*const fn (V, V, MaskOf(V)) callconv(.c) V, .{ .name = name }).*(src, @splat(0), mask);
}

pub const has_compress = using_llvm and @import("builtin").cpu.has(.x86, .avx512vbmi2);

pub fn pext(x: u64, mask: u64) u64 {
    if (!using_llvm or @inComptime()) {
        var m: u64 = mask;
        var j: u6 = 0;
        var result: u64 = 0;
        while (m != 0) {
            const m_bit: u6 = @intCast(@ctz(m));
            const shifted_m = m >> m_bit;
            const isolated = shifted_m & ~(shifted_m +% 1);
            result |= ((x >> m_bit) & isolated) << j;
            j +%= @intCast(@popCount(isolated));
            m &= ~(isolated << m_bit);
        }
        return result;
    }
    return @extern(*const fn (u64, u64) callconv(.c) u64, .{ .name = "llvm.x86.bmi.pext.64" }).*(x, mask);
}

pub fn pdep(x: u64, mask: u64) u64 {
    if (!using_llvm or @inComptime()) {
        var m: u64 = mask;
        var j: u6 = 0;
        var result: u64 = 0;
        while (m != 0) {
            const m_bit: u6 = @intCast(@ctz(m));
            const shifted_m = m >> m_bit;
            const isolated = shifted_m & ~(shifted_m +% 1);
            result |= ((x >> j) & isolated) << m_bit;
            j +%= @intCast(@popCount(isolated));
            m &= ~(isolated << m_bit);
        }
        return result;
    }
    return @extern(*const fn (u64, u64) callconv(.c) u64, .{ .name = "llvm.x86.bmi.pdep.64" }).*(x, mask);
}

fn MaskOf(V: type) type {
    return @Int(.unsigned, @typeInfo(V).vector.len);
}

const using_llvm = @import("builtin").zig_backend == .stage2_llvm;

const std = @import("std");
