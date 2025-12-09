//! Performance stress tests with extreme graph patterns.
//!
//! Tests graph query performance under pathological conditions:
//! - Deep chains (depth=200)
//! - Wide fanouts (1→200)
//! - Dense graphs (100 tasks, 1000+ dependencies)
//! - Sparse graphs (1000 independent tasks)
//! - Diamond patterns (50 concurrent diamonds)
//!
//! Targets: avg <5ms, p99 <10ms per CLAUDE.md performance requirements.
//! All tests require ReleaseFast build mode and use 50 iterations.

const std = @import("std");
const builtin = @import("builtin");
const guerilla_graph = @import("guerilla_graph");
const test_utils = @import("test_utils.zig");

// Stress test performance targets (per CLAUDE.md:13,225)
const STRESS_TARGET_AVG_NANOS: u64 = 5_000_000; // 5ms average
const STRESS_TARGET_P99_NANOS: u64 = 10_000_000; // 10ms p99 (tail latency)

/// Statistics for stress test analysis.
/// Includes avg and p99 for comprehensive performance validation.
const StressStats = struct {
    min_nanos: i64,
    max_nanos: i64,
    avg_nanos: i64,
    p99_nanos: i64,

    /// Verify both average and p99 meet targets.
    /// Tiger Style: Hard failures, not warnings.
    pub fn meetsTargets(self: StressStats) bool {
        const avg_ok = @as(u64, @intCast(self.avg_nanos)) <= STRESS_TARGET_AVG_NANOS;
        const p99_ok = @as(u64, @intCast(self.p99_nanos)) <= STRESS_TARGET_P99_NANOS;
        return avg_ok and p99_ok;
    }
};

/// Calculate statistics from timing samples.
/// Requires at least 50 samples for meaningful p99.
/// Sorts samples in-place.
///
/// Rationale: p99 reveals tail latency that avg/max can miss.
/// Tiger Style: 2+ assertions for validation.
fn calculateStats(samples: []i64) StressStats {
    // Assertions: Validate input
    std.debug.assert(samples.len >= 50); // Need enough samples for p99
    std.debug.assert(samples.len > 0);

    // Calculate min, max, total
    var min_value: i64 = std.math.maxInt(i64);
    var max_value: i64 = 0;
    var total: i64 = 0;

    for (samples) |sample| {
        min_value = @min(min_value, sample);
        max_value = @max(max_value, sample);
        total += sample;
    }

    const avg_value = @divTrunc(total, @as(i64, @intCast(samples.len)));

    // Calculate p99 (requires sorted samples)
    std.mem.sort(i64, samples, {}, std.sort.asc(i64));
    const p99_idx = (samples.len * 99) / 100;
    std.debug.assert(p99_idx < samples.len);
    const p99_value = samples[p99_idx];

    // Assertions: Verify calculated values are valid
    std.debug.assert(min_value <= avg_value);
    std.debug.assert(avg_value <= max_value);
    std.debug.assert(p99_value <= max_value);

    return StressStats{
        .min_nanos = min_value,
        .max_nanos = max_value,
        .avg_nanos = avg_value,
        .p99_nanos = p99_value,
    };
}

// ============================================================================
// Test 1: Deep chain (depth=200)
// ============================================================================

