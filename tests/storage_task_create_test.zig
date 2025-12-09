//! Tests for task creation operations.
//!
//! Covers: createTask with per-plan numbering, validation, constraints.

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
// Task Creation Tests (per-plan numbering)
// ============================================================================

test "createTask: successful creation with per-plan numbering" {
    // Methodology: Create task under plan, verify both internal ID and plan-relative
    // task number are correct by querying database. First task should be number 1.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_create_task_new_schema.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan first
    try storage.createPlan("auth", "Authentication", "User auth system", null);

    // Create task (returns internal task_id)
    const task_id = try storage.createTask("auth", "Add login endpoint", "Implement POST /login");
    try std.testing.expect(task_id > 0);

    // Verify task was created in database with correct plan_task_number
    const database = storage.database;
    const check_sql = "SELECT id, plan_id, plan_task_number, title FROM tasks WHERE id = ?";
    var statement: ?*c.sqlite3_stmt = null;
    const prepare_result = c.sqlite3_prepare_v2(database, check_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, prepare_result);
    defer _ = c.sqlite3_finalize(statement);

    try test_utils.bindInt64(statement.?, 1, @intCast(task_id));
    const step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);

    const db_id = c.sqlite3_column_int64(statement.?, 0);
    const db_plan_id = c.sqlite3_column_int64(statement.?, 1);
    const db_plan_task_number = c.sqlite3_column_int(statement.?, 2);
    const db_title = std.mem.span(c.sqlite3_column_text(statement.?, 3));

    try std.testing.expectEqual(@as(i64, @intCast(task_id)), db_id);
    try std.testing.expect(db_plan_id > 0);
    try std.testing.expectEqual(@as(c_int, 1), db_plan_task_number); // First task should be #1
    try std.testing.expectEqualStrings("Add login endpoint", db_title);
}

test "createTask: per-plan sequential numbering" {
    // Methodology: Create multiple tasks under same plan, verify each gets
    // sequential plan_task_number (1, 2, 3, ...) by querying database.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_create_task_sequential_numbering.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan
    try storage.createPlan("ui", "User Interface", "UI components", null);

    // Create multiple tasks
    const task1 = try storage.createTask("ui", "Task 1", "Description 1");
    const task2 = try storage.createTask("ui", "Task 2", "Description 2");
    const task3 = try storage.createTask("ui", "Task 3", "Description 3");

    // Query plan_task_number for each task
    const database = storage.database;
    const check_sql = "SELECT plan_task_number FROM tasks WHERE id = ?";

    // Check task1
    var statement: ?*c.sqlite3_stmt = null;
    var result = c.sqlite3_prepare_v2(database, check_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(statement);

    try test_utils.bindInt64(statement.?, 1, @intCast(task1));
    var step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);
    try std.testing.expectEqual(@as(c_int, 1), c.sqlite3_column_int(statement.?, 0));
    _ = c.sqlite3_finalize(statement);

    // Check task2
    result = c.sqlite3_prepare_v2(database, check_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    try test_utils.bindInt64(statement.?, 1, @intCast(task2));
    step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);
    try std.testing.expectEqual(@as(c_int, 2), c.sqlite3_column_int(statement.?, 0));
    _ = c.sqlite3_finalize(statement);

    // Check task3
    result = c.sqlite3_prepare_v2(database, check_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    try test_utils.bindInt64(statement.?, 1, @intCast(task3));
    step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);
    try std.testing.expectEqual(@as(c_int, 3), c.sqlite3_column_int(statement.?, 0));

    // Assertions: Internal task IDs are different
    try std.testing.expect(task1 != task2);
    try std.testing.expect(task2 != task3);
}

