const std = @import("std");
const gitty = @import("gitty");
const Alloc = std.mem.Allocator;

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    const alloc = debug_allocator.allocator();

    // var out_buffer: [1024]u8 = undefined;
    // var writer = std.fs.File.stdout().writer(&out_buffer);
    // var out = &writer.interface;
    var git_path: ?[]const u8 = null;

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    if (args.skip()) {
        git_path = args.next();
    }

    if (git_path == null) {
        // If git path is still null check root .
        //
        std.log.info("No git path given. Trying to open root .git folder ...\n", .{});
        var cwd = std.fs.cwd();
        _ = cwd.openDir(".git", .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.log.err("Failed to root .git folder does not exist\n", .{});
                std.log.info("Ensure to run the program and pass over the .git folder path or run on a git initialized folder\n", .{});
                std.log.info("`gitty -- [.git path]`", .{});
                return error.MissingGitFolder;
            },
            else => {
                std.log.err("Got error: {}", .{err});
                return err;
            },
        };
        git_path = ".git";
    }

    std.log.info("Opening git in path: {s}\n", .{git_path.?});

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var repo = try gitty.run(git_path.?, arena_alloc);
    try repo.parseRepoTrees(arena_alloc);
    defer repo.deinit();
}
