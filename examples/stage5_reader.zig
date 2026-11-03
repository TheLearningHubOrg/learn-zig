//! Stage 5 preview: the buffered Reader interface and file I/O through Io.
//! Run with `zig test examples/stage5_reader.zig`.

const std = @import("std");
const Io = std.Io;
const testing = std.testing;

/// Sums one integer per line. Works on any reader: a file, a socket, stdin
/// or, in this test, a fixed in-memory buffer.
fn sumLines(r: *Io.Reader) !i64 {
    var total: i64 = 0;
    while (try r.takeDelimiter('\n')) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");
        if (trimmed.len == 0) continue;
        total += try std.fmt.parseInt(i64, trimmed, 10);
    }
    return total;
}

test "the same function reads memory and files" {
    var mem_reader: Io.Reader = .fixed("10\n20\n\n-5\n");
    try testing.expectEqual(25, try sumLines(&mem_reader));

    const io = testing.io;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const file = try tmp.dir.createFile(io, "numbers.txt", .{ .read = true });
    defer file.close(io);
    var wbuf: [64]u8 = undefined;
    var fw: Io.File.Writer = .init(file, io, &wbuf);
    try fw.interface.writeAll("1\n2\n3\n");
    try fw.interface.flush();

    var rbuf: [64]u8 = undefined;
    var fr: Io.File.Reader = .init(file, io, &rbuf);
    try fr.seekTo(0);
    try testing.expectEqual(6, try sumLines(&fr.interface));
}
