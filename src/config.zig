//! Runtime configuration read from environment variables.

const std = @import("std");

pub const default_port: u16 = 8080;

pub const PortError = error{ InvalidPort, PortOutOfRange };

/// Parses the PORT environment variable. A missing or blank value falls back
/// to `default_port`; anything else must be a decimal integer in 1..65535.
pub fn parsePort(raw: ?[]const u8) PortError!u16 {
    const text = std.mem.trim(u8, raw orelse return default_port, " \t\r\n");
    if (text.len == 0) return default_port;
    // Parse into a wider type so 70000 reports PortOutOfRange, not InvalidPort.
    const value = std.fmt.parseInt(u32, text, 10) catch return error.InvalidPort;
    if (value == 0 or value > std.math.maxInt(u16)) return error.PortOutOfRange;
    return @intCast(value);
}

const testing = std.testing;

test "parsePort falls back to the default" {
    try testing.expectEqual(default_port, try parsePort(null));
    try testing.expectEqual(default_port, try parsePort("   "));
}

test "parsePort accepts valid ports and trims whitespace" {
    try testing.expectEqual(3000, try parsePort("3000"));
    try testing.expectEqual(65535, try parsePort(" 65535\n"));
}

test "parsePort reports distinct errors" {
    try testing.expectError(error.InvalidPort, parsePort("http"));
    try testing.expectError(error.InvalidPort, parsePort("-1"));
    try testing.expectError(error.PortOutOfRange, parsePort("0"));
    try testing.expectError(error.PortOutOfRange, parsePort("70000"));
}
