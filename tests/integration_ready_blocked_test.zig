//! Integration tests for ready and blocked task queries.
//!
//! Covers: Ready task discovery (unblocked work), blocked task identification
//! with blocker counts, and state transitions as dependencies complete.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const storage = guerilla_graph.storage;
const types = guerilla_graph.types;
const test_utils = @import("test_utils.zig");

// Import test utilities
const getTemporaryDatabasePath = test_utils.getTemporaryDatabasePath;
const cleanupDatabaseFile = test_utils.cleanupDatabaseFile;

// ============================================================================
// Integration Test: Ready and Blocked Task Queries
// ============================================================================

test "integration: ready/blocked - initial state with dependencies" {
    // Rationale: Test initial ready/blocked state with dependency graph.
    // Validates that ready query returns only tasks with no incomplete dependencies,
    // and that independent tasks are always ready.
    //
    // Test graph structure:
    //   A (no dependencies) -> ready initially
    //   B blocks_on A -> blocked initially
    //   C blocks_on A -> blocked initially
    //   D blocks_on B and C -> blocked initially
    //   E (no dependencies) -> ready always (independent)
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const database_path = try getTemporaryDatabasePath(allocator, "ready_initial");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(io, database_path);

    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Create plan and tasks
    try test_storage.createPlan("queries", "Query Testing", "Test ready/blocked queries", null);
    const task_a: u32 = try test_storage.createTask("queries", "Task A", "Foundation task");
    const task_b: u32 = try test_storage.createTask("queries", "Task B", "Depends on A");
    const task_c: u32 = try test_storage.createTask("queries", "Task C", "Depends on A");
    const task_d: u32 = try test_storage.createTask("queries", "Task D", "Depends on B and C");
    const task_e: u32 = try test_storage.createTask("queries", "Task E", "Independent task");

    // Create dependency graph: B->A, C->A, D->B, D->C
    try test_storage.addDependency(task_b, task_a);
    try test_storage.addDependency(task_c, task_a);
    try test_storage.addDependency(task_d, task_b);
    try test_storage.addDependency(task_d, task_c);

    // Query ready tasks - expect A and E (no blockers)
    var ready_tasks = try test_storage.getReadyTasks(100);
    defer {
        for (ready_tasks) |*task| task.deinit(allocator);
        allocator.free(ready_tasks);
    }

    try std.testing.expectEqual(@as(usize, 2), ready_tasks.len);

    // Verify A and E are ready with correct status
    var found_a = false;
    var found_e = false;
    for (ready_tasks) |task| {
        if (task.id == task_a) {
            found_a = true;
            try std.testing.expectEqual(types.TaskStatus.open, task.status);
        } else if (task.id == task_e) {
            found_e = true;
            try std.testing.expectEqual(types.TaskStatus.open, task.status);
        }
    }
    try std.testing.expect(found_a);
    try std.testing.expect(found_e);
}

test "integration: ready/blocked - blocker counts" {
    // Rationale: Test blocked query returns correct tasks with accurate blocker counts.
    // Validates that tasks are ordered by blocker_count DESC for bottleneck identification.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const database_path = try getTemporaryDatabasePath(allocator, "blocked_counts");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(io, database_path);

    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Create plan and tasks
    try test_storage.createPlan("queries", "Query Testing", "Test blocker counts", null);
    const task_a: u32 = try test_storage.createTask("queries", "Task A", "Foundation task");
    const task_b: u32 = try test_storage.createTask("queries", "Task B", "Depends on A");
    const task_c: u32 = try test_storage.createTask("queries", "Task C", "Depends on A");
    const task_d: u32 = try test_storage.createTask("queries", "Task D", "Depends on B and C");
    _ = try test_storage.createTask("queries", "Task E", "Independent task");

    // Create dependency graph
    try test_storage.addDependency(task_b, task_a);
    try test_storage.addDependency(task_c, task_a);
    try test_storage.addDependency(task_d, task_b);
    try test_storage.addDependency(task_d, task_c);

    // Query blocked tasks - expect B, C, D
    var result = try test_storage.getBlockedTasks();
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), result.tasks.len);
    try std.testing.expectEqual(@as(usize, 3), result.blocker_counts.len);

    // Verify D comes first (most blocked with 2 direct blockers)
    try std.testing.expectEqual(task_d, result.tasks[0].id);
    try std.testing.expectEqual(@as(u32, 2), result.blocker_counts[0]);

    // Verify B, C, D all present with correct status
    var found_b = false;
    var found_c = false;
    var found_d = false;
    for (result.tasks) |task| {
        try std.testing.expectEqual(types.TaskStatus.open, task.status);
        if (task.id == task_b) found_b = true;
        if (task.id == task_c) found_c = true;
        if (task.id == task_d) found_d = true;
    }
    try std.testing.expect(found_b);
    try std.testing.expect(found_c);
    try std.testing.expect(found_d);
}

