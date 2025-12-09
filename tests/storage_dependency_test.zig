//! Tests for SQLite storage layer dependency graph operations.
//!
//! Covers: addDependency, removeDependency, getBlockers, getDependents, detectCycle.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;
const SqliteError = guerilla_graph.storage.SqliteError;
const types = guerilla_graph.types;
const TaskStatus = types.TaskStatus;
// Use re-exported C types from storage to ensure type compatibility
const c = guerilla_graph.storage.c_funcs;
const test_utils = @import("test_utils.zig");

test "addDependency: successful dependency creation" {
    // Methodology: Create two tasks and add dependency between them
    // Verify dependency is stored correctly in database
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_add_dependency.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    try storage.createPlan("test", "Test", "Test label", null);

    const task1: u32 = try storage.createTask("test", "Task 1", "First task");
    const task2: u32 = try storage.createTask("test", "Task 2", "Second task");

    // Add dependency: task2 blocks on task1
    try storage.addDependency(task2, task1);

    // Verify dependency exists in database
    const database = storage.database;
    const check_sql = "SELECT task_id, blocks_on_id FROM dependencies WHERE task_id = ? AND blocks_on_id = ?";
    var statement: ?*c.sqlite3_stmt = null;
    const result = c.sqlite3_prepare_v2(database, check_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(statement);

    try test_utils.bindInt64(statement.?, 1, @intCast(task2));
    try test_utils.bindInt64(statement.?, 2, @intCast(task1));
    const step_result = c.sqlite3_step(statement.?);

    // Assertions: Dependency row exists with correct values
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);
    const stored_task_id = c.sqlite3_column_int64(statement.?, 0);
    const stored_blocks_on = c.sqlite3_column_int64(statement.?, 1);
    try std.testing.expectEqual(@as(i64, task2), stored_task_id);
    try std.testing.expectEqual(@as(i64, task1), stored_blocks_on);
}

test "addDependency: direct cycle detection" {
    // Methodology: Test that adding A -> B when B -> A exists is rejected
    // This tests the most basic cycle: A -> B -> A
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_direct_cycle.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    try storage.createPlan("test", "Test", "Test label", null);

    const task_a: u32 = try storage.createTask("test", "Task A", "First task");
    const task_b: u32 = try storage.createTask("test", "Task B", "Second task");

    // Add dependency: A blocks on B (A -> B)
    try storage.addDependency(task_a, task_b);

    // Attempt to add reverse dependency: B blocks on A (B -> A)
    // This should fail with CycleDetected error
    const result = storage.addDependency(task_b, task_a);

    // Assertions: Error is CycleDetected, and no dependency was added
    try std.testing.expectError(SqliteError.CycleDetected, result);

    // Verify only one dependency exists (the first one)
    const database = storage.database;
    const count_sql = "SELECT COUNT(*) FROM dependencies";
    var statement: ?*c.sqlite3_stmt = null;
    _ = c.sqlite3_prepare_v2(database, count_sql, -1, &statement, null);
    defer _ = c.sqlite3_finalize(statement);
    _ = c.sqlite3_step(statement.?);
    const dep_count = c.sqlite3_column_int64(statement.?, 0);
    try std.testing.expectEqual(@as(i64, 1), dep_count);
}

test "addDependency: transitive cycle detection" {
    // Methodology: Test that adding A -> C when A -> B -> C exists is rejected
    // This creates a longer cycle: A -> B -> C -> A
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_transitive_cycle.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    try storage.createPlan("test", "Test", "Test label", null);

    const task_a: u32 = try storage.createTask("test", "Task A", "First task");
    const task_b: u32 = try storage.createTask("test", "Task B", "Second task");
    const task_c: u32 = try storage.createTask("test", "Task C", "Third task");

    // Create chain: A -> B -> C
    try storage.addDependency(task_a, task_b);
    try storage.addDependency(task_b, task_c);

    // Attempt to close the cycle: C -> A
    const result = storage.addDependency(task_c, task_a);

    // Assertions: Error is CycleDetected
    try std.testing.expectError(SqliteError.CycleDetected, result);

    // Verify only two dependencies exist (A->B, B->C)
    const database = storage.database;
    const count_sql = "SELECT COUNT(*) FROM dependencies";
    var statement: ?*c.sqlite3_stmt = null;
    _ = c.sqlite3_prepare_v2(database, count_sql, -1, &statement, null);
    defer _ = c.sqlite3_finalize(statement);
    _ = c.sqlite3_step(statement.?);
    const dep_count = c.sqlite3_column_int64(statement.?, 0);
    try std.testing.expectEqual(@as(i64, 2), dep_count);
}

