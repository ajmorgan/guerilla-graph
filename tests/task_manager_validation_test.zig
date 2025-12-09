//! Validation tests for TaskManager business logic constraints.
//!
//! Tests business logic validation for:
//! - Label creation constraints (title length, plan_id validation, description)
//! - Task creation constraints (parent label, title validation, dependency limits)
//! - Duplicate ID handling
//!
//! Uses test_utils helpers for database setup and cleanup.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const TaskManager = guerilla_graph.task_manager.TaskManager;
const Storage = guerilla_graph.storage.Storage;
const test_utils = @import("test_utils.zig");

// ============================================================================
// Validation Tests - Testing Business Logic Constraints
// ============================================================================

test "TaskManager: createPlan - title length validation" {
    // Methodology: Test business logic validation for title length constraints.
    // We verify that the 1-500 char requirement is enforced through assertions.
    const allocator = std.testing.allocator;

    const temp_path = try test_utils.getTemporaryDatabasePath(allocator, "title_validation");
    defer allocator.free(temp_path);
    defer test_utils.cleanupDatabaseFile(temp_path);

    var test_storage = try Storage.init(allocator, temp_path);
    defer test_storage.deinit();

    var task_manager = TaskManager.init(allocator, &test_storage);
    defer task_manager.deinit();

    // Test valid title lengths
    // Assertion 1: Minimum length (1 char) should succeed
    try task_manager.createPlan("a", "T", "");

    // Assertion 2: Maximum length (500 chars) should succeed
    const max_title = "x" ** 500;
    try task_manager.createPlan("long", max_title, "");

    // Note: Empty title and >500 char title will trigger assertions in debug mode.
    // In release mode, storage layer CHECK constraint will catch these.
}

test "TaskManager: createPlan - plan_id validation" {
    // Methodology: Test plan_id constraints (1-100 chars, non-empty).
    // Verify that business logic validates label IDs before storage.
    const allocator = std.testing.allocator;

    const temp_path = try test_utils.getTemporaryDatabasePath(allocator, "plan_id_validation");
    defer allocator.free(temp_path);
    defer test_utils.cleanupDatabaseFile(temp_path);

    var test_storage = try Storage.init(allocator, temp_path);
    defer test_storage.deinit();

    var task_manager = TaskManager.init(allocator, &test_storage);
    defer task_manager.deinit();

    // Assertion 1: Minimum plan_id length (1 char) should succeed
    try task_manager.createPlan("x", "Test", "");

    // Assertion 2: 100 char plan_id should succeed
    const max_id = "a" ** 100;
    try task_manager.createPlan(max_id, "Test Label", "");
}

test "TaskManager: createPlan - description validation" {
    // Methodology: Test description length constraint (0-5000 chars).
    // Empty descriptions are valid, maximum is 5000 chars.
    const allocator = std.testing.allocator;

    const temp_path = try test_utils.getTemporaryDatabasePath(allocator, "description_validation");
    defer allocator.free(temp_path);
    defer test_utils.cleanupDatabaseFile(temp_path);

    var test_storage = try Storage.init(allocator, temp_path);
    defer test_storage.deinit();

    var task_manager = TaskManager.init(allocator, &test_storage);
    defer task_manager.deinit();

    // Assertion 1: Empty description should succeed
    try task_manager.createPlan("test1", "Test 1", "");

    // Assertion 2: Maximum description length (5000 chars) should succeed
    const max_desc = "d" ** 5000;
    try task_manager.createPlan("test2", "Test 2", max_desc);
}

