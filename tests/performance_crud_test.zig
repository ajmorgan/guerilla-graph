//! Performance benchmarks for CRUD operations (<1ms target).
//!
//! Covers: createPlan, createTask, getTask, updateTask
//! Target: <1ms average, <2ms p99
//! Requires: ReleaseFast build (skips in debug)
//!
//! Tiger Style Compliance:
//! - Release-only execution (skip in debug)
//! - Hard failures on target miss
//! - Percentile tracking (p50/p90/p99)
//! - 2+ assertions per function

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;
const test_utils = @import("test_utils.zig");

// Performance targets from CLAUDE.md:13,225
const CRUD_TARGET_AVG_NANOS: i64 = 1_000_000; // 1ms average
const CRUD_TARGET_P99_NANOS: i64 = 2_000_000; // 2ms p99 (allow 2x for tail)

test "performance: createPlan <1ms (RELEASE BUILD)" {
    // Skip in debug builds (10-100x slower, meaningless for performance validation)
    if (@import("builtin").mode != .ReleaseFast) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const iterations: usize = 1000;

    // Assertions: Validate test configuration
    std.debug.assert(iterations > 0);
    std.debug.assert(iterations <= 10000);

    // Setup: Temp database
    const database_path = try test_utils.getTemporaryDatabasePath(allocator, "crud_create_plan");
    defer allocator.free(database_path);
    defer test_utils.cleanupDatabaseFile(database_path);

    var storage = try Storage.init(allocator, database_path);
    defer storage.deinit();

    // Pre-allocate samples array
    var samples = try allocator.alloc(u64, iterations);
    defer allocator.free(samples);

    // Benchmark loop: Create plans and measure timing
    for (0..iterations) |i| {
        var timer = try std.time.Timer.start();

        // Generate unique plan ID
        var id_buffer: [32]u8 = undefined;
        const plan_id = try std.fmt.bufPrint(&id_buffer, "plan-{d:0>3}", .{i + 1});

        // MEASURE: Plan creation
        try storage.createPlan(plan_id, "Test Plan", "Description", null);

        const elapsed = timer.read();
        samples[i] = elapsed;
    }

    // Calculate statistics
    const stats = calculateStats(samples);

    // Convert samples to i64 for percentile calculation (test_utils expects i64)
    var samples_i64 = try allocator.alloc(i64, iterations);
    defer allocator.free(samples_i64);
    for (samples, 0..) |sample, i| {
        samples_i64[i] = @intCast(sample);
    }
    const percentiles = test_utils.calculatePercentiles(samples_i64);

    // Report results
    std.debug.print("\ncreatePlan: avg={d}µs p50={d}µs p90={d}µs p99={d}µs\n", .{
        stats.avg / 1000,
        @divTrunc(percentiles.p50, 1000),
        @divTrunc(percentiles.p90, 1000),
        @divTrunc(percentiles.p99, 1000),
    });

    // HARD FAIL if targets not met (Tiger Style: zero technical debt)
    try std.testing.expect(stats.avg < CRUD_TARGET_AVG_NANOS);
    try std.testing.expect(percentiles.p99 < CRUD_TARGET_P99_NANOS);
}

