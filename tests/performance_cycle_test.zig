//! Performance benchmarks for cycle detection (<5ms target).
//!
//! Covers: detectCycle (deep chain, wide fanout), addDependency
//! Target: <5ms average, <10ms p99
//! Requires: ReleaseFast build
//!
//! Rationale: Cycle detection uses recursive CTE (O(n) depth worst case).
//! Deep chains test maximum recursion depth (100 levels).
//! Wide fanout tests breadth handling (1→100 dependents).
//! No-cycle tests success path with cycle check overhead.

const std = @import("std");
const builtin = @import("builtin");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;
const test_utils = @import("test_utils.zig");

// Performance targets from CLAUDE.md:225 (graph queries <5ms)
const CYCLE_TARGET_AVG_NANOS: i64 = 5_000_000; // 5ms average
const CYCLE_TARGET_P99_NANOS: i64 = 10_000_000; // 10ms p99 (allow 2x for tail)

/// Calculate min/max/avg from timing samples.
/// Helper for benchmark result aggregation.
fn calculateStats(samples: []const i64) struct { min: i64, max: i64, avg: i64 } {
    std.debug.assert(samples.len > 0);

    var min: i64 = std.math.maxInt(i64);
    var max: i64 = 0;
    var total: i64 = 0;

    for (samples) |sample| {
        min = @min(min, sample);
        max = @max(max, sample);
        total += sample;
    }

    const avg = @divTrunc(total, @as(i64, @intCast(samples.len)));

    return .{ .min = min, .max = max, .avg = avg };
}

test "performance: detectCycle with deep chain <5ms (RELEASE BUILD)" {
    // Cycle detection performance test with deep chain structure.
    //
    // Test structure:
    // Create chain of 100 tasks: 1→2→3→...→100
    // Test detectCycle for edge 100→1 (would complete cycle)
    // Run 50 iterations to measure performance
    //
    // Rationale: Deep chains stress test maximum recursion depth in cycle
    // detection CTE. This is the worst-case scenario for O(n) depth traversal.
    // Tiger Style: 2+ assertions per section, verify correctness, hard fail on target miss.
    if (builtin.mode != .ReleaseFast) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const iterations: usize = 50; // Fewer iterations due to expensive setup
    const chain_length: usize = 100;

    // Assertions: Validate configuration (Tiger Style)
    std.debug.assert(iterations > 0);
    std.debug.assert(iterations == 50);
    std.debug.assert(chain_length > 0);
    std.debug.assert(chain_length == 100);
    std.debug.assert(chain_length <= 200); // Limit recursion depth

    // Setup: Temp database
    const database_path = try test_utils.getTemporaryDatabasePath(allocator, "cycle_deep_chain");
    defer allocator.free(database_path);
    defer test_utils.cleanupDatabaseFile(database_path);

    var storage = try Storage.init(allocator, database_path);
    defer storage.deinit();

    // Setup: Create plan and chain of tasks
    const plan_slug = "bench-plan";
    try storage.createPlan(plan_slug, "Benchmark Plan", "For cycle detection", null);

    // Create chain: 1→2→3→...→100
    var task_ids = try allocator.alloc(u32, chain_length);
    defer allocator.free(task_ids);

    for (0..chain_length) |i| {
        var title_buffer: [64]u8 = undefined;
        const title = try std.fmt.bufPrint(&title_buffer, "Task {d}", .{i + 1});
        task_ids[i] = try storage.createTask(plan_slug, title, "Chain task");

        // Add dependency to previous task (skip first task)
        if (i > 0) {
            try storage.addDependency(task_ids[i], task_ids[i - 1]);
        }
    }

    // Assertions: Verify chain was created correctly
    std.debug.assert(task_ids.len == chain_length);
    std.debug.assert(task_ids[0] > 0);
    std.debug.assert(task_ids[chain_length - 1] > 0);

    // Pre-allocate samples array
    var samples = try allocator.alloc(i64, iterations);
    defer allocator.free(samples);

    // Benchmark loop: Test cycle detection for 100→1 edge
    for (0..iterations) |i| {
        var timer = try std.time.Timer.start();

        // MEASURE: Detect cycle when adding 100→1 (would complete the chain into a cycle)
        const has_cycle = try storage.detectCycle(task_ids[chain_length - 1], task_ids[0]);

        const elapsed = timer.read();
        samples[i] = @intCast(elapsed);

        // Verify cycle was detected (correctness check)
        std.debug.assert(has_cycle == true);
    }

    // Calculate statistics
    const stats = calculateStats(samples);
    const percentiles = test_utils.calculatePercentiles(samples);

    // Assertions: Verify statistics are valid
    std.debug.assert(stats.min > 0);
    std.debug.assert(stats.max >= stats.min);
    std.debug.assert(stats.avg > 0);
    std.debug.assert(stats.avg >= stats.min);
    std.debug.assert(stats.avg <= stats.max);

    // Report results
    std.debug.print("\ndetectCycle (deep chain={d}): avg={d}µs p50={d}µs p90={d}µs p99={d}µs\n", .{
        chain_length,
        @divTrunc(stats.avg, 1000),
        @divTrunc(percentiles.p50, 1000),
        @divTrunc(percentiles.p90, 1000),
        @divTrunc(percentiles.p99, 1000),
    });

    // HARD FAIL if targets not met (Tiger Style: no warnings, hard failure)
    try std.testing.expect(stats.avg < CYCLE_TARGET_AVG_NANOS);
    try std.testing.expect(percentiles.p99 < CYCLE_TARGET_P99_NANOS);
}

