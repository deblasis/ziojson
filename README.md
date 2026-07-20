# ziojson

Small JSON text helpers for Zig. Allocation free tokenizing, a first match key lookup, and a bracket balance check.

## The pitch

Three functions, no allocator, no parse tree. Split JSON text into typed tokens, pull a value out by key, and check that the brackets balance.

```zig
const ziojson = @import("ziojson");

const json = "{\"name\": \"Alice\", \"age\": 30}";

// Tokenize JSON
var tokens: [64]ziojson.Token = undefined;
const count = try ziojson.tokenize(json, &tokens);
// tokens[0].type == .object_open, tokens[1].type == .string with text "\"name\""

// First match key lookup
const name = ziojson.findKey(json, "name").?; // "Alice"
const age = ziojson.findKey(json, "age").?;   // "30"

// Bracket balance check
if (ziojson.isValid(json)) { /* brackets balance */ }

// Token types: object_open/close, array_open/close, string, number, boolean, null_, colon, comma
```

## Install

```bash
zig fetch --save git+https://github.com/deblasis/ziojson
```

Then in your `build.zig`:

```zig
const dep = b.dependency("ziojson", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("ziojson", dep.module("ziojson"));
```

Requires Zig 0.16.

## API

- `tokenize(input, tokens)` - split JSON text into tokens, into a caller supplied buffer
- `Token{ .type, .text }` - token type plus the raw slice of the input it came from
- `findKey(json, key)` - first match substring lookup of `"key":` and the value after it
- `isValid(json)` - brackets and braces balance, ignoring string contents

## What it does not do

No parse tree, no allocator, no escape decoding, no number parsing, no schema
checks and no path queries. `findKey` is a substring search, so it can match a
key nested deeper in the document. `isValid` only counts brackets, it does not
check that they match by kind and it treats empty input as balanced. If you need
real JSON parsing, use `std.json`.

## Compatibility

- **Zig**: 0.16.0
- **Platforms**: Linux, macOS, Windows
- **Breaking changes**: follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Minor versions add features, patch versions fix bugs.

## License

MIT. Copyright (c) 2026 Alessandro De Blasis.
