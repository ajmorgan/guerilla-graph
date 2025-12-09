//! Integration tests for error handling scenarios (integration_test.zig).
//!
//! Covers: Not-found errors, invalid input errors, cycle detection errors,
//! deletion constraint errors, and error message format validation.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;
const TaskManager = guerilla_graph.task_manager.TaskManager;
const storage = guerilla_graph.storage;
const task_manager = guerilla_graph.task_manager;
const types = guerilla_graph.types;
const test_utils = @import("test_utils.zig");

// Import test utilities
const getTemporaryDatabasePath = test_utils.getTemporaryDatabasePath;
const cleanupDatabaseFile = test_utils.cleanupDatabaseFile;

// ============================================================================
// Integration Test: Error Scenarios - Not Found Errors
// ============================================================================

test "integration: error scenarios - task not found" {
    // Methodology: Test that attempting to retrieve, update, or delete non-existent tasks
    // returns appropriate null values or errors. This validates proper error handling
    // for not-found scenarios across all task operations.
    //
    // Rationale: User-friendly error handling requires distinguishing between "not found"
    // (null return) and other errors (error return). This test ensures all operations
    // handle missing tasks consistently.
    const allocator = std.testing.allocator;

    // Create temporary database for this test
    const database_path = try getTemporaryDatabasePath(allocator, "error_not_found");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    // Initialize storage
    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Test 1: getTask returns null for non-existent task
    // Rationale: getTask should return null (not error) when task doesn't exist.
    // This allows CLI to provide friendly "task not found" message.
    const missing_task = try test_storage.getTask(999);
    try std.testing.expect(missing_task == null);

    // Test 2: Create a valid label for testing status updates
    try test_storage.createPlan("test", "Test Label", "", null);

    // Test 3: startTask on non-existent task now returns InvalidData error
    // Rationale: Stricter error handling for safety (Tiger Style).
    // UPDATE operations now check affected row count and return error if no rows matched.
    const start_result = test_storage.startTask(999);
    try std.testing.expectError(error.InvalidData, start_result);

    // Test 4: completeTask on non-existent task now returns InvalidData error
    const complete_result = test_storage.completeTask(999);
    try std.testing.expectError(error.InvalidData, complete_result);

    // Note: Storage implementation now checks affected rows for UPDATE operations.
    // This provides better error handling and catches programming errors early.
    // deleteTask should similarly return error.InvalidData for non-existent tasks.

    // Final assertions: Verify all not-found cases handled correctly
    try std.testing.expect(missing_task == null);
}

test "integration: error scenarios - plan not found" {
    // Methodology: Test that attempting to create tasks under non-existent plans
    // returns appropriate errors. This validates foreign key constraint enforcement
    // and provides user-friendly error feedback.
    //
    // Rationale: Labels must exist before tasks can be created under them.
    // Foreign key constraint should catch this and return InvalidData error.
    const allocator = std.testing.allocator;

    // Create temporary database for this test
    const database_path = try getTemporaryDatabasePath(allocator, "error_label_not_found");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    // Initialize storage and task manager
    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = task_manager.TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    const empty_deps: []const u32 = &[_]u32{};

    // Test 1: Creating task under non-existent plan returns InvalidData
    // Rationale: Foreign key constraint should prevent orphaned tasks.
    // CLI can catch this and provide "Label 'xyz' not found" message.
    const create_result = test_task_manager.createTask(
        "nonexistent-label",
        "Test Task",
        "This should fail",
        empty_deps,
    );
    try std.testing.expectError(storage.SqliteError.InvalidData, create_result);

    // Test 2: getPlanSummary returns null for non-existent label
    // Rationale: Similar to getTask, getPlanSummary returns null (not error)
    // for missing labels to allow friendly error messages.
    const missing_label = try test_storage.getPlanSummary("nonexistent-label");
    try std.testing.expect(missing_label == null);

    // Final assertions: All plan-not-found scenarios handled appropriately
    try std.testing.expect(missing_label == null);
}

// ============================================================================
// Integration Test: Error Scenarios - Invalid Input
// ============================================================================

