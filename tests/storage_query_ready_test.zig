//! Tests for getReadyTasks query operations.
//!
//! Covers: finding tasks with no incomplete blockers.
//!
//! Tiger Style: Each test documents methodology, uses assertions,
//! and cleans up resources properly.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;

test "getReadyTasks: returns ready tasks with plan_slug" {
    // Methodology: Create tasks with and without dependencies, verify
    // getReadyTasks returns only unblocked tasks with plan_slug populated.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_ready_tasks_with_slug.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("auth", "Authentication", "", null);

    const task1 = try storage.createTask("auth", "Task 1", "");
    const task2 = try storage.createTask("auth", "Task 2", "");
    _ = try storage.createTask("auth", "Task 3", "");

    // Add dependency: task2 blocks on task1
    try storage.addDependency(task2, task1);

    // Get ready tasks (should be task1 and task3, not task2)
    const ready_tasks = try storage.getReadyTasks(0);
    defer {
        for (ready_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(ready_tasks);
    }

    // Verify results
    try std.testing.expectEqual(@as(usize, 2), ready_tasks.len);

    // All tasks should have plan_slug populated
    for (ready_tasks) |task| {
        try std.testing.expectEqualStrings("auth", task.plan_slug);
        try std.testing.expect(task.plan_task_number > 0);
    }

    // task2 should not be in ready list
    for (ready_tasks) |task| {
        try std.testing.expect(task.id != task2);
    }
}

test "getReadyTasks: respects limit parameter" {
    // Methodology: Create multiple ready tasks, verify limit parameter
    // constrains result set size.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_ready_tasks_limit.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("auth", "Authentication", "", null);

    _ = try storage.createTask("auth", "Task 1", "");
    _ = try storage.createTask("auth", "Task 2", "");
    _ = try storage.createTask("auth", "Task 3", "");
    _ = try storage.createTask("auth", "Task 4", "");
    _ = try storage.createTask("auth", "Task 5", "");

    // Get ready tasks with limit
    const limited_tasks = try storage.getReadyTasks(2);
    defer {
        for (limited_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(limited_tasks);
    }

    try std.testing.expectEqual(@as(usize, 2), limited_tasks.len);

    // Get all ready tasks (limit 0 = unlimited)
    const all_tasks = try storage.getReadyTasks(0);
    defer {
        for (all_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(all_tasks);
    }

    try std.testing.expectEqual(@as(usize, 5), all_tasks.len);
}

test "getReadyTasks: excludes tasks with incomplete dependencies" {
    // Methodology: Create dependency chain, verify only leaf nodes
    // (tasks with no dependencies) are returned as ready.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_ready_tasks_dependencies.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("auth", "Authentication", "", null);

    const task1 = try storage.createTask("auth", "Task 1", "");
    const task2 = try storage.createTask("auth", "Task 2", "");
    const task3 = try storage.createTask("auth", "Task 3", "");

    // Create chain: task3 -> task2 -> task1
    try storage.addDependency(task2, task1);
    try storage.addDependency(task3, task2);

    // Only task1 should be ready
    const ready_tasks = try storage.getReadyTasks(0);
    defer {
        for (ready_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(ready_tasks);
    }

    try std.testing.expectEqual(@as(usize, 1), ready_tasks.len);
    try std.testing.expectEqual(task1, ready_tasks[0].id);
}

test "getReadyTasks: includes tasks after blocker is completed" {
    // Methodology: Complete blocking task, verify dependent task becomes ready.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_ready_tasks_after_completion.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("auth", "Authentication", "", null);

    const task1 = try storage.createTask("auth", "Task 1", "");
    const task2 = try storage.createTask("auth", "Task 2", "");

    // Add dependency: task2 blocks on task1
    try storage.addDependency(task2, task1);

    // Initially, only task1 is ready
    const ready_before = try storage.getReadyTasks(0);
    defer {
        for (ready_before) |*task| {
            task.deinit(allocator);
        }
        allocator.free(ready_before);
    }
    try std.testing.expectEqual(@as(usize, 1), ready_before.len);
    try std.testing.expectEqual(task1, ready_before[0].id);

    // Complete task1
    try storage.startTask(task1);
    try storage.completeTask(task1);

    // Now task2 should be ready
    const ready_after = try storage.getReadyTasks(0);
    defer {
        for (ready_after) |*task| {
            task.deinit(allocator);
        }
        allocator.free(ready_after);
    }
    try std.testing.expectEqual(@as(usize, 1), ready_after.len);
    try std.testing.expectEqual(task2, ready_after[0].id);
}

test "getReadyTasks: spans multiple plans" {
    // Methodology: Create ready tasks under different plans, verify
    // getReadyTasks returns tasks from all plans with correct plan_slug.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_ready_tasks_multiple_plans.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plans and tasks
    try storage.createPlan("auth", "Authentication", "", null);
    try storage.createPlan("payments", "Payments", "", null);

    const auth_task = try storage.createTask("auth", "Auth task", "");
    const pay_task = try storage.createTask("payments", "Payment task", "");

    // Get ready tasks
    const ready_tasks = try storage.getReadyTasks(0);
    defer {
        for (ready_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(ready_tasks);
    }

    // Should have both tasks with correct plan_slug
    try std.testing.expectEqual(@as(usize, 2), ready_tasks.len);

    // Find auth task
    var found_auth = false;
    var found_pay = false;
    for (ready_tasks) |task| {
        if (task.id == auth_task) {
            try std.testing.expectEqualStrings("auth", task.plan_slug);
            found_auth = true;
        }
        if (task.id == pay_task) {
            try std.testing.expectEqualStrings("payments", task.plan_slug);
            found_pay = true;
        }
    }
    try std.testing.expect(found_auth);
    try std.testing.expect(found_pay);
}
