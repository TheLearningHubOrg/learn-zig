//! A fixed-capacity ring buffer. The capacity is a comptime parameter, so the
//! storage is an inline array: no allocator, no failure path, no hidden cost.

const std = @import("std");

pub fn RingBuffer(comptime T: type, comptime capacity: usize) type {
    if (capacity == 0) @compileError("RingBuffer capacity must be at least 1");

    return struct {
        const Self = @This();

        items: [capacity]T = undefined,
        /// Index of the oldest element.
        head: usize = 0,
        len: usize = 0,

        pub const empty: Self = .{};
        pub const max_len = capacity;

        /// Appends `value`. When the buffer is full the oldest element is
        /// overwritten and returned so the caller can see what was evicted.
        pub fn push(self: *Self, value: T) ?T {
            if (self.len < capacity) {
                self.items[(self.head + self.len) % capacity] = value;
                self.len += 1;
                return null;
            }
            const evicted = self.items[self.head];
            self.items[self.head] = value;
            self.head = (self.head + 1) % capacity;
            return evicted;
        }

        /// Returns the element at logical position `index`, where 0 is the
        /// oldest element still stored.
        pub fn get(self: *const Self, index: usize) ?T {
            if (index >= self.len) return null;
            return self.items[(self.head + index) % capacity];
        }

        pub fn newest(self: *const Self) ?T {
            if (self.len == 0) return null;
            return self.get(self.len - 1);
        }

        /// Copies the stored elements, oldest first, into `out` and returns
        /// the filled prefix.
        pub fn copyInto(self: *const Self, out: []T) []T {
            const n = @min(out.len, self.len);
            for (out[0..n], 0..) |*slot, i| slot.* = self.get(i).?;
            return out[0..n];
        }
    };
}

const testing = std.testing;

test "push fills, then evicts the oldest element" {
    var ring: RingBuffer(u32, 3) = .empty;
    try testing.expectEqual(null, ring.push(1));
    try testing.expectEqual(null, ring.push(2));
    try testing.expectEqual(null, ring.push(3));
    try testing.expectEqual(1, ring.push(4).?);
    try testing.expectEqual(3, ring.len);
    try testing.expectEqual(2, ring.get(0).?);
    try testing.expectEqual(4, ring.newest().?);
    try testing.expectEqual(null, ring.get(3));
}

test "copyInto returns elements oldest first" {
    var ring: RingBuffer(u8, 4) = .empty;
    for ("abcdef") |c| _ = ring.push(c);
    var out: [4]u8 = undefined;
    try testing.expectEqualStrings("cdef", ring.copyInto(&out));
}

test "the buffer lives entirely in the struct" {
    // 8 u64 slots + two usize counters, no pointers to the heap.
    const Ring = RingBuffer(u64, 8);
    try testing.expectEqual(8 * @sizeOf(u64) + 2 * @sizeOf(usize), @sizeOf(Ring));
}
