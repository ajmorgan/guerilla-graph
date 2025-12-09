//! Error handling tests for TaskManager.
//!
//! Covers: Error propagation, stress testing, and memory safety.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const TaskManager = guerilla_graph.task_manager.TaskManager;
const Storage = guerilla_graph.storage.Storage;
const types = guerilla_graph.types;

// ============================================================================
// Error Handling Tests - Testing Edge Cases and Error Conditions
// ============================================================================

test "TaskManager: createTask - proper error propagation" {
    // Methodology: Test that storage errors are properly propagated.
    // Ensures business logic doesn't swallow critical errors.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_task_manager_error_propagation.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    var test_storage = try Storage.init(allocator, temp_path);
    defer test_storage.deinit();

    var task_manager = TaskManager.init(allocator, &test_storage);
    defer task_manager.deinit();

    const empty_deps: []const u32 = &[_]u32{};

    // Assertion 1: Invalid label should return InvalidData error
    const result = task_manager.createTask("missing", "Task", "", empty_deps);

    // Assertion 2: Error should be propagated from storage layer
    try std.testing.expectError(guerilla_graph.storage.SqliteError.InvalidData, result);
}

test "TaskManager: memory safety - proper cleanup on success" {
    // Methodology: Test that successful operations don't leak memory.
    // Uses testing.allocator to detect leaks.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_task_manager_memory_success.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    var test_storage = try Storage.init(allocator, temp_path);
    defer test_storage.deinit();

    var task_manager = TaskManager.init(allocator, &test_storage);
    defer task_manager.deinit();

    try task_manager.createPlan("mem", "Memory Test", "Description");
    const empty_deps: []const u32 = &[_]u32{};

    const task_id: u32 = try task_manager.createTask("mem", "Test Task", "Description", empty_deps);

    // Assertion 1: Task was created successfully
    try std.testing.expect(task_id > 0);

    // Assertion 2: Task ID is valid u32
    try std.testing.expectEqual(@as(u32, 1), task_id);

    // Note: testing.allocator will detect any leaks at defer time
}

test "TaskManager: memory safety - proper cleanup on error" {
    // Methodology: Test that failed operations clean up properly.
    // Even on error, no memory should leak.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_task_manager_memory_error.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    var test_storage = try Storage.init(allocator, temp_path);
    defer test_storage.deinit();

    var task_manager = TaskManager.init(allocator, &test_storage);
    defer task_manager.deinit();

    const empty_deps: []const u32 = &[_]u32{};

    // Attempt to create task without label (should fail)
    const result = task_manager.createTask("missing", "Task", "Desc", empty_deps);

    // Assertion 1: Operation should fail with InvalidData
    try std.testing.expectError(guerilla_graph.storage.SqliteError.InvalidData, result);

    // Assertion 2: testing.allocator verifies no leaks occurred
    // (implicit - allocator checks at defer time)
}
