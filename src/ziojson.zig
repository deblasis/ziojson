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
// Writing
// ---------------------------------------------------------------------------

/// Error set shared by the escaper and the `Writer`. The only failure mode is
/// the backing `std.Io.Writer` refusing a write. API misuse, such as an
/// unbalanced container, a value where an object field name belongs, or
/// nesting past `Writer.max_depth`, is a programmer error and trips an
/// assertion instead of returning an error, so the set stays free of `anyerror`.
pub const WriteError = std.Io.Writer.Error;

/// Write the escaped *contents* of a JSON string to `w`, without the
/// surrounding quotes. This is the injection-safe core: `"` and `\` are
/// backslash-escaped, `\n \r \t \b \f` become their short escapes, every other
/// byte below 0x20 becomes a `\uXXXX` sequence, and every byte at or above 0x20
/// is passed through verbatim. Multibyte UTF-8 is therefore emitted unchanged,
/// since each of its bytes is at or above 0x80. Use `writeStringEscaped` if you
/// want the quotes too.
pub fn escapeInto(w: *std.Io.Writer, s: []const u8) WriteError!void {
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            0x08 => try w.writeAll("\\b"),
            0x0c => try w.writeAll("\\f"),
            else => {
                if (c < 0x20) {
                    try w.print("\\u{x:0>4}", .{c});
                } else {
                    try w.writeByte(c);
                }
            },
        }
    }
}

/// Write `s` to `w` as a complete, quoted JSON string literal: a leading `"`,
/// the fully escaped contents (see `escapeInto`), and a trailing `"`. This is
/// the drop-in for hand-rolled `writeJsonEscaped`-style helpers and the routine
/// the `Writer` uses internally for every string and field name.
pub fn writeStringEscaped(w: *std.Io.Writer, s: []const u8) WriteError!void {
    try w.writeByte('"');
    try escapeInto(w, s);
    try w.writeByte('"');
}

