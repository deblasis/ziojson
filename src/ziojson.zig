//! JSON parsing utilities for Zig.
//!
//! Tokenizer, value extraction, and type detection without full JSON tree allocation.

const std = @import("std");

/// JSON token types.
pub const TokenType = enum { object_open, object_close, array_open, array_close, string, number, boolean, null_, colon, comma };

/// A JSON token.
pub const Token = struct {
    type: TokenType,
    text: []const u8,

    pub fn init(t: TokenType, text: []const u8) Token {
        return .{ .type = t, .text = text };
    }
};

/// Split a JSON string into tokens. Backslash escapes inside strings are
/// skipped over, but escape sequences are not decoded: token text is the raw
/// slice of the input, quotes included. Numbers are only scanned for the
/// characters a number can contain, they are not validated.
/// Caller must provide an output buffer. Returns error.TooManyTokens if it
/// does not fit.
pub fn tokenize(input: []const u8, tokens: []Token) !usize {
    var count: usize = 0;
    var i: usize = 0;

    while (i < input.len) {
        const ch = input[i];
        switch (ch) {
            ' ', '\t', '\n', '\r' => i += 1,
            '{' => {
                if (count >= tokens.len) return error.TooManyTokens;
                tokens[count] = Token.init(.object_open, input[i .. i + 1]);
                count += 1;
                i += 1;
            },
            '}' => {
                if (count >= tokens.len) return error.TooManyTokens;
                tokens[count] = Token.init(.object_close, input[i .. i + 1]);
                count += 1;
                i += 1;
            },
            '[' => {
                if (count >= tokens.len) return error.TooManyTokens;
                tokens[count] = Token.init(.array_open, input[i .. i + 1]);
                count += 1;
                i += 1;
            },
            ']' => {
                if (count >= tokens.len) return error.TooManyTokens;
                tokens[count] = Token.init(.array_close, input[i .. i + 1]);
                count += 1;
                i += 1;
            },
            ':' => {
                if (count >= tokens.len) return error.TooManyTokens;
                tokens[count] = Token.init(.colon, input[i .. i + 1]);
                count += 1;
                i += 1;
            },
            ',' => {
                if (count >= tokens.len) return error.TooManyTokens;
                tokens[count] = Token.init(.comma, input[i .. i + 1]);
                count += 1;
                i += 1;
            },
            '"' => {
                var end = i + 1;
                while (end < input.len) {
                    if (input[end] == '\\' and end + 1 < input.len) {
                        end += 2; // skip escaped char
                    } else if (input[end] == '"') {
                        break;
                    } else {
                        end += 1;
                    }
                }
                if (end >= input.len) return error.UnterminatedString;
                end += 1; // include closing quote
                if (count >= tokens.len) return error.TooManyTokens;
                tokens[count] = Token.init(.string, input[i..end]);
                count += 1;
                i = end;
            },
            't' => {
                if (i + 4 > input.len or !std.mem.eql(u8, input[i .. i + 4], "true")) return error.InvalidLiteral;
                if (count >= tokens.len) return error.TooManyTokens;
                tokens[count] = Token.init(.boolean, input[i .. i + 4]);
                count += 1;
                i += 4;
            },
            'f' => {
                if (i + 5 > input.len or !std.mem.eql(u8, input[i .. i + 5], "false")) return error.InvalidLiteral;
                if (count >= tokens.len) return error.TooManyTokens;
                tokens[count] = Token.init(.boolean, input[i .. i + 5]);
                count += 1;
                i += 5;
            },
            'n' => {
                if (i + 4 > input.len or !std.mem.eql(u8, input[i .. i + 4], "null")) return error.InvalidLiteral;
                if (count >= tokens.len) return error.TooManyTokens;
                tokens[count] = Token.init(.null_, input[i .. i + 4]);
                count += 1;
                i += 4;
            },
            '-', '0'...'9' => {
                var end = i + 1;
                while (end < input.len) : (end += 1) {
                    switch (input[end]) {
                        '0'...'9', '.', 'e', 'E', '+', '-' => {},
                        else => break,
                    }
                }
                if (count >= tokens.len) return error.TooManyTokens;
                tokens[count] = Token.init(.number, input[i..end]);
                count += 1;
                i = end;
            },
            else => return error.UnexpectedCharacter,
        }
    }
    return count;
}

/// Find the value for a key by scanning the text for the first occurrence of
/// "key" and reading whatever follows the colon. This is a plain substring
/// search, it is not object aware: it will happily match a key nested deeper
/// in the document or a quoted string that just looks like the key. Returns
/// null if the key is not found or if the key is longer than 254 bytes.
pub fn findKey(json: []const u8, key: []const u8) ?[]const u8 {
    // Search for "key":
    var search: [256]u8 = undefined;
    const pattern = std.fmt.bufPrint(&search, "\"{s}\"", .{key}) catch return null;

    const pos = std.mem.indexOf(u8, json, pattern) orelse return null;
    const after_key = pos + pattern.len;
    // Skip whitespace and colon
    var i = after_key;
    while (i < json.len and (json[i] == ' ' or json[i] == '\t' or json[i] == '\n' or json[i] == '\r' or json[i] == ':')) : (i += 1) {}

    if (i >= json.len) return null;

    if (json[i] == '"') {
        // String value
        var end = i + 1;
        while (end < json.len and json[end] != '"') : (end += 1) {}
        return json[i + 1 .. end];
    }
    // Non-string value
    var end = i;
    while (end < json.len and json[end] != ',' and json[end] != '}' and json[end] != ']') : (end += 1) {}
    return std.mem.trim(u8, json[i..end], " \t\n\r");
}

