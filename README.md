# GITTY. ZIG GIT PARSER (WIP)

*This lib is in work in progress and should not be used in prod*

A zig lib for parsing git objects.

The lib for now parse. 
 - Blobs
 - Trees

 As this lib is part of a bigger project I am working on I expect it will evolve with new features that I end up needing.

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

## Usage
The CLI tool can be run against a `.git` folder to list its contents:
```bash
zig build run -- [path to .git folder]
```
If no path is provided, it attempts to open the `.git` folder in the current directory.


## Contribution.
Firstly I really appreciate one desire to contribute. That said I won't be open to any contribution as this is mostly a project I am 
on to learn about low level programming. That said you are free to branch from this if you feel like. I will appreciate a repo-mention though.
