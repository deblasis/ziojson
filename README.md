# ziojson

JSON tokenizer and lookup for Zig. Zero-alloc tokenization, key extraction, structural validation.

Tokenize JSON strings into typed tokens. Look up keys in JSON objects (shallow). Validate JSON structure.

## Quick start

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

## Example output

`zig build run-example` produces:

```
=== ziojson example ===

Tokenizing: {"name": "Alice", "age": 30, "active": true}
  object_open: "{"
  string: "\"name\""
  colon: ":"
  string: "\"Alice\""
  ...
  object_close: "}"

Key lookup:
  name = Alice
  age = 30
  active = true
```

See [examples/example.zig](examples/example.zig) for the source.

## API

- `tokenize(input, tokens)` — tokenize JSON into typed tokens
- `Token{ .type, .text }` — typed token
- `TokenType` — object_open/close, array_open/close, string, number, boolean, null, colon, comma
- `findKey(json, key)` — shallow key lookup
- `isValid(json)` — structural bracket matching

## Compatibility

- **Zig**: 0.16.0
- **Platforms**: Linux, macOS, Windows
- **Breaking changes**: follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Minor versions add features, patch versions fix bugs.

## License

MIT. Copyright (c) 2026 Alessandro De Blasis.
