# ziojson

## Overview

JSON toolkit for Zig. Extends std.json with jq-style path queries, streaming parser, schema validation, and pretty printing.

## Project Structure

```
src/
  ziojson.zig    - Main library source
examples/
  example.zig    - Runnable example
build.zig        - Build configuration
```

## Commands

```bash
zig build test          # Run tests
zig build run-example   # Run the example
zig build               - Build the library
```

## Architecture

Single-file library with no external dependencies. All public symbols have doc comments.

## Testing

Tests are inline in `src/ziojson.zig`. Run with `zig build test`.
