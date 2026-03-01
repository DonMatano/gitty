const std = @import("std");
const testing = std.testing;
const Alloc = std.mem.Allocator;

const StringHashMap = std.StringHashMap;
const repo_log = std.log.scoped(.Repo_Log);
const Blob = struct {
    size: usize,
    content: std.ArrayList(u8),
    pub fn init(alloc: Alloc, size: usize) !Blob {
        .{
            .size = size,
            .content = try std.ArrayList(u8).initCapacity(alloc, size),
        };
    }
    pub fn setContent(self: *Blob, alloc: Alloc, content: []const u8) !void {
        self.content.clearRetainingCapacity();
        try self.content.appendSlice(alloc, content);
    }
    pub fn getContent(self: *Blob) []u8 {
        return self.content.items;
    }
    pub fn deinit(self: *Blob, alloc: Alloc) void {
        self.content.deinit(alloc);
    }
};
const Commit = struct {
    size: usize,
    content: std.ArrayList(u8),
    pub fn init(alloc: Alloc, size: usize) !Commit {
        .{
            .size = size,
            .content = try std.ArrayList(u8).initCapacity(alloc, size),
        };
    }
    pub fn setContent(self: *Commit, alloc: Alloc, content: []const u8) !void {
        self.content.clearRetainingCapacity();
        try self.content.appendSlice(alloc, content);
    }
    pub fn getContent(self: *Commit) []u8 {
        return self.content.items;
    }
    pub fn deinit(self: *Commit, alloc: Alloc) void {
        self.content.deinit(alloc);
    }
};
const Tag = struct {
    size: usize,
    content: std.ArrayList(u8),
    pub fn init(alloc: Alloc, size: usize) !Tag {
        .{
            .size = size,
            .content = try std.ArrayList(u8).initCapacity(alloc, size),
        };
    }
    pub fn setContent(self: *Tag, alloc: Alloc, content: []const u8) !void {
        self.content.clearRetainingCapacity();
        try self.content.appendSlice(alloc, content);
    }
    pub fn getContent(self: *Tag) []u8 {
        return self.content.items;
    }
    pub fn deinit(self: *Tag, alloc: Alloc) void {
        self.content.deinit(alloc);
    }
};
const FileType = enum {
    folder,
    file,
    pub fn getFileTypeFromMode(mode: []const u8) !FileType {
        const mode_in_int = try std.fmt.parseInt(isize, mode, 10);
        return switch (mode_in_int) {
            100644 => FileType.file,
            40000 => FileType.folder,
            else => {
                repo_log.err("Missing tree file type: {s}", .{mode});
                return error.MissingTreeFileType;
            },
        };
    }
};

const TreeContent = struct {
    file_name: std.ArrayList(u8),
    file_mode: FileType,
    binary_sha: std.ArrayList(u8),
    pub fn init(alloc: Alloc, file_mode: FileType, file_name_size: usize) !TreeContent {
        .{ .file_mode = file_mode, .file_name = try std.ArrayList(u8).initCapacity(alloc, file_name_size), .binary_sha = try std.ArrayList(u8).initCapacity(alloc, 40) };
    }
    pub fn setFileName(self: *TreeContent, alloc: Alloc, content: []const u8) !void {
        self.file_name.clearRetainingCapacity();
        try self.file_name.appendSlice(alloc, content);
    }
    pub fn getFileName(self: *TreeContent) []u8 {
        return self.file_name.items;
    }
    pub fn setBinarySha(self: *TreeContent, alloc: Alloc, content: []const u8) !void {
        self.binary_sha.clearRetainingCapacity();
        try self.binary_sha.appendSlice(alloc, content);
    }
    pub fn getBinarySha(self: *TreeContent) []u8 {
        return self.binary_sha.items;
    }
    pub fn deinit(self: *TreeContent, alloc: Alloc) void {
        self.file_name.deinit(alloc);
        self.binary_sha.deinit(alloc);
    }
    pub fn format(self: TreeContent, w: *std.Io.Writer) !void {
        try w.print("\n{{\n file_name: {s}\n file_mode:{s}\n binary_sha:{s}\n}}\n", .{ self.file_name.items, @tagName(self.file_mode), self.binary_sha.items });
    }
};

