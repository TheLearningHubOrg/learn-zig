//! Stage 1 examples: values, integer semantics, arrays, slices, strings,
//! optionals and control flow. Run with `zig test examples/stage1_basics.zig`.

const std = @import("std");
const testing = std.testing;

test "const, var and type inference" {
    const answer = 42; // comptime_int: no fixed size until it meets a typed context
    const small: u8 = answer; // fits, so the coercion is allowed
    var counter: u32 = 0; // `var` must be mutated, or the compiler rejects it
    counter += small;
    try testing.expectEqual(42, counter);
    try testing.expect(@TypeOf(answer) == comptime_int);
}

test "arbitrary-width integers" {
    const nibble: u4 = 15; // 0..15
    const tiny: i3 = -4; // -4..3
    try testing.expectEqual(15, nibble);
    try testing.expectEqual(-4, tiny);
    try testing.expectEqual(1, @sizeOf(u4)); // stored in a whole byte
    try testing.expectEqual(4, @bitSizeOf(u4));
}

test "overflow is explicit: wrapping, saturating and checked" {
    const max: u8 = 255;
    try testing.expectEqual(0, max +% 1); // wrapping add
    try testing.expectEqual(255, max +| 1); // saturating add
    // Checked add returns a tuple { result, overflow_bit }.
    const sum, const overflowed = @addWithOverflow(max, 1);
    try testing.expectEqual(0, sum);
    try testing.expectEqual(1, overflowed);
    // `max + 1` with runtime values panics in debug/safe builds:
    // "panic: integer overflow".
}

test "casting is always spelled out" {
    const big: u32 = 300;
    const narrowed: u8 = @truncate(big); // keep the low 8 bits: 300 - 256 = 44
    try testing.expectEqual(44, narrowed);

    const fits: u32 = 200;
    const checked: u8 = @intCast(fits); // safety-checked: panics if it does not fit
    try testing.expectEqual(200, checked);

    const f: f64 = @floatFromInt(checked);
    try testing.expectEqual(200.0, f);
    const back: i32 = @intFromFloat(@trunc(12.9));
    try testing.expectEqual(12, back);

    // @as performs only coercions that can never lose information.
    try testing.expectEqual(@as(u64, 7), @as(u64, @as(u8, 7)));
}

test "arrays have a comptime length, slices a runtime one" {
    const primes = [_]u32{ 2, 3, 5, 7, 11 }; // [5]u32, length inferred
    const zeroes: [4]u8 = @splat(0); // every element set to 0
    try testing.expectEqual(5, primes.len);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, &zeroes);

    const middle: []const u32 = primes[1..4]; // pointer + length, no copy
    try testing.expectEqualSlices(u32, &.{ 3, 5, 7 }, middle);

    // Slicing with comptime-known bounds produces a pointer to an array.
    const first_two = primes[0..2];
    try testing.expect(@TypeOf(first_two) == *const [2]u32);
}

test "strings are byte slices" {
    const literal = "zig"; // *const [3:0]u8: pointer to a null-terminated array
    try testing.expect(@TypeOf(literal) == *const [3:0]u8);
    const as_slice: []const u8 = literal; // coerces to a slice
    try testing.expectEqual(3, as_slice.len);
    try testing.expectEqual(0, literal[3]); // the sentinel is readable

    const joined = "hello, " ++ "world"; // ++ concatenates at compile time
    try testing.expectEqualStrings("hello, world", joined);
    try testing.expect(std.mem.eql(u8, "abc", "abc")); // == compares pointers, not bytes
}

test "multiline string literals" {
    const banner =
        \\GET /health HTTP/1.1
        \\Host: localhost
    ;
    try testing.expectEqual(2, std.mem.count(u8, banner, "\n") + 1);
}

fn findIndex(haystack: []const u32, needle: u32) ?usize {
    for (haystack, 0..) |value, i| {
        if (value == needle) return i;
    }
    return null;
}

test "optionals replace null pointers and sentinel return values" {
    const xs = [_]u32{ 4, 8, 15, 16 };
    try testing.expectEqual(2, findIndex(&xs, 15).?); // .? asserts non-null
    try testing.expectEqual(null, findIndex(&xs, 99));

    const fallback = findIndex(&xs, 99) orelse xs.len;
    try testing.expectEqual(4, fallback);

    if (findIndex(&xs, 16)) |i| {
        try testing.expectEqual(3, i); // `i` is the unwrapped usize
    } else unreachable;
}

test "if, while and for are expressions or take captures" {
    const n: u32 = 7;
    const parity = if (n % 2 == 0) "even" else "odd";
    try testing.expectEqualStrings("odd", parity);

    var i: u32 = 0;
    var sum: u32 = 0;
    while (i < 5) : (i += 1) sum += i; // continue expression runs every iteration
    try testing.expectEqual(10, sum);

    var total: usize = 0;
    for (0..4) |k| total += k; // ranges are half-open
    try testing.expectEqual(6, total);

    const a = [_]u8{ 1, 2, 3 };
    const b = [_]u8{ 10, 20, 30 };
    var dot: u32 = 0;
    for (a, b) |x, y| dot += @as(u32, x) * y; // lengths must match (safety-checked)
    try testing.expectEqual(140, dot);
}

test "labeled blocks and loops" {
    const grid = [_][3]u8{ .{ 1, 2, 3 }, .{ 4, 5, 6 } };
    const found = outer: for (grid, 0..) |row, r| {
        for (row, 0..) |cell, c| {
            if (cell == 5) break :outer .{ r, c };
        }
    } else null;
    try testing.expectEqual(1, found.?[0]);
    try testing.expectEqual(1, found.?[1]);

    const clamped = blk: {
        const raw: i32 = -12;
        if (raw < 0) break :blk 0;
        break :blk raw;
    };
    try testing.expectEqual(0, clamped);
}

test "switch is exhaustive and returns a value" {
    const code: u16 = 404;
    const class = switch (code) {
        200...299 => "success",
        300...399 => "redirect",
        400, 404, 410 => "client error",
        500...599 => "server error",
        else => "other",
    };
    try testing.expectEqualStrings("client error", class);
}