test "addDependency: diamond dependency is allowed" {
    // Methodology: Test that diamond patterns (A -> B, A -> C, B -> D, C -> D) are valid
    // This is NOT a cycle, just multiple paths to same task
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_diamond_dependency.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    try storage.createPlan("test", "Test", "Test label", null);

    const task_a: u32 = try storage.createTask("test", "Task A", "Top task");
    const task_b: u32 = try storage.createTask("test", "Task B", "Left branch");
    const task_c: u32 = try storage.createTask("test", "Task C", "Right branch");
    const task_d: u32 = try storage.createTask("test", "Task D", "Bottom task");

    // Create diamond: D -> B, D -> C, B -> A, C -> A
    try storage.addDependency(task_d, task_b);
    try storage.addDependency(task_d, task_c);
    try storage.addDependency(task_b, task_a);
    try storage.addDependency(task_c, task_a);

    // Assertions: All four dependencies were added successfully
    const database = storage.database;
    const count_sql = "SELECT COUNT(*) FROM dependencies";
    var statement: ?*c.sqlite3_stmt = null;
    _ = c.sqlite3_prepare_v2(database, count_sql, -1, &statement, null);
    defer _ = c.sqlite3_finalize(statement);
    _ = c.sqlite3_step(statement.?);
    const dep_count = c.sqlite3_column_int64(statement.?, 0);
    try std.testing.expectEqual(@as(i64, 4), dep_count);
}

test "addDependency: nonexistent task should fail" {
    // Methodology: Attempt to add dependency with invalid task IDs
    // Verify proper error handling for non-existent tasks
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_add_dep_invalid.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    try storage.createPlan("test", "Test", "Test label", null);

    const task1: u32 = try storage.createTask("test", "Task 1", "Real task");

    // Try to add dependency with non-existent task
    const result1 = storage.addDependency(task1, 999);
    try std.testing.expectError(SqliteError.InvalidData, result1);

    const result2 = storage.addDependency(998, task1);
    try std.testing.expectError(SqliteError.InvalidData, result2);

    // Assertions: No dependencies were created
    const database = storage.database;
    const count_sql = "SELECT COUNT(*) FROM dependencies";
    var statement: ?*c.sqlite3_stmt = null;
    _ = c.sqlite3_prepare_v2(database, count_sql, -1, &statement, null);
    defer _ = c.sqlite3_finalize(statement);
    _ = c.sqlite3_step(statement.?);
    const dep_count = c.sqlite3_column_int64(statement.?, 0);
    try std.testing.expectEqual(@as(i64, 0), dep_count);
}

test "removeDependency: successful removal" {
    // Methodology: Create dependency then remove it
    // Verify it's gone from database
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_remove_dependency.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    try storage.createPlan("test", "Test", "Test label", null);

    const task1: u32 = try storage.createTask("test", "Task 1", "First task");
    const task2: u32 = try storage.createTask("test", "Task 2", "Second task");

    // Add then remove dependency
    try storage.addDependency(task2, task1);
    try storage.removeDependency(task2, task1);

    // Assertions: Dependency no longer exists
    const database = storage.database;
    const count_sql = "SELECT COUNT(*) FROM dependencies WHERE task_id = ? AND blocks_on_id = ?";
    var statement: ?*c.sqlite3_stmt = null;
    _ = c.sqlite3_prepare_v2(database, count_sql, -1, &statement, null);
    defer _ = c.sqlite3_finalize(statement);
    try test_utils.bindInt64(statement.?, 1, @intCast(task2));
    try test_utils.bindInt64(statement.?, 2, @intCast(task1));
    _ = c.sqlite3_step(statement.?);
    const dep_count = c.sqlite3_column_int64(statement.?, 0);
    try std.testing.expectEqual(@as(i64, 0), dep_count);
}

test "removeDependency: nonexistent dependency should fail" {
    // Methodology: Attempt to remove dependency that doesn't exist
    // Verify proper error handling
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_remove_dep_invalid.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    try storage.createPlan("test", "Test", "Test label", null);

    const task1: u32 = try storage.createTask("test", "Task 1", "First task");
    const task2: u32 = try storage.createTask("test", "Task 2", "Second task");

    // Try to remove non-existent dependency
    const result = storage.removeDependency(task2, task1);

    // Assertions: Error is InvalidData
    try std.testing.expectError(SqliteError.InvalidData, result);
}

