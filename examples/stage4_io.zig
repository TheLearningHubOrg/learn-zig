//! Stage 4 preview: the `std.Io` interface. Run with
//! `zig test examples/stage4_io.zig`.

const std = @import("std");
const Io = std.Io;
const testing = std.testing;

fn checksum(data: []const u8) u32 {
    var h: u32 = 2166136261; // FNV-1a
    for (data) |b| {
        h ^= b;
        h *%= 16777619;
    }
    return h;
}

test "io.async expresses independence; await collects the result" {
    const io = testing.io;
    var a = io.async(checksum, .{"left half"});
    var b = io.async(checksum, .{"right half"});
    // Whether these ran in parallel depends on the Io implementation; the
    // code is correct either way.
    const total = a.await(io) +% b.await(io);
    try testing.expectEqual(checksum("left half") +% checksum("right half"), total);
}

const Counter = struct {
    mutex: Io.Mutex = .init,
    value: u64 = 0,

    fn addMany(c: *Counter, io: Io, n: u64) Io.Cancelable!void {
        for (0..n) |_| {
            try c.mutex.lock(io);
            defer c.mutex.unlock(io);
            c.value += 1;
        }
    }
};

test "a Group awaits many tasks together" {
    const io = testing.io;
    var counter: Counter = .{};
    var group: Io.Group = .init;
    for (0..4) |_| group.async(io, Counter.addMany, .{ &counter, io, 1000 });
    try group.await(io);
    try testing.expectEqual(4000, counter.value);
}

test "atomics with explicit memory ordering" {
    var hits: std.atomic.Value(u32) = .init(0);
    const worker = struct {
        fn run(h: *std.atomic.Value(u32)) void {
            for (0..1000) |_| _ = h.fetchAdd(1, .monotonic);
        }
    }.run;

    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, worker, .{&hits});
    for (threads) |t| t.join();
    try std.testing.expectEqual(4000, hits.load(.acquire));
}
