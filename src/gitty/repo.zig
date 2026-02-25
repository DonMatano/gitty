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
    arena: *std.heap.ArenaAllocator,
    git_path: []const u8,
    blobs: StringHashMap(Blob),

    pub fn init(git_path: []const u8, alloc: Alloc) !Repo {
        var arena = std.heap.ArenaAllocator.init(alloc);

        return .{
            .arena = &arena,
            .git_path = git_path,
            .blobs = StringHashMap(Blob).init(arena.allocator()),
        };
    }

    pub fn deinit(self: *Repo) void {
        self.blobs.deinit();
        self.arena.deinit();
    }

    pub fn parseRepoBlobs(self: *Repo) !void {
        const alloc = self.arena.allocator();
        const obj_path = try std.fmt.allocPrint(alloc, "{s}/objects", .{self.git_path});
        var dir = try std.fs.cwd().openDir(obj_path, .{ .iterate = true });
        var walker = try dir.walk(alloc);
        // defer walker.deinit();
        while (try walker.next()) |entry| {
            repo_log.debug("{s}: {s}", .{ entry.basename, @tagName(entry.kind) });
        }
    }

    // pub fn getRepoBlobs(self: *Repo) !StringHashMap(Blob) {}
};
test "ensure single commit " {
    var repo = try Repo.init("testGit/singleCommit/git", testing.allocator);
    try repo.parseRepoBlobs();
    repo.deinit();
}