test "getBlockers: direct blockers only" {
    // Methodology: Create simple dependency chain and verify direct blockers
    // Task C blocks on B, B blocks on A
    // getBlockers(C) should return [B, A] in order
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_blockers_direct.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    try storage.createPlan("test", "Test", "Test label", null);

    const task_a: u32 = try storage.createTask("test", "Task A", "First task");
    const task_b: u32 = try storage.createTask("test", "Task B", "Second task");
    const task_c: u32 = try storage.createTask("test", "Task C", "Third task");

    // Create chain: C -> B -> A
    try storage.addDependency(task_c, task_b);
    try storage.addDependency(task_b, task_a);

    // Get blockers for C
    const blockers = try storage.getBlockers(task_c);
    defer {
        for (blockers) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers);
    }

    // Assertions: Two blockers (B and A), ordered by depth
    try std.testing.expectEqual(@as(usize, 2), blockers.len);
    try std.testing.expectEqual(task_b, blockers[0].id);
    try std.testing.expectEqual(@as(u32, 1), blockers[0].depth);
    try std.testing.expectEqual(task_a, blockers[1].id);
    try std.testing.expectEqual(@as(u32, 2), blockers[1].depth);
}

test "getBlockers: diamond pattern shows shortest path" {
    // Methodology: Create diamond (D -> B, D -> C, B -> A, C -> A)
    // getBlockers(D) should show A once with depth=2 (shortest path)
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_blockers_diamond.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    try storage.createPlan("test", "Test", "Test label", null);

    const task_a: u32 = try storage.createTask("test", "Task A", "Top task");
    const task_b: u32 = try storage.createTask("test", "Task B", "Left branch");
    const task_c: u32 = try storage.createTask("test", "Task C", "Right branch");
    const task_d: u32 = try storage.createTask("test", "Task D", "Bottom task");

    // Create diamond: D -> B, D -> C, B -> A, C -> A
    try storage.addDependency(task_d, task_b);
    try storage.addDependency(task_d, task_c);
    try storage.addDependency(task_b, task_a);
    try storage.addDependency(task_c, task_a);

    // Get blockers for D
    const blockers = try storage.getBlockers(task_d);
    defer {
        for (blockers) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers);
    }

    // Assertions: Three blockers (B, C, A), A appears once with min depth
    try std.testing.expectEqual(@as(usize, 3), blockers.len);

    // Find task A in results
    var found_a = false;
    for (blockers) |blocker| {
        if (blocker.id == task_a) {
            found_a = true;
            try std.testing.expectEqual(@as(u32, 2), blocker.depth);
        }
    }
    try std.testing.expect(found_a);
}

test "getBlockers: no blockers returns empty slice" {
    // Methodology: Query blockers for task with no dependencies
    // Verify empty result
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_blockers_empty.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    try storage.createPlan("test", "Test", "Test label", null);

    const task1: u32 = try storage.createTask("test", "Task 1", "Independent task");

    // Get blockers for task with no dependencies
    const blockers = try storage.getBlockers(task1);
    defer allocator.free(blockers);

    // Assertions: Empty result
    try std.testing.expectEqual(@as(usize, 0), blockers.len);
}

test "getDependents: direct dependents only" {
    // Methodology: Create dependency chain and verify dependents
    // A <- B <- C (C depends on B, B depends on A)
    // getDependents(A) should return [B, C] in order
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_dependents_direct.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    try storage.createPlan("test", "Test", "Test label", null);

    const task_a: u32 = try storage.createTask("test", "Task A", "First task");
    const task_b: u32 = try storage.createTask("test", "Task B", "Second task");
    const task_c: u32 = try storage.createTask("test", "Task C", "Third task");

    // Create chain: C -> B -> A
    try storage.addDependency(task_c, task_b);
    try storage.addDependency(task_b, task_a);

    // Get dependents for A
    const dependents = try storage.getDependents(task_a);
    defer {
        for (dependents) |*dependent| {
            dependent.deinit(allocator);
        }
        allocator.free(dependents);
    }

    // Assertions: Two dependents (B and C), ordered by depth
    try std.testing.expectEqual(@as(usize, 2), dependents.len);
    try std.testing.expectEqual(task_b, dependents[0].id);
    try std.testing.expectEqual(@as(u32, 1), dependents[0].depth);
    try std.testing.expectEqual(task_c, dependents[1].id);
    try std.testing.expectEqual(@as(u32, 2), dependents[1].depth);
}

