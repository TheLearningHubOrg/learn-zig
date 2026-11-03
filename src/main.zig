//! Text statistics HTTP service.
//!
//!   GET  /health          liveness probe
//!   POST /stats?top=N     word, line and frequency statistics for the body
//!   GET  /history         summaries of the last 8 analysed bodies
//!   GET  /roadmap         the guide's stages as JSON
//!
//! Connections are served one at a time. Stage 4 replaces this loop with
//! concurrent handling through `std.Io`.

const std = @import("std");
const Io = std.Io;
const learn_zig = @import("learn_zig");
const router = learn_zig.router;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const port = learn_zig.config.parsePort(init.environ_map.get("PORT")) catch |err| {
        std.log.err("PORT is not a valid TCP port: {t}", .{err});
        return err;
    };

    // 0.0.0.0, not 127.0.0.1: inside a container, loopback is unreachable
    // from the host.
    const address: Io.net.IpAddress = .{ .ip4 = .unspecified(port) };
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    std.log.info("listening on http://0.0.0.0:{d}", .{port});

    var app: router.App = .{};
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();

    while (true) {
        const stream = server.accept(io) catch |err| {
            std.log.warn("accept failed: {t}", .{err});
            continue;
        };
        // One arena per request: everything the handler allocates is freed
        // by a single reset, and the capacity is reused next time.
        defer _ = arena_state.reset(.retain_capacity);
        defer stream.close(io);
        serve(io, arena_state.allocator(), &app, stream) catch |err| {
            std.log.warn("request failed: {t}", .{err});
        };
    }
}

fn serve(io: Io, arena: std.mem.Allocator, app: *router.App, stream: Io.net.Stream) !void {
    var recv_buffer: [8 * 1024]u8 = undefined;
    var send_buffer: [8 * 1024]u8 = undefined;
    var stream_reader = stream.reader(io, &recv_buffer);
    var stream_writer = stream.writer(io, &send_buffer);
    var http: std.http.Server = .init(&stream_reader.interface, &stream_writer.interface);

    var request = try http.receiveHead();

    // `head` points into the receive buffer, which reading the body reuses.
    // Copy what we need first.
    const method = request.head.method;
    const target = try arena.dupe(u8, request.head.target);

    if (request.head.content_length) |len| {
        if (len > learn_zig.text.max_input_len) {
            return request.respond("{\"error\":\"body exceeds 64 KiB\"}", .{
                .status = .payload_too_large,
                .keep_alive = false,
            });
        }
    }

    var body: []const u8 = "";
    if (method.requestHasBody()) {
        var body_buffer: [4096]u8 = undefined;
        const body_reader = request.readerExpectNone(&body_buffer);
        body = try body_reader.allocRemaining(arena, .limited(learn_zig.text.max_input_len));
    }

    const res = try router.handle(app, arena, method, target, body);
    std.log.info("{t} {s} -> {d}", .{ method, target, @backingInt(res.status) });
    try request.respond(res.body, .{
        .status = res.status,
        .keep_alive = false,
        .extra_headers = &.{.{ .name = "content-type", .value = res.content_type }},
    });
}