test "stress: deep chain (depth=200, getReadyTasks=1)" {
    // Stress test: Long dependency chain.
    //
    // Graph structure: 1→2→3→...→200 (sequential chain)
    // Expected ready tasks: 1 (only first task is unblocked)
    //
    // Rationale: Tests recursive CTE performance with deep traversal.
    // Real workflows can have long sequential chains (e.g., database migrations).
    //
    // Performance targets:
    // - Average: <5ms per CLAUDE.md:13,225
    // - P99: <10ms (tail latency acceptable for deep chains)
    //
    // Tiger Style:
    // - 2+ assertions per section
    // - Hard failures on target misses
    // - Release-only check
    const allocator = std.testing.allocator;

    // REQUIRES: ReleaseFast build mode
    if (builtin.mode != .ReleaseFast) {
        return error.SkipZigTest;
    }

    const Storage = guerilla_graph.storage.Storage;

    // Create temporary database
    const database_path = try test_utils.getTemporaryDatabasePath(allocator, "stress_deep_chain");
    defer allocator.free(database_path);
    defer test_utils.cleanupDatabaseFile(database_path);

    var storage = try Storage.init(allocator, database_path);
    defer storage.deinit();

    // Setup: Create plan for chain
    const plan_slug = "chain";
    try storage.createPlan(plan_slug, "Deep Chain Test", "Sequential dependency chain", null);

    // Create 200 tasks in chain: 1→2→3→...→200
    const chain_depth: u32 = 200;
    var task_ids = try std.ArrayList(u32).initCapacity(allocator, chain_depth);
    defer task_ids.deinit(allocator);

    for (0..chain_depth) |i| {
        const task_title = try std.fmt.allocPrint(allocator, "Chain task {d}", .{i + 1});
        defer allocator.free(task_title);

        const task_id = try storage.createTask(plan_slug, task_title, "Sequential task");
        try task_ids.append(allocator, task_id);
    }

    // Assertions: Verify all tasks created
    std.debug.assert(task_ids.items.len == chain_depth);
    std.debug.assert(task_ids.items.len == 200);

    // Create chain dependencies: task[i] depends on task[i-1]
    for (1..chain_depth) |i| {
        try storage.addDependency(task_ids.items[i], task_ids.items[i - 1]);
    }

    // Benchmark: getReadyTasks with deep chain (50 iterations)
    const iterations: u32 = 50;
    var samples = try std.ArrayList(i64).initCapacity(allocator, iterations);
    defer samples.deinit(allocator);

    for (0..iterations) |_| {
        var timer = try std.time.Timer.start();

        var ready_tasks = try storage.getReadyTasks(10);
        defer {
            for (ready_tasks) |*task| {
                task.deinit(allocator);
            }
            allocator.free(ready_tasks);
        }

        const elapsed = timer.read();
        try samples.append(allocator, @intCast(elapsed));

        // Assertions: Verify correctness
        std.debug.assert(ready_tasks.len == 1); // Only first task is ready
        std.debug.assert(ready_tasks[0].id == task_ids.items[0]); // Verify it's task 1
    }

    // Calculate statistics and verify targets
    const stats = calculateStats(samples.items);

    // Assertions: Verify performance targets met
    std.debug.assert(stats.avg_nanos > 0);
    std.debug.assert(stats.p99_nanos > 0);

    // Tiger Style: Hard assertion on targets
    try std.testing.expect(stats.meetsTargets());
}

// ============================================================================
// Test 2: Wide fanout (1→200 dependents)
// ============================================================================

test "stress: wide fanout (1→200, getReadyTasks=1)" {
    // Stress test: Single blocker with many dependents.
    //
    // Graph structure: task1 blocks 200 other tasks (2-201 all depend on 1)
    // Expected ready tasks: 1 (only task 1 is unblocked)
    //
    // Rationale: Tests query performance with large result sets from recursive CTE.
    // Real scenarios: foundational task (e.g., database setup) blocks many features.
    //
    // Performance targets:
    // - Average: <5ms per CLAUDE.md:13,225
    // - P99: <10ms (tail latency acceptable for wide fanouts)
    //
    // Tiger Style:
    // - 2+ assertions per section
    // - Hard failures on target misses
    // - Release-only check
    const allocator = std.testing.allocator;

    // REQUIRES: ReleaseFast build mode
    if (builtin.mode != .ReleaseFast) {
        return error.SkipZigTest;
    }

    const Storage = guerilla_graph.storage.Storage;

    // Create temporary database
    const database_path = try test_utils.getTemporaryDatabasePath(allocator, "stress_wide_fanout");
    defer allocator.free(database_path);
    defer test_utils.cleanupDatabaseFile(database_path);

    var storage = try Storage.init(allocator, database_path);
    defer storage.deinit();

    // Setup: Create plan for fanout
    const plan_slug = "fanout";
    try storage.createPlan(plan_slug, "Wide Fanout Test", "Single blocker with 200 dependents", null);

    // Create 201 tasks (1 blocker + 200 dependents)
    const total_tasks: u32 = 201;
    var task_ids = try std.ArrayList(u32).initCapacity(allocator, total_tasks);
    defer task_ids.deinit(allocator);

    for (0..total_tasks) |i| {
        const task_title = try std.fmt.allocPrint(allocator, "Fanout task {d}", .{i + 1});
        defer allocator.free(task_title);

        const task_id = try storage.createTask(plan_slug, task_title, "Fanout task");
        try task_ids.append(allocator, task_id);
    }

    // Assertions: Verify all tasks created
    std.debug.assert(task_ids.items.len == total_tasks);
    std.debug.assert(task_ids.items.len == 201);

    // Create fanout dependencies: tasks 2-201 all depend on task 1
    const blocker_id = task_ids.items[0];
    for (1..total_tasks) |i| {
        try storage.addDependency(task_ids.items[i], blocker_id);
    }

    // Benchmark: getReadyTasks with wide fanout (50 iterations)
    const iterations: u32 = 50;
    var samples = try std.ArrayList(i64).initCapacity(allocator, iterations);
    defer samples.deinit(allocator);

    for (0..iterations) |_| {
        var timer = try std.time.Timer.start();

        var ready_tasks = try storage.getReadyTasks(10);
        defer {
            for (ready_tasks) |*task| {
                task.deinit(allocator);
            }
            allocator.free(ready_tasks);
        }

        const elapsed = timer.read();
        try samples.append(allocator, @intCast(elapsed));

        // Assertions: Verify correctness
        std.debug.assert(ready_tasks.len == 1); // Only blocker is ready
        std.debug.assert(ready_tasks[0].id == blocker_id); // Verify it's task 1
    }

    // Calculate statistics and verify targets
    const stats = calculateStats(samples.items);

    // Assertions: Verify performance targets met
    std.debug.assert(stats.avg_nanos > 0);
    std.debug.assert(stats.p99_nanos > 0);

    // Tiger Style: Hard assertion on targets
    try std.testing.expect(stats.meetsTargets());
}

