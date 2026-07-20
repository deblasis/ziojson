const std = @import("std");
const ziojson = @import("ziojson");

pub fn main() !void {
    const json = "{\"name\": \"Alice\", \"age\": 30}";

    var tokens: [64]ziojson.Token = undefined;
    const count = try ziojson.tokenize(json, &tokens);
    std.debug.print("tokens: {d}, first is {s}\n", .{ count, @tagName(tokens[0].type) });

    std.debug.print("name: {s}\n", .{ziojson.findKey(json, "name").?});
    std.debug.print("age: {s}\n", .{ziojson.findKey(json, "age").?});
    std.debug.print("brackets balance: {}\n", .{ziojson.isValid(json)});
}