/// A stateful compact-JSON emitter over a `*std.Io.Writer`.
///
/// The writer tracks object and array nesting internally and inserts commas,
/// colons, and quotes for you, so a caller that only ever calls these methods
/// cannot produce malformed JSON. Field names and string values are escaped
/// through `writeStringEscaped`. Output is compact: no spaces, no newlines.
///
/// Construct with `init`, then drive it:
///
///     var buf: [128]u8 = undefined;
///     var out = std.Io.Writer.fixed(&buf);
///     var jw = Writer.init(&out);
///     try jw.beginObject();
///     try jw.field("name");
///     try jw.writeString("Alice");
///     try jw.field("age");
///     try jw.writeInt(30);
///     try jw.endObject();
///     // buf[0..out.end] == "{\"name\":\"Alice\",\"age\":30}"
///
/// Misuse (unbalanced `begin`/`end`, a value in an object without a preceding
/// `field`, nesting past `max_depth`) is a programmer error and asserts.
pub const Writer = struct {
    /// The backing byte sink. Every byte the writer emits goes here.
    out: *std.Io.Writer,
    /// Nesting stack of open containers. Only the first `depth` entries are live.
    stack: [max_depth]Container = undefined,
    /// Number of currently open objects and arrays.
    depth: usize = 0,
    /// True after `field` when a value is expected next, so the value writer
    /// knows not to emit a separator (the field already emitted one).
    pending_value: bool = false,

    /// Maximum object/array nesting depth. Opening a container beyond this
    /// trips an assertion.
    pub const max_depth = 32;

    /// One open container on the nesting stack.
    const Container = struct {
        /// Whether this container is an object or an array.
        kind: Kind,
        /// Whether at least one element has been written into it yet, which
        /// decides whether the next element needs a leading comma.
        has_child: bool,
    };

    /// The kind of an open container.
    const Kind = enum { object, array };

    /// Create a writer that emits compact JSON to `out`. The writer borrows
    /// `out`; there is nothing to free.
    pub fn init(out: *std.Io.Writer) Writer {
        return .{ .out = out };
    }

    /// Emit the separator, if any, that must precede a value: a comma when the
    /// value continues an array, nothing when it is the first array element or
    /// a top-level value, and nothing when it follows a `field` (whose colon
    /// already separates it). Asserts if a bare value is written directly into
    /// an object without a field name.
    fn beforeValue(self: *Writer) WriteError!void {
        if (self.pending_value) {
            self.pending_value = false;
            return;
        }
        if (self.depth == 0) return;
        const top = &self.stack[self.depth - 1];
        std.debug.assert(top.kind == .array); // an object value needs a field name first
        if (top.has_child) try self.out.writeByte(',');
        top.has_child = true;
    }

    /// Push a freshly opened container onto the nesting stack.
    fn push(self: *Writer, kind: Kind) void {
        std.debug.assert(self.depth < max_depth);
        self.stack[self.depth] = .{ .kind = kind, .has_child = false };
        self.depth += 1;
    }

    /// Begin an object, emitting `{`. Must be balanced by `endObject`. Valid at
    /// the top level, as an array element, or as an object field value.
    pub fn beginObject(self: *Writer) WriteError!void {
        try self.beforeValue();
        try self.out.writeByte('{');
        self.push(.object);
    }

    /// End the current object, emitting `}`. Asserts the innermost open
    /// container is an object and that no field is awaiting its value.
    pub fn endObject(self: *Writer) WriteError!void {
        std.debug.assert(self.depth > 0 and !self.pending_value);
        std.debug.assert(self.stack[self.depth - 1].kind == .object);
        self.depth -= 1;
        try self.out.writeByte('}');
    }

    /// Begin an array, emitting `[`. Must be balanced by `endArray`. Valid at
    /// the top level, as an array element, or as an object field value.
    pub fn beginArray(self: *Writer) WriteError!void {
        try self.beforeValue();
        try self.out.writeByte('[');
        self.push(.array);
    }

    /// End the current array, emitting `]`. Asserts the innermost open
    /// container is an array and that no field is awaiting its value.
    pub fn endArray(self: *Writer) WriteError!void {
        std.debug.assert(self.depth > 0 and !self.pending_value);
        std.debug.assert(self.stack[self.depth - 1].kind == .array);
        self.depth -= 1;
        try self.out.writeByte(']');
    }

    /// Write an object field name (an escaped, quoted key followed by `:`). The
    /// next call must write exactly one value (a scalar, `beginObject`, or
    /// `beginArray`). Asserts the innermost open container is an object and that
    /// a previous field is not already awaiting its value.
    pub fn field(self: *Writer, name: []const u8) WriteError!void {
        std.debug.assert(self.depth > 0 and !self.pending_value);
        const top = &self.stack[self.depth - 1];
        std.debug.assert(top.kind == .object);
        if (top.has_child) try self.out.writeByte(',');
        top.has_child = true;
        try writeStringEscaped(self.out, name);
        try self.out.writeByte(':');
        self.pending_value = true;
    }

    /// Write a JSON string value, escaped and quoted.
    pub fn writeString(self: *Writer, s: []const u8) WriteError!void {
        try self.beforeValue();
        try writeStringEscaped(self.out, s);
    }

    /// Write a JSON integer value. Accepts any integer type.
    pub fn writeInt(self: *Writer, value: anytype) WriteError!void {
        try self.beforeValue();
        try self.out.print("{d}", .{value});
    }

    /// Write a JSON number value from a float. JSON has no way to spell NaN or
    /// infinity, so a non-finite `value` is emitted as `null`; every finite
    /// value is emitted as its shortest round-tripping decimal form.
    pub fn writeFloat(self: *Writer, value: anytype) WriteError!void {
        try self.beforeValue();
        if (std.math.isNan(value) or std.math.isInf(value)) {
            try self.out.writeAll("null");
        } else {
            try self.out.print("{d}", .{value});
        }
    }

    /// Write a JSON boolean value: `true` or `false`.
    pub fn writeBool(self: *Writer, value: bool) WriteError!void {
        try self.beforeValue();
        try self.out.writeAll(if (value) "true" else "false");
    }

    /// Write a JSON `null` value.
    pub fn writeNull(self: *Writer) WriteError!void {
        try self.beforeValue();
        try self.out.writeAll("null");
    }
};

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

