const std = @import("std");
const testing = std.testing;
const Alloc = std.mem.Allocator;
const log = std.log.scoped(.gittyParse);

const ObjectIn = enum {
    blob,
    commit,
    tag,
    tree,
};
const Object = union(ObjectIn) {
    blob: Blob,
    commit: Commit,
    tag: Tag,
    tree: Tree,
    fn getObjectTypeFromString(tag: []const u8) !ObjectIn {
        return std.meta.stringToEnum(ObjectIn, tag) orelse return error.MissingObjectIn;
    }
};

const Tag = struct {
    size: usize,
    content: []const u8,
};
const Blob = struct {
    size: usize,
    content: []const u8,
};
const Commit = struct {
    size: usize,
    content: []const u8,
};

const Tree = struct {
    size: usize,
    file_name: []const u8,
    file_mode: []const u8,
    binary_sha: []const u8,
};

// const Object = struct {
//     type: ObjectType,
//     size: usize,
//     content: []const u8,
// };
const ObjectParser = struct {
    alloc: Alloc,
    tree: []u8,
    blob: []u8,

    pub fn init(git_path: []const u8, alloc: Alloc) !void {
        var gitDir = try std.fs.cwd().openDir(git_path, .{ .iterate = true });
        defer gitDir.close();
        var it = gitDir.iterate();
        while (try it.next()) |entry| {
            switch (entry.kind) {
                .directory => {
                    if (std.mem.eql(u8, entry.name, "objects")) {
                        var obj_dir = try gitDir.openDir("objects", .{ .iterate = true });
                        defer obj_dir.close();
                        try iterateDir(&obj_dir, alloc);
                    }
                },
                else => {},
            }
        }
    }

    fn iterateDir(obj_dir: *std.fs.Dir, alloc: Alloc) !void {
        var it = obj_dir.iterate();
        while (try it.next()) |entry| {
            std.debug.print("{s} - {s} \n", .{ entry.name, @tagName(entry.kind) });
            switch (entry.kind) {
                .directory => {
                    var dir = try obj_dir.openDir(entry.name, .{ .iterate = true });
                    defer dir.close();
                    try iterateDir(&dir, alloc);
                },
                else => {
                    var f = try obj_dir.openFile(entry.name, .{});
                    defer f.close();
                    const stat = try f.stat();
                    const size = stat.size;
                    const content = try alloc.alloc(u8, size);
                    defer alloc.free(content);
                    _ = try obj_dir.readFile(entry.name, content);
                    std.debug.print("content {s}\n", .{content});
                    const decompressed_content = try decompressZipContent(content, alloc);
                    defer alloc.free(decompressed_content);
                    std.debug.print("decomp content out: {s}\n", .{decompressed_content});
                    var parseReader: std.Io.Reader = .fixed(decompressed_content);
                    const obj = try parseDecompressedObject(&parseReader);
                    std.debug.print("decomp obj: {}\n", .{obj});
                    switch (obj) {
                        .blob => std.debug.print("\n\n\ndecomp obj blob content: {}\n", .{obj.blob}),
                        .commit => std.debug.print("\n\n\ndecomp obj commit content: {}\n", .{obj.commit}),
                        .tag => std.debug.print("\n\n\ndecomp obj tag content: {}\n", .{obj.tag}),
                        .tree => std.debug.print("\n\n\ndecomp obj tree content: {}\n", .{obj.tree}),
                    }
                },
            }
        }
    }
};
fn decompressZipContent(compressed_content: []const u8, alloc: Alloc) ![]const u8 {
    var reader: std.Io.Reader = .fixed(compressed_content);
    var writer: std.Io.Writer.Allocating = .init(alloc);
    defer writer.deinit();
    var decompress = std.compress.flate.Decompress.init(&reader, .zlib, &.{});
    _ = try decompress.reader.streamRemaining(&writer.writer);
    const decompressed_content = writer.written();
    const new_string = try alloc.alloc(u8, decompressed_content.len);
    @memcpy(new_string, decompressed_content);
    return new_string;
}

