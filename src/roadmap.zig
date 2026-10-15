const std = @import("std");

pub const RoadmapStage = struct {
    stage_number: u8,
    title: []const u8,
    domain_focus: []const u8,
    completed: bool,
};

pub const STAGES = [_]RoadmapStage{
    .{
        .stage_number = 1,
        .title = "Syntax, Primitive Types & Memory Layout",
        .domain_focus = "Variables (const/var), integers, floats, pointers, and memory alignment",
        .completed = true,
    },
    .{
        .stage_number = 2,
        .title = "Control Flow, Errors & Defer Mechanics",
        .domain_focus = "Error sets, try/catch, errdefer, and deterministic cleanup with defer",
        .completed = true,
    },
    .{
        .stage_number = 3,
        .title = "Explicit Allocators & Memory Management",
        .domain_focus = "GeneralPurposeAllocator, ArenaAllocator, FixedBufferAllocator, leak detection",
        .completed = true,
    },
    .{
        .stage_number = 4,
        .title = "Compile-Time Metaprogramming (comptime)",
        .domain_focus = "Generic types, @typeInfo, compile-time reflection, inline loops",
        .completed = false,
    },
    .{
        .stage_number = 5,
        .title = "Data Structures & Standard Library (std)",
        .domain_focus = "ArrayList, AutoHashMap, StringHashMap, PriorityQueue, RingBuffer",
        .completed = false,
    },
    .{
        .stage_number = 6,
        .title = "C Interoperability & Build System (build.zig)",
        .domain_focus = "@cImport, translate-c, zero-cost C ABI binding, cross-compilation",
        .completed = false,
    },
    .{
        .stage_number = 7,
        .title = "Staff Zig Systems Architect Handbook",
        .domain_focus = "Zero-overhead embedded kernels, SIMD vectorization, safety checks",
        .completed = true,
    },
};

pub fn getCompletedCount() usize {
    var count: usize = 0;
    for (STAGES) |s| {
        if (s.completed) count += 1;
    }
    return count;
}

pub fn getProgressPercentage() u8 {
    const completed = getCompletedCount();
    return @intCast((completed * 100) / STAGES.len);
}
