//! Stage 3 examples: allocators, defer/errdefer, error unions, pointers,
//! comptime generics, reflection and memory layout. Run with
//! `zig test examples/stage3_memory.zig`.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// ---- allocators -----------------------------------------------------------------

test "FixedBufferAllocator: heap-style API over stack memory" {
    var storage: [256]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&storage);
    const a = fba.allocator();

    const nums = try a.alloc(u32, 16); // 64 bytes out of 256
    defer a.free(nums);
    try testing.expectError(error.OutOfMemory, a.alloc(u8, 1024));
}

test "ArenaAllocator: many allocations, one free" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit(); // frees everything below in one call
    const a = arena.allocator();

    for (0..100) |i| {
        _ = try a.print("item-{d}", .{i}); // no individual free needed
    }
}

test "SafeAllocator reports leaks on deinit" {
    var safe: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
    const a = safe.allocator();
    const leaked = try a.alloc(u8, 10);
    _ = leaked;
    // deinitLog(false) returns the leak count without printing a report.
    try testing.expectEqual(1, safe.deinitLog(false));
}

test "BufferFirstAllocator: stack first, heap when it runs out" {
    var stack_buf: [64]u8 = undefined;
    var bfa: std.heap.BufferFirstAllocator = .init(&stack_buf, testing.allocator);
    const a = bfa.allocator();
    const small = try a.alloc(u8, 32); // served from stack_buf
    defer a.free(small);
    const large = try a.alloc(u8, 4096); // falls through to testing.allocator
    defer a.free(large);
}

/// Wraps another allocator and counts live bytes. Implementing the four
/// vtable functions is all it takes to plug into every std API.
const CountingAllocator = struct {
    child: Allocator,
    live_bytes: usize = 0,
    peak_bytes: usize = 0,

    fn allocator(self: *CountingAllocator) Allocator {
        return .{ .ptr = self, .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        } };
    }

    fn track(self: *CountingAllocator, old_len: usize, new_len: usize) void {
        self.live_bytes = self.live_bytes - old_len + new_len;
        self.peak_bytes = @max(self.peak_bytes, self.live_bytes);
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.child.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.track(0, len);
        return ptr;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        if (!self.child.rawResize(memory, alignment, new_len, ret_addr)) return false;
        self.track(memory.len, new_len);
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.child.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        self.track(memory.len, new_len);
        return ptr;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.child.rawFree(memory, alignment, ret_addr);
        self.track(memory.len, 0);
    }
};

test "a custom allocator is just a vtable" {
    var counting: CountingAllocator = .{ .child = testing.allocator };
    const a = counting.allocator();

    var list: std.ArrayList(u64) = .empty;
    try list.appendSlice(a, &.{ 1, 2, 3, 4, 5, 6, 7, 8 });
    try testing.expect(counting.live_bytes >= 8 * @sizeOf(u64));
    list.deinit(a);
    try testing.expectEqual(0, counting.live_bytes);
    try testing.expect(counting.peak_bytes >= 64);
}

// ---- defer and errdefer -----------------------------------------------------------

const Buffers = struct {
    header: []u8,
    body: []u8,

    /// If the second allocation fails, errdefer frees the first one.
    /// On success, ownership of both moves to the caller.
    fn init(gpa: Allocator, header_len: usize, body_len: usize) !Buffers {
        const header = try gpa.alloc(u8, header_len);
        errdefer gpa.free(header);
        const body = try gpa.alloc(u8, body_len);
        return .{ .header = header, .body = body };
    }

    fn deinit(b: Buffers, gpa: Allocator) void {
        gpa.free(b.body);
        gpa.free(b.header);
    }
};

test "errdefer cleans up partial initialisation" {
    // Fail the second allocation; testing.allocator would report a leak if
    // errdefer did not run.
    var failing: std.testing.FailingAllocator = .init(testing.allocator, .{ .fail_index = 1 });
    try testing.expectError(error.OutOfMemory, Buffers.init(failing.allocator(), 8, 8));

    const ok = try Buffers.init(testing.allocator, 8, 8);
    ok.deinit(testing.allocator);
}

test "defer runs in reverse order at scope exit" {
    var log: [3]u8 = undefined;
    var n: usize = 0;
    {
        defer {
            log[n] = 'a';
            n += 1;
        }
        defer {
            log[n] = 'b';
            n += 1;
        }
        log[n] = 'c';
        n += 1;
    }
    try testing.expectEqualStrings("cba", &log);
}

// ---- errors ---------------------------------------------------------------------------

const ParseError = error{ Empty, NotANumber, TooLarge };

fn parsePercent(text: []const u8) ParseError!u7 {
    if (text.len == 0) return error.Empty;
    const n = std.fmt.parseInt(u32, text, 10) catch return error.NotANumber;
    if (n > 100) return error.TooLarge;
    return @intCast(n);
}

/// The error set is inferred (`!u7`) and includes everything parsePercent
/// can return, plus error.Negative.
fn parseSigned(text: []const u8) !u7 {
    if (text.len > 0 and text[0] == '-') return error.Negative;
    return parsePercent(text);
}