// ============================================================================
// Test 3: Dense graph (100 tasks, 1000+ dependencies)
// ============================================================================

test "stress: dense graph (100 tasks, 1000+ deps, getReadyTasks=10)" {
    // Stress test: Highly interconnected dependency graph.
    //
    // Graph structure: 100 tasks with dependency pattern:
    // - Each task i depends on max(0, i-15) through i-1 (up to 15 blockers)
    // - Creates ~1000-1500 total dependencies
    // - Tasks 1-10 have no dependencies (ready)
    //
    // Expected ready tasks: 10 (first 10 tasks are unblocked)
    //
    // Rationale: Tests performance with complex interconnected graphs.
    // Real scenarios: microservice dependencies, build system graphs.
    //
    // Performance targets:
    // - Average: <5ms per CLAUDE.md:13,225
    // - P99: <10ms (tail latency for dense graphs)
    //
    // Tiger Style:
    // - 2+ assertions per section
    // - Hard failures on target misses
    // - Release-only check
    const allocator = std.testing.allocator;

    // REQUIRES: ReleaseFast build mode
    if (builtin.mode != .ReleaseFast) {
        return error.SkipZigTest;
    }

    const Storage = guerilla_graph.storage.Storage;

    // Create temporary database
    const database_path = try test_utils.getTemporaryDatabasePath(allocator, "stress_dense_graph");
    defer allocator.free(database_path);
    defer test_utils.cleanupDatabaseFile(database_path);

    var storage = try Storage.init(allocator, database_path);
    defer storage.deinit();

    // Setup: Create plan for dense graph
    const plan_slug = "dense";
    try storage.createPlan(plan_slug, "Dense Graph Test", "Highly interconnected dependencies", null);

    // Create 100 tasks
    const task_count: u32 = 100;
    var task_ids = try std.ArrayList(u32).initCapacity(allocator, task_count);
    defer task_ids.deinit(allocator);

    for (0..task_count) |i| {
        const task_title = try std.fmt.allocPrint(allocator, "Dense task {d}", .{i + 1});
        defer allocator.free(task_title);

        const task_id = try storage.createTask(plan_slug, task_title, "Dense graph task");
        try task_ids.append(allocator, task_id);
    }

    // Assertions: Verify all tasks created
    std.debug.assert(task_ids.items.len == task_count);
    std.debug.assert(task_ids.items.len == 100);

    // Create dense dependencies: task i depends on max(0, i-15)..i-1
    var dependency_count: u32 = 0;
    for (1..task_count) |i| {
        const start_idx = if (i >= 15) i - 15 else 0;
        for (start_idx..i) |blocker_idx| {
            try storage.addDependency(task_ids.items[i], task_ids.items[blocker_idx]);
            dependency_count += 1;
        }
    }

    // Assertions: Verify dense graph created
    std.debug.assert(dependency_count >= 1000); // Should have 1000+ dependencies
    std.debug.assert(dependency_count <= 1500); // Upper bound validation

    // Benchmark: getReadyTasks with dense graph (50 iterations)
    const iterations: u32 = 50;
    var samples = try std.ArrayList(i64).initCapacity(allocator, iterations);
    defer samples.deinit(allocator);

    for (0..iterations) |_| {
        var timer = try std.time.Timer.start();

        var ready_tasks = try storage.getReadyTasks(20);
        defer {
            for (ready_tasks) |*task| {
                task.deinit(allocator);
            }
            allocator.free(ready_tasks);
        }

        const elapsed = timer.read();
        try samples.append(allocator, @intCast(elapsed));

        // Assertions: Verify correctness
        std.debug.assert(ready_tasks.len == 10); // First 10 tasks are ready
        // Verify first task is task 1 (0-indexed as items[0])
        std.debug.assert(ready_tasks[0].id == task_ids.items[0]);
    }

    // Calculate statistics and verify targets
    const stats = calculateStats(samples.items);

    // Assertions: Verify performance targets met
    std.debug.assert(stats.avg_nanos > 0);
    std.debug.assert(stats.p99_nanos > 0);

    // Tiger Style: Hard assertion on targets
    try std.testing.expect(stats.meetsTargets());
}