test "integration: ready/blocked - complete A transitions B and C to ready" {
    // Rationale: Test that completing a task unblocks its dependents.
    // Validates state transitions from blocked to ready as dependencies complete.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const database_path = try getTemporaryDatabasePath(allocator, "complete_a");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(io, database_path);

    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Create plan and tasks
    try test_storage.createPlan("queries", "Query Testing", "Test unblocking transitions", null);
    const task_a: u32 = try test_storage.createTask("queries", "Task A", "Foundation task");
    const task_b: u32 = try test_storage.createTask("queries", "Task B", "Depends on A");
    const task_c: u32 = try test_storage.createTask("queries", "Task C", "Depends on A");
    const task_d: u32 = try test_storage.createTask("queries", "Task D", "Depends on B and C");
    const task_e: u32 = try test_storage.createTask("queries", "Task E", "Independent task");

    // Create dependency graph
    try test_storage.addDependency(task_b, task_a);
    try test_storage.addDependency(task_c, task_a);
    try test_storage.addDependency(task_d, task_b);
    try test_storage.addDependency(task_d, task_c);

    // Complete task A
    try test_storage.startTask(task_a);
    try test_storage.completeTask(task_a);

    // Query ready tasks - expect B, C, E (A completed, D still blocked)
    var ready_tasks = try test_storage.getReadyTasks(100);
    defer {
        for (ready_tasks) |*task| task.deinit(allocator);
        allocator.free(ready_tasks);
    }

    try std.testing.expectEqual(@as(usize, 3), ready_tasks.len);

    // Verify B, C, E are ready
    var found_b = false;
    var found_c = false;
    var found_e = false;
    for (ready_tasks) |task| {
        if (task.id == task_b) found_b = true;
        if (task.id == task_c) found_c = true;
        if (task.id == task_e) found_e = true;
    }
    try std.testing.expect(found_b);
    try std.testing.expect(found_c);
    try std.testing.expect(found_e);

    // Query blocked tasks - expect only D (still waiting for B and C)
    var blocked_result = try test_storage.getBlockedTasks();
    defer blocked_result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), blocked_result.tasks.len);
    try std.testing.expectEqual(task_d, blocked_result.tasks[0].id);
    try std.testing.expectEqual(@as(u32, 2), blocked_result.blocker_counts[0]);
}

