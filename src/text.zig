//! Word statistics over a block of ASCII text.
//!
//! Every slice in a `Report` points into memory owned by the allocator that
//! was passed to `analyze`. Pass an arena and free everything in one call.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Inputs larger than this are rejected before any allocation happens.
pub const max_input_len: usize = 64 * 1024;

pub const WordCount = struct {
    word: []const u8,
    count: u32,
};

pub const Report = struct {
    bytes: usize,
    lines: usize,
    words: usize,
    unique: usize,
    top: []const WordCount,
};

pub const AnalyzeError = Allocator.Error || error{InputTooLarge};

/// A word is a run of ASCII letters, digits or apostrophes. Matching is
/// case-insensitive: "Zig" and "zig" count as the same word.
pub fn isWordByte(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '\'';
}

/// Counts newline-terminated lines, plus a final line without a newline.
/// This matches what a reader sees, not what `wc -l` prints.
pub fn countLines(input: []const u8) usize {
    if (input.len == 0) return 0;
    var lines: usize = std.mem.count(u8, input, "\n");
    if (input[input.len - 1] != '\n') lines += 1;
    return lines;
}

/// Iterates over the words of `input` without allocating.
pub const WordIterator = struct {
    input: []const u8,
    index: usize = 0,

    pub fn next(it: *WordIterator) ?[]const u8 {
        // Skip separators.
        while (it.index < it.input.len and !isWordByte(it.input[it.index])) : (it.index += 1) {}
        if (it.index == it.input.len) return null;
        const start = it.index;
        while (it.index < it.input.len and isWordByte(it.input[it.index])) : (it.index += 1) {}
        return it.input[start..it.index];
    }
};

pub fn words(input: []const u8) WordIterator {
    return .{ .input = input };
}

fn moreFrequent(_: void, a: WordCount, b: WordCount) bool {
    if (a.count != b.count) return a.count > b.count;
    return std.mem.lessThan(u8, a.word, b.word);
}

/// Builds a `Report` for `input`, keeping the `top_n` most frequent words.
/// Ties are broken alphabetically so the output is deterministic.
pub fn analyze(gpa: Allocator, input: []const u8, top_n: usize) AnalyzeError!Report {
    if (input.len > max_input_len) return error.InputTooLarge;

    // One lowercase copy keeps every word slice stable for the map keys.
    const lower = try std.ascii.allocLowerString(gpa, input);

    var counts: std.StringHashMapUnmanaged(u32) = .empty;
    var total: usize = 0;
    var it = words(lower);
    while (it.next()) |word| {
        total += 1;
        const entry = try counts.getOrPut(gpa, word);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }

    var ranked: std.ArrayList(WordCount) = .empty;
    try ranked.ensureTotalCapacityPrecise(gpa, counts.count());
    var map_it = counts.iterator();
    while (map_it.next()) |entry| {
        ranked.appendAssumeCapacity(.{ .word = entry.key_ptr.*, .count = entry.value_ptr.* });
    }
    std.mem.sort(WordCount, ranked.items, {}, moreFrequent);

    return .{
        .bytes = input.len,
        .lines = countLines(input),
        .words = total,
        .unique = counts.count(),
        .top = ranked.items[0..@min(top_n, ranked.items.len)],
    };
}

const testing = std.testing;

test "word iterator splits on punctuation and whitespace" {
    var it = words("  Hello, zig-world!\nit's 2026 ");
    const expected = [_][]const u8{ "Hello", "zig", "world", "it's", "2026" };
    for (expected) |want| {
        try testing.expectEqualStrings(want, it.next().?);
    }
    try testing.expectEqual(null, it.next());
}

test "countLines handles empty, terminated and unterminated input" {
    try testing.expectEqual(0, countLines(""));
    try testing.expectEqual(1, countLines("one"));
    try testing.expectEqual(1, countLines("one\n"));
    try testing.expectEqual(2, countLines("one\ntwo"));
}

test "analyze counts case-insensitively and ranks deterministically" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const report = try analyze(arena.allocator(), "the cat and The dog\nand THE bird", 2);
    try testing.expectEqual(8, report.words);
    try testing.expectEqual(5, report.unique);
    try testing.expectEqual(2, report.lines);
    try testing.expectEqual(2, report.top.len);
    try testing.expectEqualStrings("the", report.top[0].word);
    try testing.expectEqual(3, report.top[0].count);
    try testing.expectEqualStrings("and", report.top[1].word);
}

test "analyze rejects oversized input before allocating" {
    const too_big: []const u8 = &@as([max_input_len + 1]u8, @splat('a'));
    try testing.expectError(error.InputTooLarge, analyze(testing.failing_allocator, too_big, 3));
}

test "analyze handles empty input" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const report = try analyze(arena.allocator(), "", 5);
    try testing.expectEqual(0, report.words);
    try testing.expectEqual(0, report.top.len);
}