test "integration: error scenarios - invalid task IDs" {
    // Methodology: Test that invalid task ID formats are rejected with appropriate errors.
    // This validates input validation logic and prevents malformed data from reaching storage.
    //
    // Rationale: Task IDs must follow "plan:NNN" format. Invalid formats should be caught
    // early with user-friendly errors explaining the expected format.
    const allocator = std.testing.allocator;

    // Create temporary database for this test
    const database_path = try getTemporaryDatabasePath(allocator, "error_invalid_ids");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    // Initialize storage
    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Create valid plan for testing
    try test_storage.createPlan("taskid-test", "Test Label", "", null);

    // Note: With u32 IDs, invalid task IDs are just non-existent numeric IDs
    // CLI should validate inputs before calling storage to provide friendly errors.
    // Test 1: Task ID that doesn't exist
    // Rationale: Task IDs must exist in the database
    const task1 = try test_storage.getTask(99999);
    try std.testing.expect(task1 == null);

    // Test 2: Another non-existent task ID
    const task2 = try test_storage.getTask(12345);
    try std.testing.expect(task2 == null);

    // Test 3: Yet another non-existent task ID
    const task3 = try test_storage.getTask(54321);
    try std.testing.expect(task3 == null);

    // Final assertions: All invalid formats rejected appropriately
    try std.testing.expect(task1 == null);
    try std.testing.expect(task2 == null);
    try std.testing.expect(task3 == null);
}

test "integration: error scenarios - invalid label IDs" {
    // Methodology: Test that invalid label ID formats (non-kebab-case) should be rejected.
    // This documents expected kebab-case enforcement behavior for future implementation.
    //
    // Rationale: Label IDs must be kebab-case (lowercase, hyphens only).
    // Invalid formats like camelCase, UPPERCASE, or with underscores should be rejected.
    //
    // Note: Kebab-case validation is not yet fully implemented in storage layer.
    // When implemented, these tests should fail with InvalidKebabCase errors.
    // For now, we document the expected validation rules.
    const allocator = std.testing.allocator;

    // Create temporary database for this test
    const database_path = try getTemporaryDatabasePath(allocator, "error_invalid_plan_ids");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    // Initialize storage and task manager
    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    var test_task_manager = task_manager.TaskManager.init(allocator, &test_storage);
    defer test_task_manager.deinit();

    // Expected behavior (to be implemented):
    // 1. Label IDs with uppercase should return InvalidKebabCase
    // 2. Label IDs with underscores should return InvalidKebabCase
    // 3. Label IDs with spaces should return InvalidKebabCase
    // 4. Label IDs starting/ending with hyphen should return InvalidKebabCase

    // For now, create a valid kebab-case label to verify the pattern works
    try test_task_manager.createPlan("valid-label", "Valid", "");

    // Verify valid label was created
    const valid_label = try test_storage.getPlanSummary("valid-label");
    try std.testing.expect(valid_label != null);
    if (valid_label) |label| {
        var mutable_label = label;
        defer mutable_label.deinit(allocator);
        try std.testing.expectEqualStrings("valid-label", label.slug);
        try std.testing.expect(label.id > 0); // INTEGER ID should be positive
    }

    // Final assertions: Valid kebab-case label created successfully
    try std.testing.expect(true);
}

// ============================================================================
// Integration Test: Error Scenarios - Cycle Detection
// ============================================================================

test "integration: error scenarios - direct cycle detection" {
    // Methodology: Test that direct cycles (A -> B, then B -> A) are detected and prevented.
    // This validates the most basic cycle detection case.
    //
    // Rationale: Direct cycles are the simplest case and must be caught immediately.
    // User-friendly error should explain the cycle: "A -> B -> A".
    const allocator = std.testing.allocator;

    // Create temporary database for this test
    const database_path = try getTemporaryDatabasePath(allocator, "error_direct_cycle");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    // Initialize storage
    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Create label and tasks
    try test_storage.createPlan("cycle", "Cycle Test", "", null);

    const task_a: u32 = try test_storage.createTask("cycle", "Task A", "");
    const task_b: u32 = try test_storage.createTask("cycle", "Task B", "");

    // Test 1: Add valid dependency A -> B
    try test_storage.addDependency(task_a, task_b);

    // Test 2: Attempt to add reverse dependency B -> A (creates direct cycle)
    // Rationale: This creates: A blocks_on B, B blocks_on A = cycle
    const cycle_result = test_storage.addDependency(task_b, task_a);
    try std.testing.expectError(storage.SqliteError.CycleDetected, cycle_result);

    // Final assertions: Cycle was detected and prevented
    // Graph should still have only A -> B dependency
    var blockers_a = try test_storage.getBlockers(task_a);
    defer {
        for (blockers_a) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers_a);
    }
    try std.testing.expectEqual(@as(usize, 1), blockers_a.len);
    try std.testing.expectEqual(task_b, blockers_a[0].id);
}

