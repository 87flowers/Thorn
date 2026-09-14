pub fn Broadcast(comptime T: type) type {
    return struct {
        msg: std.atomic.Value(*const T),
        futex: std.atomic.Value(u32),
        reader_count: u31,

        pub fn new(reader_count: u31) Self {
            return .{
                .msg = .init(null),
                .futex = .{
                    .count = 0,
                    .generation = 0,
                },
                .reader_count = reader_count,
            };
        }

        pub fn createReceiver(self: *Self) Receiver {
            return .{
                .sender = self,
                .generation = 0,
            };
        }

        pub fn broadcast(self: *Self, io: std.Io, msg: *const T) void {
            const prev: Futex = @bitCast(self.futex.load(.acquire));
            assert(prev.count == 0);

            self.msg.store(msg, .unordered);

            self.futex.store(@bitCast(Futex{
                .generation = ~prev.generation,
                .count = self.reader_count,
            }), .release);
            io.futexWake(u32, &self.futex.raw, self.reader_count);

            while (true) {
                const f: Futex = @bitCast(self.futex.load(.acquire));
                if (f.count == 0) break;
                io.futexWaitUncancelable(u32, &self.futex.raw, @bitCast(f));
            }

            self.msg.store(null, .unordered);
        }

        pub const Receiver = struct {
            sender: *Self,
            generation: u1,

            pub fn wait(self: *Receiver, io: std.Io) *const T {
                while (true) {
                    const f = @atomicLoad(Futex, &self.sender.futex, .acquire);
                    if (f.generation != self.generation) break;
                    io.futexWaitUncancelable(Futex, &self.sender.futex, f);
                }

                self.generation = ~self.generation;

                return self.sender.msg;
            }

            pub fn done(self: *Receiver, io: std.Io) void {
                const f: Futex = @bitCast(self.sender.futex.rmw(.Sub, @bitCast(Futex{
                    .count = 1,
                    .generation = 0,
                }), .release));

                if (f.count == 1) io.futexWake(u32, &self.sender.futex.raw, self.sender.reader_count);
            }
        };

        const Self = @This();
    };
}

const Futex = packed struct(u32) {
    count: u31,
    generation: u1,
};

const std = @import("std");
const assert = std.debug.assert;