test "performance: detectCycle with wide fanout <5ms (RELEASE BUILD)" {
    // Cycle detection performance test with wide fanout structure.
    //
    // Test structure:
    // Create 1 root task blocking 100 dependent tasks
    // Test detectCycle for edge root→dependent[50] (reverse edge)
    // Run 50 iterations to measure performance
    //
    // Rationale: Wide fanout tests breadth handling in cycle detection.
    // Expected to be faster than deep chain (O(1) recursion depth, O(n) breadth).
    // Tiger Style: 2+ assertions per section, verify correctness, hard fail on target miss.
    if (builtin.mode != .ReleaseFast) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const iterations: usize = 50;
    const fanout_width: usize = 100;

    // Assertions: Validate configuration
    std.debug.assert(iterations > 0);
    std.debug.assert(iterations == 50);
    std.debug.assert(fanout_width > 0);
    std.debug.assert(fanout_width == 100);

    // Setup: Temp database
    const database_path = try test_utils.getTemporaryDatabasePath(allocator, "cycle_wide_fanout");
    defer allocator.free(database_path);
    defer test_utils.cleanupDatabaseFile(database_path);

    var storage = try Storage.init(allocator, database_path);
    defer storage.deinit();

    // Setup: Create plan and tasks
    const plan_slug = "bench-plan";
    try storage.createPlan(plan_slug, "Benchmark Plan", "For cycle detection", null);

    // Create root task
    const root_id = try storage.createTask(plan_slug, "Root Task", "Blocks all dependents");

    // Assertions: Verify root task was created
    std.debug.assert(root_id > 0);

    // Create 100 dependent tasks (all block on root)
    var dependent_ids = try allocator.alloc(u32, fanout_width);
    defer allocator.free(dependent_ids);

    for (0..fanout_width) |i| {
        var title_buffer: [64]u8 = undefined;
        const title = try std.fmt.bufPrint(&title_buffer, "Dependent {d}", .{i + 1});
        dependent_ids[i] = try storage.createTask(plan_slug, title, "Depends on root");
        try storage.addDependency(dependent_ids[i], root_id);
    }

    // Assertions: Verify all dependents were created
    std.debug.assert(dependent_ids.len == fanout_width);
    std.debug.assert(dependent_ids[0] > 0);
    std.debug.assert(dependent_ids[fanout_width - 1] > 0);

    // Pre-allocate samples array
    var samples = try allocator.alloc(i64, iterations);
    defer allocator.free(samples);

    // Benchmark loop: Test cycle detection for root→dependent[50] edge
    for (0..iterations) |i| {
        var timer = try std.time.Timer.start();

        // MEASURE: Detect cycle when adding root→dependent[50] (reverse edge)
        const has_cycle = try storage.detectCycle(root_id, dependent_ids[50]);

        const elapsed = timer.read();
        samples[i] = @intCast(elapsed);

        // Verify cycle was detected (correctness check)
        std.debug.assert(has_cycle == true);
    }

    // Calculate statistics
    const stats = calculateStats(samples);
    const percentiles = test_utils.calculatePercentiles(samples);

    // Assertions: Verify statistics are valid
    std.debug.assert(stats.min > 0);
    std.debug.assert(stats.max >= stats.min);
    std.debug.assert(stats.avg > 0);
    std.debug.assert(stats.avg >= stats.min);
    std.debug.assert(stats.avg <= stats.max);

    // Report results
    std.debug.print("\ndetectCycle (wide fanout={d}): avg={d}µs p50={d}µs p90={d}µs p99={d}µs\n", .{
        fanout_width,
        @divTrunc(stats.avg, 1000),
        @divTrunc(percentiles.p50, 1000),
        @divTrunc(percentiles.p90, 1000),
        @divTrunc(percentiles.p99, 1000),
    });

    // HARD FAIL if targets not met (Tiger Style: no warnings, hard failure)
    try std.testing.expect(stats.avg < CYCLE_TARGET_AVG_NANOS);
    try std.testing.expect(percentiles.p99 < CYCLE_TARGET_P99_NANOS);
}