const Tree = struct {
    size: usize,
    contents: []TreeContent,
    pub fn format(self: Tree, w: *std.Io.Writer) !void {
        for (self.contents) |value| {
            try w.print("{f}", .{value});
        }
    }
};
const ObjectType = enum {
    blob,
    commit,
    tag,
    tree,
};
const Object = union(ObjectType) {
    blob: Blob,
    commit: Commit,
    tag: Tag,
    tree: Tree,
};

pub const Repo = struct {
    git_path: []const u8,
    blobs: StringHashMap(Blob),
    trees: StringHashMap(Tree),
    objectTypeMap: StringHashMap(ObjectType),

    pub fn init(git_path: []const u8, alloc: Alloc) !Repo {
        return .{
            .git_path = git_path,
            .blobs = StringHashMap(Blob).init(alloc),
            .trees = StringHashMap(Tree).init(alloc),
            .objectTypeMap = StringHashMap(ObjectType).init(alloc),
        };
    }

    pub fn deinit(self: *Repo) void {
        self.blobs.deinit();
    }

    pub fn parseRepoBlobs(self: *Repo, alloc: Alloc) !void {
        const obj_path = try std.fmt.allocPrint(alloc, "{s}/objects", .{self.git_path});
        defer alloc.free(obj_path);
        var dir = try std.fs.cwd().openDir(obj_path, .{ .iterate = true });
        var walker = try dir.walk(alloc);
        defer walker.deinit();
        while (try walker.next()) |entry| {
            repo_log.debug("{s}: {s}\n", .{ entry.basename, @tagName(entry.kind) });
        }
    }
    pub fn parseRepoTrees(self: *Repo, alloc: Alloc) !void {
        const obj_path = try std.fmt.allocPrint(alloc, "{s}/objects", .{self.git_path});
        defer alloc.free(obj_path);
        var dir = try std.fs.cwd().openDir(obj_path, .{ .iterate = true });
        var walker = try dir.walk(alloc);
        defer walker.deinit();
        while (try walker.next()) |entry| {
            switch (entry.kind) {
                .file => {
                    repo_log.debug("{s}: {s}\n", .{ entry.basename, @tagName(entry.kind) });
                    const parent_dir_path = try entry.dir.realpathAlloc(alloc, ".");
                    const dir_name = std.fs.path.basename(parent_dir_path);
                    defer alloc.free(dir_name);
                    var f = try entry.dir.openFile(entry.basename, .{});
                    defer f.close();
                    const stat = try f.stat();
                    const size = stat.size;
                    const content = try alloc.alloc(u8, size);
                    defer alloc.free(content);
                    _ = try entry.dir.readFile(entry.basename, content);
                    repo_log.debug("\tcontent {s}\n", .{content});
                    const decompressed_content = try decompressZipContent(content, alloc);
                    defer alloc.free(decompressed_content);
                    repo_log.debug("decomp content out: {s}\n", .{decompressed_content});
                    var parseReader: std.Io.Reader = .fixed(decompressed_content);
                    const object = try parseDecompressedObject(&parseReader, alloc);
                    const full_hash = try std.fmt.allocPrint(alloc, "{s}{s}", .{ dir_name, entry.basename });
                    repo_log.debug("hash - {s}\n", .{full_hash});
                    defer alloc.free(full_hash);
                    try self.storeObject(object, full_hash);
                },
                else => {
                    repo_log.debug("in folder \t {s}\n", .{entry.basename});
                },
            }
        }
        repo_log.info("stored {f}", .{self.*});
        std.debug.print("stored {f}", .{self.*});
    }

    fn storeObject(self: *Repo, object: Object, hash: []const u8) !void {
        switch (object) {
            .blob => {
                try self.blobs.putNoClobber(hash, object.blob);
            },
            .commit => {
                repo_log.info("Adding commit not yet handle", .{});
            },
            .tag => {
                repo_log.info("Adding tag not yet handle", .{});
            },
            .tree => {
                try self.trees.putNoClobber(hash, object.tree);
            },
        }
    }
    pub fn format(self: Repo, w: *std.Io.Writer) !void {
        var trees_it = self.trees.iterator();
        try w.print("\nTrees contents\n", .{});
        while (trees_it.next()) |tree| {
            for (tree.value_ptr.contents) |content| {
                try w.print("{f}\n", .{content});
            }
        }
    }

    // pub fn getRepoBlobs(self: *Repo) !StringHashMap(Blob) {}
};
fn parseDecompressedObject(reader: *std.Io.Reader, alloc: Alloc) !Object {
    const obj_type_string = reader.takeDelimiter(' ') catch |err| {
        repo_log.err("Failed to get type: {}", .{err});
        return error.InvalidObjectType;
    } orelse return error.MissingObjectType;
    var object: Object = undefined;

    const obj_type = std.meta.stringToEnum(ObjectType, obj_type_string) orelse return error.InvalidObjectType;
    switch (obj_type) {
        .blob => {
            const size_string = reader.takeDelimiter(0) catch |err| {
                repo_log.err("Failed to get size: {}", .{err});
                return error.InvalidObjectSize;
            } orelse return error.MissingObjectSize;
            const size = try std.fmt.parseInt(usize, size_string, 10);

            const content = reader.take(size) catch |err| {
                repo_log.err("Failed to get content: {}", .{err});
                return error.InvalidObjectContent;
            };
            try testing.expectEqual(size, content.len);
            var arr = try std.ArrayList(u8).initCapacity(alloc, content.len);
            arr.appendSlice(alloc, content);
            const blob = try Blob.init(alloc, size);
            blob.setContent(alloc, content);

            object = .{
                .blob = blob,
            };
        },
        .tree => {
            const tree = try parseTreeObject(reader, alloc);
            object = .{ .tree = tree };
        },
        .tag => {
            const size_string = reader.takeDelimiter(0) catch |err| {
                repo_log.err("Failed to get size: {}", .{err});
                return error.InvalidObjectSize;
            } orelse return error.MissingObjectSize;
            const size = try std.fmt.parseInt(usize, size_string, 10);

            const content = reader.take(size) catch |err| {
                repo_log.err("Failed to get content: {}", .{err});
                return error.InvalidObjectContent;
            };
            try testing.expectEqual(size, content.len);
            object = .{
                .tag = Tag{ .size = size, .content = content },
            };
        },
        .commit => {
            const size_string = reader.takeDelimiter(0) catch |err| {
                repo_log.err("Failed to get size: {}", .{err});
                return error.InvalidObjectSize;
            } orelse return error.MissingObjectSize;
            const size = try std.fmt.parseInt(usize, size_string, 10);

            const content = reader.take(size) catch |err| {
                repo_log.err("Failed to get content: {}", .{err});
                return error.InvalidObjectContent;
            };
            try testing.expectEqual(size, content.len);
            object = .{
                .commit = Commit{ .size = size, .content = content },
            };
        },
    }
    return object;
}
fn parseTreeObject(reader: *std.Io.Reader, alloc: Alloc) !Tree {
    const size_string = reader.takeDelimiter(0) catch |err| {
        repo_log.err("Failed to get size: {}", .{err});
        return error.InvalidObjectSize;
    } orelse return error.MissingObjectSize;
    const size = try std.fmt.parseInt(usize, size_string, 10);
    var tree_list = try std.ArrayList(TreeContent).initCapacity(alloc, 100);
    defer tree_list.deinit(alloc);

    while (reader.bufferedLen() > 0) {
        const mode = reader.takeDelimiter(' ') catch |err| {
            repo_log.err("Failed to get mode: {}", .{err});
            return error.InvalidObjectMode;
        } orelse return error.MissingObjectMode;
        std.debug.print(" tree mode: {s} \n", .{mode});
        const file_type = try FileType.getFileTypeFromMode(mode);
        repo_log.info("file type gotten {s}\n", .{@tagName(file_type)});
        const file_name = reader.takeDelimiter(0) catch |err| {
            repo_log.err("Failed to get file name: {}", .{err});
            return error.InvalidObjectFileName;
        } orelse return error.MissingObjectFileName;
        std.debug.print(" tree file name: {s} \n", .{file_name});
        var encrypted_binary: [20]u8 = undefined;
        reader.readSliceAll(&encrypted_binary) catch |err| {
            repo_log.err("Failed to get encrypted binary: {}", .{err});
            return error.InvalidObjectEncrypted;
        };
        try std.testing.expect(encrypted_binary.len == 20);
        repo_log.debug(" tree binary : {s} \n", .{encrypted_binary});

        var decrypted_binary: [40]u8 = undefined;
        decrypted_binary = std.fmt.bytesToHex(encrypted_binary, .lower);
        repo_log.debug("decrypted bin {s}\n", .{decrypted_binary});
        var tree: TreeContent = TreeContent.init(alloc, file_type, file_name.len);
        try tree.setFileName(alloc, file_name);
        tree.setBinarySha(alloc, decrypted_binary);
        try tree_list.append(alloc, tree);
    }
    return .{ .size = size, .contents = try tree_list.toOwnedSlice(alloc) };
}
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