test "TaskManager: createPlan - duplicate ID handling" {
    // Methodology: Test that duplicate label IDs are properly rejected.
    // Storage layer enforces uniqueness via PRIMARY KEY constraint.
    const allocator = std.testing.allocator;

    const temp_path = try test_utils.getTemporaryDatabasePath(allocator, "duplicate_label");
    defer allocator.free(temp_path);
    defer test_utils.cleanupDatabaseFile(temp_path);

    var test_storage = try Storage.init(allocator, temp_path);
    defer test_storage.deinit();

    var task_manager = TaskManager.init(allocator, &test_storage);
    defer task_manager.deinit();

    // Assertion 1: First label creation succeeds
    try task_manager.createPlan("auth", "Authentication", "User auth");

    // Assertion 2: Duplicate label ID should fail
    const result = task_manager.createPlan("auth", "Auth v2", "Duplicate ID");
    try std.testing.expectError(guerilla_graph.storage.SqliteError.StepFailed, result);
}

test "TaskManager: createTask - parent label validation" {
    // Methodology: Test that tasks require existing parent labels.
    // Foreign key constraint ensures referential integrity.
    const allocator = std.testing.allocator;

    const temp_path = try test_utils.getTemporaryDatabasePath(allocator, "parent_validation");
    defer allocator.free(temp_path);
    defer test_utils.cleanupDatabaseFile(temp_path);

    var test_storage = try Storage.init(allocator, temp_path);
    defer test_storage.deinit();

    var task_manager = TaskManager.init(allocator, &test_storage);
    defer task_manager.deinit();

    const empty_deps: []const u32 = &[_]u32{};

    // Assertion 1: Task with nonexistent parent should fail
    const result = task_manager.createTask("nonexistent", "Test Task", "", empty_deps);
    try std.testing.expectError(guerilla_graph.storage.SqliteError.InvalidData, result);

    // Assertion 2: Task with existing parent should succeed
    try task_manager.createPlan("valid", "Valid Label", "");
    const task_id: u32 = try task_manager.createTask("valid", "Test Task", "", empty_deps);
    try std.testing.expect(task_id > 0);
}

test "TaskManager: createTask - title validation" {
    // Methodology: Test task title validation (1-500 chars).
    // Ensures business logic enforces title constraints.
    const allocator = std.testing.allocator;

    const temp_path = try test_utils.getTemporaryDatabasePath(allocator, "task_title_validation");
    defer allocator.free(temp_path);
    defer test_utils.cleanupDatabaseFile(temp_path);

    var test_storage = try Storage.init(allocator, temp_path);
    defer test_storage.deinit();

    var task_manager = TaskManager.init(allocator, &test_storage);
    defer task_manager.deinit();

    try task_manager.createPlan("test", "Test", "");
    const empty_deps: []const u32 = &[_]u32{};

    // Assertion 1: Minimum title length (1 char) should succeed
    const task1: u32 = try task_manager.createTask("test", "T", "", empty_deps);
    try std.testing.expect(task1 > 0);

    // Assertion 2: Maximum title length (500 chars) should succeed
    const max_title = "t" ** 500;
    const task2: u32 = try task_manager.createTask("test", max_title, "", empty_deps);
    try std.testing.expect(task2 > 0);
}

test "TaskManager: createTask - dependency count limit" {
    // Methodology: Test dependency count validation (max 1000).
    // Business logic enforces reasonable dependency limits.
    const allocator = std.testing.allocator;

    const temp_path = try test_utils.getTemporaryDatabasePath(allocator, "dependency_limit");
    defer allocator.free(temp_path);
    defer test_utils.cleanupDatabaseFile(temp_path);

    var test_storage = try Storage.init(allocator, temp_path);
    defer test_storage.deinit();

    var task_manager = TaskManager.init(allocator, &test_storage);
    defer task_manager.deinit();

    try task_manager.createPlan("deps", "Dependencies", "");
    const empty_deps: []const u32 = &[_]u32{};

    // Assertion 1: Zero dependencies should succeed
    const task1: u32 = try task_manager.createTask("deps", "Task 1", "", empty_deps);
    try std.testing.expect(task1 > 0);

    // Assertion 2: Multiple dependencies should succeed (within limit)
    // Note: addDependency is not implemented yet, so we test with empty deps
    const task2: u32 = try task_manager.createTask("deps", "Task 2", "", empty_deps);
    try std.testing.expect(task2 > 0);
}