// ---- writer: escaping -----------------------------------------------------

test "escapeInto quote and backslash" {
    var buf: [64]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try escapeInto(&w, "a\"b\\c");
    try std.testing.expectEqualStrings("a\\\"b\\\\c", buf[0..w.end]);
}

test "escapeInto short escapes" {
    var buf: [64]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try escapeInto(&w, "\n\r\t\x08\x0c");
    try std.testing.expectEqualStrings("\\n\\r\\t\\b\\f", buf[0..w.end]);
}

test "escapeInto every control char below 0x20" {
    // Each of 0x00..0x1f must come out as a short escape or a \uXXXX sequence,
    // never as a raw control byte.
    var c: u8 = 0;
    while (c < 0x20) : (c += 1) {
        var buf: [8]u8 = undefined;
        var w = std.Io.Writer.fixed(&buf);
        try escapeInto(&w, &[_]u8{c});
        const out = buf[0..w.end];
        try std.testing.expect(out[0] == '\\');
        switch (c) {
            '\n' => try std.testing.expectEqualStrings("\\n", out),
            '\r' => try std.testing.expectEqualStrings("\\r", out),
            '\t' => try std.testing.expectEqualStrings("\\t", out),
            0x08 => try std.testing.expectEqualStrings("\\b", out),
            0x0c => try std.testing.expectEqualStrings("\\f", out),
            else => {
                try std.testing.expect(out[1] == 'u');
                try std.testing.expectEqual(@as(usize, 6), out.len);
            },
        }
    }
}

test "escapeInto uXXXX for an odd control char" {
    var buf: [16]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try escapeInto(&w, "\x01\x1f");
    try std.testing.expectEqualStrings("\\u0001\\u001f", buf[0..w.end]);
}

test "escapeInto passes multibyte UTF-8 through unchanged" {
    const s = "héllo — 日本語 😀";
    var buf: [64]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try escapeInto(&w, s);
    try std.testing.expectEqualStrings(s, buf[0..w.end]);
}

test "writeStringEscaped adds quotes" {
    var buf: [64]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeStringEscaped(&w, "hi\n");
    try std.testing.expectEqualStrings("\"hi\\n\"", buf[0..w.end]);
}

// ---- writer: structure ----------------------------------------------------

test "writer empty object" {
    var buf: [16]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    var jw = Writer.init(&out);
    try jw.beginObject();
    try jw.endObject();
    try std.testing.expectEqualStrings("{}", buf[0..out.end]);
}

test "writer empty array" {
    var buf: [16]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    var jw = Writer.init(&out);
    try jw.beginArray();
    try jw.endArray();
    try std.testing.expectEqualStrings("[]", buf[0..out.end]);
}

test "writer object with mixed scalar fields" {
    var buf: [128]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    var jw = Writer.init(&out);
    try jw.beginObject();
    try jw.field("name");
    try jw.writeString("Alice");
    try jw.field("age");
    try jw.writeInt(30);
    try jw.field("member");
    try jw.writeBool(true);
    try jw.field("note");
    try jw.writeNull();
    try jw.endObject();
    try std.testing.expectEqualStrings(
        "{\"name\":\"Alice\",\"age\":30,\"member\":true,\"note\":null}",
        buf[0..out.end],
    );
}

