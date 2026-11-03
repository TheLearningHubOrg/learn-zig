//! Stage 2 examples: functions, structs, enums, tagged unions, std
//! containers, iterators and formatting. Run with
//! `zig test examples/stage2_data.zig`.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// ---- functions --------------------------------------------------------------

/// Parameters are immutable. Small values are copied; large ones may be
/// passed by reference behind the scenes, so never rely on either.
fn clampAdd(a: u8, b: u8, limit: u8) u8 {
    return @min(a +| b, limit);
}

/// `anytype` makes the function generic over its argument type. Each distinct
/// type gets its own compiled instance.
fn sumAll(values: anytype) u64 {
    var total: u64 = 0;
    for (values) |v| total += v;
    return total;
}

test "functions" {
    try testing.expectEqual(100, clampAdd(90, 30, 100));
    try testing.expectEqual(6, sumAll([_]u8{ 1, 2, 3 }));
    try testing.expectEqual(10, sumAll(&[_]u32{ 4, 6 }));
}

// ---- structs ----------------------------------------------------------------

const Vec2 = struct {
    x: f32 = 0,
    y: f32 = 0,

    /// A decl literal: `.zero` works wherever a Vec2 is expected.
    pub const zero: Vec2 = .{};

    pub fn init(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    /// Methods that mutate take a pointer.
    pub fn scale(v: *Vec2, k: f32) void {
        v.x *= k;
        v.y *= k;
    }

    /// Called by `{f}` in format strings.
    pub fn format(v: Vec2, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("({d}, {d})", .{ v.x, v.y });
    }
};

test "structs, methods and decl literals" {
    var p: Vec2 = .init(1, 2); // decl literal calling Vec2.init
    p.scale(3); // same as Vec2.scale(&p, 3)
    const q = p.add(.zero);
    try testing.expectEqual(3, q.x);

    var buf: [32]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf, "{f}", .{q});
    try testing.expectEqualStrings("(3, 6)", s);
}

// ---- enums and tagged unions -----------------------------------------------

const Method = enum {
    get,
    post,
    delete,

    pub fn isSafe(m: Method) bool {
        return switch (m) {
            .get => true,
            .post, .delete => false,
        };
    }
};

const Shape = union(enum) {
    circle: f32, // radius
    rect: struct { w: f32, h: f32 },
    point,

    fn area(s: Shape) f32 {
        return switch (s) {
            .circle => |r| std.math.pi * r * r,
            .rect => |r| r.w * r.h,
            .point => 0,
        };
    }
};

test "enums and tagged unions" {
    try testing.expect(Method.get.isSafe());
    try testing.expectEqualStrings("post", @tagName(Method.post));
    try testing.expectEqual(.delete, std.meta.stringToEnum(Method, "delete").?);

    const shapes = [_]Shape{ .{ .circle = 1 }, .{ .rect = .{ .w = 2, .h = 3 } }, .point };
    var total: f32 = 0;
    for (shapes) |s| total += s.area();
    try testing.expectApproxEqAbs(9.14159, total, 0.0001);
    try testing.expectEqual(.rect, std.meta.activeTag(shapes[1]));
}

// ---- containers ---------------------------------------------------------------

test "ArrayList takes the allocator on every call" {
    const gpa = testing.allocator;
    var list: std.ArrayList(u32) = .empty;
    defer list.deinit(gpa);

    try list.append(gpa, 1);
    try list.appendSlice(gpa, &.{ 2, 3, 4 });
    try testing.expectEqual(4, list.items.len);
    try testing.expectEqual(4, list.pop().?);
    try testing.expectEqual(3, list.last().?);

    try testing.expectEqual(1, list.orderedRemove(0)); // shifts the rest left
    try testing.expectEqual(2, list.swapRemove(0)); // moves the last item into the hole
    try testing.expectEqualSlices(u32, &.{3}, list.items);
}

test "hash maps" {
    const gpa = testing.allocator;

    var ages: std.StringHashMapUnmanaged(u8) = .empty;
    defer ages.deinit(gpa);
    try ages.put(gpa, "ada", 36);
    try ages.put(gpa, "linus", 21);
    try testing.expectEqual(36, ages.get("ada").?);
    try testing.expectEqual(null, ages.get("grace"));

    // Insertion-ordered map: iterate in the order keys were added.
    var by_id: std.array_hash_map.Auto(u32, []const u8) = .empty;
    defer by_id.deinit(gpa);
    try by_id.put(gpa, 30, "c");
    try by_id.put(gpa, 10, "a");
    try testing.expectEqualSlices(u32, &.{ 30, 10 }, by_id.keys());
}

test "MultiArrayList stores each field in its own array" {
    const gpa = testing.allocator;
    const Particle = struct { x: f32, alive: bool };
    var ps: std.MultiArrayList(Particle) = .empty;
    defer ps.deinit(gpa);
    try ps.append(gpa, .{ .x = 1, .alive = true });
    try ps.append(gpa, .{ .x = 2, .alive = false });
    const xs: []f32 = ps.items(.x); // contiguous f32s, cache friendly
    try testing.expectEqualSlices(f32, &.{ 1, 2 }, xs);
}

// ---- iterators ------------------------------------------------------------------

const Countdown = struct {
    n: u32,
    fn next(c: *Countdown) ?u32 {
        if (c.n == 0) return null;
        defer c.n -= 1;
        return c.n;
    }
};

test "the iterator convention: next() returns ?T" {
    var it: Countdown = .{ .n = 3 };
    var seen: [3]u32 = undefined;
    var i: usize = 0;
    while (it.next()) |v| : (i += 1) seen[i] = v;
    try testing.expectEqualSlices(u32, &.{ 3, 2, 1 }, &seen);

    var parts = std.mem.splitScalar(u8, "a,b,,c", ',');
    try testing.expectEqualStrings("a", parts.next().?);
    try testing.expectEqualStrings("b", parts.next().?);
    try testing.expectEqualStrings("", parts.next().?); // split keeps empties
    var toks = std.mem.tokenizeScalar(u8, "a,b,,c", ',');
    _ = toks.next();
    _ = toks.next();
    try testing.expectEqualStrings("c", toks.next().?); // tokenize skips them
}

// ---- formatting and writers ---------------------------------------------------------

test "formatting into a fixed buffer and into an allocating writer" {
    var buf: [64]u8 = undefined;
    var fixed: std.Io.Writer = .fixed(&buf);
    try fixed.print("{s}={d} hex={x} pad=[{d:>4}] tag={t}", .{ "n", 255, 255, 7, Method.get });
    try testing.expectEqualStrings("n=255 hex=ff pad=[   7] tag=get", fixed.buffered());

    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    try aw.writer.print("{any}", .{[_]u8{ 1, 2 }});
    try testing.expectEqualStrings("{ 1, 2 }", aw.written());

    const owned = try testing.allocator.print("{d}-{d}", .{ 1, 2 });
    defer testing.allocator.free(owned);
    try testing.expectEqualStrings("1-2", owned);
}