test "performance: createTask <1ms (RELEASE BUILD)" {
    // Skip in debug builds (10-100x slower, meaningless for performance validation)
    if (@import("builtin").mode != .ReleaseFast) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const iterations: usize = 1000;

    // Assertions: Validate test configuration
    std.debug.assert(iterations > 0);
    std.debug.assert(iterations <= 10000);

    // Setup: Temp database
    const database_path = try test_utils.getTemporaryDatabasePath(allocator, "crud_create_task");
    defer allocator.free(database_path);
    defer test_utils.cleanupDatabaseFile(database_path);

    var storage = try Storage.init(allocator, database_path);
    defer storage.deinit();

    // Pre-create 10 plans for task distribution
    var plan_ids: [10][32]u8 = undefined;
    for (0..10) |i| {
        const plan_id = try std.fmt.bufPrint(&plan_ids[i], "plan-{d:0>3}", .{i + 1});
        try storage.createPlan(plan_id, "Test Plan", "Description", null);
    }

    // Pre-allocate samples array
    var samples = try allocator.alloc(u64, iterations);
    defer allocator.free(samples);

    // Benchmark loop: Create tasks distributed across plans
    for (0..iterations) |i| {
        var timer = try std.time.Timer.start();

        // Distribute tasks across plans (round-robin)
        const plan_idx = i % 10;
        const plan_id = plan_ids[plan_idx][0 .. std.mem.indexOfScalar(u8, &plan_ids[plan_idx], 0) orelse plan_ids[plan_idx].len];

        // Stack buffer for task title
        var title_buffer: [64]u8 = undefined;
        const title = try std.fmt.bufPrint(&title_buffer, "Task {d}", .{i + 1});

        // MEASURE: Task creation
        _ = try storage.createTask(plan_id, title, "Description");

        const elapsed = timer.read();
        samples[i] = elapsed;
    }

    // Calculate statistics
    const stats = calculateStats(samples);

    // Convert samples to i64 for percentile calculation
    var samples_i64 = try allocator.alloc(i64, iterations);
    defer allocator.free(samples_i64);
    for (samples, 0..) |sample, i| {
        samples_i64[i] = @intCast(sample);
    }
    const percentiles = test_utils.calculatePercentiles(samples_i64);

    // Report results
    std.debug.print("\ncreateTask: avg={d}µs p50={d}µs p90={d}µs p99={d}µs\n", .{
        stats.avg / 1000,
        @divTrunc(percentiles.p50, 1000),
        @divTrunc(percentiles.p90, 1000),
        @divTrunc(percentiles.p99, 1000),
    });

    // HARD FAIL if targets not met (Tiger Style: zero technical debt)
    try std.testing.expect(stats.avg < CRUD_TARGET_AVG_NANOS);
    try std.testing.expect(percentiles.p99 < CRUD_TARGET_P99_NANOS);
}

test "performance: getTask <1ms (RELEASE BUILD)" {
    // Skip in debug builds (10-100x slower, meaningless for performance validation)
    if (@import("builtin").mode != .ReleaseFast) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const iterations: usize = 1000;

    // Assertions: Validate test configuration
    std.debug.assert(iterations > 0);
    std.debug.assert(iterations <= 10000);

    // Setup: Temp database
    const database_path = try test_utils.getTemporaryDatabasePath(allocator, "crud_get_task");
    defer allocator.free(database_path);
    defer test_utils.cleanupDatabaseFile(database_path);

    var storage = try Storage.init(allocator, database_path);
    defer storage.deinit();

    // Phase 1: Setup - Create plan and 1000 tasks
    try storage.createPlan("test-plan", "Test Plan", "Description", null);

    var task_ids: [1000]u32 = undefined;
    for (0..iterations) |i| {
        var title_buffer: [64]u8 = undefined;
        const title = try std.fmt.bufPrint(&title_buffer, "Task {d}", .{i + 1});
        task_ids[i] = try storage.createTask("test-plan", title, "Description");
    }

    // Pre-allocate samples array
    var samples = try allocator.alloc(u64, iterations);
    defer allocator.free(samples);

    // Phase 2: Benchmark - Retrieve each task by ID
    for (0..iterations) |i| {
        var timer = try std.time.Timer.start();

        // MEASURE: Task retrieval
        const task = try storage.getTask(task_ids[i]);

        const elapsed = timer.read();
        samples[i] = elapsed;

        // Verify task was retrieved
        std.debug.assert(task != null);
    }

    // Calculate statistics
    const stats = calculateStats(samples);

    // Convert samples to i64 for percentile calculation
    var samples_i64 = try allocator.alloc(i64, iterations);
    defer allocator.free(samples_i64);
    for (samples, 0..) |sample, i| {
        samples_i64[i] = @intCast(sample);
    }
    const percentiles = test_utils.calculatePercentiles(samples_i64);

    // Report results
    std.debug.print("\ngetTask: avg={d}µs p50={d}µs p90={d}µs p99={d}µs\n", .{
        stats.avg / 1000,
        @divTrunc(percentiles.p50, 1000),
        @divTrunc(percentiles.p90, 1000),
        @divTrunc(percentiles.p99, 1000),
    });

    // HARD FAIL if targets not met (Tiger Style: zero technical debt)
    try std.testing.expect(stats.avg < CRUD_TARGET_AVG_NANOS);
    try std.testing.expect(percentiles.p99 < CRUD_TARGET_P99_NANOS);
}

