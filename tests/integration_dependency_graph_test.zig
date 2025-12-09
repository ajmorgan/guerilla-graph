//! Integration tests for dependency graph operations.
//!
//! Covers: Adding dependencies, cycle detection (direct and transitive),
//! blockers/dependents queries, and dependency removal.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const storage = guerilla_graph.storage;
const test_utils = @import("test_utils.zig");

// Import test utilities
const getTemporaryDatabasePath = test_utils.getTemporaryDatabasePath;
const cleanupDatabaseFile = test_utils.cleanupDatabaseFile;

// ============================================================================
// Integration Test: Dependency Graph Operations
// ============================================================================

test "integration: dependency graph - create tasks and add valid deps" {
    // Rationale: Test basic dependency graph construction with diamond pattern.
    // This validates that valid dependencies can be added and queried correctly.
    // Diamond pattern: A is foundation, B and C depend on A, D depends on B and C.
    const allocator = std.testing.allocator;

    const database_path = try getTemporaryDatabasePath(allocator, "graph_valid_deps");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Create plan and tasks for diamond pattern
    try test_storage.createPlan("graph", "Graph Testing", "Dependency graph tests", null);
    const task_a: u32 = try test_storage.createTask("graph", "Task A", "Foundation task");
    const task_b: u32 = try test_storage.createTask("graph", "Task B", "First branch task");
    const task_c: u32 = try test_storage.createTask("graph", "Task C", "Second branch task");
    const task_d: u32 = try test_storage.createTask("graph", "Task D", "Convergence task");

    // Verify all tasks created successfully
    try std.testing.expect(task_a > 0);
    try std.testing.expect(task_b > 0);
    try std.testing.expect(task_c > 0);
    try std.testing.expect(task_d > 0);

    // Add valid dependencies to create diamond pattern
    // B blocks_on A, C blocks_on A, D blocks_on B, D blocks_on C
    try test_storage.addDependency(task_b, task_a);
    try test_storage.addDependency(task_c, task_a);
    try test_storage.addDependency(task_d, task_b);
    try test_storage.addDependency(task_d, task_c);

    // Verify B blocks on A with correct depth
    var blockers_b = try test_storage.getBlockers(task_b);
    defer {
        for (blockers_b) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers_b);
    }
    try std.testing.expectEqual(@as(usize, 1), blockers_b.len);
    try std.testing.expectEqual(task_a, blockers_b[0].id);
    try std.testing.expectEqual(@as(u32, 1), blockers_b[0].depth);

    // Verify C blocks on A with correct depth
    var blockers_c = try test_storage.getBlockers(task_c);
    defer {
        for (blockers_c) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers_c);
    }
    try std.testing.expectEqual(@as(usize, 1), blockers_c.len);
    try std.testing.expectEqual(task_a, blockers_c[0].id);
    try std.testing.expectEqual(@as(u32, 1), blockers_c[0].depth);
}

test "integration: dependency graph - direct cycle detection" {
    // Rationale: Test that direct cycles (A -> B -> A) are detected and prevented.
    // This is critical for maintaining a valid DAG structure.
    const allocator = std.testing.allocator;

    const database_path = try getTemporaryDatabasePath(allocator, "graph_direct_cycle");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Create plan and tasks
    try test_storage.createPlan("graph", "Graph Testing", "Cycle detection tests", null);
    const task_a: u32 = try test_storage.createTask("graph", "Task A", "First task");
    const task_b: u32 = try test_storage.createTask("graph", "Task B", "Second task");

    // Add valid dependency: B blocks_on A
    try test_storage.addDependency(task_b, task_a);

    // Attempt to create direct cycle: A blocks_on B (should fail)
    const direct_cycle_result = test_storage.addDependency(task_a, task_b);

    // Verify cycle was detected and prevented
    try std.testing.expectError(storage.SqliteError.CycleDetected, direct_cycle_result);
}

