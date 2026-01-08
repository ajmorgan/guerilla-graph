//! Tests for listTasks query operations.
//!
//! Covers: listing tasks with filters (status, plan), ordering, pagination.
//!
//! Tiger Style: Each test documents methodology, uses assertions,
//! and cleans up resources properly.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;
const types = guerilla_graph.types;
const TaskStatus = types.TaskStatus;

test "listTasks: returns tasks with plan_slug populated" {
    // Methodology: Create tasks under multiple plans, list all tasks,
    // verify plan_slug is correctly populated from JOIN.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_list_tasks_with_slug.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plans and tasks
    try storage.createPlan("auth", "Authentication", "", null);
    try storage.createPlan("payments", "Payments", "", null);

    _ = try storage.createTask("auth", "Auth task 1", "");
    _ = try storage.createTask("auth", "Auth task 2", "");
    _ = try storage.createTask("payments", "Payment task 1", "");

    // List all tasks
    const tasks = try storage.listTasks(null, null);
    defer {
        for (tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(tasks);
    }

    // Verify results
    try std.testing.expectEqual(@as(usize, 3), tasks.len);

    // Tasks should be sorted by plan_id, then plan_task_number
    // Auth tasks come first (assuming auth plan has lower id)
    try std.testing.expectEqualStrings("auth", tasks[0].plan_slug);
    try std.testing.expectEqual(@as(u32, 1), tasks[0].plan_task_number);
    try std.testing.expectEqualStrings("Auth task 1", tasks[0].title);

    try std.testing.expectEqualStrings("auth", tasks[1].plan_slug);
    try std.testing.expectEqual(@as(u32, 2), tasks[1].plan_task_number);
    try std.testing.expectEqualStrings("Auth task 2", tasks[1].title);

    try std.testing.expectEqualStrings("payments", tasks[2].plan_slug);
    try std.testing.expectEqual(@as(u32, 1), tasks[2].plan_task_number);
    try std.testing.expectEqualStrings("Payment task 1", tasks[2].title);
}

test "listTasks: filter by status" {
    // Methodology: Create tasks with different statuses, filter by status,
    // verify only matching tasks are returned.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_list_tasks_filter_status.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("auth", "Authentication", "", null);

    const task1 = try storage.createTask("auth", "Task 1", "");
    const task2 = try storage.createTask("auth", "Task 2", "");
    _ = try storage.createTask("auth", "Task 3", "");

    // Start task1
    try storage.startTask(task1);

    // Complete task2
    try storage.startTask(task2);
    try storage.completeTask(task2);

    // task3 remains open

    // Filter by open status
    const open_tasks = try storage.listTasks(TaskStatus.open, null);
    defer {
        for (open_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(open_tasks);
    }
    try std.testing.expectEqual(@as(usize, 1), open_tasks.len);
    try std.testing.expectEqual(TaskStatus.open, open_tasks[0].status);

    // Filter by in_progress status
    const in_progress_tasks = try storage.listTasks(TaskStatus.in_progress, null);
    defer {
        for (in_progress_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(in_progress_tasks);
    }
    try std.testing.expectEqual(@as(usize, 1), in_progress_tasks.len);
    try std.testing.expectEqual(TaskStatus.in_progress, in_progress_tasks[0].status);

    // Filter by completed status
    const completed_tasks = try storage.listTasks(TaskStatus.completed, null);
    defer {
        for (completed_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(completed_tasks);
    }
    try std.testing.expectEqual(@as(usize, 1), completed_tasks.len);
    try std.testing.expectEqual(TaskStatus.completed, completed_tasks[0].status);
}

test "listTasks: filter by plan slug" {
    // Methodology: Create tasks under multiple plans, filter by plan slug,
    // verify only tasks from that plan are returned.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_list_tasks_filter_plan.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plans and tasks
    try storage.createPlan("auth", "Authentication", "", null);
    try storage.createPlan("payments", "Payments", "", null);

    _ = try storage.createTask("auth", "Auth task 1", "");
    _ = try storage.createTask("auth", "Auth task 2", "");
    _ = try storage.createTask("payments", "Payment task 1", "");

    // Filter by auth plan
    const auth_tasks = try storage.listTasks(null, "auth");
    defer {
        for (auth_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(auth_tasks);
    }

    try std.testing.expectEqual(@as(usize, 2), auth_tasks.len);
    for (auth_tasks) |task| {
        try std.testing.expectEqualStrings("auth", task.plan_slug);
    }

    // Filter by payments plan
    const payment_tasks = try storage.listTasks(null, "payments");
    defer {
        for (payment_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(payment_tasks);
    }

    try std.testing.expectEqual(@as(usize, 1), payment_tasks.len);
    try std.testing.expectEqualStrings("payments", payment_tasks[0].plan_slug);
}

test "listTasks: filter by both status and plan" {
    // Methodology: Create tasks under multiple plans with different statuses,
    // filter by both status and plan, verify correct subset is returned.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_list_tasks_filter_both.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plans and tasks
    try storage.createPlan("auth", "Authentication", "", null);
    try storage.createPlan("payments", "Payments", "", null);

    const auth1 = try storage.createTask("auth", "Auth task 1", "");
    _ = try storage.createTask("auth", "Auth task 2", "");
    const pay1 = try storage.createTask("payments", "Payment task 1", "");

    // Start auth1 and pay1
    try storage.startTask(auth1);
    try storage.startTask(pay1);

    // Filter by in_progress status and auth plan
    const filtered_tasks = try storage.listTasks(TaskStatus.in_progress, "auth");
    defer {
        for (filtered_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(filtered_tasks);
    }

    // Should only return auth task 1 (in_progress)
    try std.testing.expectEqual(@as(usize, 1), filtered_tasks.len);
    try std.testing.expectEqualStrings("auth", filtered_tasks[0].plan_slug);
    try std.testing.expectEqual(TaskStatus.in_progress, filtered_tasks[0].status);
    try std.testing.expectEqualStrings("Auth task 1", filtered_tasks[0].title);
}

test "listTasks: empty result for nonexistent plan" {
    // Methodology: Filter by nonexistent plan slug, verify empty array is returned.
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_list_tasks_empty_result.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plan and task
    try storage.createPlan("auth", "Authentication", "", null);
    _ = try storage.createTask("auth", "Task", "");

    // Filter by nonexistent plan
    const tasks = try storage.listTasks(null, "nonexistent");
    defer allocator.free(tasks);

    try std.testing.expectEqual(@as(usize, 0), tasks.len);
}

test "listTasks: sorting by created_at ascending" {
    // Methodology: Create tasks in random order, verify listTasks returns
    // them sorted by created_at (oldest first).
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    const temp_path = "/tmp/test_list_tasks_sorting.db";
    std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.Io.Dir.deleteFileAbsolute(io, temp_path) catch {};

    // Create plans in specific order
    try storage.createPlan("auth", "Authentication", "", null);
    try storage.createPlan("payments", "Payments", "", null);

    // Create tasks in mixed order
    _ = try storage.createTask("payments", "Pay 1", "");
    _ = try storage.createTask("auth", "Auth 2", "");
    _ = try storage.createTask("auth", "Auth 1", "");
    _ = try storage.createTask("payments", "Pay 2", "");

    // List all tasks
    const tasks = try storage.listTasks(null, null);
    defer {
        for (tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(tasks);
    }

    // Verify sorting: chronological order (oldest first)
    try std.testing.expectEqual(@as(usize, 4), tasks.len);

    // First task: "Pay 1" (created first)
    try std.testing.expectEqualStrings("Pay 1", tasks[0].title);
    try std.testing.expectEqualStrings("payments", tasks[0].plan_slug);

    // Second task: "Auth 2" (created second)
    try std.testing.expectEqualStrings("Auth 2", tasks[1].title);
    try std.testing.expectEqualStrings("auth", tasks[1].plan_slug);

    // Third task: "Auth 1" (created third)
    try std.testing.expectEqualStrings("Auth 1", tasks[2].title);
    try std.testing.expectEqualStrings("auth", tasks[2].plan_slug);

    // Fourth task: "Pay 2" (created fourth)
    try std.testing.expectEqualStrings("Pay 2", tasks[3].title);
    try std.testing.expectEqualStrings("payments", tasks[3].plan_slug);

    // Verify chronological ordering by timestamps (timestamps may be equal due to second-level resolution)
    try std.testing.expect(tasks[0].created_at <= tasks[1].created_at);
    try std.testing.expect(tasks[1].created_at <= tasks[2].created_at);
    try std.testing.expect(tasks[2].created_at <= tasks[3].created_at);
}
