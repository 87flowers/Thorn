pub const Has = packed struct(u3) { time: bool, depth: bool, nodes: bool };

pub const none: Control(.{ .time = false, .depth = false, .nodes = false }) = undefined;

pub fn Control(has: Has) type {
    return struct {
        time_limit: if (has.time) struct { soft: i64, hard: i64 } else void,
        depth_limit: if (has.depth) struct { target_depth: i32 } else void,
        nodes_limit: if (has.nodes) struct { soft: ?u64, hard: ?u64 } else void,

        pub fn checkSoftTermination(self: *const @This(), search: *Search, depth: i32) bool {
            if (has.time and self.time_limit.soft <= getMs(search)) return true;
            if (has.depth and depth >= self.depth_limit.target_depth) return true;
            if (has.nodes) if (self.nodes_limit.soft) |soft| if (getNodes(search) >= soft) return true;
            return false;
        }

        pub fn checkHardTermination(self: *const @This(), search: *Search) bool {
            if (has.time and getNodes(search) % 1024 == 0) {
                std.debug.print("{}\r", .{getMs(search)});
                if (self.time_limit.hard <= getMs(search)) return true;
            }
            if (has.nodes) if (self.nodes_limit.hard) |hard| if (getNodes(search) >= hard) return true;
            return false;
        }

        fn getMs(search: *Search) i64 {
            return search.search_start.untilNow(search.io, .awake).toMilliseconds();
        }

        fn getNodes(search: *Search) u64 {
            return search.nodes.load(.monotonic);
        }
    };
}

const std = @import("std");
const thorn = @import("../../thorn.zig");
const Search = thorn.Search;
