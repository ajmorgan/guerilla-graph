//! Tests for task CRUD operations in storage layer (storage.zig).
//!
//! Covers: createTask, startTask, completeTask, reopenTask, deleteTask
//! and related task lifecycle operations.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;
const SqliteError = guerilla_graph.storage.SqliteError;
const types = guerilla_graph.types;
const TaskStatus = types.TaskStatus;
const test_utils = @import("test_utils.zig");

// Use re-exported C types from storage to ensure type compatibility
const c = guerilla_graph.storage.c_funcs;

test "createTask: successful creation" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_create_task.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create label first
    try storage.createPlan("api", "API", "API development", null);

    // Create task
    const task_id: u32 = try storage.createTask("api", "Add login endpoint", "Implement POST /login");

    // Verify task ID is 1 (first task)
    try std.testing.expectEqual(@as(u32, 1), task_id);

    // Verify task was created in database
    const database = storage.database;
    const check_sql = "SELECT id, plan, title, description, status FROM tasks WHERE id = ?";
    var statement: ?*c.sqlite3_stmt = null;
    const result = c.sqlite3_prepare_v2(database, check_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(statement);

    try test_utils.bindInt64(statement.?, 1, @intCast(task_id));
    const step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);

    const db_id = c.sqlite3_column_int64(statement.?, 0);
    const db_plan = std.mem.span(c.sqlite3_column_text(statement.?, 1));
    const db_title = std.mem.span(c.sqlite3_column_text(statement.?, 2));
    const db_description = std.mem.span(c.sqlite3_column_text(statement.?, 3));
    const db_status = std.mem.span(c.sqlite3_column_text(statement.?, 4));

    try std.testing.expectEqual(@as(i64, 1), db_id);
    try std.testing.expectEqualStrings("api", db_plan);
    try std.testing.expectEqualStrings("Add login endpoint", db_title);
    try std.testing.expectEqualStrings("Implement POST /login", db_description);
    try std.testing.expectEqualStrings("open", db_status);
}

test "createTask: invalid label should fail" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_create_task_invalid_label.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Attempt to create task without label
    const result = storage.createTask("nonexistent", "Test Task", "Should fail");
    try std.testing.expectError(SqliteError.InvalidData, result);
}

test "createTask: sequential task numbers" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_create_task_sequential.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create label
    try storage.createPlan("ui", "UI", "User interface", null);

    // Create multiple tasks and verify sequential numbering
    const task1: u32 = try storage.createTask("ui", "Task 1", "Description 1");
    try std.testing.expectEqual(@as(u32, 1), task1);

    const task2: u32 = try storage.createTask("ui", "Task 2", "Description 2");
    try std.testing.expectEqual(@as(u32, 2), task2);

    const task3: u32 = try storage.createTask("ui", "Task 3", "Description 3");
    try std.testing.expectEqual(@as(u32, 3), task3);
}

test "startTask: successful status transition" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_start_task.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create label and task
    try storage.createPlan("backend", "Backend", "Backend work", null);
    const task_id: u32 = try storage.createTask("backend", "Implement API", "Build REST API");

    // Start task
    try storage.startTask(task_id);

    // Verify status changed to 'in_progress'
    const database = storage.database;
    const check_sql = "SELECT status, completed_at FROM tasks WHERE id = ?";
    var statement: ?*c.sqlite3_stmt = null;
    const result = c.sqlite3_prepare_v2(database, check_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(statement);

    try test_utils.bindInt64(statement.?, 1, @intCast(task_id));
    const step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);

    const status = std.mem.span(c.sqlite3_column_text(statement.?, 0));
    const completed_at_type = c.sqlite3_column_type(statement.?, 1);

    try std.testing.expectEqualStrings("in_progress", status);
    try std.testing.expectEqual(c.SQLITE_NULL, completed_at_type);
}

test "startTask: nonexistent task should error" {
    // Rationale: startTask now validates task existence for safety (Tiger Style).
    // This prevents silent failures and catches programming errors early.
    // The test verifies that InvalidData error is returned for nonexistent tasks.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_start_nonexistent.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage_instance = try Storage.init(allocator, temp_path);
    defer storage_instance.deinit();

    // Attempt to start a task that doesn't exist
    // This should return InvalidData error (stricter safety check)
    const result = storage_instance.startTask(999);
    try std.testing.expectError(error.InvalidData, result);
}

