const std = @import("std");
pub const roadmap = @import("roadmap.zig");

// Comptime validation demonstrating Zig's primary superpower
comptime {
    std.debug.assert(roadmap.STAGES.len == 7);
}

test "roadmap stages count and integrity" {
    try std.testing.expectEqual(@as(usize, 7), roadmap.STAGES.len);
    try std.testing.expectEqual(@as(u8, 1), roadmap.STAGES[0].stage_number);
    try std.testing.expectEqual(@as(u8, 7), roadmap.STAGES[6].stage_number);
}

test "progress percentage calculation" {
    const completed = roadmap.getCompletedCount();
    try std.testing.expect(completed >= 2);

    const percent = roadmap.getProgressPercentage();
    try std.testing.expect(percent > 0 and percent <= 100);
}

test "explicit memory allocation with GeneralPurposeAllocator" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("Memory leak detected!");
    }
    const allocator = gpa.allocator();

    const slice = try allocator.alloc(u8, 64);
    defer allocator.free(slice);

    @memcpy(slice[0..13], "Hello Zig 0.13");
    try std.testing.expectEqualStrings("Hello Zig 0.13", slice[0..13]);
}