test "performance: addDependency (no cycle) <5ms (RELEASE BUILD)" {
    // addDependency performance test with no cycles (success path).
    //
    // Test structure:
    // Create 100 independent tasks
    // Add 50 valid forward dependencies (i+1 depends on i)
    // Measure each addDependency call (includes cycle check)
    //
    // Rationale: Tests success path where no cycle is detected.
    // Includes cycle check overhead but should be fast (simple chain).
    // Tiger Style: 2+ assertions per section, verify correctness, hard fail on target miss.
    if (builtin.mode != .ReleaseFast) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const iterations: usize = 50;
    const task_count: usize = 100;

    // Assertions: Validate configuration
    std.debug.assert(iterations > 0);
    std.debug.assert(iterations == 50);
    std.debug.assert(task_count > 0);
    std.debug.assert(task_count == 100);
    std.debug.assert(task_count > iterations); // Need enough tasks for all iterations

    // Setup: Temp database
    const database_path = try test_utils.getTemporaryDatabasePath(allocator, "cycle_no_cycle");
    defer allocator.free(database_path);
    defer test_utils.cleanupDatabaseFile(database_path);

    var storage = try Storage.init(allocator, database_path);
    defer storage.deinit();

    // Setup: Create plan and independent tasks
    const plan_slug = "bench-plan";
    try storage.createPlan(plan_slug, "Benchmark Plan", "For dependency addition", null);

    var task_ids = try allocator.alloc(u32, task_count);
    defer allocator.free(task_ids);

    for (0..task_count) |i| {
        var title_buffer: [64]u8 = undefined;
        const title = try std.fmt.bufPrint(&title_buffer, "Task {d}", .{i + 1});
        task_ids[i] = try storage.createTask(plan_slug, title, "Independent task");
    }

    // Assertions: Verify all tasks were created
    std.debug.assert(task_ids.len == task_count);
    std.debug.assert(task_ids[0] > 0);
    std.debug.assert(task_ids[task_count - 1] > 0);

    // Pre-allocate samples array
    var samples = try allocator.alloc(i64, iterations);
    defer allocator.free(samples);

    // Benchmark loop: Add valid dependencies (i+1 depends on i)
    for (0..iterations) |i| {
        var timer = try std.time.Timer.start();

        // MEASURE: Add dependency that doesn't create cycle
        // Task i+1 depends on task i (forward dependency)
        try storage.addDependency(task_ids[i + 1], task_ids[i]);

        const elapsed = timer.read();
        samples[i] = @intCast(elapsed);
    }

    // Calculate statistics
    const stats = calculateStats(samples);
    const percentiles = test_utils.calculatePercentiles(samples);

    // Assertions: Verify statistics are valid
    std.debug.assert(stats.min > 0);
    std.debug.assert(stats.max >= stats.min);
    std.debug.assert(stats.avg > 0);
    std.debug.assert(stats.avg >= stats.min);
    std.debug.assert(stats.avg <= stats.max);

    // Report results
    std.debug.print("\naddDependency (no cycle, count={d}): avg={d}µs p50={d}µs p90={d}µs p99={d}µs\n", .{
        iterations,
        @divTrunc(stats.avg, 1000),
        @divTrunc(percentiles.p50, 1000),
        @divTrunc(percentiles.p90, 1000),
        @divTrunc(percentiles.p99, 1000),
    });

    // HARD FAIL if targets not met (Tiger Style: no warnings, hard failure)
    try std.testing.expect(stats.avg < CYCLE_TARGET_AVG_NANOS);
    try std.testing.expect(percentiles.p99 < CYCLE_TARGET_P99_NANOS);
}
