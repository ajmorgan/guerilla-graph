//! Tests for plan CRUD operations in SQLite storage layer.
//!
//! Covers: Plan creation, duplicate detection, validation

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;
const SqliteError = guerilla_graph.storage.SqliteError;
// Use re-exported C types from storage to ensure type compatibility
const c = guerilla_graph.storage.c_funcs;

fn bindText(statement: *c.sqlite3_stmt, index: c_int, text: []const u8) !void {
    const result = c.sqlite3_bind_text(statement, index, text.ptr, @intCast(text.len), null);
    if (result != c.SQLITE_OK) return SqliteError.BindFailed;
}

test "createPlan: successful creation" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_create_plan.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create a plan
    try storage.createPlan("auth", "Authentication", "User authentication and authorization", null);

    // Verify plan was created by querying it
    const database = storage.database;
    const check_sql = "SELECT id, title, description FROM plans WHERE id = ?";
    var statement: ?*c.sqlite3_stmt = null;
    const result = c.sqlite3_prepare_v2(database, check_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(statement);

    try bindText(statement.?, 1, "auth");
    const step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);

    const id = std.mem.span(c.sqlite3_column_text(statement.?, 0));
    const title = std.mem.span(c.sqlite3_column_text(statement.?, 1));
    const description = std.mem.span(c.sqlite3_column_text(statement.?, 2));

    try std.testing.expectEqualStrings("auth", id);
    try std.testing.expectEqualStrings("Authentication", title);
    try std.testing.expectEqualStrings("User authentication and authorization", description);
}

test "createPlan: duplicate ID should fail" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_create_plan_duplicate.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create first plan
    try storage.createPlan("payments", "Payments", "Payment processing", null);

    // Attempt to create duplicate - should fail
    const result = storage.createPlan("payments", "Duplicate", "Should fail", null);
    try std.testing.expectError(SqliteError.StepFailed, result);
}

// NOTE: Tests for empty title and title-too-long are omitted because they
// would trigger assertions in debug builds. These constraints are enforced
// by assertions (assert(title.len > 0) and assert(title.len <= 500)) which
// are the correct behavior for debug builds. In release builds, CHECK
// constraints in SQL provide the enforcement.

// ============================================================================
// Plan Deletion Tests
// ============================================================================

test "deletePlan: successful deletion with no tasks" {
    // Methodology: Verify deletion works when no tasks exist (regression test).
    // Ensures basic deletion still works after CASCADE implementation.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    const temp_path = "/tmp/test_delete_plan_empty.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plan with no tasks
    try storage.createPlan("cleanup", "Cleanup Tasks", "", null);

    // Delete plan (should succeed with 0 tasks deleted)
    const task_count = try storage.deletePlan("cleanup");
    try std.testing.expectEqual(@as(u64, 0), task_count);

    // Verify plan is actually deleted
    const check_sql = "SELECT COUNT(*) FROM plans WHERE id = ?";
    var statement: ?*c.sqlite3_stmt = null;
    const result = c.sqlite3_prepare_v2(storage.database, check_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(statement);

    try bindText(statement.?, 1, "cleanup");
    const step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);

    const count = c.sqlite3_column_int64(statement.?, 0);
    try std.testing.expectEqual(@as(i64, 0), count); // Plan deleted
}

