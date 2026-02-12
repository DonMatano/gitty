const std = @import("std");
const testing = std.testing;
const Alloc = std.mem.Allocator;

const ObjectType = enum {
    blob,
    commit,
    tag,
    tree,
};

const Object = struct {
    type: ObjectType,
    size: usize,
    content: []const u8,
};
const ObjectParser = struct {
    alloc: Alloc,
    tree: []u8,
    blob: []u8,

    pub fn init(git_path: []const u8, alloc: Alloc) !void {
        var gitDir = try std.fs.cwd().openDir(git_path, .{ .iterate = true });
        defer gitDir.close();
        var it = gitDir.iterate();
        while (try it.next()) |entry| {
            std.debug.print("{s} - {s} \n", .{ entry.name, @tagName(entry.kind) });
            switch (entry.kind) {
                .directory => {
                    if (std.mem.eql(u8, entry.name, "objects")) {
                        var obj_dir = try gitDir.openDir("objects", .{ .iterate = true });
                        defer obj_dir.close();
                        try iterateDir(&obj_dir, alloc);
                    }
                },
                else => {
                    std.debug.print("Unhandled Kind, {s}\n", .{@tagName(entry.kind)});
                },
            }
        }
    }

    fn iterateDir(obj_dir: *std.fs.Dir, alloc: Alloc) !void {
        var it = obj_dir.iterate();
        // var buf: [4096]u8 = undefined;
        // var writer_buf: [4096]u8 = undefined;
        // var std_out = std.fs.File.stdout().writer(&writer_buf);
        // var writer = &std_out.interface;

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
    const header = decompress.container_metadata.container().headerSize();
    std.debug.print("header: {d}\n", .{header});
    _ = try decompress.reader.streamRemaining(&writer.writer);
    const decompressed_content = writer.written();
    std.debug.print("decomp content: {s}\n", .{decompressed_content});
    const new_string = try alloc.alloc(u8, decompressed_content.len);
    @memcpy(new_string, decompressed_content);
    return new_string;
}

fn parseDecompressedObject(decompressed_object: []const u8) !Object {
    std.debug.print("decomp in content: {s}\n", .{decompressed_object});
    for (decompressed_object, 0..) |ch, i| {
        std.debug.print("\t\tdecomp in char: {c} = {d} - ind {d}\n", .{ ch, ch, i });
    }
    const first_space_ind = std.mem.indexOfScalar(u8, decompressed_object, ' ') orelse return error.InvalidObject;
    std.debug.print("first space {d}\n", .{first_space_ind});
    const null_ind = std.mem.indexOfScalar(u8, decompressed_object, 0) orelse return error.InvalidObject;
    std.debug.print("null ind {d}\n", .{null_ind});

    const obj_type = std.meta.stringToEnum(ObjectType, decompressed_object[0..first_space_ind]) orelse return error.InvalidObjectType;
    const size = try std.fmt.parseInt(usize, decompressed_object[(first_space_ind + 1)..null_ind], 10);

    const content = decompressed_object[null_ind + 1 .. null_ind + 1 + size];
    try testing.expectEqual(size, content.len);
    return Object{
        .content = content,
        .size = size,
        .type = obj_type,
    };
}

// test "ensure empty " {
//     _ = try ObjectParser.init("testGit/emptyGit/.git", testing.allocator);
// }
test "ensure single commit " {
    _ = try ObjectParser.init("testGit/singleCommit/.git", testing.allocator);
}
