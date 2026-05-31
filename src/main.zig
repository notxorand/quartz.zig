const std = @import("std");
const Quartz = @import("root.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var runner = Quartz.init(allocator, io, .{});
    defer runner.deinit();

    try runner.add("fib", fibonacci, &.{ .{1}, .{2}, .{4}, .{8}, .{16}, .{32} }, .{ .sample_size = 100 });
    try runner.run();
}

fn fibonacci(n: u64) u64 {
    if (n <= 1) return 1;
    return fibonacci(n - 1) + fibonacci(n - 2);
}