// ============================================================================
// Test 4: Sparse graph (1000 independent tasks)
// ============================================================================

test "stress: sparse graph (1000 independent, getReadyTasks=50)" {
    // Stress test: Large number of independent tasks.
    //
    // Graph structure: 1000 tasks with no dependencies (all ready)
    // Expected ready tasks: 50 (limit parameter)
    //
    // Rationale: Tests query performance with large result sets.
    // Real scenarios: initial project setup with many independent tasks.
    //
    // Performance targets:
    // - Average: <5ms per CLAUDE.md:13,225
    // - P99: <10ms (should be fast with no dependency resolution)
    //
    // Tiger Style:
    // - 2+ assertions per section
    // - Hard failures on target misses
    // - Release-only check
    const allocator = std.testing.allocator;

    // REQUIRES: ReleaseFast build mode
    if (builtin.mode != .ReleaseFast) {
        return error.SkipZigTest;
    }

    const Storage = guerilla_graph.storage.Storage;

    // Create temporary database
    const database_path = try test_utils.getTemporaryDatabasePath(allocator, "stress_sparse_graph");
    defer allocator.free(database_path);
    defer test_utils.cleanupDatabaseFile(database_path);

    var storage = try Storage.init(allocator, database_path);
    defer storage.deinit();

    // Setup: Create plan for sparse graph
    const plan_slug = "sparse";
    try storage.createPlan(plan_slug, "Sparse Graph Test", "1000 independent tasks", null);

    // Create 1000 independent tasks (no dependencies)
    const task_count: u32 = 1000;
    var task_ids = try std.ArrayList(u32).initCapacity(allocator, task_count);
    defer task_ids.deinit(allocator);

    for (0..task_count) |i| {
        const task_title = try std.fmt.allocPrint(allocator, "Sparse task {d}", .{i + 1});
        defer allocator.free(task_title);

        const task_id = try storage.createTask(plan_slug, task_title, "Independent task");
        try task_ids.append(allocator, task_id);
    }

    // Assertions: Verify all tasks created
    std.debug.assert(task_ids.items.len == task_count);
    std.debug.assert(task_ids.items.len == 1000);

    // Benchmark: getReadyTasks with sparse graph (50 iterations)
    const iterations: u32 = 50;
    const query_limit: u32 = 50; // Request 50 tasks
    var samples = try std.ArrayList(i64).initCapacity(allocator, iterations);
    defer samples.deinit(allocator);

    for (0..iterations) |_| {
        var timer = try std.time.Timer.start();

        var ready_tasks = try storage.getReadyTasks(query_limit);
        defer {
            for (ready_tasks) |*task| {
                task.deinit(allocator);
            }
            allocator.free(ready_tasks);
        }

        const elapsed = timer.read();
        try samples.append(allocator, @intCast(elapsed));

        // Assertions: Verify correctness
        std.debug.assert(ready_tasks.len == query_limit); // Should return exactly 50
        std.debug.assert(ready_tasks.len == 50);
    }

    // Calculate statistics and verify targets
    const stats = calculateStats(samples.items);

    // Assertions: Verify performance targets met
    std.debug.assert(stats.avg_nanos > 0);
    std.debug.assert(stats.p99_nanos > 0);

    // Tiger Style: Hard assertion on targets
    try std.testing.expect(stats.meetsTargets());
}

// ============================================================================
// Test 5: Diamond patterns (50 concurrent diamonds)
// ============================================================================

