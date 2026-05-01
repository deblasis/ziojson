# ziojson

JSON tokenizer and lookup for Zig. Zero-alloc tokenization, key extraction, structural validation.

## The pitch

Tokenize JSON strings into typed tokens. Look up keys in JSON objects (shallow). Validate JSON structure.

```zig
const ziojson = @import("ziojson");

// Tokenize JSON
var tokens: [64]ziojson.Token = undefined;
const count = try ziojson.tokenize("{\"name\": \"Alice\", \"age\": 30}", &tokens);
// tokens[0] = .object_open, tokens[1] = .string("name"), ...

// Shallow key lookup
const name = ziojson.findKey(json, "name").?; // "Alice"
const age = ziojson.findKey(json, "age").?;   // "30"

// Validate structure (bracket matching)
if (ziojson.isValid(json)) { /* balanced brackets */ }

// Token types: object_open/close, array_open/close, string, number, boolean, null, colon, comma
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

- `tokenize(input, tokens)` — tokenize JSON
- `Token{ .type, .text }` — typed token
- `findKey(json, key)` — shallow key lookup
- `isValid(json)` — bracket matching

## Compatibility

- **Zig**: 0.16.0
- **Platforms**: Linux, macOS, Windows
- **Breaking changes**: follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Minor versions add features, patch versions fix bugs.

## License

MIT. Copyright (c) 2026 Alessandro De Blasis.