test "completeTask: successful status transition" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_complete_task.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create label and task
    try storage.createPlan("docs", "Documentation", "Documentation tasks", null);
    const task_id: u32 = try storage.createTask("docs", "Write README", "Create project README");

    // Start task first (required for completeTask)
    try storage.startTask(task_id);

    // Complete task
    try storage.completeTask(task_id);

    // Verify status changed to 'completed' and completed_at is set
    const database = storage.database;
    const check_sql = "SELECT status, completed_at FROM tasks WHERE id = ?";
    var statement: ?*c.sqlite3_stmt = null;
    const result = c.sqlite3_prepare_v2(database, check_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(statement);

    try test_utils.bindInt64(statement.?, 1, @intCast(task_id));
    const step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);

    const status = std.mem.span(c.sqlite3_column_text(statement.?, 0));
    const completed_at_type = c.sqlite3_column_type(statement.?, 1);

    try std.testing.expectEqualStrings("completed", status);
    try std.testing.expect(completed_at_type != c.SQLITE_NULL); // Should have timestamp
}

test "deleteTask: successful deletion" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_delete_task.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create label and task
    try storage.createPlan("cleanup", "Cleanup", "Cleanup tasks", null);
    const task_id: u32 = try storage.createTask("cleanup", "Remove old code", "Delete deprecated files");

    // Delete task
    try storage.deleteTask(task_id);

    // Verify task no longer exists
    const database = storage.database;
    const check_sql = "SELECT COUNT(*) FROM tasks WHERE id = ?";
    var statement: ?*c.sqlite3_stmt = null;
    const result = c.sqlite3_prepare_v2(database, check_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(statement);

    try test_utils.bindInt64(statement.?, 1, @intCast(task_id));
    const step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);

    const count = c.sqlite3_column_int64(statement.?, 0);
    try std.testing.expectEqual(@as(i64, 0), count);
}

test "deleteTask: fails when task has dependents" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_delete_task_with_dependents.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create label and two tasks
    try storage.createPlan("migration", "Migration", "Database migration", null);
    const task1: u32 = try storage.createTask("migration", "Create schema", "Design database schema");
    const task2: u32 = try storage.createTask("migration", "Write migration", "Implement migration script");

    // Add dependency: task2 blocks on task1
    try storage.addDependency(task2, task1);

    // Attempt to delete task1 (which task2 depends on) - should fail
    const result = storage.deleteTask(task1);
    try std.testing.expectError(SqliteError.InvalidData, result);

    // Verify task1 still exists
    const database = storage.database;
    const check_sql = "SELECT COUNT(*) FROM tasks WHERE id = ?";
    var statement: ?*c.sqlite3_stmt = null;
    const check_result = c.sqlite3_prepare_v2(database, check_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, check_result);
    defer _ = c.sqlite3_finalize(statement);

    try test_utils.bindInt64(statement.?, 1, @intCast(task1));
    const step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);

    const count = c.sqlite3_column_int64(statement.?, 0);
    try std.testing.expectEqual(@as(i64, 1), count);
}

test "deleteTask: nonexistent task should fail" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_delete_nonexistent_task.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Attempt to delete nonexistent task
    const result = storage.deleteTask(999);
    try std.testing.expectError(SqliteError.InvalidData, result);
}

test "deleteTask: removes dependencies when deleting dependent task" {
    // Rationale: When a task is deleted, its dependencies (where it blocks on others) are removed.
    // deleteTask allows deletion of tasks that have blockers (tasks they depend on).
    // deleteTask prevents deletion of tasks that have dependents (tasks that depend on them).
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_delete_with_deps.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage_instance = try Storage.init(allocator, temp_path);
    defer storage_instance.deinit();

    // Create label and tasks
    try storage_instance.createPlan("cascade", "Cascade Test", "", null);
    const task1: u32 = try storage_instance.createTask("cascade", "Task 1", "");
    const task2: u32 = try storage_instance.createTask("cascade", "Task 2", "");

    // Add dependency: task2 blocks_on task1
    // This means task2 depends on task1, so task1 has task2 as a dependent
    try storage_instance.addDependency(task2, task1);

    // Verify dependency exists
    var blockers = try storage_instance.getBlockers(task2);
    defer {
        for (blockers) |*blocker| {
            blocker.deinit(allocator);
        }
        allocator.free(blockers);
    }
    try std.testing.expectEqual(@as(usize, 1), blockers.len);

    // Delete task2 (which has blockers but no dependents)
    // This should succeed and cascade-delete the dependency entry
    try storage_instance.deleteTask(task2);

    // Verify task2 is gone
    const deleted_task = try storage_instance.getTask(task2);
    try std.testing.expect(deleted_task == null);

    // Verify task1 still exists (it was not deleted)
    const remaining_task = try storage_instance.getTask(task1);
    try std.testing.expect(remaining_task != null);
    if (remaining_task) |task| {
        var mutable_task = task;
        defer mutable_task.deinit(allocator);
    }
}
