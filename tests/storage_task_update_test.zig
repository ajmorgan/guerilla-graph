//! Tests for task update operations.
//!
//! Covers: updateTask for title, description, status changes.

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
// Task Update Tests
// ============================================================================

test "updateTask: title only" {
    // Methodology: Update task title, verify change persists.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_update_task_title.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and task
    try storage.createPlan("auth", "Authentication", "", null);
    const task_id = try storage.createTask("auth", "Old Title", "Description");

    // Update title
    try storage.updateTask(task_id, "New Title", null, null);

    // Verify update
    const maybe_task = try storage.getTask(task_id);
    try std.testing.expect(maybe_task != null);
    var task = maybe_task.?;
    defer task.deinit(allocator);

    try std.testing.expectEqualStrings("New Title", task.title);
    try std.testing.expectEqualStrings("Description", task.description); // Unchanged
}

test "updateTask: description only" {
    // Methodology: Update task description, verify change persists.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_update_task_description.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and task
    try storage.createPlan("auth", "Authentication", "", null);
    const task_id = try storage.createTask("auth", "Title", "Old Description");

    // Update description
    try storage.updateTask(task_id, null, "New Description", null);

    // Verify update
    const maybe_task = try storage.getTask(task_id);
    try std.testing.expect(maybe_task != null);
    var task = maybe_task.?;
    defer task.deinit(allocator);

    try std.testing.expectEqualStrings("Title", task.title); // Unchanged
    try std.testing.expectEqualStrings("New Description", task.description);
}

test "updateTask: status only" {
    // Methodology: Update task status via updateTask, verify timestamps are set correctly.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_update_task_status.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and task
    try storage.createPlan("auth", "Authentication", "", null);
    const task_id = try storage.createTask("auth", "Title", "Description");

    // Update status to in_progress
    try storage.updateTask(task_id, null, null, TaskStatus.in_progress);

    // Verify status and started_at
    const maybe_task = try storage.getTask(task_id);
    try std.testing.expect(maybe_task != null);
    var task = maybe_task.?;
    defer task.deinit(allocator);

    try std.testing.expectEqual(TaskStatus.in_progress, task.status);
    try std.testing.expect(task.started_at != null); // Should be set
}