fn parseDecompressedObject(reader: *std.Io.Reader) !Object {
    const obj_type_string = reader.takeDelimiter(' ') catch |err| {
        log.err("Failed to get type: {}", .{err});
        return error.InvalidObjectType;
    } orelse return error.MissingObjectType;

    const obj_type = std.meta.stringToEnum(ObjectIn, obj_type_string) orelse return error.InvalidObjectType;
    const obj: Object = switch (obj_type) {
        .blob => {
            const size_string = reader.takeDelimiter(0) catch |err| {
                log.err("Failed to get size: {}", .{err});
                return error.InvalidObjectSize;
            } orelse return error.MissingObjectSize;
            const size = try std.fmt.parseInt(usize, size_string, 10);

            const content = reader.take(size) catch |err| {
                log.err("Failed to get content: {}", .{err});
                return error.InvalidObjectContent;
            };
            try testing.expectEqual(size, content.len);
            return Object{
                .blob = Blob{ .size = size, .content = content },
            };
        },
        .tree => {
            const tree = try parseTreeObject(reader);

            // const content = decompressed_object[null_ind + 1 .. null_ind + 1 + size];
            return Object{ .tree = tree };
        },
        .tag => {
            const size_string = reader.takeDelimiter(0) catch |err| {
                log.err("Failed to get size: {}", .{err});
                return error.InvalidObjectSize;
            } orelse return error.MissingObjectSize;
            const size = try std.fmt.parseInt(usize, size_string, 10);

            const content = reader.take(size) catch |err| {
                log.err("Failed to get content: {}", .{err});
                return error.InvalidObjectContent;
            };
            try testing.expectEqual(size, content.len);
            return Object{
                .tag = Tag{ .size = size, .content = content },
            };
        },
        .commit => {
            const size_string = reader.takeDelimiter(0) catch |err| {
                log.err("Failed to get size: {}", .{err});
                return error.InvalidObjectSize;
            } orelse return error.MissingObjectSize;
            const size = try std.fmt.parseInt(usize, size_string, 10);

            const content = reader.take(size) catch |err| {
                log.err("Failed to get content: {}", .{err});
                return error.InvalidObjectContent;
            };
            try testing.expectEqual(size, content.len);
            return Object{
                .commit = Commit{ .size = size, .content = content },
            };
        },
    };
    return obj;
}

fn parseTreeObject(reader: *std.Io.Reader) !Tree {
    const size_string = reader.takeDelimiter(0) catch |err| {
        log.err("Failed to get size: {}", .{err});
        return error.InvalidObjectSize;
    } orelse return error.MissingObjectSize;
    const size = try std.fmt.parseInt(usize, size_string, 10);
    const mode = reader.takeDelimiter(' ') catch |err| {
        log.err("Failed to get mode: {}", .{err});
        return error.InvalidObjectMode;
    } orelse return error.MissingObjectMode;
    std.debug.print(" tree mode: {s} \n", .{mode});
    const file_name = reader.takeDelimiter(0) catch |err| {
        log.err("Failed to get file name: {}", .{err});
        return error.InvalidObjectFileName;
    } orelse return error.MissingObjectFileName;
    std.debug.print(" tree file name: {s} \n", .{file_name});
    var encrypted_binary: [20]u8 = undefined;
    reader.readSliceAll(&encrypted_binary) catch |err| {
        log.err("Failed to get encrypted binary: {}", .{err});
        return error.InvalidObjectEncrypted;
    };
    try std.testing.expect(encrypted_binary.len == 20);
    std.debug.print(" tree binary : {s} \n", .{encrypted_binary});
    for (encrypted_binary) |c| {
        std.debug.print(" {c}, ", .{c});
    }
    std.debug.print("\n", .{});
    return Tree{
        .size = size,
        .file_name = file_name,
        .file_mode = mode,
        .binary_sha = "",
    };
}

// test "ensure empty " {
//     _ = try ObjectParser.init("testGit/emptyGit/.git", testing.allocator);
// }
test "ensure single commit " {
    _ = try ObjectParser.init("testGit/singleCommit/git", testing.allocator);
}
