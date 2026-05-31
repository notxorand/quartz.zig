//! A benchmarking utility library written in Zig with simplicity in mind.
const Quartz = @This();

const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Io = std.Io;

io: Io,
arena: std.heap.ArenaAllocator,
benchmarks: ArrayListUnmanaged(Benchmark),
opts: RunnerOpts,

pub const Benchmark = struct {
    name: []const u8,
    func: *const fn (*const anyopaque) anyerror!void,
    input: *const anyopaque,
    opts: BenchmarkOpts,
};

const BenchmarkOpts = struct {
    sample_size: usize = 1,
    threads: usize = 1,
};

pub const RunnerOpts = struct {
    baseline: BaselineStrategy = .none,

    const BaselineStrategy = union(enum) {
        none,
        /// path to baseline file
        pinned: []const u8,
        /// path to log file, compare against last entry
        log: []const u8,
    };
};

pub fn init(allocator: std.mem.Allocator, io: Io, opts: RunnerOpts) Quartz {
    const arena = std.heap.ArenaAllocator.init(allocator);
    return .{
        .io = io,
        .arena = arena,
        .benchmarks = .empty,
        .opts = opts,
    };
}

pub fn deinit(self: *Quartz) void {
    self.arena.deinit();
}

fn formatField(allocator: std.mem.Allocator, comptime field: anytype, label: []const u8) ![]const u8 {
    const FieldType = @TypeOf(field);
    const field_type_info = @typeInfo(FieldType);
    if (field_type_info == .array) {
        const arr_info = field_type_info.array;
        if (arr_info.child == u8) {
            return try std.fmt.allocPrint(allocator, "{s}{s}", .{ label, field[0..] });
        } else {
            return try std.fmt.allocPrint(allocator, "{s}{any}", .{ label, field });
        }
    } else if (field_type_info == .pointer) {
        const ptr_info = field_type_info.pointer;
        const child_info = @typeInfo(ptr_info.child);
        if (child_info == .array) {
            const child_arr = child_info.array;
            if (child_arr.child == u8) {
                return try std.fmt.allocPrint(allocator, "{s}{s}", .{ label, field.* });
            } else {
                return try std.fmt.allocPrint(allocator, "{s}{any}", .{ label, field });
            }
        } else if (ptr_info.child == u8) {
            return try std.fmt.allocPrint(allocator, "{s}{s}", .{ label, field });
        } else {
            return try std.fmt.allocPrint(allocator, "{s}{any}", .{ label, field });
        }
    } else if (field_type_info == .int) {
        return try std.fmt.allocPrint(allocator, "{s}{d}", .{ label, field });
    } else if (field_type_info == .comptime_int) {
        return try std.fmt.allocPrint(allocator, "{s}{d}", .{ label, @as(i64, field) });
    } else {
        return try std.fmt.allocPrint(allocator, "{s}{any}", .{ label, field });
    }
}

fn formatLabel(allocator: std.mem.Allocator, comptime name: []const u8, comptime input: anytype) ![]const u8 {
    var label: []const u8 = try std.fmt.allocPrint(allocator, "{s}[", .{name});
    inline for (input, 0..) |field, i| {
        if (i > 0) label = try std.fmt.allocPrint(allocator, "{s}, ", .{label});
        label = try formatField(allocator, field, label);
    }
    label = try std.fmt.allocPrint(allocator, "{s}]", .{label});
    return label;
}

pub fn add(self: *Quartz, comptime name: []const u8, comptime func: anytype, comptime inputs: anytype, opts: BenchmarkOpts) !void {
    const Args = std.meta.ArgsTuple(@TypeOf(func));
    const allocator = self.arena.allocator();

    const wrapper = struct {
        fn run(ptr: *const anyopaque) anyerror!void {
            const args = @as(*const Args, @ptrCast(@alignCast(ptr)));
            std.mem.doNotOptimizeAway(@call(.auto, func, args.*));
        }
    };

    inline for (inputs) |input| {
        const args_ptr = try allocator.create(Args);
        args_ptr.* = input;

        const label = try formatLabel(allocator, name, input);

        try self.benchmarks.append(allocator, .{
            .name = label,
            .func = wrapper.run,
            .input = @as(*const anyopaque, @ptrCast(args_ptr)),
            .opts = opts,
        });
    }
}

fn measureTimingOverhead(io: Io, sample_count: usize) f64 {
    var total: f64 = 0;
    for (0..sample_count) |_| {
        const start = std.Io.Clock.awake.now(io);
        std.mem.doNotOptimizeAway(start);
        const elapsed = start.untilNow(io, .awake).toNanoseconds();
        total += @floatFromInt(elapsed);
    }
    return total / @as(f64, @floatFromInt(sample_count));
}

pub fn run(self: *Quartz) !void {
    const timing_overhead = measureTimingOverhead(self.io, 100);

    for (self.benchmarks.items) |*benchmark| {
        var inner_iters: usize = 1;
        while (inner_iters < 10_000_000) {
            const start = std.Io.Clock.awake.now(self.io);
            for (0..inner_iters) |_| {
                std.mem.doNotOptimizeAway(try benchmark.func(benchmark.input));
            }
            const elapsed: f64 = @floatFromInt(start.untilNow(self.io, .awake).toNanoseconds());
            if (elapsed >= 1_000_000) break;
            inner_iters = @max(inner_iters * 2, inner_iters + 1);
        }

        var samples: ArrayListUnmanaged(f64) = .empty;
        defer samples.deinit(self.arena.allocator());

        for (0..benchmark.opts.sample_size) |_| {
            const start = std.Io.Clock.awake.now(self.io);
            for (0..inner_iters) |_| {
                std.mem.doNotOptimizeAway(try benchmark.func(benchmark.input));
            }
            const elapsed: f64 = @floatFromInt(start.untilNow(self.io, .awake).toNanoseconds());
            const per_iter = (elapsed - timing_overhead) / @as(f64, @floatFromInt(inner_iters));
            try samples.append(self.arena.allocator(), @max(per_iter, 0));
        }

        var total_ns: f64 = 0;
        var fastest: f64 = samples.items[0];
        var slowest: f64 = samples.items[0];
        for (samples.items) |sample| {
            total_ns += sample;
            if (sample < fastest) fastest = sample;
            if (sample > slowest) slowest = sample;
        }

        const avg_ns = total_ns / @as(f64, @floatFromInt(benchmark.opts.sample_size));

        var display_avg = avg_ns;
        var display_fastest = fastest;
        var display_slowest = slowest;
        var unit: []const u8 = "ns";
        if (avg_ns >= 1_000_000_000) {
            display_avg = avg_ns / 1_000_000_000;
            display_fastest = fastest / 1_000_000_000;
            display_slowest = slowest / 1_000_000_000;
            unit = "s";
        } else if (avg_ns >= 1_000_000) {
            display_avg = avg_ns / 1_000_000;
            display_fastest = fastest / 1_000_000;
            display_slowest = slowest / 1_000_000;
            unit = "ms";
        } else if (avg_ns >= 1_000) {
            display_avg = avg_ns / 1_000;
            display_fastest = fastest / 1_000;
            display_slowest = slowest / 1_000;
            unit = "us";
        }

        std.debug.print("{s}: {d:.3} {s}, fastest: {d:.3} {s}, slowest: {d:.3} {s}\n", .{ benchmark.name, display_avg, unit, display_fastest, unit, display_slowest, unit });
    }
}