test "integration: dependency graph - transitive cycle detection" {
    // Rationale: Test that transitive cycles (A -> B -> D -> A) are detected.
    // This validates recursive cycle detection through intermediate nodes.
    const allocator = std.testing.allocator;

    const database_path = try getTemporaryDatabasePath(allocator, "graph_transitive_cycle");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Create plan and tasks for diamond pattern
    try test_storage.createPlan("graph", "Graph Testing", "Transitive cycle tests", null);
    const task_a: u32 = try test_storage.createTask("graph", "Task A", "Foundation task");
    const task_b: u32 = try test_storage.createTask("graph", "Task B", "First branch task");
    const task_c: u32 = try test_storage.createTask("graph", "Task C", "Second branch task");
    const task_d: u32 = try test_storage.createTask("graph", "Task D", "Convergence task");

    // Create diamond pattern: A <- B <- D, A <- C <- D
    try test_storage.addDependency(task_b, task_a);
    try test_storage.addDependency(task_c, task_a);
    try test_storage.addDependency(task_d, task_b);
    try test_storage.addDependency(task_d, task_c);

    // Attempt to create transitive cycle: A blocks_on D (would create A -> B -> D -> A)
    const transitive_cycle_result = test_storage.addDependency(task_a, task_d);

    // Verify transitive cycle was detected and prevented
    try std.testing.expectError(storage.SqliteError.CycleDetected, transitive_cycle_result);
}

test "integration: dependency graph - diamond pattern blockers query" {
    // Rationale: Test blocker queries with complex diamond pattern.
    // Validates transitive blocker resolution and shortest path depth calculation.
    const allocator = std.testing.allocator;

    const database_path = try getTemporaryDatabasePath(allocator, "graph_blockers");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Create plan and tasks for diamond pattern
    try test_storage.createPlan("graph", "Graph Testing", "Blocker query tests", null);
    const task_a: u32 = try test_storage.createTask("graph", "Task A", "Foundation task");
    const task_b: u32 = try test_storage.createTask("graph", "Task B", "First branch task");
    const task_c: u32 = try test_storage.createTask("graph", "Task C", "Second branch task");
    const task_d: u32 = try test_storage.createTask("graph", "Task D", "Convergence task");

    // Create diamond pattern
    try test_storage.addDependency(task_b, task_a);
    try test_storage.addDependency(task_c, task_a);
    try test_storage.addDependency(task_d, task_b);
    try test_storage.addDependency(task_d, task_c);

    // Query blockers for D: should have [B(depth=1), C(depth=1), A(depth=2)]
    var blockers_d = try test_storage.getBlockers(task_d);
    defer {
        for (blockers_d) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers_d);
    }

    // Verify D has 3 blockers total (B, C direct; A transitive)
    try std.testing.expectEqual(@as(usize, 3), blockers_d.len);

    // Verify blocker IDs and depths
    var found_a = false;
    var found_b = false;
    var found_c = false;
    for (blockers_d) |blocker| {
        if (blocker.id == task_a) {
            found_a = true;
            try std.testing.expectEqual(@as(u32, 2), blocker.depth); // Shortest path: D->B->A or D->C->A
        } else if (blocker.id == task_b) {
            found_b = true;
            try std.testing.expectEqual(@as(u32, 1), blocker.depth); // Direct: D->B
        } else if (blocker.id == task_c) {
            found_c = true;
            try std.testing.expectEqual(@as(u32, 1), blocker.depth); // Direct: D->C
        }
    }
    try std.testing.expect(found_a);
    try std.testing.expect(found_b);
    try std.testing.expect(found_c);
}