fn testRunProcess(child: *std.process.Child) !void {
    try child.spawn();
    const exit_code = child.wait();
    try std.testing.expectEqual(exit_code, std.process.Child.Term{ .Exited = 0 });
}
test "test empty repo " {
    const testing_alloc = testing.allocator;
    var temp_dir = testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer temp_dir.cleanup();
    const temp_path = try temp_dir.dir.realpathAlloc(testing_alloc, ".");
    defer testing_alloc.free(temp_path);
    const argv = [_][]const u8{ "git", "init", "-q", temp_path };
    var child = std.process.Child.init(&argv, testing_alloc);
    try testRunProcess(&child);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const full_path = try std.fmt.allocPrint(alloc, "{s}/.git", .{temp_path});
    var repo = try Repo.init(full_path, alloc);
    try repo.parseRepoTrees(alloc);
    repo.deinit();
}
test "repo with unadded test file" {
    const testing_alloc = testing.allocator;
    var temp_dir = testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer temp_dir.cleanup();
    const temp_path = try temp_dir.dir.realpathAlloc(testing_alloc, ".");
    defer testing_alloc.free(temp_path);
    // const argv = [_][]const u8{ "git", "-C", temp_path, "init" };
    const argv = [_][]const u8{ "git", "init", "-q", temp_path };
    var child = std.process.Child.init(&argv, testing_alloc);
    try testRunProcess(&child);
    // Create File
    var file = try temp_dir.dir.createFile("test.text", .{});
    // Write to File
    _ = try file.write("Testing.\n");
    file.close();

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const full_path = try std.fmt.allocPrint(alloc, "{s}/.git", .{temp_path});
    var repo = try Repo.init(full_path, alloc);
    try repo.parseRepoTrees(alloc);
    repo.deinit();
}