/// Check that brackets and braces balance, ignoring anything inside strings.
/// This is not a JSON validator: it does not check that the brackets match
/// each other by kind, and empty input counts as balanced.
pub fn isValid(json: []const u8) bool {
    var depth: i32 = 0;
    var in_string = false;
    for (json) |ch| {
        if (ch == '"' and !in_string) {
            in_string = true;
        } else if (ch == '"' and in_string) {
            in_string = false;
        } else if (!in_string) {
            if (ch == '{' or ch == '[') depth += 1;
            if (ch == '}' or ch == ']') depth -= 1;
            if (depth < 0) return false;
        }
    }
    return depth == 0;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "tokenize simple object" {
    const input = "{\"name\": \"Alice\", \"age\": 30}";
    var tokens: [20]Token = undefined;
    const count = try tokenize(input, &tokens);
    try std.testing.expectEqual(@as(usize, 9), count);
    try std.testing.expectEqual(TokenType.object_open, tokens[0].type);
    try std.testing.expectEqual(TokenType.string, tokens[1].type);
    try std.testing.expectEqualStrings("\"name\"", tokens[1].text);
    try std.testing.expectEqual(TokenType.colon, tokens[2].type);
    try std.testing.expectEqual(TokenType.string, tokens[3].type);
    try std.testing.expectEqual(TokenType.comma, tokens[4].type);
    try std.testing.expectEqual(TokenType.string, tokens[5].type);
    try std.testing.expectEqual(TokenType.colon, tokens[6].type);
    try std.testing.expectEqual(TokenType.number, tokens[7].type);
    try std.testing.expectEqual(TokenType.object_close, tokens[8].type);
}

test "tokenize array" {
    const input = "[1, 2, 3]";
    var tokens: [10]Token = undefined;
    const count = try tokenize(input, &tokens);
    try std.testing.expectEqual(@as(usize, 7), count);
    try std.testing.expectEqual(TokenType.array_open, tokens[0].type);
    try std.testing.expectEqual(TokenType.number, tokens[1].type);
    try std.testing.expectEqual(TokenType.array_close, tokens[6].type);
}

test "tokenize booleans and null" {
    const input = "[true, false, null]";
    var tokens: [10]Token = undefined;
    const count = try tokenize(input, &tokens);
    try std.testing.expectEqual(@as(usize, 7), count);
    try std.testing.expectEqual(TokenType.boolean, tokens[1].type);
    try std.testing.expectEqual(TokenType.boolean, tokens[3].type);
    try std.testing.expectEqual(TokenType.null_, tokens[5].type);
}

test "tokenize negative number" {
    const input = "-42.5e+3";
    var tokens: [5]Token = undefined;
    const count = try tokenize(input, &tokens);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqualStrings("-42.5e+3", tokens[0].text);
}

test "tokenize escaped string" {
    const input = "\"hello\\\"world\"";
    var tokens: [5]Token = undefined;
    const count = try tokenize(input, &tokens);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqualStrings("\"hello\\\"world\"", tokens[0].text);
}

test "findKey string value" {
    const json = "{\"name\": \"Alice\", \"age\": 30}";
    try std.testing.expectEqualStrings("Alice", findKey(json, "name").?);
    try std.testing.expectEqualStrings("30", findKey(json, "age").?);
    try std.testing.expect(findKey(json, "missing") == null);
}

test "findKey missing key" {
    const json = "{}";
    try std.testing.expect(findKey(json, "anything") == null);
}

test "isValid balanced" {
    try std.testing.expect(isValid("{\"a\": [1, 2]}"));
    try std.testing.expect(isValid("[]"));
    try std.testing.expect(isValid("{}"));
}

test "isValid unbalanced" {
    try std.testing.expect(!isValid("{{{"));
    try std.testing.expect(!isValid("[[["));
    try std.testing.expect(!isValid("}"));
}

test "tokenize empty object" {
    const input = "{}";
    var tokens: [10]Token = undefined;
    const count = try tokenize(input, &tokens);
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqual(TokenType.object_open, tokens[0].type);
    try std.testing.expectEqual(TokenType.object_close, tokens[1].type);
}

test "tokenize whitespace handling" {
    const input = "  {  \"key\"  :  \"value\"  }  ";
    var tokens: [10]Token = undefined;
    const count = try tokenize(input, &tokens);
    try std.testing.expectEqual(@as(usize, 5), count);
}

test "findKey nested" {
    const json = "{\"outer\": \"hello\"}";
    try std.testing.expectEqualStrings("hello", findKey(json, "outer").?);
}

test "findKey missing" {
    const json = "{\"name\": \"Alice\"}";
    try std.testing.expect(findKey(json, "age") == null);
}

test "tokenize empty input" {
    var tokens: [10]Token = undefined;
    const count = try tokenize("", &tokens);
    try std.testing.expectEqual(@as(usize, 0), count);
}

test "tokenize boolean and null" {
    var tokens: [10]Token = undefined;
    const count = try tokenize("true false null", &tokens);
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqual(TokenType.boolean, tokens[0].type);
    try std.testing.expectEqual(TokenType.null_, tokens[2].type);
}

test "tokenize nested object" {
    var tokens: [20]Token = undefined;
    const count = try tokenize("{\"a\": {\"b\": 1}}", &tokens);
    try std.testing.expect(count >= 4);
}

test "isValid empty string" {
    try std.testing.expect(isValid(""));
}
