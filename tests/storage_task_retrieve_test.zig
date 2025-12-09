//! Tests for task retrieval operations.
//!
//! Covers: getTask by ID, getTaskByPlanAndNumber resolution.

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
// Task Retrieval Tests (getTask with plan_slug JOIN)
// ============================================================================

test "getTask: retrieves task with plan_slug from JOIN" {
    // Methodology: Create task and retrieve it, verify plan_slug is populated
    // correctly from JOIN with plans table.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_task_with_slug.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and task
    try storage.createPlan("auth", "Authentication", "Auth system", null);
    const task_id = try storage.createTask("auth", "Login endpoint", "Add POST /login");

    // Retrieve task
    const maybe_task = try storage.getTask(task_id);
    try std.testing.expect(maybe_task != null);

    var task = maybe_task.?;
    defer task.deinit(allocator);

    // Assertions: Task fields match what was created
    try std.testing.expectEqual(task_id, task.id);
    try std.testing.expectEqual(@as(u32, 1), task.plan_task_number);
    try std.testing.expectEqualStrings("auth", task.plan_slug);
    try std.testing.expectEqualStrings("Login endpoint", task.title);
    try std.testing.expectEqualStrings("Add POST /login", task.description);
    try std.testing.expectEqual(TaskStatus.open, task.status);
}

test "getTask: returns null for nonexistent task" {
    // Methodology: Query nonexistent task ID, verify null is returned.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_task_nonexistent.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Query nonexistent task
    const maybe_task = try storage.getTask(999);
    try std.testing.expectEqual(@as(?types.Task, null), maybe_task);
}

// ============================================================================
// Task Lookup by Plan and Number (getTaskByPlanAndNumber)
// ============================================================================

test "getTaskByPlanAndNumber: resolves slug:number to internal ID" {
    // Methodology: Create task, lookup by slug:number, verify correct
    // internal task ID is returned.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_task_by_plan_and_number.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("auth", "Authentication", "", null);
    const task1 = try storage.createTask("auth", "Task 1", "");
    const task2 = try storage.createTask("auth", "Task 2", "");

    // Lookup tasks by slug:number
    const found1 = try storage.tasks.getTaskByPlanAndNumber("auth", 1);
    try std.testing.expectEqual(task1, found1.?);

    const found2 = try storage.tasks.getTaskByPlanAndNumber("auth", 2);
    try std.testing.expectEqual(task2, found2.?);
}

test "getTaskByPlanAndNumber: returns null for nonexistent combination" {
    // Methodology: Query nonexistent slug:number combinations, verify null.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_task_by_plan_and_number_null.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and one task
    try storage.createPlan("auth", "Authentication", "", null);
    _ = try storage.createTask("auth", "Task 1", "");

    // Query nonexistent plan slug
    const result1 = try storage.tasks.getTaskByPlanAndNumber("nonexistent", 1);
    try std.testing.expectEqual(@as(?u32, null), result1);

    // Query valid plan but nonexistent task number
    const result2 = try storage.tasks.getTaskByPlanAndNumber("auth", 999);
    try std.testing.expectEqual(@as(?u32, null), result2);
}

test "getTaskByPlanAndNumber: distinguishes tasks between plans" {
    // Methodology: Create tasks with same plan_task_number under different plans,
    // verify lookup correctly distinguishes them.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_task_by_plan_and_number_distinguish.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create two plans with tasks numbered 1
    try storage.createPlan("auth", "Authentication", "", null);
    try storage.createPlan("payments", "Payments", "", null);

    const auth_task1 = try storage.createTask("auth", "Auth Task 1", "");
    const pay_task1 = try storage.createTask("payments", "Payment Task 1", "");

    // Lookup should return correct internal IDs
    const found_auth = try storage.tasks.getTaskByPlanAndNumber("auth", 1);
    try std.testing.expectEqual(auth_task1, found_auth.?);

    const found_pay = try storage.tasks.getTaskByPlanAndNumber("payments", 1);
    try std.testing.expectEqual(pay_task1, found_pay.?);

    // Assertions: Internal IDs are different
    try std.testing.expect(auth_task1 != pay_task1);
}
