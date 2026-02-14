const std = @import("std");
const testing = std.testing;
const Alloc = std.mem.Allocator;

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
                    const obj = try parseDecompressedObject(decompressed_content);
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

fn parseDecompressedObject(decompressed_object: []const u8) !Object {
    const first_space_ind = std.mem.indexOfScalar(u8, decompressed_object, ' ') orelse return error.InvalidObject;

    const obj_type = std.meta.stringToEnum(ObjectIn, decompressed_object[0..first_space_ind]) orelse return error.InvalidObjectType;
    // try testing.expectEqual(size, content.len);
    const obj: Object = switch (obj_type) {
        .blob => {
            const null_ind = std.mem.indexOfScalar(u8, decompressed_object, 0) orelse return error.InvalidObject;
            const size = try std.fmt.parseInt(usize, decompressed_object[(first_space_ind + 1)..null_ind], 10);

            const content = decompressed_object[null_ind + 1 .. null_ind + 1 + size];
            return Object{
                .blob = Blob{ .size = size, .content = content },
            };
        },
        .tree => {
            const tree = try parseTreeObject(decompressed_object[first_space_ind + 1 .. decompressed_object.len]);

            // const content = decompressed_object[null_ind + 1 .. null_ind + 1 + size];
            return Object{ .tree = tree };
        },
        .tag => {
            const null_ind = std.mem.indexOfScalar(u8, decompressed_object, 0) orelse return error.InvalidObject;
            const size = try std.fmt.parseInt(usize, decompressed_object[(first_space_ind + 1)..null_ind], 10);

            const content = decompressed_object[null_ind + 1 .. null_ind + 1 + size];
            return Object{
                .tag = Tag{ .size = size, .content = content },
            };
        },
        .commit => {
            const null_ind = std.mem.indexOfScalar(u8, decompressed_object, 0) orelse return error.InvalidObject;
            const size = try std.fmt.parseInt(usize, decompressed_object[(first_space_ind + 1)..null_ind], 10);

            const content = decompressed_object[null_ind + 1 .. null_ind + 1 + size];
            return Object{
                .commit = Commit{ .size = size, .content = content },
            };
        },
    };
    return obj;
}

fn parseTreeObject(decompressed_object: []const u8) !Tree {
    const first_null_ind = std.mem.indexOfScalar(u8, decompressed_object, 0) orelse return error.InvalidObject;
    const size = try std.fmt.parseInt(usize, decompressed_object[0..first_null_ind], 10);
    var temp_ind = std.mem.indexOfScalar(u8, decompressed_object[first_null_ind + 1 .. decompressed_object.len], ' ') orelse return error.InvalidObject;
    const mode_ind_end = temp_ind + first_null_ind + 1;
    const mode = decompressed_object[first_null_ind + 1 .. mode_ind_end];
    std.debug.print(" tree mode: {s} \n", .{mode});
    temp_ind = std.mem.indexOfScalar(u8, decompressed_object[mode_ind_end + 1 .. decompressed_object.len], 0) orelse return error.InvalidObject;
    const file_name_ind_end = temp_ind + mode_ind_end + 1;
    const file_name = decompressed_object[mode_ind_end + 1 .. file_name_ind_end];
    std.debug.print(" tree file name: {s} \n", .{file_name});
    const encrypted_binary = decompressed_object[file_name_ind_end + 1 .. file_name_ind_end + 21];
    try testing.expectEqual(20, encrypted_binary.len);
    std.debug.print(" tree binary : {s} \n", .{encrypted_binary});
    for (encrypted_binary) |c| {
        std.debug.print(" {c}, ", .{c});
    }
    std.debug.print("\n", .{});
    return Tree{
        .size = size,
        .file_name = file_name,
        .file_mode = mode,
        .binary_sha = encrypted_binary,
    };
}

// test "ensure empty " {
//     _ = try ObjectParser.init("testGit/emptyGit/.git", testing.allocator);
// }
test "ensure single commit " {
    _ = try ObjectParser.init("testGit/singleCommit/git", testing.allocator);
}