test "repo with added test file" {
    const testing_alloc = testing.allocator;
    var temp_dir = testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer temp_dir.cleanup();
    const temp_path = try temp_dir.dir.realpathAlloc(testing_alloc, ".");
    defer testing_alloc.free(temp_path);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const full_path = try std.fmt.allocPrint(alloc, "{s}/.git", .{temp_path});
    const argv = [_][]const u8{ "git", "init", "-q", temp_path };
    var child = std.process.Child.init(&argv, testing_alloc);

    try testRunProcess(&child);
    // Create File
    var file = try temp_dir.dir.createFile("test.text", .{});
    // Write to File
    _ = try file.write("Testing.\n");
    file.close();
    const second_argv = [_][]const u8{ "git", "-C", temp_path, "add", "." };
    child = std.process.Child.init(&second_argv, testing_alloc);

    try testRunProcess(&child);

    var repo = try Repo.init(full_path, alloc);
    try repo.parseRepoTrees(alloc);
    repo.deinit();
}

test "repo with commited test file" {
    const testing_alloc = testing.allocator;
    var temp_dir = testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer temp_dir.cleanup();
    const temp_path = try temp_dir.dir.realpathAlloc(testing_alloc, ".");
    defer testing_alloc.free(temp_path);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const full_path = try std.fmt.allocPrint(alloc, "{s}/.git", .{temp_path});
    const argv = [_][]const u8{ "git", "init", "-q", temp_path };
    var child = std.process.Child.init(&argv, testing_alloc);

    try testRunProcess(&child);
    // Create File
    var file = try temp_dir.dir.createFile("test.text", .{});
    // Write to File
    _ = try file.write("Testing.\n");
    file.close();
    const second_argv = [_][]const u8{ "git", "-C", temp_path, "add", "." };
    child = std.process.Child.init(&second_argv, testing_alloc);

    try testRunProcess(&child);

    const commit_argv = [_][]const u8{
        "git",
        "-C",
        temp_path,
        "commit",
        "-m",
        "\"Test commit\"",
    };
    child = std.process.Child.init(&commit_argv, testing_alloc);

    try testRunProcess(&child);

    var repo = try Repo.init(full_path, alloc);
    try repo.parseRepoTrees(alloc);
    repo.deinit();
}
test "repo with unadded 2 test files" {
    const testing_alloc = testing.allocator;
    var temp_dir = testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer temp_dir.cleanup();
    const temp_path = try temp_dir.dir.realpathAlloc(testing_alloc, ".");
    defer testing_alloc.free(temp_path);
    // const argv = [_][]const u8{ "git", "-C", temp_path, "init" };
    const argv = [_][]const u8{ "git", "init", "-q", temp_path };
    var child = std.process.Child.init(&argv, testing_alloc);
    try testRunProcess(&child);
    for (1..3) |i| {
        // Create File
        repo_log.debug("index {d}", .{i});
        const file_name = try std.fmt.allocPrint(testing_alloc, "test-{d}", .{i});
        const file_content = try std.fmt.allocPrint(testing_alloc, "testing-{d}\n", .{i});
        defer {
            testing_alloc.free(file_name);
            testing_alloc.free(file_content);
        }
        var file = try temp_dir.dir.createFile(file_name, .{});
        // Write to File
        _ = try file.write(file_content);
        file.close();
    }

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const full_path = try std.fmt.allocPrint(alloc, "{s}/.git", .{temp_path});
    var repo = try Repo.init(full_path, alloc);
    try repo.parseRepoTrees(alloc);
    repo.deinit();
}
test "repo with added 2 test files" {
    const testing_alloc = testing.allocator;
    var temp_dir = testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer temp_dir.cleanup();
    const temp_path = try temp_dir.dir.realpathAlloc(testing_alloc, ".");
    defer testing_alloc.free(temp_path);
    // const argv = [_][]const u8{ "git", "-C", temp_path, "init" };
    const argv = [_][]const u8{ "git", "init", "-q", temp_path };
    var child = std.process.Child.init(&argv, testing_alloc);
    try testRunProcess(&child);
    for (1..3) |i| {
        // Create File
        repo_log.debug("index {d}", .{i});
        const file_name = try std.fmt.allocPrint(testing_alloc, "test-{d}", .{i});
        const file_content = try std.fmt.allocPrint(testing_alloc, "testing-{d}\n", .{i});
        defer {
            testing_alloc.free(file_name);
            testing_alloc.free(file_content);
        }
        var file = try temp_dir.dir.createFile(file_name, .{});
        // Write to File
        _ = try file.write(file_content);
        file.close();
    }
    const second_argv = [_][]const u8{ "git", "-C", temp_path, "add", "." };
    child = std.process.Child.init(&second_argv, testing_alloc);

    try testRunProcess(&child);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const full_path = try std.fmt.allocPrint(alloc, "{s}/.git", .{temp_path});
    var repo = try Repo.init(full_path, alloc);
    try repo.parseRepoTrees(alloc);
    repo.deinit();
}
test "repo with commited 2 test files" {
    const testing_alloc = testing.allocator;
    var temp_dir = testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer temp_dir.cleanup();
    const temp_path = try temp_dir.dir.realpathAlloc(testing_alloc, ".");
    defer testing_alloc.free(temp_path);
    // const argv = [_][]const u8{ "git", "-C", temp_path, "init" };
    const argv = [_][]const u8{ "git", "init", "-q", temp_path };
    var child = std.process.Child.init(&argv, testing_alloc);
    try testRunProcess(&child);
    for (1..3) |i| {
        // Create File
        repo_log.debug("index {d}", .{i});
        const file_name = try std.fmt.allocPrint(testing_alloc, "test-{d}", .{i});
        const file_content = try std.fmt.allocPrint(testing_alloc, "testing-{d}\n", .{i});
        defer {
            testing_alloc.free(file_name);
            testing_alloc.free(file_content);
        }
        var file = try temp_dir.dir.createFile(file_name, .{});
        // Write to File
        _ = try file.write(file_content);
        file.close();
    }
    const second_argv = [_][]const u8{ "git", "-C", temp_path, "add", "." };
    child = std.process.Child.init(&second_argv, testing_alloc);

    try testRunProcess(&child);

    const commit_argv = [_][]const u8{
        "git",
        "-C",
        temp_path,
        "commit",
        "-m",
        "\"Test 2 files commit\"",
    };
    child = std.process.Child.init(&commit_argv, testing_alloc);

    try testRunProcess(&child);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const full_path = try std.fmt.allocPrint(alloc, "{s}/.git", .{temp_path});
    var repo = try Repo.init(full_path, alloc);
    try repo.parseRepoTrees(alloc);
    repo.deinit();
}
test "repo with commited individually 2 test files" {
    const testing_alloc = testing.allocator;
    var temp_dir = testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer temp_dir.cleanup();
    const temp_path = try temp_dir.dir.realpathAlloc(testing_alloc, ".");
    defer testing_alloc.free(temp_path);
    // const argv = [_][]const u8{ "git", "-C", temp_path, "init" };
    const argv = [_][]const u8{ "git", "init", "-q", temp_path };
    var child = std.process.Child.init(&argv, testing_alloc);
    try testRunProcess(&child);
    for (1..3) |i| {
        // Create File
        repo_log.debug("index {d}", .{i});
        const file_name = try std.fmt.allocPrint(testing_alloc, "test-{d}", .{i});
        const file_content = try std.fmt.allocPrint(testing_alloc, "testing-{d}\n", .{i});
        defer {
            testing_alloc.free(file_name);
            testing_alloc.free(file_content);
        }
        var file = try temp_dir.dir.createFile(file_name, .{});
        // Write to File
        _ = try file.write(file_content);
        file.close();
    }
    const second_argv = [_][]const u8{ "git", "-C", temp_path, "add", "test-1" };
    child = std.process.Child.init(&second_argv, testing_alloc);

    try testRunProcess(&child);

    var commit_argv = [_][]const u8{
        "git",
        "-C",
        temp_path,
        "commit",
        "-m",
        "\"Test first file commit\"",
    };
    child = std.process.Child.init(&commit_argv, testing_alloc);

    try testRunProcess(&child);

    const third_argv = [_][]const u8{ "git", "-C", temp_path, "add", "test-2" };
    child = std.process.Child.init(&third_argv, testing_alloc);

    try testRunProcess(&child);

    commit_argv = [_][]const u8{
        "git",
        "-C",
        temp_path,
        "commit",
        "-m",
        "\"Test second file commit\"",
    };
    child = std.process.Child.init(&commit_argv, testing_alloc);
    try testRunProcess(&child);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const full_path = try std.fmt.allocPrint(alloc, "{s}/.git", .{temp_path});
    var repo = try Repo.init(full_path, alloc);
    try repo.parseRepoTrees(alloc);
    repo.deinit();
}
test "repo with commited 2 test files and subfolder" {
    testing.log_level = .info;
    const testing_alloc = testing.allocator;
    var temp_dir = testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer temp_dir.cleanup();
    const temp_path = try temp_dir.dir.realpathAlloc(testing_alloc, ".");
    defer testing_alloc.free(temp_path);
    // const argv = [_][]const u8{ "git", "-C", temp_path, "init" };
    const argv = [_][]const u8{ "git", "init", "-q", temp_path };
    var child = std.process.Child.init(&argv, testing_alloc);
    try testRunProcess(&child);
    for (1..3) |i| {
        // Create File
        repo_log.debug("index {d}", .{i});
        const file_name = try std.fmt.allocPrint(testing_alloc, "test-{d}", .{i});
        const file_content = try std.fmt.allocPrint(testing_alloc, "testing-{d}\n", .{i});
        defer {
            testing_alloc.free(file_name);
            testing_alloc.free(file_content);
        }
        var file = try temp_dir.dir.createFile(file_name, .{});
        // Write to File
        _ = try file.write(file_content);
        file.close();
    }
    const test_folder_name = "test folder";
    try temp_dir.dir.makeDir(test_folder_name);
    var sub_dir = try temp_dir.dir.openDir(test_folder_name, .{});
    for (1..3) |i| {
        // Create File
        repo_log.debug("index {d}", .{i});
        const file_name = try std.fmt.allocPrint(testing_alloc, "sub_test-{d}", .{i});
        const file_content = try std.fmt.allocPrint(testing_alloc, "sub_testing-{d}\n", .{i});
        defer {
            testing_alloc.free(file_name);
            testing_alloc.free(file_content);
        }
        var file = try sub_dir.createFile(file_name, .{});
        // Write to File
        _ = try file.write(file_content);
        file.close();
    }

    sub_dir.close();
    const second_argv = [_][]const u8{ "git", "-C", temp_path, "add", "." };
    child = std.process.Child.init(&second_argv, testing_alloc);

    try testRunProcess(&child);

    const commit_argv = [_][]const u8{
        "git",
        "-C",
        temp_path,
        "commit",
        "-m",
        "\"Test sub files files commit\"",
    };
    child = std.process.Child.init(&commit_argv, testing_alloc);

    try testRunProcess(&child);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const full_path = try std.fmt.allocPrint(alloc, "{s}/.git", .{temp_path});
    var repo = try Repo.init(full_path, alloc);
    try repo.parseRepoTrees(alloc);
    repo.deinit();
}
