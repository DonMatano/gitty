const std = @import("std");
const testing = std.testing;
const Alloc = std.mem.Allocator;

const StringHashMap = std.StringHashMap;
const Blob = struct {
    size: usize,
    content: []const u8,
};

const repo_log = std.log.scoped(.Repo_Log);

pub const Repo = struct {
    git_path: []const u8,
    blobs: StringHashMap(Blob),

    pub fn init(git_path: []const u8, alloc: Alloc) !Repo {
        return .{
            .git_path = git_path,
            .blobs = StringHashMap(Blob).init(alloc),
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
            std.debug.print("{s}: {s}\n", .{ entry.basename, @tagName(entry.kind) });
        }
    }

    // pub fn getRepoBlobs(self: *Repo) !StringHashMap(Blob) {}
};
pub const std_options = struct {
    pub const log_level: std.log.Level = .debug;
};

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
    const argv = [_][]const u8{ "git", "init", temp_path };
    var child = std.process.Child.init(&argv, testing_alloc);
    try testRunProcess(&child);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const full_path = try std.fmt.allocPrint(alloc, "{s}/.git", .{temp_path});
    var repo = try Repo.init(full_path, alloc);
    try repo.parseRepoBlobs(alloc);
    repo.deinit();
}
test "repo with unadded test file" {
    const testing_alloc = testing.allocator;
    var temp_dir = testing.tmpDir(.{ .iterate = true, .access_sub_paths = true });
    defer temp_dir.cleanup();
    const temp_path = try temp_dir.dir.realpathAlloc(testing_alloc, ".");
    defer testing_alloc.free(temp_path);
    // const argv = [_][]const u8{ "git", "-C", temp_path, "init" };
    const argv = [_][]const u8{ "git", "init", temp_path };
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
    try repo.parseRepoBlobs(alloc);
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
    const argv = [_][]const u8{ "git", "init", temp_path };
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
    try repo.parseRepoBlobs(alloc);
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
    const argv = [_][]const u8{ "git", "init", temp_path };
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
    try repo.parseRepoBlobs(alloc);
    repo.deinit();
}
