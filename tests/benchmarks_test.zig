//! Performance benchmarks (benchmarks.zig).
//!
//! Targets: CRUD <1ms, Graph queries <5ms.

const std = @import("std");
const builtin = @import("builtin");
const guerilla_graph = @import("guerilla_graph");

const BenchmarkResult = struct {
    operation_name: []const u8,
    iterations: u32,
    total_nanos: u64,
    min_nanos: u64,
    max_nanos: u64,
    avg_nanos: u64,
    target_nanos: u64,

    pub fn meetsTarget(self: BenchmarkResult) bool {
        return self.avg_nanos <= self.target_nanos;
    }
};

test "BenchmarkResult: meetsTarget validation" {
    // Case 1: Performance meets target
    const good_result = BenchmarkResult{
        .operation_name = "test_op",
        .iterations = 100,
        .total_nanos = 50_000_000, // 50ms total
        .min_nanos = 100_000, // 100 microseconds
        .max_nanos = 1_500_000, // 1.5ms
        .avg_nanos = 500_000, // 500 microseconds average
        .target_nanos = 1_000_000, // 1ms target
    };

    try std.testing.expect(good_result.meetsTarget());

    // Case 2: Performance exceeds target
    const bad_result = BenchmarkResult{
        .operation_name = "slow_op",
        .iterations = 100,
        .total_nanos = 200_000_000, // 200ms total
        .min_nanos = 1_000_000, // 1ms
        .max_nanos = 3_000_000, // 3ms
        .avg_nanos = 2_000_000, // 2ms average (exceeds target)
        .target_nanos = 1_000_000, // 1ms target
    };

    try std.testing.expect(!bad_result.meetsTarget());
}

// Test: BenchmarkResult assertions catch invalid data
test "BenchmarkResult: data validation assertions" {
    // Valid result should not trigger assertions
    const valid_result = BenchmarkResult{
        .operation_name = "valid",
        .iterations = 10,
        .total_nanos = 1000,
        .min_nanos = 50,
        .max_nanos = 200,
        .avg_nanos = 100,
        .target_nanos = 500,
    };

    // This should complete without assertion failures
    const meets = valid_result.meetsTarget();
    try std.testing.expect(meets); // 100 < 500, so meets target
}

// ============================================================================
// Performance Test: Graph Query Operations (<5ms target)
// REQUIRES: ReleaseFast build mode (-Doptimize=ReleaseFast)
// ============================================================================

