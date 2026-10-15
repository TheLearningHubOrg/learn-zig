const std = @import("std");
const root = @import("root");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // Explicit memory management using GeneralPurposeAllocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.debug.print("CRITICAL: Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    try stdout.print("\n======================================================\n", .{});
    try stdout.print("   The Learning Hub - Zig 0.13+ Systems Architecture\n", .{});
    try stdout.print("======================================================\n", .{});
    try stdout.print("Philosophy: Robustness, Optimal Performance, Maintainability\n", .{});
    try stdout.print("Memory Model: Zero Hidden Control Flow, Explicit Allocators\n\n", .{});

    // Allocate dynamic banner message demonstration
    const dynamic_msg = try std.fmt.allocPrint(
        allocator,
        "Running on Zig {}.{}.{} [{s}]",
        .{
            std.builtin.zig_version.major,
            std.builtin.zig_version.minor,
            std.builtin.zig_version.patch,
            @tagName(std.builtin.target.os.tag),
        },
    );
    defer allocator.free(dynamic_msg);

    try stdout.print("Status: {s}\n\n", .{dynamic_msg});
    try stdout.print("7-Stage Pedagogical Roadmap:\n", .{});
    try stdout.print("------------------------------------------------------\n", .{});

    for (root.roadmap.STAGES) |stage| {
        const icon = if (stage.completed) "[OK]" else "[..]";
        try stdout.print(" {s} Stage {d}: {s}\n", .{ icon, stage.stage_number, stage.title });
        try stdout.print("      Focus: {s}\n", .{stage.domain_focus});
    }

    const completed = root.roadmap.getCompletedCount();
    const percent = root.roadmap.getProgressPercentage();
    try stdout.print("------------------------------------------------------\n", .{});
    try stdout.print("Progress: {d}/7 Stages Complete ({d}%)\n", .{ completed, percent });
    try stdout.print("======================================================\n\n", .{});
}