test "stress: diamond patterns (50 diamonds, getReadyTasks=50)" {
    // Stress test: Multiple diamond dependency patterns.
    //
    // Graph structure: 50 independent diamond patterns
    // Each diamond: root → left + right → convergence (4 tasks per diamond, 200 total)
    // Expected ready tasks: 50 (all diamond roots are ready)
    //
    // Rationale: Tests query performance with common parallel merge patterns.
    // Real scenarios: feature branches, parallel build tasks converging.
    //
    // Performance targets:
    // - Average: <5ms per CLAUDE.md:13,225
    // - P99: <10ms (diamonds are common pattern)
    //
    // Tiger Style:
    // - 2+ assertions per section
    // - Hard failures on target misses
    // - Release-only check
    const allocator = std.testing.allocator;

    // REQUIRES: ReleaseFast build mode
    if (builtin.mode != .ReleaseFast) {
        return error.SkipZigTest;
    }

    const Storage = guerilla_graph.storage.Storage;

    // Create temporary database
    const database_path = try test_utils.getTemporaryDatabasePath(allocator, "stress_diamond_patterns");
    defer allocator.free(database_path);
    defer test_utils.cleanupDatabaseFile(database_path);

    var storage = try Storage.init(allocator, database_path);
    defer storage.deinit();

    // Setup: Create plan for diamond patterns
    const plan_slug = "diamonds";
    try storage.createPlan(plan_slug, "Diamond Patterns Test", "50 concurrent diamond patterns", null);

    // Create 50 diamond patterns (4 tasks each = 200 total tasks)
    const diamond_count: u32 = 50;
    const tasks_per_diamond: u32 = 4;
    const total_tasks = diamond_count * tasks_per_diamond;

    var task_ids = try std.ArrayList(u32).initCapacity(allocator, total_tasks);
    defer task_ids.deinit(allocator);

    // Create all tasks first
    for (0..total_tasks) |i| {
        const task_title = try std.fmt.allocPrint(allocator, "Diamond task {d}", .{i + 1});
        defer allocator.free(task_title);

        const task_id = try storage.createTask(plan_slug, task_title, "Diamond pattern task");
        try task_ids.append(allocator, task_id);
    }

    // Assertions: Verify all tasks created
    std.debug.assert(task_ids.items.len == total_tasks);
    std.debug.assert(task_ids.items.len == 200);

    // Create diamond dependencies
    // Each diamond: root (0) → left (1) + right (2) → convergence (3)
    var diamond_roots = try std.ArrayList(u32).initCapacity(allocator, diamond_count);
    defer diamond_roots.deinit(allocator);

    for (0..diamond_count) |diamond_idx| {
        const base_idx = diamond_idx * tasks_per_diamond;
        const root_idx = base_idx;
        const left_idx = base_idx + 1;
        const right_idx = base_idx + 2;
        const converge_idx = base_idx + 3;

        // Track root tasks (these will be ready)
        try diamond_roots.append(allocator, task_ids.items[root_idx]);

        // Left and right depend on root
        try storage.addDependency(task_ids.items[left_idx], task_ids.items[root_idx]);
        try storage.addDependency(task_ids.items[right_idx], task_ids.items[root_idx]);

        // Convergence depends on both left and right
        try storage.addDependency(task_ids.items[converge_idx], task_ids.items[left_idx]);
        try storage.addDependency(task_ids.items[converge_idx], task_ids.items[right_idx]);
    }

    // Assertions: Verify diamond patterns created
    std.debug.assert(diamond_roots.items.len == diamond_count);
    std.debug.assert(diamond_roots.items.len == 50);

    // Benchmark: getReadyTasks with diamond patterns (50 iterations)
    const iterations: u32 = 50;
    var samples = try std.ArrayList(i64).initCapacity(allocator, iterations);
    defer samples.deinit(allocator);

    for (0..iterations) |_| {
        var timer = try std.time.Timer.start();

        var ready_tasks = try storage.getReadyTasks(60); // Request more than 50 for safety
        defer {
            for (ready_tasks) |*task| {
                task.deinit(allocator);
            }
            allocator.free(ready_tasks);
        }

        const elapsed = timer.read();
        try samples.append(allocator, @intCast(elapsed));

        // Assertions: Verify correctness
        std.debug.assert(ready_tasks.len == diamond_count); // All 50 roots ready
        std.debug.assert(ready_tasks.len == 50);

        // Verify first task is first diamond root
        std.debug.assert(ready_tasks[0].id == diamond_roots.items[0]);
    }

    // Calculate statistics and verify targets
    const stats = calculateStats(samples.items);

    // Assertions: Verify performance targets met
    std.debug.assert(stats.avg_nanos > 0);
    std.debug.assert(stats.p99_nanos > 0);

    // Tiger Style: Hard assertion on targets
    try std.testing.expect(stats.meetsTargets());
}
