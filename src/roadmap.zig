//! The guide's seven stages as data. `completed` marks the stages whose
//! README sections are written to full depth.

pub const RoadmapStage = struct {
    stage_number: u8,
    title: []const u8,
    domain_focus: []const u8,
    completed: bool,
};

pub const STAGES = [_]RoadmapStage{
    .{
        .stage_number = 1,
        .title = "Toolchain, Syntax & Types",
        .domain_focus = "zig init, zig build, const/var, integers, floats, arrays, slices, optionals",
        .completed = true,
    },
    .{
        .stage_number = 2,
        .title = "Functions, Data Structures & Modules",
        .domain_focus = "structs, enums, tagged unions, switch, ArrayList, hash maps, @import, build.zig modules",
        .completed = true,
    },
    .{
        .stage_number = 3,
        .title = "Memory, Errors & Comptime Generics",
        .domain_focus = "allocators, defer/errdefer, error unions, comptime generics, pointers and alignment",
        .completed = true,
    },
    .{
        .stage_number = 4,
        .title = "Concurrency & the Io Interface",
        .domain_focus = "std.Io, io.async, Future, Group, Queue, threads, atomics, cancelation",
        .completed = false,
    },
    .{
        .stage_number = 5,
        .title = "I/O, Networking, HTTP & Testing",
        .domain_focus = "Reader/Writer, files, sockets, std.http, std.json, test blocks, fuzzing",
        .completed = false,
    },
    .{
        .stage_number = 6,
        .title = "Performance, Safety, C Interop & Shipping",
        .domain_focus = "build modes, SIMD, profiling, translate-c, cross-compilation, packaging",
        .completed = false,
    },
    .{
        .stage_number = 7,
        .title = "Staff Zig Engineer Interview Handbook",
        .domain_focus = "40+ Q&As on internals, design trade-offs and production debugging",
        .completed = false,
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
    return @intCast((getCompletedCount() * 100) / STAGES.len);
}