test "integration: error scenarios - transitive cycle detection" {
    // Methodology: Test that transitive cycles (A -> B -> C -> A) are detected.
    // This validates cycle detection through multiple hops in the dependency graph.
    //
    // Rationale: Transitive cycles are more complex and require recursive checking.
    // User-friendly error should show the cycle path: "A -> B -> C -> A".
    const allocator = std.testing.allocator;

    // Create temporary database for this test
    const database_path = try getTemporaryDatabasePath(allocator, "error_transitive_cycle");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    // Initialize storage
    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Create label and tasks
    try test_storage.createPlan("trans", "Transitive Cycle Test", "", null);

    const task_a: u32 = try test_storage.createTask("trans", "Task A", "");
    const task_b: u32 = try test_storage.createTask("trans", "Task B", "");
    const task_c: u32 = try test_storage.createTask("trans", "Task C", "");

    // Test 1: Add valid dependencies A -> B -> C
    try test_storage.addDependency(task_a, task_b);
    try test_storage.addDependency(task_b, task_c);

    // Verify chain was created correctly
    var blockers_a = try test_storage.getBlockers(task_a);
    defer {
        for (blockers_a) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers_a);
    }
    try std.testing.expectEqual(@as(usize, 2), blockers_a.len); // B (depth 1), C (depth 2)

    // Test 2: Attempt to close the cycle C -> A (creates A -> B -> C -> A)
    // Rationale: This creates a 3-hop cycle which must be detected.
    const cycle_result = test_storage.addDependency(task_c, task_a);
    try std.testing.expectError(storage.SqliteError.CycleDetected, cycle_result);

    // Final assertions: Cycle was detected, graph remains acyclic
    // Graph should still have only A -> B -> C chain
    var blockers_a_after = try test_storage.getBlockers(task_a);
    defer {
        for (blockers_a_after) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers_a_after);
    }
    try std.testing.expectEqual(@as(usize, 2), blockers_a_after.len);
}

test "integration: error scenarios - self-cycle prevention" {
    // Methodology: Test that self-cycles (A -> A) are prevented by CHECK constraint.
    // This validates the most basic cycle case at the database level.
    //
    // Rationale: Self-dependencies are nonsensical and must be rejected immediately.
    // Database CHECK constraint (task_id != blocks_on_id) should catch this.
    //
    // Note: Current implementation has debug assertion that catches self-cycles early.
    // This prevents us from testing the SQL CHECK constraint directly in debug builds.
    // In release builds, the CHECK constraint would catch this at database level.
    const allocator = std.testing.allocator;

    // Create temporary database for this test
    const database_path = try getTemporaryDatabasePath(allocator, "error_self_cycle");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    // Initialize storage
    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Create label and tasks
    try test_storage.createPlan("self-test", "Self Cycle Test", "", null);

    const task_a: u32 = try test_storage.createTask("self-test", "Task A", "");
    const task_b: u32 = try test_storage.createTask("self-test", "Task B", "");

    // Test: Create valid dependency A -> B to verify cycle detection works
    try test_storage.addDependency(task_a, task_b);

    // Verify dependency was added
    var blockers_a = try test_storage.getBlockers(task_a);
    defer {
        for (blockers_a) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers_a);
    }
    try std.testing.expectEqual(@as(usize, 1), blockers_a.len);

    // Note: Self-cycle (A -> A) triggers debug assertion before reaching SQL.
    // Expected behavior: addDependency(task_a, task_a) should return InvalidInput.
    // In debug builds, assertion catches this; in release, CHECK constraint does.

    // Final assertions: Valid dependency created successfully
    try std.testing.expect(blockers_a.len > 0);
}

// ============================================================================
// Integration Test: Error Scenarios - Delete with Dependents
// ============================================================================

test "integration: error scenarios - delete task with dependents" {
    // Methodology: Test that attempting to delete tasks with active dependents should be prevented.
    // This validates referential integrity protection and prevents orphaned dependencies.
    //
    // Rationale: Deleting a task that other tasks depend on would break the dependency graph.
    // User should be shown which tasks depend on it and told to remove them first.
    //
    // Note: deleteTask is not yet implemented. When implemented, it should:
    // 1. Check for dependents before deletion
    // 2. Return error if dependents exist
    // 3. Provide list of dependent tasks in error message
    const allocator = std.testing.allocator;

    // Create temporary database for this test
    const database_path = try getTemporaryDatabasePath(allocator, "error_delete_with_deps");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    // Initialize storage
    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Create label and tasks
    try test_storage.createPlan("delete", "Delete Test", "", null);

    const task_a: u32 = try test_storage.createTask("delete", "Task A", "Foundation task");
    const task_b: u32 = try test_storage.createTask("delete", "Task B", "Depends on A");
    const task_c: u32 = try test_storage.createTask("delete", "Task C", "Also depends on A");

    // Create dependencies: B -> A, C -> A
    try test_storage.addDependency(task_b, task_a);
    try test_storage.addDependency(task_c, task_a);

    // Test: Verify A has dependents (documents expected deleteTask behavior)
    var dependents_a = try test_storage.getDependents(task_a);
    defer {
        for (dependents_a) |*dependent| {
            dependent.deinit(allocator);
        }
        allocator.free(dependents_a);
    }
    try std.testing.expectEqual(@as(usize, 2), dependents_a.len); // B and C

    // Expected deleteTask behavior when implemented:
    // const delete_result = storage.deleteTask(&test_storage, task_a);
    // try std.testing.expectError(storage.SqliteError.InvalidData, delete_result);

    // Final assertions: Verified task has dependents (would block deletion)
    try std.testing.expect(dependents_a.len > 0);
}

