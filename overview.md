# Gitty Project Overview
*This doc is meant to be read by AI to give it an overview*

`gitty` is a Work-In-Progress (WIP) Git-core package written in Zig 0.15.2, designed to parse and interact with `.git` repository internals.

## Core Goals
- Provide a lightweight, Zig-native library for reading Git object databases.
- Handle core Git objects (Blobs, Trees, Commits, Tags) directly from the `.git` folder.
- Eventually support the full Git protocol and file formats (Packfiles, Refs, etc.).

## Current Status
- **Parsing:** Successfully parses decompressed Git objects (Blobs and Trees) from `.git/objects`.
- **Decompression:** Uses `std.compress.flate` for zlib decompression of Git objects.
- **I/O:** Utilizes the new `std.Io` abstraction introduced in recent Zig versions.
- **Objects:**
    - `Blob`: Fully implemented (size and content).
    - `Tree`: Fully implemented (file modes, names, and binary SHAs).
    - `Commit`: Stubbed (recognized but content parsing not yet implemented).
    - `Tag`: Stubbed (recognized but content parsing not yet implemented).
- **Limitations:**
    - Packfiles (`.git/objects/pack`) are currently skipped.
    - Reference parsing (`.git/refs`) is not yet implemented.
    - Writing/creating objects is not yet supported.

## Architecture
- `src/root.zig`: Library entry point.
- `src/main.zig`: CLI entry point, primarily for debugging and testing the parser.
- `src/gitty/repo.zig`: The core logic, containing the `Repo` struct and object parsing functions.
- `src/gitty/gitty.zig`: Internal module exporter.

## Key Structures
- `Repo`: Manages the repository state, including a path to the `.git` folder and hash maps for stored objects (Blobs, Trees, etc.).
- `Object`: A tagged union representing the various Git object types.
- `TreeContent`: Represents an entry in a Git tree (file/folder, mode, name, SHA).

## Usage
The CLI tool can be run against a `.git` folder to list its contents:
```bash
zig build run -- [path to .git folder]
```
If no path is provided, it attempts to open the `.git` folder in the current directory.

## Testing
Unit tests are available in `src/gitty/repo.zig` and can be run using:
```bash
zig build test
```
The tests include creating temporary Git repositories to verify the parser's behavior.
