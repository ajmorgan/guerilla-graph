//! Tests for task lifecycle and deletion operations.
//!
//! Covers: startTask, completeTask state transitions, deleteTask cascade behavior.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;
const SqliteError = guerilla_graph.storage.SqliteError;
const types = guerilla_graph.types;
const TaskStatus = types.TaskStatus;
// Use re-exported C types from storage to ensure type compatibility
const c = guerilla_graph.storage.c_funcs;
const test_utils = @import("test_utils.zig");

// ============================================================================
// Task Lifecycle Tests (startTask, completeTask)
// ============================================================================

test "startTask: transitions status and sets started_at" {
    // Methodology: Start task, verify status changes to in_progress
    // and started_at timestamp is set.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_start_task.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and task
    try storage.createPlan("auth", "Authentication", "", null);
    const task_id = try storage.createTask("auth", "Task", "Description");

    // Start task
    try storage.startTask(task_id);

    // Verify status change
    const maybe_task = try storage.getTask(task_id);
    try std.testing.expect(maybe_task != null);
    var task = maybe_task.?;
    defer task.deinit(allocator);

    try std.testing.expectEqual(TaskStatus.in_progress, task.status);
    try std.testing.expect(task.started_at != null);
    try std.testing.expectEqual(@as(?i64, null), task.completed_at);
}

test "completeTask: transitions status and sets completed_at" {
    // Methodology: Start then complete task, verify status changes to completed
    // and completed_at timestamp is set.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_complete_task.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and task
    try storage.createPlan("auth", "Authentication", "", null);
    const task_id = try storage.createTask("auth", "Task", "Description");

    // Start then complete task
    try storage.startTask(task_id);
    try storage.completeTask(task_id);

    // Verify status change
    const maybe_task = try storage.getTask(task_id);
    try std.testing.expect(maybe_task != null);
    var task = maybe_task.?;
    defer task.deinit(allocator);

    try std.testing.expectEqual(TaskStatus.completed, task.status);
    try std.testing.expect(task.started_at != null);
    try std.testing.expect(task.completed_at != null);
}

// ============================================================================
// Task Deletion Tests
// ============================================================================

test "deleteTask: removes task successfully" {
    // Methodology: Create and delete task, verify it no longer exists.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_delete_task.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and task
    try storage.createPlan("auth", "Authentication", "", null);
    const task_id = try storage.createTask("auth", "Task", "Description");

    // Delete task
    try storage.deleteTask(task_id);

    // Verify task no longer exists
    const maybe_task = try storage.getTask(task_id);
    try std.testing.expectEqual(@as(?types.Task, null), maybe_task);
}

test "deleteTask: nonexistent task fails" {
    // Methodology: Attempt to delete nonexistent task, verify error.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_delete_task_nonexistent.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Attempt to delete nonexistent task
    const result = storage.deleteTask(999);
    try std.testing.expectError(SqliteError.InvalidData, result);
}