test "error unions, try, catch and switch on errors" {
    try testing.expectEqual(42, try parsePercent("42"));
    try testing.expectError(error.TooLarge, parsePercent("101"));

    const with_default = parsePercent("") catch 50;
    try testing.expectEqual(50, with_default);

    const message = if (parseSigned("-5")) |_| "ok" else |err| switch (err) {
        error.Negative => "negative",
        error.Empty, error.NotANumber, error.TooLarge => "invalid",
    };
    try testing.expectEqualStrings("negative", message);

    // Error sets merge with ||.
    const AllErrors = ParseError || error{Negative};
    const e: AllErrors = error.Empty;
    try testing.expectEqualStrings("Empty", @errorName(e));
}

// ---- pointers -------------------------------------------------------------------------

test "pointer kinds" {
    var arr = [_]u8{ 1, 2, 3, 4 };

    const one: *u8 = &arr[0]; // single item, no arithmetic
    one.* = 10;

    const to_array: *[4]u8 = &arr; // length is part of the type
    try testing.expectEqual(4, to_array.len);

    const slice: []u8 = arr[1..]; // pointer + runtime length
    slice[0] = 20;

    const many: [*]u8 = &arr; // unknown length, C-style, no bounds checks
    try testing.expectEqual(3, many[2]);

    const c_str: [*:0]const u8 = "abc"; // many-item, null-terminated
    try testing.expectEqual(3, std.mem.len(c_str));

    var maybe: ?*u8 = null; // only optional pointers can be null
    maybe = &arr[3];
    try testing.expectEqual(4, maybe.?.*);
    try testing.expectEqualSlices(u8, &.{ 10, 20, 3, 4 }, &arr);
}

test "alignment is part of the pointer type" {
    var x: u32 align(16) = 0;
    const p: *align(16) u32 = &x;
    try testing.expect(@intFromPtr(p) % 16 == 0);
    try testing.expectEqual(4, @alignOf(u32));
}

// ---- comptime -------------------------------------------------------------------------

/// A generic function: `T` is known at compile time, so each call with a new
/// type produces a specialised copy.
fn maxOf(comptime T: type, items: []const T) ?T {
    if (items.len == 0) return null;
    var best = items[0];
    for (items[1..]) |v| best = @max(best, v);
    return best;
}

/// A generic type: a function that returns a struct.
fn Pair(comptime A: type, comptime B: type) type {
    return struct {
        first: A,
        second: B,

        const Self = @This();
        fn swap(self: Self) Pair(B, A) {
            return .{ .first = self.second, .second = self.first };
        }
    };
}

fn fibonacci(n: u32) u64 {
    var a: u64 = 0;
    var b: u64 = 1;
    for (0..n) |_| {
        const next = a + b;
        a = b;
        b = next;
    }
    return a;
}

test "comptime generics" {
    try testing.expectEqual(9, maxOf(i32, &.{ 3, 9, -2 }).?);
    try testing.expectEqual(null, maxOf(f64, &.{}));

    const p: Pair(u8, []const u8) = .{ .first = 1, .second = "one" };
    const s = p.swap();
    try testing.expectEqualStrings("one", s.first);

    // Any function can run at compile time; the result is a constant.
    const table = comptime blk: {
        var t: [10]u64 = undefined;
        for (&t, 0..) |*slot, i| slot.* = fibonacci(@intCast(i));
        break :blk t;
    };
    try testing.expectEqual(34, table[9]);
}

const Config = struct {
    port: u16 = 8080,
    host: []const u8 = "0.0.0.0",
    verbose: bool = false,
};

/// Reflection: count fields of a given type. @typeInfo returns field names
/// and types as parallel arrays (struct-of-arrays) since 0.17.
fn countFieldsOfType(comptime S: type, comptime F: type) usize {
    const info = @typeInfo(S).@"struct";
    var n: usize = 0;
    inline for (info.field_types) |T| {
        if (T == F) n += 1;
    }
    return n;
}

test "reflection with @typeInfo and @field" {
    try testing.expectEqual(1, comptime countFieldsOfType(Config, bool));
    const info = @typeInfo(Config).@"struct";
    try testing.expectEqualStrings("port", info.field_names[0]);

    const c: Config = .{};
    try testing.expectEqual(8080, @field(c, "port"));
    try testing.expect(@hasField(Config, "host"));
}

// ---- memory layout ----------------------------------------------------------------------

const Auto = struct { a: u8, b: u32, c: u8 }; // compiler may reorder fields
const CLayout = extern struct { a: u8, b: u32, c: u8 }; // C ABI order and padding
const Flags = packed struct(u8) { read: bool, write: bool, exec: bool, _pad: u5 = 0 };

test "layout: auto, extern and packed" {
    try testing.expectEqual(12, @sizeOf(CLayout)); // 1 + 3 pad + 4 + 1 + 3 pad
    try testing.expectEqual(4, @offsetOf(CLayout, "b"));
    try testing.expect(@sizeOf(Auto) <= @sizeOf(CLayout)); // reordering may shrink it

    const f: Flags = .{ .read = true, .write = false, .exec = true };
    try testing.expectEqual(0b101, @as(u8, @bitCast(f)));
    try testing.expectEqual(1, @sizeOf(Flags));
}