test "integration: ready/blocked - complete B and C transitions D to ready" {
    // Rationale: Test that completing multiple blockers unblocks downstream tasks.
    // Validates that tasks with multiple dependencies only become ready when all complete.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const database_path = try getTemporaryDatabasePath(allocator, "complete_b_c");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(io, database_path);

    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Create plan and tasks
    try test_storage.createPlan("queries", "Query Testing", "Test multiple blocker completion", null);
    const task_a: u32 = try test_storage.createTask("queries", "Task A", "Foundation task");
    const task_b: u32 = try test_storage.createTask("queries", "Task B", "Depends on A");
    const task_c: u32 = try test_storage.createTask("queries", "Task C", "Depends on A");
    const task_d: u32 = try test_storage.createTask("queries", "Task D", "Depends on B and C");
    const task_e: u32 = try test_storage.createTask("queries", "Task E", "Independent task");

    // Create dependency graph and complete A
    try test_storage.addDependency(task_b, task_a);
    try test_storage.addDependency(task_c, task_a);
    try test_storage.addDependency(task_d, task_b);
    try test_storage.addDependency(task_d, task_c);
    try test_storage.startTask(task_a);
    try test_storage.completeTask(task_a);

    // Complete task B (D still blocked by C)
    try test_storage.startTask(task_b);
    try test_storage.completeTask(task_b);

    // Query ready tasks - expect C, E (D still blocked by C)
    var ready_after_b = try test_storage.getReadyTasks(100);
    defer {
        for (ready_after_b) |*task| task.deinit(allocator);
        allocator.free(ready_after_b);
    }
    try std.testing.expectEqual(@as(usize, 2), ready_after_b.len);

    // Complete task C (D should now become ready)
    try test_storage.startTask(task_c);
    try test_storage.completeTask(task_c);

    // Query ready tasks - expect D, E
    var ready_after_c = try test_storage.getReadyTasks(100);
    defer {
        for (ready_after_c) |*task| task.deinit(allocator);
        allocator.free(ready_after_c);
    }

    try std.testing.expectEqual(@as(usize, 2), ready_after_c.len);

    var found_d = false;
    var found_e = false;
    for (ready_after_c) |task| {
        if (task.id == task_d) found_d = true;
        if (task.id == task_e) found_e = true;
    }
    try std.testing.expect(found_d);
    try std.testing.expect(found_e);

    // Query blocked tasks - expect none
    var blocked_result = try test_storage.getBlockedTasks();
    defer blocked_result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), blocked_result.tasks.len);
}

test "integration: ready/blocked - all complete returns empty" {
    // Rationale: Test that ready/blocked queries return empty when all tasks complete.
    // Also validates that ready query respects limit parameter correctly.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const database_path = try getTemporaryDatabasePath(allocator, "all_complete");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(io, database_path);

    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Create plan and tasks
    try test_storage.createPlan("queries", "Query Testing", "Test completion state", null);
    const task_a: u32 = try test_storage.createTask("queries", "Task A", "Foundation task");
    const task_b: u32 = try test_storage.createTask("queries", "Task B", "Depends on A");
    const task_c: u32 = try test_storage.createTask("queries", "Task C", "Depends on A");
    const task_d: u32 = try test_storage.createTask("queries", "Task D", "Depends on B and C");
    const task_e: u32 = try test_storage.createTask("queries", "Task E", "Independent task");

    // Create dependency graph
    try test_storage.addDependency(task_b, task_a);
    try test_storage.addDependency(task_c, task_a);
    try test_storage.addDependency(task_d, task_b);
    try test_storage.addDependency(task_d, task_c);

    // Complete all tasks
    try test_storage.startTask(task_a);
    try test_storage.completeTask(task_a);
    try test_storage.startTask(task_b);
    try test_storage.completeTask(task_b);
    try test_storage.startTask(task_c);
    try test_storage.completeTask(task_c);
    try test_storage.startTask(task_d);
    try test_storage.completeTask(task_d);
    try test_storage.startTask(task_e);
    try test_storage.completeTask(task_e);

    // Query ready tasks - expect empty
    var ready_final = try test_storage.getReadyTasks(100);
    defer {
        for (ready_final) |*task| task.deinit(allocator);
        allocator.free(ready_final);
    }
    try std.testing.expectEqual(@as(usize, 0), ready_final.len);

    // Query blocked tasks - expect empty
    var blocked_final = try test_storage.getBlockedTasks();
    defer blocked_final.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), blocked_final.tasks.len);

    // Test limit parameter: Create two new tasks and query with limit=1
    _ = try test_storage.createTask("queries", "Task F", "Test limit parameter 1");
    _ = try test_storage.createTask("queries", "Task G", "Test limit parameter 2");

    var ready_with_limit = try test_storage.getReadyTasks(1);
    defer {
        for (ready_with_limit) |*task| task.deinit(allocator);
        allocator.free(ready_with_limit);
    }
    try std.testing.expectEqual(@as(usize, 1), ready_with_limit.len);
}