test "deletePlan: cascade deletes all tasks" {
    // Methodology: Create plan with multiple tasks, delete plan,
    // verify all tasks are CASCADE deleted (not orphaned with NULL plan).
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    const temp_path = "/tmp/test_delete_plan_cascade.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("auth", "Authentication", "", null);
    const task1 = try storage.createTask("auth", "Add login", "");
    const task2 = try storage.createTask("auth", "Add JWT", "");
    const task3 = try storage.createTask("auth", "Add tests", "");

    // Delete plan (should CASCADE delete all 3 tasks)
    const task_count = try storage.deletePlan("auth");
    try std.testing.expectEqual(@as(u64, 3), task_count);

    // Verify plan deleted
    const check_plan_sql = "SELECT COUNT(*) FROM plans WHERE id = ?";
    var plan_statement: ?*c.sqlite3_stmt = null;
    var result = c.sqlite3_prepare_v2(storage.database, check_plan_sql, -1, &plan_statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(plan_statement);

    try bindText(plan_statement.?, 1, "auth");
    var step_result = c.sqlite3_step(plan_statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);
    const plan_count = c.sqlite3_column_int64(plan_statement.?, 0);
    try std.testing.expectEqual(@as(i64, 0), plan_count);

    // Verify all tasks are CASCADE deleted (not orphaned)
    const check_tasks_sql = "SELECT COUNT(*) FROM tasks";
    var tasks_statement: ?*c.sqlite3_stmt = null;
    result = c.sqlite3_prepare_v2(storage.database, check_tasks_sql, -1, &tasks_statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(tasks_statement);

    step_result = c.sqlite3_step(tasks_statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);
    const total_task_count = c.sqlite3_column_int64(tasks_statement.?, 0);
    try std.testing.expectEqual(@as(i64, 0), total_task_count); // All tasks deleted

    // Verify no orphans exist (plan IS NULL)
    const check_orphans_sql = "SELECT COUNT(*) FROM tasks WHERE plan IS NULL";
    var orphans_statement: ?*c.sqlite3_stmt = null;
    result = c.sqlite3_prepare_v2(storage.database, check_orphans_sql, -1, &orphans_statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(orphans_statement);

    step_result = c.sqlite3_step(orphans_statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);
    const orphan_count = c.sqlite3_column_int64(orphans_statement.?, 0);
    try std.testing.expectEqual(@as(i64, 0), orphan_count); // No orphans - tasks deleted

    _ = task1;
    _ = task2;
    _ = task3;
}

test "deletePlan: cascade deletes tasks and their dependencies" {
    // Methodology: Create plan with tasks that have dependencies, delete plan,
    // verify tasks AND dependencies are all CASCADE deleted.
    // Tests full cascade chain: plan → tasks → dependencies.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    const temp_path = "/tmp/test_delete_plan_deps.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plan and tasks with dependencies
    try storage.createPlan("feature", "Feature X", "", null);
    const task1 = try storage.createTask("feature", "Task 1", "");
    const task2 = try storage.createTask("feature", "Task 2", "");
    const task3 = try storage.createTask("feature", "Task 3", "");

    // Add dependencies: task2 blocks on task1, task3 blocks on task2
    try storage.addDependency(task2, task1);
    try storage.addDependency(task3, task2);

    // Verify dependencies exist before deletion
    const check_deps_before_sql = "SELECT COUNT(*) FROM dependencies";
    var deps_before_statement: ?*c.sqlite3_stmt = null;
    var result = c.sqlite3_prepare_v2(storage.database, check_deps_before_sql, -1, &deps_before_statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(deps_before_statement);

    var step_result = c.sqlite3_step(deps_before_statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);
    const deps_before = c.sqlite3_column_int64(deps_before_statement.?, 0);
    try std.testing.expectEqual(@as(i64, 2), deps_before); // 2 dependencies

    // Delete plan (should CASCADE delete tasks AND dependencies)
    const task_count = try storage.deletePlan("feature");
    try std.testing.expectEqual(@as(u64, 3), task_count);

    // Verify all dependencies CASCADE deleted
    const check_deps_after_sql = "SELECT COUNT(*) FROM dependencies";
    var deps_after_statement: ?*c.sqlite3_stmt = null;
    result = c.sqlite3_prepare_v2(storage.database, check_deps_after_sql, -1, &deps_after_statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(deps_after_statement);

    step_result = c.sqlite3_step(deps_after_statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);
    const deps_after = c.sqlite3_column_int64(deps_after_statement.?, 0);
    try std.testing.expectEqual(@as(i64, 0), deps_after); // All dependencies deleted
}

test "deletePlan: fails for non-existent plan" {
    // Methodology: Verify clear error when trying to delete non-existent plan.
    // Error handling regression test.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    const temp_path = "/tmp/test_delete_plan_notfound.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Attempt to delete non-existent plan (should fail with InvalidData)
    const result = storage.deletePlan("nonexistent");
    try std.testing.expectError(SqliteError.InvalidData, result);
}
