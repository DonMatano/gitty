//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const gitty = @import("gitty/gitty.zig");

pub fn run(git_path: []const u8, alloc: std.mem.Allocator) !gitty.RepoLib.Repo {
    return try gitty.RepoLib.Repo.init(git_path, alloc);
}
