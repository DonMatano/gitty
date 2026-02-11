const std = @import("std");
const testing = std.testing;
const Alloc = std.mem.Allocator;
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
                    _ = try decompressZipContent(content, alloc);

                    // f.rea
                    //
                    // var f_reader = f.reader(&buf);
                    // var reader = &f_reader.interface;
                    // while (reader.readSliceAll(&buf)) {
                    //     try writer.print("{s}", .{buf});
                    // } else |err| {
                    //     if (err != error.EndOfStream) {
                    //         return err;
                    //     }
                    // }
                    // try writer.flush();
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
    std.debug.print("decomp content: {s}\n", .{decompressed_content});
    return decompressed_content;
    // var in: std.Io.Reader = .fixed(compressed);
    // var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    // defer aw.deinit();
    //
    // var decompress: Decompress = .init(&in, container, &.{});
    // const decompressed_len = try decompress.reader.streamRemaining(&aw.writer);
}

// test "ensure empty " {
//     _ = try ObjectParser.init("testGit/emptyGit/.git", testing.allocator);
// }
test "ensure single commit " {
    _ = try ObjectParser.init("testGit/singleCommit/.git", testing.allocator);
}
