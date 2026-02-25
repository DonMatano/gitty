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
    tree: []Tree,
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

const FileType = enum { folder, file };

const TreeContent = struct {
    file_name: []const u8,
    file_mode: FileType,
    binary_sha: []const u8,
};

const Tree = struct {
    size: usize,
    contents: []TreeContent,
};

// const Object = struct {
//     type: ObjectType,
//     size: usize,
//     content: []const u8,
// };
const ObjectParser = struct {
    arena: *std.heap.ArenaAllocator,
    obj_dir: *std.fs.Dir,

    pub fn init(git_path: []const u8, alloc: Alloc) !ObjectParser {
        const obj_path = try std.fmt.allocPrint(alloc, "{s}/objects", .{git_path});
        defer alloc.free(obj_path);
        var obj_dir = try std.fs.cwd().openDir(obj_path, .{ .iterate = true });
        var arena = std.heap.ArenaAllocator.init(alloc);

        return .{
            .arena = &arena,
            .obj_dir = &obj_dir,
        };
    }

    pub fn deinit(self: ObjectParser) void {
        self.obj_dir.close();
        self.arena.deinit();
    }

    pub fn parseObjects(self: ObjectParser) !void {
        try iterateDir(self.obj_dir.*, self.arena.allocator(), handleFile);
    }

    // fn iterateDir(self: ObjectParser) !void {
    //     var it = self.obj_dir.iterate();
    //     while (try it.next()) |entry| {
    //         std.debug.print("{s} - {s} \n", .{ entry.name, @tagName(entry.kind) });
    //         switch (entry.kind) {
    //             .directory => {
    //                 var dir = try self.obj_dir.openDir(entry.name, .{ .iterate = true });
    //                 defer dir.close();
    //                 try iterateDir(&dir, self.alloc);
    //             },
    //             else => {
    //                 var f = try self.obj_dir.openFile(entry.name, .{});
    //                 defer f.close();
    //                 const stat = try f.stat();
    //                 const size = stat.size;
    //                 const content = try self.alloc.alloc(u8, size);
    //                 defer self.alloc.free(content);
    //                 _ = try self.obj_dir.readFile(entry.name, content);
    //                 std.debug.print("content {s}\n", .{content});
    //                 const decompressed_content = try decompressZipContent(content, self.alloc);
    //                 defer self.alloc.free(decompressed_content);
    //                 std.debug.print("decomp content out: {s}\n", .{decompressed_content});
    //                 var parseReader: std.Io.Reader = .fixed(decompressed_content);
    //                 const obj = try parseDecompressedObject(&parseReader);
    //                 std.debug.print("decomp obj: {}\n", .{obj});
    //                 switch (obj) {
    //                     .blob => std.debug.print("\n\n\ndecomp obj blob content: {}\n", .{obj.blob}),
    //                     .commit => std.debug.print("\n\n\ndecomp obj commit content: {}\n", .{obj.commit}),
    //                     .tag => std.debug.print("\n\n\ndecomp obj tag content: {}\n", .{obj.tag}),
    //                     .tree => std.debug.print("\n\n\ndecomp obj tree content: {}\n", .{obj.tree}),
    //                 }
    //             },
    //         }
    //     }
    // }
    fn parseDecompressedObject(self: ObjectParser, reader: *std.Io.Reader) !Object {
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
                const tree = try self.parseTreeObject(reader);

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

    // TODO: Move to obect
    fn parseTreeObject(self: ObjectParser, reader: *std.Io.Reader) ![]Tree {
        const size_string = reader.takeDelimiter(0) catch |err| {
            log.err("Failed to get size: {}", .{err});
            return error.InvalidObjectSize;
        } orelse return error.MissingObjectSize;
        const size = try std.fmt.parseInt(usize, size_string, 10);
        var tree_list = try std.ArrayList(Tree).initCapacity(self.alloc, 100);
        defer tree_list.deinit(self.alloc);

        while (reader.bufferedLen() > 0) {
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

            var decrypted_binary: [40]u8 = undefined;
            decrypted_binary = std.fmt.bytesToHex(encrypted_binary, .lower);
            std.debug.print("decrypted bin {s}\n", .{decrypted_binary});
            tree_list.append(self.alloc, Tree{ .size = size, .file_name = file_name, .file_mode = mode, .binary_sha = "" });
        }
        return try tree_list.toOwnedSlice(self.alloc);
    }
    fn handleFile(file: *std.fs.File, alloc: Alloc) !void {
        const stat = try file.stat();
        const size = stat.size;
        const content = try alloc.alloc(u8, size);
        const reader = &file.readerStreaming(content).interface;
        defer alloc.free(content);
        const read = try reader.readAlloc(alloc, content.len);
        defer alloc.free(read);
        // _ = try self.obj_dir.readFile(entry.name, content);
        std.debug.print("content {s}\n", .{read});
        const decompressed_content = try decompressZipContent(read, alloc);
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
fn iterateDir(dir: *std.fs.Dir, alloc: Alloc, onFileFound: fn (file: *std.fs.File, alloc: Alloc) anyerror!void) !void {
    var it = dir.iterate();
    while (try it.next()) |entry| {
        std.debug.print("{s} - {s} \n", .{ entry.name, @tagName(entry.kind) });
        switch (entry.kind) {
            .directory => {
                var sub_dir = try dir.openDir(entry.name, .{ .iterate = true });
                defer sub_dir.close();
                try iterateDir(&dir, alloc, onFileFound);
            },
            else => {
                var f = try dir.openFile(entry.name, .{});
                try onFileFound(&f, alloc);
                defer f.close();
            },
        }
    }
}

// fn parseCommitObject(reader: *std.Io.Reader) !void {}

// test "ensure empty " {
//     _ = try ObjectParser.init("testGit/emptyGit/.git", testing.allocator);
// }
test "ensure single commit " {
    var obj_parser = try ObjectParser.init("testGit/singleCommit/git", testing.allocator);
    try obj_parser.parseObjects();

    ObjectParser.deinit();
}
