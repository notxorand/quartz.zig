# quartz.zig

A benchmarking utility library written in Zig with simplicity in mind.

## Add to your project

```sh
zig fetch --save git+https://github.com/notxorand/quartz.zig
```

```zig
// build.zig
exe.root_module.addImport(
    "quartz",
    b.dependency("quartz", .{ .target = target, .optimize = optimize }).module("quartz"),
);
```

## Usage

```zig
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
```

## Runner options

```zig
var runner = Quartz.init(allocator, .{
    .baseline = .{ .log = ".quartz/history.json" },
});
```

| option | type | default | description |
|---|---|---|---|
| `baseline` | `BaselineStrategy` | `.none` | comparison strategy |

## Benchmark options

```zig
try runner.add("fib", fibonacci, &.{.{32}}, .{
    .sample_size = 1000,
    .threads = 1,
});
```

| option | type | default | description |
|---|---|---|---|
| `sample_size` | `usize` | `1` | number of iterations per input |
| `threads` | `usize` | `1` | number of threads |

## Baseline strategies

```zig
.baseline = .none                            // no comparison
.baseline = .{ .pinned = "baseline.json" }  // compare against saved file
.baseline = .{ .log = "history.json" }      // append runs, compare against last
```
