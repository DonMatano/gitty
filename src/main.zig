const std = @import("std");
const gitty = @import("gitty");

pub fn main() !void {
    try gitty.bufferedPrint();
}