test "integration: dependency graph - dependents query" {
    // Rationale: Test dependents query (inverse of blockers) with diamond pattern.
    // Validates that we can discover what tasks will be unblocked when a task completes.
    const allocator = std.testing.allocator;

    const database_path = try getTemporaryDatabasePath(allocator, "graph_dependents");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Create plan and tasks for diamond pattern
    try test_storage.createPlan("graph", "Graph Testing", "Dependents query tests", null);
    const task_a: u32 = try test_storage.createTask("graph", "Task A", "Foundation task");
    const task_b: u32 = try test_storage.createTask("graph", "Task B", "First branch task");
    const task_c: u32 = try test_storage.createTask("graph", "Task C", "Second branch task");
    const task_d: u32 = try test_storage.createTask("graph", "Task D", "Convergence task");

    // Create diamond pattern
    try test_storage.addDependency(task_b, task_a);
    try test_storage.addDependency(task_c, task_a);
    try test_storage.addDependency(task_d, task_b);
    try test_storage.addDependency(task_d, task_c);

    // Query dependents for A: should have [B(depth=1), C(depth=1), D(depth=2)]
    var dependents_a = try test_storage.getDependents(task_a);
    defer {
        for (dependents_a) |*dependent| {
            dependent.deinit(allocator);
        }
        allocator.free(dependents_a);
    }

    // Verify A has 3 dependents total (B, C direct; D transitive)
    try std.testing.expectEqual(@as(usize, 3), dependents_a.len);

    // Verify dependent IDs and depths
    var found_dep_b = false;
    var found_dep_c = false;
    var found_dep_d = false;
    for (dependents_a) |dependent| {
        if (dependent.id == task_b) {
            found_dep_b = true;
            try std.testing.expectEqual(@as(u32, 1), dependent.depth); // Direct: A<-B
        } else if (dependent.id == task_c) {
            found_dep_c = true;
            try std.testing.expectEqual(@as(u32, 1), dependent.depth); // Direct: A<-C
        } else if (dependent.id == task_d) {
            found_dep_d = true;
            try std.testing.expectEqual(@as(u32, 2), dependent.depth); // Transitive: A<-B<-D or A<-C<-D
        }
    }
    try std.testing.expect(found_dep_b);
    try std.testing.expect(found_dep_c);
    try std.testing.expect(found_dep_d);
}

test "integration: dependency graph - add remove deps and verify updates" {
    // Rationale: Test dependency removal and graph updates. Validates that
    // removal updates graph structure and enables previously invalid deps.
    const allocator = std.testing.allocator;
    const database_path = try getTemporaryDatabasePath(allocator, "graph_add_remove");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    try test_storage.createPlan("graph", "Graph Testing", "Add/remove dependency tests", null);
    const task_a: u32 = try test_storage.createTask("graph", "Task A", "Foundation task");
    const task_b: u32 = try test_storage.createTask("graph", "Task B", "First branch task");
    const task_c: u32 = try test_storage.createTask("graph", "Task C", "Second branch task");
    const task_d: u32 = try test_storage.createTask("graph", "Task D", "Convergence task");

    // Create diamond pattern: A <- B <- D, A <- C <- D
    try test_storage.addDependency(task_b, task_a);
    try test_storage.addDependency(task_c, task_a);
    try test_storage.addDependency(task_d, task_b);
    try test_storage.addDependency(task_d, task_c);

    // Remove D -> B dependency
    try test_storage.removeDependency(task_d, task_b);

    // Verify D now has 2 blockers (C direct, A transitive through C)
    {
        var blockers_d = try test_storage.getBlockers(task_d);
        defer {
            for (blockers_d) |*b| b.deinit(allocator);
            allocator.free(blockers_d);
        }
        try std.testing.expectEqual(@as(usize, 2), blockers_d.len);
    }

    // Test removing non-existent dependency fails
    const remove_result = test_storage.removeDependency(task_d, task_b);
    try std.testing.expectError(storage.SqliteError.InvalidData, remove_result);

    // With D -> B removed, can now add B -> D (reverse direction)
    try test_storage.addDependency(task_b, task_d);

    // Verify B now blocks on both A and D
    {
        var blockers_b = try test_storage.getBlockers(task_b);
        defer {
            for (blockers_b) |*b| b.deinit(allocator);
            allocator.free(blockers_b);
        }
        try std.testing.expect(blockers_b.len >= 2);
    }

    // Verify graph integrity with dependents query
    {
        var dependents_a = try test_storage.getDependents(task_a);
        defer {
            for (dependents_a) |*d| d.deinit(allocator);
            allocator.free(dependents_a);
        }
        // A should still have dependents (B, C at minimum)
        try std.testing.expect(dependents_a.len >= 2);
    }
}
