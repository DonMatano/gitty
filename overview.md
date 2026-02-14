# Gitty Project Overview

`gitty` is a Work-In-Progress (WIP) git-core package written in Zig 0.15.2. It focuses on parsing the `.git` folder and its underlying object storage directly.

## Core Objectives

- **Git Object Parsing**: Direct reading and decompression of git objects (blobs, commits, tags, and trees).
- **Filesystem Interaction**: Efficiently traversing the `.git/objects` directory structure.
- **Minimal Dependencies**: Leveraging the Zig standard library for all operations, including zlib decompression.

## Project Structure

- `src/root.zig`: Library entry point.
- `src/main.zig`: CLI executable entry point.
- `src/gitty/`: Core module directory.
    - `gitty.zig`: Module re-exports.
    - `gitParser.zig`: Implementation of git object parsing logic, including decompression and data structure mapping.
- `testGit/`: Contains sample git repositories used for integration testing.
    - `emptyGit/`
    - `singleCommit/`
    - `singleUnCommit/`

## Key Implementation Details

### Git Object Model
The project defines a Zig `union(enum)` called `Object` to represent the four primary git object types:
- `Blob`: Represents file contents.
- `Commit`: Represents a snapshot of the repository.
- `Tag`: Represents a named pointer to a commit.
- `Tree`: Represents directory structures, linking filenames to their respective blobs or other trees.

### Parser Logic (`gitParser.zig`)
- **Decompression**: Uses `std.compress.flate.Decompress` to handle the zlib-compressed format of git objects.
- **Header Parsing**: Extracts object type and size information from the initial bytes of the decompressed data.
- **Tree Parsing**: Implements the specialized binary format parsing required for git trees, which includes file modes, names, and binary SHA-1 hashes.

## Build and Test

The project uses the standard Zig build system.
- `zig build`: Compiles the CLI tool.
- `zig build test`: Runs the test suite, including integration tests against real `.git` data.

## Future AI Client Guidance

When working with this codebase, focus on:
1. **Memory Management**: Ensure proper allocation and deallocation of buffers during decompression and parsing, following Zig's explicit allocator patterns.
2. **Object Completeness**: Many object types are still in the early stages of implementation (e.g., `Commit` and `Tag` currently only capture raw content).
3. **Error Handling**: The parser uses Zig's error union return types. Maintain this pattern for robust error reporting during repository traversal.