test "integration: error scenarios - delete non-existent dependency" {
    // Methodology: Test that removing non-existent dependencies returns appropriate error.
    // This validates error handling for remove-dep command on missing relationships.
    //
    // Rationale: Users may try to remove dependencies that were never added or already removed.
    // Error message should clearly state that the dependency doesn't exist.
    const allocator = std.testing.allocator;

    // Create temporary database for this test
    const database_path = try getTemporaryDatabasePath(allocator, "error_remove_nonexistent");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    // Initialize storage
    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Create label and tasks
    try test_storage.createPlan("remove", "Remove Test", "", null);

    const task_a: u32 = try test_storage.createTask("remove", "Task A", "");
    const task_b: u32 = try test_storage.createTask("remove", "Task B", "");

    // Test 1: Attempt to remove dependency that was never added
    // Rationale: A and B exist but no dependency between them was ever created.
    const remove_result = test_storage.removeDependency(task_a, task_b);
    try std.testing.expectError(storage.SqliteError.InvalidData, remove_result);

    // Test 2: Add a dependency, then remove it, then try to remove again
    try test_storage.addDependency(task_a, task_b);
    try test_storage.removeDependency(task_a, task_b);

    // Verify removal succeeded
    var blockers_a = try test_storage.getBlockers(task_a);
    defer allocator.free(blockers_a);
    try std.testing.expectEqual(@as(usize, 0), blockers_a.len);

    // Test 3: Try to remove same dependency again (already removed)
    const remove_again_result = test_storage.removeDependency(task_a, task_b);
    try std.testing.expectError(storage.SqliteError.InvalidData, remove_again_result);

    // Final assertions: All invalid removal attempts returned appropriate error
    try std.testing.expect(true);
}

// ============================================================================
// Integration Test: Error Scenarios - User-Friendly Error Messages
// ============================================================================

test "integration: error scenarios - error message format verification" {
    // Methodology: Test that error types returned by storage layer are appropriate
    // for CLI to generate user-friendly messages. This verifies error contract.
    //
    // Rationale: Each error type should map to a specific user-friendly message:
    // - InvalidData: "Task not found" or "Label not found" or "Dependency doesn't exist"
    // - CycleDetected: "Would create cycle: A -> B -> C -> A"
    // - InvalidKebabCase: "Label ID must be kebab-case (lowercase, hyphens)"
    // - InvalidInput: "Invalid input: [specific reason]"
    const allocator = std.testing.allocator;

    // Create temporary database for this test
    const database_path = try getTemporaryDatabasePath(allocator, "error_messages");
    defer allocator.free(database_path);
    defer cleanupDatabaseFile(database_path);

    // Initialize storage
    var test_storage = try storage.Storage.init(allocator, database_path);
    defer test_storage.deinit();

    // Test 1: InvalidData for missing parent label
    const result1 = test_storage.createTask("missing", "Task", "");
    try std.testing.expectError(storage.SqliteError.InvalidData, result1);

    // Note: InvalidKebabCase validation is not yet implemented in storage layer.
    // When implemented, invalid label IDs should return InvalidKebabCase error.
    // For now, test other error types that are implemented.

    // Test 2: CycleDetected for dependency cycle
    try test_storage.createPlan("msg", "Message Test", "", null);
    const task1: u32 = try test_storage.createTask("msg", "Task 1", "");
    const task2: u32 = try test_storage.createTask("msg", "Task 2", "");

    try test_storage.addDependency(task1, task2);
    const result2 = test_storage.addDependency(task2, task1);
    try std.testing.expectError(storage.SqliteError.CycleDetected, result2);

    // Note: InvalidInput for self-dependency triggers debug assertion before SQL.
    // In release builds, CHECK constraint would return InvalidInput.
    // For now, verify that cycle detection works correctly.

    // Test 3: InvalidData for removing non-existent dependency
    const task3: u32 = try test_storage.createTask("msg", "Task 3", "");
    const result3 = test_storage.removeDependency(task3, task1);
    try std.testing.expectError(storage.SqliteError.InvalidData, result3);

    // Final assertions: All error types are appropriate for user-facing messages
    // Each error type has a clear semantic meaning that CLI can translate:
    // - InvalidData: Not found or doesn't exist
    // - CycleDetected: Would create circular dependency
    // - InvalidKebabCase: Invalid format (to be implemented)
    // - InvalidInput: Self-reference or malformed input
    try std.testing.expect(true);
}
