//! Library root of the starter project. `main.zig` imports this module as
//! "learn_zig"; `zig build test` runs every test reachable from here.

const std = @import("std");

pub const text = @import("text.zig");
pub const ring = @import("ring.zig");
pub const config = @import("config.zig");
pub const router = @import("router.zig");
pub const roadmap = @import("roadmap.zig");

pub const RingBuffer = ring.RingBuffer;

// Checked by the compiler on every build, not by a test at runtime.
comptime {
    std.debug.assert(roadmap.STAGES.len == 7);
    for (roadmap.STAGES, 1..) |stage, n| std.debug.assert(stage.stage_number == n);
}

test {
    // Pull the tests of every imported file into `zig build test`.
    std.testing.refAllDecls(@This());
}

test "roadmap progress" {
    try std.testing.expectEqual(3, roadmap.getCompletedCount());
    try std.testing.expectEqual(42, roadmap.getProgressPercentage());
}

test "explicit allocation is checked for leaks by std.testing.allocator" {
    const gpa = std.testing.allocator;
    const greeting = "Hello, Zig";
    const copy = try gpa.alloc(u8, greeting.len);
    defer gpa.free(copy);
    @memcpy(copy, greeting);
    try std.testing.expectEqualStrings(greeting, copy);
}