test "writer array of scalars" {
    var buf: [32]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    var jw = Writer.init(&out);
    try jw.beginArray();
    try jw.writeInt(1);
    try jw.writeInt(2);
    try jw.writeInt(3);
    try jw.endArray();
    try std.testing.expectEqualStrings("[1,2,3]", buf[0..out.end]);
}

test "writer nested object and array" {
    var buf: [128]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    var jw = Writer.init(&out);
    try jw.beginObject();
    try jw.field("id");
    try jw.writeInt(7);
    try jw.field("tags");
    try jw.beginArray();
    try jw.writeString("a");
    try jw.writeString("b");
    try jw.endArray();
    try jw.field("meta");
    try jw.beginObject();
    try jw.field("ok");
    try jw.writeBool(false);
    try jw.endObject();
    try jw.endObject();
    try std.testing.expectEqualStrings(
        "{\"id\":7,\"tags\":[\"a\",\"b\"],\"meta\":{\"ok\":false}}",
        buf[0..out.end],
    );
}

test "writer array of objects" {
    var buf: [128]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    var jw = Writer.init(&out);
    try jw.beginArray();
    try jw.beginObject();
    try jw.field("x");
    try jw.writeInt(1);
    try jw.endObject();
    try jw.beginObject();
    try jw.field("x");
    try jw.writeInt(2);
    try jw.endObject();
    try jw.endArray();
    try std.testing.expectEqualStrings("[{\"x\":1},{\"x\":2}]", buf[0..out.end]);
}

test "writer escapes field names and string values" {
    var buf: [64]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    var jw = Writer.init(&out);
    try jw.beginObject();
    try jw.field("a\"b");
    try jw.writeString("line1\nline2");
    try jw.endObject();
    try std.testing.expectEqualStrings("{\"a\\\"b\":\"line1\\nline2\"}", buf[0..out.end]);
}

// ---- writer: number edge cases --------------------------------------------

test "writer negative and large integers" {
    var buf: [64]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    var jw = Writer.init(&out);
    try jw.beginArray();
    try jw.writeInt(@as(i64, -42));
    try jw.writeInt(@as(u64, 18446744073709551615));
    try jw.writeInt(0);
    try jw.endArray();
    try std.testing.expectEqualStrings("[-42,18446744073709551615,0]", buf[0..out.end]);
}

test "writer finite floats" {
    var buf: [64]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    var jw = Writer.init(&out);
    try jw.beginArray();
    try jw.writeFloat(@as(f64, 0.5));
    try jw.writeFloat(@as(f64, -1.25));
    try jw.writeFloat(@as(f64, 1.0));
    try jw.endArray();
    try std.testing.expectEqualStrings("[0.5,-1.25,1]", buf[0..out.end]);
}

test "writer non-finite floats become null" {
    var buf: [64]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    var jw = Writer.init(&out);
    try jw.beginArray();
    try jw.writeFloat(std.math.nan(f64));
    try jw.writeFloat(std.math.inf(f64));
    try jw.writeFloat(-std.math.inf(f64));
    try jw.endArray();
    try std.testing.expectEqualStrings("[null,null,null]", buf[0..out.end]);
}

test "writer top-level scalar" {
    var buf: [16]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    var jw = Writer.init(&out);
    try jw.writeInt(42);
    try std.testing.expectEqualStrings("42", buf[0..out.end]);
}

test "writer round-trips through the tokenizer" {
    var buf: [128]u8 = undefined;
    var out = std.Io.Writer.fixed(&buf);
    var jw = Writer.init(&out);
    try jw.beginObject();
    try jw.field("name");
    try jw.writeString("Alice");
    try jw.field("age");
    try jw.writeInt(30);
    try jw.endObject();
    const produced = buf[0..out.end];
    try std.testing.expect(isValid(produced));
    var tokens: [16]Token = undefined;
    const count = try tokenize(produced, &tokens);
    try std.testing.expectEqual(@as(usize, 9), count);
    try std.testing.expectEqualStrings("Alice", findKey(produced, "name").?);
}
