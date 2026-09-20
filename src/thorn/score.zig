pub const Score = i32;

pub const none: Score = -32768;
pub const infinity: Score = 32767;
pub const min_score: Score = -32766;
pub const max_score: Score = 32766;

pub const max_mate_ply = 256;
pub const min_normal_score = min_score + (max_mate_ply + 1);
pub const max_normal_score = max_score - (max_mate_ply + 1);

pub fn matedIn(ply: i32) Score {
    assert(ply >= 0);
    return @min(min_score + ply, min_normal_score);
}

pub fn matingIn(ply: i32) Score {
    assert(ply >= 0);
    return @min(max_score - ply, max_normal_score);
}

pub fn isTheoretical(s: Score) bool {
    return s < min_normal_score or s > max_normal_score;
}

pub fn distanceToMate(s: Score) ?i32 {
    if (!isTheoretical(s)) return null;
    return if (s < 0) s - min_score else max_score - s;
}

const std = @import("std");
const assert = std.debug.assert;
