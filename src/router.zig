//! HTTP routing with no sockets involved. `handle` maps a method, a target and
//! a body to a `Response`, which keeps every route unit-testable.

const std = @import("std");
const Allocator = std.mem.Allocator;
const text = @import("text.zig");
const roadmap = @import("roadmap.zig");
const RingBuffer = @import("ring.zig").RingBuffer;

pub const Response = struct {
    status: std.http.Status,
    body: []const u8,
    content_type: []const u8 = "application/json",
};

/// One line per analysed document, kept for GET /history.
pub const Summary = struct {
    words: usize,
    unique: usize,
    top_word: []const u8,
};

pub const history_len = 8;

/// State shared by every request. Summaries own their `top_word` bytes in
/// `top_word_storage`, because the request arena is reset after each request.
pub const App = struct {
    history: RingBuffer(Summary, history_len) = .empty,
    top_word_storage: [history_len][32]u8 = undefined,
    next_slot: usize = 0,
    requests: u64 = 0,

    fn remember(app: *App, report: text.Report) void {
        const slot = &app.top_word_storage[app.next_slot];
        app.next_slot = (app.next_slot + 1) % history_len;
        const word = if (report.top.len > 0) report.top[0].word else "";
        const n = @min(word.len, slot.len);
        @memcpy(slot[0..n], word[0..n]);
        _ = app.history.push(.{ .words = report.words, .unique = report.unique, .top_word = slot[0..n] });
    }
};

const Route = enum { health, stats, history, roadmap };

/// Built at compile time: a sorted lookup table with no runtime setup.
const routes = std.StaticStringMap(Route).initComptime(.{
    .{ "/health", .health },
    .{ "/stats", .stats },
    .{ "/history", .history },
    .{ "/roadmap", .roadmap },
});

/// Returns the value of `name` in the query string of `target`, if present.
pub fn queryParam(target: []const u8, name: []const u8) ?[]const u8 {
    const q = std.mem.findScalar(u8, target, '?') orelse return null;
    var pairs = std.mem.splitScalar(u8, target[q + 1 ..], '&');
    while (pairs.next()) |pair| {
        const eq = std.mem.findScalar(u8, pair, '=') orelse continue;
        if (std.mem.eql(u8, pair[0..eq], name)) return pair[eq + 1 ..];
    }
    return null;
}

fn json(arena: Allocator, status: std.http.Status, value: anytype) Allocator.Error!Response {
    const body = try std.json.Stringify.valueAlloc(arena, value, .{});
    return .{ .status = status, .body = body };
}

fn errorBody(arena: Allocator, status: std.http.Status, message: []const u8) Allocator.Error!Response {
    return json(arena, status, .{ .@"error" = message });
}

pub fn handle(
    app: *App,
    arena: Allocator,
    method: std.http.Method,
    target: []const u8,
    body: []const u8,
) Allocator.Error!Response {
    app.requests += 1;
    const path = target[0 .. std.mem.findScalar(u8, target, '?') orelse target.len];
    const route = routes.get(path) orelse return errorBody(arena, .not_found, "no such route");

    switch (route) {
        .health => {
            if (method != .GET and method != .HEAD) return errorBody(arena, .method_not_allowed, "use GET");
            return json(arena, .ok, .{ .status = "ok", .requests = app.requests });
        },
        .stats => {
            if (method != .POST) return errorBody(arena, .method_not_allowed, "use POST");
            if (body.len == 0) return errorBody(arena, .bad_request, "request body is empty");
            const top_n: u8 = blk: {
                const raw = queryParam(target, "top") orelse break :blk 5;
                break :blk std.fmt.parseInt(u8, raw, 10) catch
                    return errorBody(arena, .bad_request, "top must be an integer in 0..255");
            };
            const report = text.analyze(arena, body, top_n) catch |err| switch (err) {
                error.InputTooLarge => return errorBody(arena, .payload_too_large, "body exceeds 64 KiB"),
                error.OutOfMemory => |e| return e,
            };
            app.remember(report);
            return json(arena, .ok, report);
        },
        .history => {
            if (method != .GET) return errorBody(arena, .method_not_allowed, "use GET");
            var buf: [history_len]Summary = undefined;
            return json(arena, .ok, app.history.copyInto(&buf));
        },
        .roadmap => {
            if (method != .GET) return errorBody(arena, .method_not_allowed, "use GET");
            return json(arena, .ok, .{
                .stages = roadmap.STAGES,
                .written = roadmap.getCompletedCount(),
                .percent = roadmap.getProgressPercentage(),
            });
        },
    }
}

const testing = std.testing;

fn call(app: *App, arena: *std.heap.ArenaAllocator, method: std.http.Method, target: []const u8, body: []const u8) !Response {
    _ = arena.reset(.retain_capacity);
    return handle(app, arena.allocator(), method, target, body);
}

test "GET /health answers 200 with a JSON body" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var app: App = .{};
    const res = try call(&app, &arena, .GET, "/health", "");
    try testing.expectEqual(.ok, res.status);
    try testing.expectEqualStrings("{\"status\":\"ok\",\"requests\":1}", res.body);
}

test "unknown routes and wrong methods" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var app: App = .{};
    try testing.expectEqual(.not_found, (try call(&app, &arena, .GET, "/nope", "")).status);
    try testing.expectEqual(.method_not_allowed, (try call(&app, &arena, .GET, "/stats", "")).status);
    try testing.expectEqual(.bad_request, (try call(&app, &arena, .POST, "/stats", "")).status);
    try testing.expectEqual(.bad_request, (try call(&app, &arena, .POST, "/stats?top=many", "x")).status);
}

test "POST /stats returns the report and records history" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var app: App = .{};

    const res = try call(&app, &arena, .POST, "/stats?top=1", "zig zig ZIG c");
    try testing.expectEqual(.ok, res.status);
    try testing.expectEqualStrings(
        "{\"bytes\":13,\"lines\":1,\"words\":4,\"unique\":2,\"top\":[{\"word\":\"zig\",\"count\":3}]}",
        res.body,
    );

    // The arena is reset here, so history must not point into it.
    const hist = try call(&app, &arena, .GET, "/history", "");
    try testing.expectEqualStrings("[{\"words\":4,\"unique\":2,\"top_word\":\"zig\"}]", hist.body);
}

test "queryParam finds values and ignores malformed pairs" {
    try testing.expectEqualStrings("3", queryParam("/stats?x&top=3", "top").?);
    try testing.expectEqual(null, queryParam("/stats", "top"));
    try testing.expectEqual(null, queryParam("/stats?topx=1", "top"));
}