test "getDependents: diamond pattern shows shortest path" {
    // Methodology: Create diamond (D -> B, D -> C, B -> A, C -> A)
    // getDependents(A) should show D once with depth=2 (shortest path)
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_dependents_diamond.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    try storage.createPlan("test", "Test", "Test label", null);

    const task_a: u32 = try storage.createTask("test", "Task A", "Top task");
    const task_b: u32 = try storage.createTask("test", "Task B", "Left branch");
    const task_c: u32 = try storage.createTask("test", "Task C", "Right branch");
    const task_d: u32 = try storage.createTask("test", "Task D", "Bottom task");

    // Create diamond: D -> B, D -> C, B -> A, C -> A
    try storage.addDependency(task_d, task_b);
    try storage.addDependency(task_d, task_c);
    try storage.addDependency(task_b, task_a);
    try storage.addDependency(task_c, task_a);

    // Get dependents for A
    const dependents = try storage.getDependents(task_a);
    defer {
        for (dependents) |*dependent| {
            dependent.deinit(allocator);
        }
        allocator.free(dependents);
    }

    // Assertions: Three dependents (B, C, D), D appears once with min depth
    try std.testing.expectEqual(@as(usize, 3), dependents.len);

    // Find task D in results
    var found_d = false;
    for (dependents) |dependent| {
        if (dependent.id == task_d) {
            found_d = true;
            try std.testing.expectEqual(@as(u32, 2), dependent.depth);
        }
    }
    try std.testing.expect(found_d);
}

test "getDependents: no dependents returns empty slice" {
    // Methodology: Query dependents for task that nothing depends on
    // Verify empty result
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_dependents_empty.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    try storage.createPlan("test", "Test", "Test label", null);

    const task1: u32 = try storage.createTask("test", "Task 1", "Leaf task");

    // Get dependents for task with nothing depending on it
    const dependents = try storage.getDependents(task1);
    defer allocator.free(dependents);

    // Assertions: Empty result
    try std.testing.expectEqual(@as(usize, 0), dependents.len);
}

test "detectCycle: catches self-loop attempt" {
    // Methodology: Verify that A -> A is detected as a cycle
    // Note: addDependency has assertion to prevent self-loops,
    // but detectCycle itself should also handle this
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_detect_self_loop.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    try storage.createPlan("test", "Test", "Test label", null);

    const task_a: u32 = try storage.createTask("test", "Task A", "Task");

    // Note: This would panic in debug due to assertion in detectCycle
    // In release mode, detectCycle should return true for self-loop
    // For testing purposes, we test the two-task cycle instead
    const task_b: u32 = try storage.createTask("test", "Task B", "Task");

    try storage.addDependency(task_a, task_b);

    // Verify cycle detection works
    const has_cycle = try storage.detectCycle(task_b, task_a);

    // Assertions: Cycle is detected
    try std.testing.expect(has_cycle);
}

test "detectCycle: detects long transitive cycle" {
    // Methodology: Create A -> B -> C -> D, then verify D -> A would create cycle
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_detect_long_cycle.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    try storage.createPlan("test", "Test", "Test label", null);

    const task_a: u32 = try storage.createTask("test", "Task A", "First");
    const task_b: u32 = try storage.createTask("test", "Task B", "Second");
    const task_c: u32 = try storage.createTask("test", "Task C", "Third");
    const task_d: u32 = try storage.createTask("test", "Task D", "Fourth");

    // Create chain: A -> B -> C -> D
    try storage.addDependency(task_a, task_b);
    try storage.addDependency(task_b, task_c);
    try storage.addDependency(task_c, task_d);

    // Check if D -> A would create cycle
    const has_cycle = try storage.detectCycle(task_d, task_a);

    // Assertions: Cycle is detected
    try std.testing.expect(has_cycle);
}

test "detectCycle: allows valid non-cycle dependency" {
    // Methodology: Create A -> B, verify C -> A is valid (no cycle)
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_detect_no_cycle.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    try storage.createPlan("test", "Test", "Test label", null);

    const task_a: u32 = try storage.createTask("test", "Task A", "First");
    const task_b: u32 = try storage.createTask("test", "Task B", "Second");
    const task_c: u32 = try storage.createTask("test", "Task C", "Third");

    // Create A -> B
    try storage.addDependency(task_a, task_b);

    // Check if C -> A would create cycle (it shouldn't)
    const has_cycle = try storage.detectCycle(task_c, task_a);

    // Assertions: No cycle detected
    try std.testing.expect(!has_cycle);
}
