//! Tests for TaskManager initialization and basic delegation.
//!
//! Extracted from task_manager_test.zig - covers init/deinit and simple delegation tests.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const TaskManager = guerilla_graph.task_manager.TaskManager;
const Storage = guerilla_graph.storage.Storage;
const types = guerilla_graph.types;
const test_utils = @import("test_utils.zig");

test "TaskManager: init and deinit" {
    const allocator = std.testing.allocator;

    // Create temporary storage for testing
    const temp_path = "/tmp/test_task_manager_init.db";
    var test_storage = try Storage.init(allocator, temp_path);
    defer test_storage.deinit();

    // Initialize TaskManager with storage
    var task_manager = TaskManager.init(allocator, &test_storage);
    defer task_manager.deinit();

    // Assertions: Verify task_manager initialized correctly
    try std.testing.expectEqual(allocator, task_manager.allocator);
    try std.testing.expect(task_manager.storage == &test_storage);
}

test "TaskManager: createPlan delegates to storage" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create temporary storage for testing
    const temp_path = "/tmp/test_task_manager_create_plan.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var test_storage = try Storage.init(allocator, temp_path);
    defer test_storage.deinit();

    // Initialize TaskManager with storage
    var task_manager = TaskManager.init(allocator, &test_storage);
    defer task_manager.deinit();

    // Test createPlan succeeds
    try task_manager.createPlan("auth", "Authentication", "User auth system");

    // Assertions: Plan was created in storage
    try std.testing.expect(test_storage.database != null);

    // Verify plan can be retrieved
    const plan_opt = try task_manager.getPlan("auth");
    try std.testing.expect(plan_opt != null);
    if (plan_opt) |p| {
        var plan_copy = p;
        defer plan_copy.deinit(allocator);
        try std.testing.expectEqualStrings("auth", plan_copy.slug);
    }
}

test "TaskManager: createTask with no dependencies" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Create temporary storage for testing
    const temp_path = "/tmp/test_task_manager_create_task.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var test_storage = try Storage.init(allocator, temp_path);
    defer test_storage.deinit();

    // Initialize TaskManager with storage
    var task_manager = TaskManager.init(allocator, &test_storage);
    defer task_manager.deinit();

    // Create plan first
    try task_manager.createPlan("auth", "Authentication", "");

    // Test createTask with empty dependencies
    const empty_deps: []const u32 = &[_]u32{};
    const task_id: u32 = try task_manager.createTask("auth", "Add login", "Implement endpoint", empty_deps);

    // Assertion: Task ID was created with correct value
    try std.testing.expect(task_id > 0);
    try std.testing.expectEqual(@as(u32, 1), task_id);
}

test "TaskManager: getPlan returns null for nonexistent plan" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_task_manager_get_plan.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var test_storage = try Storage.init(allocator, temp_path);
    defer test_storage.deinit();

    var task_manager = TaskManager.init(allocator, &test_storage);
    defer task_manager.deinit();

    // Test getPlan returns null for missing plan
    const result = try task_manager.getPlan("nonexistent");
    try std.testing.expect(result == null);

    // Positive space: Create and retrieve a plan to verify getPlan works correctly
    try task_manager.createPlan("auth", "Authentication", "");
    const found_plan_opt = try task_manager.getPlan("auth");
    try std.testing.expect(found_plan_opt != null);
    if (found_plan_opt) |p| {
        var plan_copy = p;
        defer plan_copy.deinit(allocator);
    }
}

test "TaskManager: getTask returns null for nonexistent task" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_task_manager_get_task.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var test_storage = try Storage.init(allocator, temp_path);
    defer test_storage.deinit();

    var task_manager = TaskManager.init(allocator, &test_storage);
    defer task_manager.deinit();

    // Test getTask returns null for missing task
    const result = try task_manager.getTask(999);
    try std.testing.expect(result == null);

    // Positive space: Create and retrieve a task to verify getTask works correctly
    try task_manager.createPlan("auth", "Authentication", "");
    const empty_deps: []const u32 = &[_]u32{};
    const task_id = try task_manager.createTask("auth", "Test task", "", empty_deps);

    const found_task_opt = try task_manager.getTask(task_id);
    try std.testing.expect(found_task_opt != null);
    if (found_task_opt) |t| {
        var task_copy = t;
        defer task_copy.deinit(allocator);
    }
}
