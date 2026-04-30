# ziojson

JSON toolkit with comptime queries for Zig

JSON toolkit for Zig. Extends std.json with jq-style path queries, streaming parser, schema validation, and pretty printing.

## Features

- jq-style path queries
- streaming parser
- schema validation
- pretty printing

## Quick Start

```zig
const ziojson = @import("ziojson");

pub fn main() !void {
    // See examples/ for runnable code
}
```

## Installation

Add to your `build.zig.zon`:

```zig
.{
    .dependencies = .{
        .ziojson = .{ .url = "https://github.com/deblasis/ziojson/archive/refs/heads/main.tar.gz", .hash = "..." },
    },
}
```

Then in your `build.zig`:

```zig
const ziojson = b.dependency("ziojson", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("ziojson", ziojson.module("ziojson"));
```

## Examples

Run the included example:

```bash
zig build run-example
```

## API Reference

See [src/ziojson.zig](src/ziojson.zig) for full documentation. All public symbols have doc comments.

## Compatibility

- **Zig:** 0.16.0
- **Platforms:** Linux, macOS, Windows
- **Breaking changes:** Follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Minor versions may add features, patch versions fix bugs.

## License

MIT