test "createTask: independent numbering per plan" {
    // Methodology: Create tasks under different plans, verify each plan
    // maintains its own sequential numbering (both start at 1).
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_create_task_independent_numbering.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create two plans
    try storage.createPlan("auth", "Authentication", "", null);
    try storage.createPlan("payments", "Payments", "", null);

    // Create tasks under auth plan
    const auth1 = try storage.createTask("auth", "Auth task 1", "");
    const auth2 = try storage.createTask("auth", "Auth task 2", "");

    // Create tasks under payments plan - numbering should restart at 1
    const pay1 = try storage.createTask("payments", "Payment task 1", "");
    const pay2 = try storage.createTask("payments", "Payment task 2", "");

    // Create another auth task - should continue from 2
    const auth3 = try storage.createTask("auth", "Auth task 3", "");

    // Query plan_task_number for verification
    const database = storage.database;
    const check_sql = "SELECT plan_task_number FROM tasks WHERE id = ?";

    // Verify auth tasks are numbered 1, 2, 3
    const auth_numbers = [_]u32{ auth1, auth2, auth3 };
    for (auth_numbers, 0..) |task_id, i| {
        var statement: ?*c.sqlite3_stmt = null;
        const result = c.sqlite3_prepare_v2(database, check_sql, -1, &statement, null);
        try std.testing.expectEqual(c.SQLITE_OK, result);
        defer _ = c.sqlite3_finalize(statement);

        try test_utils.bindInt64(statement.?, 1, @intCast(task_id));
        const step_result = c.sqlite3_step(statement.?);
        try std.testing.expectEqual(c.SQLITE_ROW, step_result);
        try std.testing.expectEqual(@as(c_int, @intCast(i + 1)), c.sqlite3_column_int(statement.?, 0));
    }

    // Verify payments tasks are numbered 1, 2
    const pay_numbers = [_]u32{ pay1, pay2 };
    for (pay_numbers, 0..) |task_id, i| {
        var statement: ?*c.sqlite3_stmt = null;
        const result = c.sqlite3_prepare_v2(database, check_sql, -1, &statement, null);
        try std.testing.expectEqual(c.SQLITE_OK, result);
        defer _ = c.sqlite3_finalize(statement);

        try test_utils.bindInt64(statement.?, 1, @intCast(task_id));
        const step_result = c.sqlite3_step(statement.?);
        try std.testing.expectEqual(c.SQLITE_ROW, step_result);
        try std.testing.expectEqual(@as(c_int, @intCast(i + 1)), c.sqlite3_column_int(statement.?, 0));
    }

    // Assertions: All task IDs are unique (internal IDs are globally unique)
    try std.testing.expect(auth1 != auth2);
    try std.testing.expect(auth1 != pay1);
    try std.testing.expect(pay1 != pay2);
}

test "createTask: atomic counter increment" {
    // Methodology: Verify counter is atomically incremented by checking
    // plan's task_counter after task creation.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_create_task_atomic_counter.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan
    try storage.createPlan("api", "API", "", null);

    // Create task
    _ = try storage.createTask("api", "Task 1", "");

    // Verify plan's task_counter was incremented to 1
    const database = storage.database;
    const check_sql = "SELECT task_counter FROM plans WHERE slug = ?";
    var statement: ?*c.sqlite3_stmt = null;
    const result = c.sqlite3_prepare_v2(database, check_sql, -1, &statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(statement);

    try test_utils.bindText(statement.?, 1, "api");
    const step_result = c.sqlite3_step(statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);

    const counter = c.sqlite3_column_int(statement.?, 0);
    try std.testing.expectEqual(@as(c_int, 1), counter);
}

test "createTask: nonexistent plan fails" {
    // Methodology: Attempt to create task under nonexistent plan slug,
    // verify it fails with InvalidData error.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_create_task_nonexistent_plan.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Attempt to create task under nonexistent plan
    const result = storage.createTask("nonexistent", "Test Task", "Should fail");
    try std.testing.expectError(SqliteError.InvalidData, result);
}

test "createTask: UNIQUE constraint on plan_id and plan_task_number" {
    // Methodology: Manually insert task with duplicate (plan_id, plan_task_number),
    // verify UNIQUE constraint prevents insertion.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_create_task_unique_constraint.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and task
    try storage.createPlan("auth", "Authentication", "", null);
    _ = try storage.createTask("auth", "Task 1", "");

    // Manually attempt to insert duplicate (plan_id, plan_task_number)
    // Get plan_id first
    const database = storage.database;
    const get_plan_sql = "SELECT id FROM plans WHERE slug = ?";
    var get_statement: ?*c.sqlite3_stmt = null;
    var result = c.sqlite3_prepare_v2(database, get_plan_sql, -1, &get_statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(get_statement);

    try test_utils.bindText(get_statement.?, 1, "auth");
    var step_result = c.sqlite3_step(get_statement.?);
    try std.testing.expectEqual(c.SQLITE_ROW, step_result);
    const plan_id = c.sqlite3_column_int64(get_statement.?, 0);

    // Attempt manual insert with same plan_id and plan_task_number=1
    const insert_sql =
        \\INSERT INTO tasks (plan_id, plan_task_number, title, description, status, created_at, updated_at)
        \\VALUES (?, 1, 'Duplicate', 'Should fail', 'open', unixepoch(), unixepoch())
    ;
    var insert_statement: ?*c.sqlite3_stmt = null;
    result = c.sqlite3_prepare_v2(database, insert_sql, -1, &insert_statement, null);
    try std.testing.expectEqual(c.SQLITE_OK, result);
    defer _ = c.sqlite3_finalize(insert_statement);

    try test_utils.bindInt64(insert_statement.?, 1, plan_id);
    step_result = c.sqlite3_step(insert_statement.?);

    // Should fail with SQLITE_CONSTRAINT due to UNIQUE(plan_id, plan_task_number)
    try std.testing.expectEqual(c.SQLITE_CONSTRAINT, step_result);
}
