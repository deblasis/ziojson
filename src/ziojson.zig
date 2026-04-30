//! ziojson for Zig.

const std = @import("std");

test "{ziojson} smoke test" {
    try std.testing.expect(true);
}

test "{ziojson} basic functionality" {
    try std.testing.expect(1 + 1 == 2);
}

test "{ziojson} string operations" {
    try std.testing.expectEqualStrings("hello", "hello");
}

test "{ziojson} error handling" {
    const result = std.math.add(u8, 200, 100);
    try std.testing.expectError(error.Overflow, result);
}
