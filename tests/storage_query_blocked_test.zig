//! Tests for getBlockedTasks query operations.
//!
//! Covers: finding tasks blocked by incomplete dependencies.
//!
//! Tiger Style: Each test documents methodology, uses assertions,
//! and cleans up resources properly.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;

test "getBlockedTasks: returns blocked tasks with plan_slug" {
    // Methodology: Create tasks with dependencies, verify getBlockedTasks
    // returns only blocked tasks with plan_slug populated.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_blocked_tasks_with_slug.db";
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

    // Get blocked tasks
    const result = try storage.getBlockedTasks();
    defer {
        for (result.tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(result.tasks);
        allocator.free(result.blocker_counts);
    }

    // Verify results
    try std.testing.expectEqual(@as(usize, 1), result.tasks.len);
    try std.testing.expectEqual(task2, result.tasks[0].id);
    try std.testing.expectEqualStrings("auth", result.tasks[0].plan_slug);
    try std.testing.expectEqual(@as(u32, 1), result.blocker_counts[0]);
}

test "getBlockedTasks: excludes ready and completed tasks" {
    // Methodology: Create mix of ready, blocked, and completed tasks,
    // verify only blocked open/in_progress tasks are returned.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_blocked_tasks_excludes.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("auth", "Authentication", "", null);

    const task1 = try storage.createTask("auth", "Ready task", "");
    const task2 = try storage.createTask("auth", "Blocked task", "");
    const task3 = try storage.createTask("auth", "Completed blocker", "");
    const task4 = try storage.createTask("auth", "Task blocked by completed", "");

    // Add dependencies
    try storage.addDependency(task2, task1); // task2 blocked by task1
    try storage.addDependency(task4, task3); // task4 blocked by task3

    // Complete task3
    try storage.startTask(task3);
    try storage.completeTask(task3);

    // Get blocked tasks
    const result = try storage.getBlockedTasks();
    defer {
        for (result.tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(result.tasks);
        allocator.free(result.blocker_counts);
    }

    // Only task2 should be blocked (task4 is no longer blocked since task3 is completed)
    try std.testing.expectEqual(@as(usize, 1), result.tasks.len);
    try std.testing.expectEqual(task2, result.tasks[0].id);
}

test "getBlockedTasks: correct blocker counts" {
    // Methodology: Create tasks with multiple blockers, verify blocker_counts
    // are accurate.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_blocked_tasks_counts.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("auth", "Authentication", "", null);

    const blocker1 = try storage.createTask("auth", "Blocker 1", "");
    const blocker2 = try storage.createTask("auth", "Blocker 2", "");
    const blocker3 = try storage.createTask("auth", "Blocker 3", "");
    const blocked = try storage.createTask("auth", "Blocked task", "");

    // Add multiple dependencies
    try storage.addDependency(blocked, blocker1);
    try storage.addDependency(blocked, blocker2);
    try storage.addDependency(blocked, blocker3);

    // Get blocked tasks
    const result = try storage.getBlockedTasks();
    defer {
        for (result.tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(result.tasks);
        allocator.free(result.blocker_counts);
    }

    // Verify blocker count
    try std.testing.expectEqual(@as(usize, 1), result.tasks.len);
    try std.testing.expectEqual(blocked, result.tasks[0].id);
    try std.testing.expectEqual(@as(u32, 3), result.blocker_counts[0]);
}

test "getBlockedTasks: sorted by blocker_count descending" {
    // Methodology: Create tasks with different blocker counts, verify
    // results are sorted by blocker_count (highest first).
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_blocked_tasks_sorting.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("auth", "Authentication", "", null);

    const blocker1 = try storage.createTask("auth", "Blocker 1", "");
    const blocker2 = try storage.createTask("auth", "Blocker 2", "");
    const blocker3 = try storage.createTask("auth", "Blocker 3", "");

    const blocked1 = try storage.createTask("auth", "Blocked by 1", ""); // 1 blocker
    const blocked2 = try storage.createTask("auth", "Blocked by 3", ""); // 3 blockers
    const blocked3 = try storage.createTask("auth", "Blocked by 2", ""); // 2 blockers

    // Add dependencies
    try storage.addDependency(blocked1, blocker1);

    try storage.addDependency(blocked2, blocker1);
    try storage.addDependency(blocked2, blocker2);
    try storage.addDependency(blocked2, blocker3);

    try storage.addDependency(blocked3, blocker1);
    try storage.addDependency(blocked3, blocker2);

    // Get blocked tasks
    const result = try storage.getBlockedTasks();
    defer {
        for (result.tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(result.tasks);
        allocator.free(result.blocker_counts);
    }

    // Verify sorting: blocked2 (3), blocked3 (2), blocked1 (1)
    try std.testing.expectEqual(@as(usize, 3), result.tasks.len);
    try std.testing.expectEqual(@as(u32, 3), result.blocker_counts[0]);
    try std.testing.expectEqual(@as(u32, 2), result.blocker_counts[1]);
    try std.testing.expectEqual(@as(u32, 1), result.blocker_counts[2]);
}

test "getBlockedTasks: spans multiple plans" {
    // Methodology: Create blocked tasks under different plans, verify
    // getBlockedTasks returns tasks from all plans with correct plan_slug.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_get_blocked_tasks_multiple_plans.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plans and tasks
    try storage.createPlan("auth", "Authentication", "", null);
    try storage.createPlan("payments", "Payments", "", null);

    const auth_blocker = try storage.createTask("auth", "Auth blocker", "");
    const auth_blocked = try storage.createTask("auth", "Auth blocked", "");
    const pay_blocker = try storage.createTask("payments", "Payment blocker", "");
    const pay_blocked = try storage.createTask("payments", "Payment blocked", "");

    // Add dependencies
    try storage.addDependency(auth_blocked, auth_blocker);
    try storage.addDependency(pay_blocked, pay_blocker);

    // Get blocked tasks
    const result = try storage.getBlockedTasks();
    defer {
        for (result.tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(result.tasks);
        allocator.free(result.blocker_counts);
    }

    // Should have both blocked tasks with correct plan_slug
    try std.testing.expectEqual(@as(usize, 2), result.tasks.len);

    var found_auth = false;
    var found_pay = false;
    for (result.tasks) |task| {
        if (task.id == auth_blocked) {
            try std.testing.expectEqualStrings("auth", task.plan_slug);
            found_auth = true;
        }
        if (task.id == pay_blocked) {
            try std.testing.expectEqualStrings("payments", task.plan_slug);
            found_pay = true;
        }
    }
    try std.testing.expect(found_auth);
    try std.testing.expect(found_pay);
}
