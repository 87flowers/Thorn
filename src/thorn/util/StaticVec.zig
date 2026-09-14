pub fn StaticVec(comptime T: type, comptime capacity: usize) type {
    return struct {
        len: usize,
        storage: [capacity]T,

        pub fn new() Self {
            return .{
                .storage = undefined,
                .len = 0,
            };
        }

        pub fn push(self: *Self, item: T) void {
            assert(self.len < capacity);
            self.storage[self.len] = item;
            self.len += 1;
        }

        pub fn constSlice(self: *const Self) []const T {
            return self.storage[0..self.len];
        }

        pub fn back(self: *Self) T {
            assert(self.len > 0);
            return self.storage[self.len - 1];
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
        }

        pub fn format(self: *const Self, writer: *Writer) Writer.Error!void {
            if (T != u8) @compileError("Attempted to print non-u8 StaticVec");
            return writer.print("{s}", .{self.constSlice()});
        }

        const Self = @This();
    };
}

const std = @import("std");
const assert = std.debug.assert;
const Writer = std.Io.Writer;