test "performance: updateTask <1ms (RELEASE BUILD)" {
    // Skip in debug builds (10-100x slower, meaningless for performance validation)
    if (@import("builtin").mode != .ReleaseFast) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const iterations: usize = 1000;

    // Assertions: Validate test configuration
    std.debug.assert(iterations > 0);
    std.debug.assert(iterations <= 10000);

    // Setup: Temp database
    const database_path = try test_utils.getTemporaryDatabasePath(allocator, "crud_update_task");
    defer allocator.free(database_path);
    defer test_utils.cleanupDatabaseFile(database_path);

    var storage = try Storage.init(allocator, database_path);
    defer storage.deinit();

    // Phase 1: Setup - Create plan and 1000 tasks
    try storage.createPlan("test-plan", "Test Plan", "Description", null);

    var task_ids: [1000]u32 = undefined;
    for (0..iterations) |i| {
        var title_buffer: [64]u8 = undefined;
        const title = try std.fmt.bufPrint(&title_buffer, "Task {d}", .{i + 1});
        task_ids[i] = try storage.createTask("test-plan", title, "Description");
    }

    // Pre-allocate samples array
    var samples = try allocator.alloc(u64, iterations);
    defer allocator.free(samples);

    // Phase 2: Benchmark - Update each task status to in_progress
    for (0..iterations) |i| {
        var timer = try std.time.Timer.start();

        // MEASURE: Task update (status change)
        try storage.updateTask(task_ids[i], null, null, .in_progress);

        const elapsed = timer.read();
        samples[i] = elapsed;
    }

    // Calculate statistics
    const stats = calculateStats(samples);

    // Convert samples to i64 for percentile calculation
    var samples_i64 = try allocator.alloc(i64, iterations);
    defer allocator.free(samples_i64);
    for (samples, 0..) |sample, i| {
        samples_i64[i] = @intCast(sample);
    }
    const percentiles = test_utils.calculatePercentiles(samples_i64);

    // Report results
    std.debug.print("\nupdateTask: avg={d}µs p50={d}µs p90={d}µs p99={d}µs\n", .{
        stats.avg / 1000,
        @divTrunc(percentiles.p50, 1000),
        @divTrunc(percentiles.p90, 1000),
        @divTrunc(percentiles.p99, 1000),
    });

    // HARD FAIL if targets not met (Tiger Style: zero technical debt)
    try std.testing.expect(stats.avg < CRUD_TARGET_AVG_NANOS);
    try std.testing.expect(percentiles.p99 < CRUD_TARGET_P99_NANOS);
}

/// Calculate min/max/avg from timing samples.
/// Helper for benchmark result aggregation.
fn calculateStats(samples: []u64) struct { min: u64, max: u64, avg: u64 } {
    std.debug.assert(samples.len > 0);

    var min: u64 = std.math.maxInt(u64);
    var max: u64 = 0;
    var total: u64 = 0;

    for (samples) |sample| {
        min = @min(min, sample);
        max = @max(max, sample);
        total += sample;
    }

    const avg = total / @as(u64, @intCast(samples.len));

    return .{ .min = min, .max = max, .avg = avg };
}