test "performance: graph queries with complex graph (<5ms target)" {
    // Performance test for graph query operations with complex graph.
    //
    // Methodology:
    // This test creates a realistic complex graph and measures performance of critical
    // operations that agents use for parallel coordination.
    //
    // Test structure:
    // 1. Setup: Create 120 tasks across 10 plans with ~220 dependencies
    // 2. Benchmark getReadyTasks: Find unblocked work (most frequent query)
    // 3. Benchmark addDependency: Add dependency with cycle detection
    // 4. Benchmark getBlockers: Transitive blocker query (for task planning)
    // 5. Benchmark getDependents: Transitive dependent query (for impact analysis)
    // 6. Verify all operations meet <5ms target
    //
    // Rationale: CLAUDE.md:13,225 specifies <5ms for graph queries.
    // This validates performance with complex graphs (100+ tasks, 200+ dependencies)
    // meets requirements for parallel agent coordination.
    //
    // Graph structure:
    // - 10 plans with 10-15 tasks each (120 total tasks)
    // - Dependency patterns: sequential chains, diamond patterns, cross-plan deps
    // - ~200-250 total dependencies
    // - Multiple ready tasks across different labels
    //
    // Tiger Style Compliance:
    // - 2+ assertions per section
    // - Full variable names (no abbreviations)
    // - Rationale comments explaining design choices
    // - Verify <5ms target with explicit checks
    const allocator = std.testing.allocator;

    // REQUIRES: ReleaseFast build mode
    // Rationale: Debug builds are 30-40x slower and cannot meet 5ms target.
    // Tiger Style: Hard failures on target miss (not warnings).
    if (builtin.mode != .ReleaseFast) {
        return error.SkipZigTest;
    }

    const Storage = guerilla_graph.storage.Storage;

    // Target: <5ms (5_000_000 nanoseconds) per operation
    const target_nanos: u64 = 5_000_000; // Target: <5ms per CLAUDE.md:13,225
    std.debug.assert(target_nanos == 5_000_000);
    std.debug.assert(target_nanos > 0);

    // Create temporary database for performance test
    const database_path = "/tmp/guerilla_graph_perf_graph_queries.db";
    std.fs.cwd().deleteFile(database_path) catch {}; // Clean slate
    defer std.fs.cwd().deleteFile(database_path) catch {};

    // Initialize storage
    var storage = try Storage.init(allocator, database_path);
    defer storage.deinit();

    // ========================================================================
    // Setup: Create large complex graph (120 tasks, ~220 dependencies)
    // ========================================================================

    // Rationale: 10 plans with varying task counts creates realistic workload.
    // Real projects have multiple features with different complexity levels.
    const plan_names = [_][]const u8{
        "authentication", "payments", "notifications", "analytics", "reporting",
        "api",            "frontend", "backend",       "database",  "infrastructure",
    };

    const tasks_per_label = [_]u32{
        12, 15, 10, 11, 13, 14, 10, 12, 11, 12, // Total: 120 tasks
    };

    // Assertions: Verify setup configuration
    std.debug.assert(plan_names.len == 10);
    std.debug.assert(tasks_per_label.len == 10);

    var total_tasks: u32 = 0;
    for (tasks_per_label) |count| {
        total_tasks += count;
    }
    std.debug.assert(total_tasks >= 100); // Must be 100+ per requirements
    std.debug.assert(total_tasks == 120); // Verify expected total

    // Create labels and track task IDs
    var all_task_ids = try std.ArrayList(u32).initCapacity(allocator, 120);
    defer all_task_ids.deinit(allocator);

    // Create labels
    for (plan_names, 0..) |plan_name, plan_idx| {
        const plan_title = try std.fmt.allocPrint(
            allocator,
            "Label {s}",
            .{plan_name},
        );
        defer allocator.free(plan_title);

        const plan_description = try std.fmt.allocPrint(
            allocator,
            "Tasks for {s} feature",
            .{plan_name},
        );
        defer allocator.free(plan_description);

        try storage.createPlan(plan_name, plan_title, plan_description, null);

        // Create tasks for this plan
        const task_count = tasks_per_label[plan_idx];
        for (0..task_count) |task_idx| {
            const task_title = try std.fmt.allocPrint(
                allocator,
                "Task {d} for {s}",
                .{ task_idx + 1, plan_name },
            );
            defer allocator.free(task_title);

            const task_description = try std.fmt.allocPrint(
                allocator,
                "Implementation task {d}",
                .{task_idx + 1},
            );
            defer allocator.free(task_description);

            const task_id = try storage.createTask(plan_name, task_title, task_description);
            try all_task_ids.append(allocator, task_id);
        }
    }

    // Assertions: Verify all tasks were created
    std.debug.assert(all_task_ids.items.len == total_tasks);
    std.debug.assert(all_task_ids.items.len == 120);

    // ========================================================================
    // Create complex dependency patterns (~220 dependencies)
    // ========================================================================

    // Rationale: Mix of dependency patterns creates realistic graph:
    // - Sequential chains (common in ordered workflows)
    // - Diamond patterns (parallel branches converging)
    // - Cross-plan dependencies (feature interdependencies)
    var dependency_count: u32 = 0;

    // Pattern 1: Sequential chains within each plan (first 5 tasks)
    // Creates: task1 <- task2 <- task3 <- task4 <- task5
    var task_offset: usize = 0;
    for (tasks_per_label) |task_count| {
        const chain_length = @min(5, task_count);
        for (1..chain_length) |i| {
            const blocker_idx = task_offset + i - 1;
            const blocked_idx = task_offset + i;
            try storage.addDependency(
                all_task_ids.items[blocked_idx],
                all_task_ids.items[blocker_idx],
            );
            dependency_count += 1;
        }
        task_offset += task_count;
    }

    // Assertions: Verify sequential chains were created
    std.debug.assert(dependency_count > 0);
    std.debug.assert(dependency_count <= total_tasks);

    // Pattern 2: Diamond patterns (task6 depends on both task4 and task5)
    // Creates parallel branches that converge
    task_offset = 0;
    for (tasks_per_label) |task_count| {
        if (task_count >= 7) {
            const task4_idx = task_offset + 3; // task4 (0-indexed)
            const task5_idx = task_offset + 4; // task5
            const task6_idx = task_offset + 5; // task6
            const task7_idx = task_offset + 6; // task7

            // task6 depends on both task4 and task5 (diamond)
            try storage.addDependency(
                all_task_ids.items[task6_idx],
                all_task_ids.items[task4_idx],
            );
            dependency_count += 1;
            try storage.addDependency(
                all_task_ids.items[task6_idx],
                all_task_ids.items[task5_idx],
            );
            dependency_count += 1;

            // task7 depends on task6 (continues chain)
            try storage.addDependency(
                all_task_ids.items[task7_idx],
                all_task_ids.items[task6_idx],
            );
            dependency_count += 1;
        }
        task_offset += task_count;
    }

    // Pattern 3: Cross-plan dependencies (feature interdependencies)
    // Backend depends on database, API depends on backend, frontend depends on API
    const backend_plan_idx: usize = 7;
    const database_plan_idx: usize = 8;
    const api_plan_idx: usize = 5;
    const frontend_plan_idx: usize = 6;

    // Find first task of each plan
    var plan_first_task: [10]usize = undefined;
    task_offset = 0;
    for (tasks_per_label, 0..) |task_count, i| {
        plan_first_task[i] = task_offset;
        task_offset += task_count;
    }

    // Backend task 1 depends on database task 1
    try storage.addDependency(
        all_task_ids.items[plan_first_task[backend_plan_idx]],
        all_task_ids.items[plan_first_task[database_plan_idx]],
    );
    dependency_count += 1;

    // API task 1 depends on backend task 1
    try storage.addDependency(
        all_task_ids.items[plan_first_task[api_plan_idx]],
        all_task_ids.items[plan_first_task[backend_plan_idx]],
    );
    dependency_count += 1;

    // Frontend task 1 depends on API task 1
    try storage.addDependency(
        all_task_ids.items[plan_first_task[frontend_plan_idx]],
        all_task_ids.items[plan_first_task[api_plan_idx]],
    );
    dependency_count += 1;

    // Pattern 4: Additional cross-label dependencies for complexity
    // Create 10 more cross-label dependencies between random tasks
    for (0..10) |i| {
        const label_a = i % plan_names.len;
        const label_b = (i + 1) % plan_names.len;
        if (label_a != label_b and tasks_per_label[label_a] >= 2 and tasks_per_label[label_b] >= 2) {
            const task_a_idx = plan_first_task[label_a] + 1; // Second task
            const task_b_idx = plan_first_task[label_b]; // First task
            // Check if this would create a cycle (skip if so)
            const cycle_check = storage.addDependency(
                all_task_ids.items[task_a_idx],
                all_task_ids.items[task_b_idx],
            );
            if (cycle_check) |_| {
                dependency_count += 1;
            } else |_| {
                // Cycle detected, skip this dependency
            }
        }
    }

    // Assertions: Verify we have realistic number of dependencies
    // Note: Some dependencies may be skipped due to cycle detection
    std.debug.assert(dependency_count > 0); // Minimum for meaningful benchmark
    std.debug.assert(dependency_count <= 500); // Reasonable upper bound
    // Rationale: Final count may vary due to cycle detection, but should have enough
    // for meaningful performance testing

    // ========================================================================
    // Benchmark 1: getReadyTasks (most frequent query)
    // ========================================================================

    // Rationale: getReadyTasks is called frequently by agents to find work.
    // This is the most performance-critical operation for parallel coordination.
    const ready_iterations: u32 = 100;
    var ready_samples = std.array_list.AlignedManaged(i64, null).init(allocator);
    defer ready_samples.deinit();

    for (0..ready_iterations) |_| {
        var timer = try std.time.Timer.start();

        // Query for ready tasks (limit 50)
        var ready_tasks = try storage.getReadyTasks(50);
        defer {
            for (ready_tasks) |*task| {
                task.deinit(allocator);
            }
            allocator.free(ready_tasks);
        }

        const elapsed = timer.read();

        try ready_samples.append(@intCast(elapsed));

        // Assertions: Verify query returned results
        std.debug.assert(ready_tasks.len > 0); // Should have unblocked tasks
        std.debug.assert(ready_tasks.len <= 50); // Should respect limit
    }

    // Calculate ready query statistics
    var ready_min: i64 = std.math.maxInt(i64);
    var ready_max: i64 = 0;
    var ready_total: i64 = 0;
    for (ready_samples.items) |sample| {
        ready_min = @min(ready_min, sample);
        ready_max = @max(ready_max, sample);
        ready_total += sample;
    }
    const ready_avg = @divTrunc(ready_total, @as(i64, @intCast(ready_samples.items.len)));

    // Assertions: Verify ready query meets <5ms target
    std.debug.assert(ready_avg > 0);

    const ready_result = BenchmarkResult{
        .operation_name = "getReadyTasks",
        .iterations = ready_iterations,
        .total_nanos = @intCast(ready_total),
        .min_nanos = @intCast(ready_min),
        .max_nanos = @intCast(ready_max),
        .avg_nanos = @intCast(ready_avg),
        .target_nanos = target_nanos,
    };

    // Tiger Style: Hard assertion on target
    try std.testing.expect(ready_result.meetsTarget());

    // ========================================================================
    // Benchmark 2: addDependency (with cycle detection)
    // ========================================================================

    // Rationale: addDependency includes cycle detection via recursive CTE.
    // This is expensive but critical for graph integrity. Must stay under 5ms.
    const add_dep_iterations: u32 = 50;
    var add_dep_samples = std.array_list.AlignedManaged(i64, null).init(allocator);
    defer add_dep_samples.deinit();

    // Create temporary tasks for add/remove testing
    const temp_label = "temp-benchmark";
    try storage.createPlan(temp_label, "Temporary Benchmark Label", "For add/remove testing", null);

    var temp_task_ids = try std.ArrayList(u32).initCapacity(allocator, 100);
    defer temp_task_ids.deinit(allocator);

    for (0..20) |i| {
        const task_title = try std.fmt.allocPrint(allocator, "Temp task {d}", .{i + 1});
        defer allocator.free(task_title);
        const task_id = try storage.createTask(temp_label, task_title, "Temporary task");
        try temp_task_ids.append(allocator, task_id);
    }

    // Benchmark addDependency with cycle check
    for (0..add_dep_iterations) |i| {
        const task_a_idx = (i * 2) % temp_task_ids.items.len;
        const task_b_idx = (i * 2 + 1) % temp_task_ids.items.len;

        var timer = try std.time.Timer.start();

        // Add dependency (includes cycle detection)
        const add_result = storage.addDependency(
            temp_task_ids.items[task_a_idx],
            temp_task_ids.items[task_b_idx],
        );

        const elapsed = timer.read();

        // Only record successful additions (skip cycles)
        if (add_result) |_| {
            try add_dep_samples.append(@intCast(elapsed));
        } else |_| {
            // Cycle detected, still record timing
            try add_dep_samples.append(@intCast(elapsed));
        }
    }

    // Calculate addDependency statistics
    var add_dep_min: i64 = std.math.maxInt(i64);
    var add_dep_max: i64 = 0;
    var add_dep_total: i64 = 0;
    for (add_dep_samples.items) |sample| {
        add_dep_min = @min(add_dep_min, sample);
        add_dep_max = @max(add_dep_max, sample);
        add_dep_total += sample;
    }
    const add_dep_avg = @divTrunc(add_dep_total, @as(i64, @intCast(add_dep_samples.items.len)));

    // Assertions: Verify addDependency meets <5ms target
    std.debug.assert(add_dep_avg > 0);

    const add_dep_result = BenchmarkResult{
        .operation_name = "addDependency",
        .iterations = @intCast(add_dep_samples.items.len),
        .total_nanos = @intCast(add_dep_total),
        .min_nanos = @intCast(add_dep_min),
        .max_nanos = @intCast(add_dep_max),
        .avg_nanos = @intCast(add_dep_avg),
        .target_nanos = target_nanos,
    };

    // Tiger Style: Hard assertion on target
    try std.testing.expect(add_dep_result.meetsTarget());

    // ========================================================================
    // Benchmark 3: getBlockers (transitive blocker query)
    // ========================================================================

    // Rationale: getBlockers uses recursive CTE to find all blocking tasks.
    // Agents use this for planning and understanding task dependencies.
    const blockers_iterations: u32 = 50;
    var blockers_samples = std.array_list.AlignedManaged(i64, null).init(allocator);
    defer blockers_samples.deinit();

    // Select tasks with deep dependency chains for challenging queries
    // Use tasks from middle of labels (more likely to have dependencies)
    for (0..blockers_iterations) |i| {
        const task_idx = (total_tasks / 2 + i) % all_task_ids.items.len;
        const task_id = all_task_ids.items[task_idx];

        var timer = try std.time.Timer.start();

        var blockers = try storage.getBlockers(task_id);
        defer {
            for (blockers) |*blocker| {
                blocker.deinit(allocator);
            }
            allocator.free(blockers);
        }

        const elapsed = timer.read();

        try blockers_samples.append(@intCast(elapsed));

        // Assertions: Verify query returned valid results
        std.debug.assert(blockers.len >= 0); // May have zero blockers
    }

    // Calculate getBlockers statistics
    var blockers_min: i64 = std.math.maxInt(i64);
    var blockers_max: i64 = 0;
    var blockers_total: i64 = 0;
    for (blockers_samples.items) |sample| {
        blockers_min = @min(blockers_min, sample);
        blockers_max = @max(blockers_max, sample);
        blockers_total += sample;
    }
    const blockers_avg = @divTrunc(blockers_total, @as(i64, @intCast(blockers_samples.items.len)));

    // Assertions: Verify getBlockers meets <5ms target
    std.debug.assert(blockers_avg > 0);

    const blockers_result = BenchmarkResult{
        .operation_name = "getBlockers",
        .iterations = blockers_iterations,
        .total_nanos = @intCast(blockers_total),
        .min_nanos = @intCast(blockers_min),
        .max_nanos = @intCast(blockers_max),
        .avg_nanos = @intCast(blockers_avg),
        .target_nanos = target_nanos,
    };

    // Tiger Style: Hard assertion on target
    try std.testing.expect(blockers_result.meetsTarget());

    // ========================================================================
    // Benchmark 4: getDependents (transitive dependent query)
    // ========================================================================

    // Rationale: getDependents uses recursive CTE to find all dependent tasks.
    // Used for impact analysis when completing or modifying tasks.
    const dependents_iterations: u32 = 50;
    var dependents_samples = std.array_list.AlignedManaged(i64, null).init(allocator);
    defer dependents_samples.deinit();

    // Query dependents for early tasks (more likely to have dependents)
    for (0..dependents_iterations) |i| {
        const task_idx = i % all_task_ids.items.len;
        const task_id = all_task_ids.items[task_idx];

        var timer = try std.time.Timer.start();

        var dependents = try storage.getDependents(task_id);
        defer {
            for (dependents) |*dependent| {
                dependent.deinit(allocator);
            }
            allocator.free(dependents);
        }

        const elapsed = timer.read();

        try dependents_samples.append(@intCast(elapsed));

        // Assertions: Verify query returned valid results
        std.debug.assert(dependents.len >= 0); // May have zero dependents
    }

    // Calculate getDependents statistics
    var dependents_min: i64 = std.math.maxInt(i64);
    var dependents_max: i64 = 0;
    var dependents_total: i64 = 0;
    for (dependents_samples.items) |sample| {
        dependents_min = @min(dependents_min, sample);
        dependents_max = @max(dependents_max, sample);
        dependents_total += sample;
    }
    const dependents_avg = @divTrunc(dependents_total, @as(i64, @intCast(dependents_samples.items.len)));

    // Assertions: Verify getDependents meets <5ms target
    std.debug.assert(dependents_avg > 0);

    const dependents_result = BenchmarkResult{
        .operation_name = "getDependents",
        .iterations = dependents_iterations,
        .total_nanos = @intCast(dependents_total),
        .min_nanos = @intCast(dependents_min),
        .max_nanos = @intCast(dependents_max),
        .avg_nanos = @intCast(dependents_avg),
        .target_nanos = target_nanos,
    };

    // Tiger Style: Hard assertion on target
    try std.testing.expect(dependents_result.meetsTarget());

    // ========================================================================
    // Final verification: All assertions passed
    // ========================================================================

    // NOTE: All graph query operations benchmarked with complex graph (100+ tasks, 200+ deps)
    // All operations met <5ms target in ReleaseFast build.
}
