//! Tests for SQLite storage layer query operations (storage.zig).
//!
//! Covers: listTasks, getReadyTasks, getBlockedTasks with various filters and edge cases.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const Storage = guerilla_graph.storage.Storage;
const SqliteError = guerilla_graph.storage.SqliteError;
const types = guerilla_graph.types;
const TaskStatus = types.TaskStatus;
// Use re-exported C types from storage to ensure type compatibility
const c = guerilla_graph.storage.c_funcs;

fn getTemporaryDatabasePath(allocator: std.mem.Allocator, test_name: []const u8) ![]u8 {
    var path_buffer: [256]u8 = undefined;
    const temp_path = try std.fmt.bufPrint(&path_buffer, "/tmp/guerilla_graph_storage_{s}.db", .{test_name});
    return try allocator.dupe(u8, temp_path);
}

fn cleanupDatabaseFile(database_path: []const u8) void {
    std.fs.cwd().deleteFile(database_path) catch {};
}

fn bindText(statement: *c.sqlite3_stmt, index: c_int, text: []const u8) !void {
    const result = c.sqlite3_bind_text(statement, index, text.ptr, @intCast(text.len), null);
    if (result != c.SQLITE_OK) return SqliteError.BindFailed;
}

fn bindInt64(statement: *c.sqlite3_stmt, index: c_int, value: i64) !void {
    const result = c.sqlite3_bind_int64(statement, index, value);
    if (result != c.SQLITE_OK) return SqliteError.BindFailed;
}

// ========== Query Operation Tests ==========
// Methodology: Test getReadyTasks, getBlockedTasks, listTasks filters, and edge cases
// Tiger Style: 2+ assertions per test, clear test names, edge case coverage

test "listTasks: filters by status" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_list_tasks_status.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks with different statuses
    try storage.createPlan("test", "Test", "Test tasks", null);
    const task1: u32 = try storage.createTask("test", "Task 1", "Desc 1");
    const task2: u32 = try storage.createTask("test", "Task 2", "Desc 2");
    const task3: u32 = try storage.createTask("test", "Task 3", "Desc 3");

    // Change statuses
    try storage.startTask(task2);
    try storage.startTask(task3);
    try storage.completeTask(task3);

    // List only 'open' tasks
    const open_tasks = try storage.listTasks(types.TaskStatus.open, null);
    defer {
        for (open_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(open_tasks);
    }

    try std.testing.expectEqual(@as(usize, 1), open_tasks.len);
    try std.testing.expectEqual(task1, open_tasks[0].id);
}

test "listTasks: filters by plan" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_list_tasks_plan.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create two plans with tasks
    try storage.createPlan("frontend", "Frontend", "Frontend work", null);
    try storage.createPlan("backend", "Backend", "Backend work", null);

    _ = try storage.createTask("frontend", "UI Task", "Build UI");
    _ = try storage.createTask("backend", "API Task", "Build API");
    _ = try storage.createTask("frontend", "CSS Task", "Style components");

    // List only 'frontend' tasks
    const frontend_tasks = try storage.listTasks(null, "frontend");
    defer {
        for (frontend_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(frontend_tasks);
    }

    try std.testing.expectEqual(@as(usize, 2), frontend_tasks.len);
    try std.testing.expectEqualStrings("frontend", frontend_tasks[0].plan.?);
    try std.testing.expectEqualStrings("frontend", frontend_tasks[1].plan.?);
}

test "getReadyTasks: returns tasks with no dependencies" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_ready_tasks_no_deps.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks with no dependencies
    try storage.createPlan("backend", "Backend", "Backend work", null);
    const task1: u32 = try storage.createTask("backend", "Task 1", "First task");
    _ = try storage.createTask("backend", "Task 2", "Second task");
    _ = try storage.createTask("backend", "Task 3", "Third task");

    // Get ready tasks
    const ready_tasks = try storage.getReadyTasks(10);
    defer {
        for (ready_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(ready_tasks);
    }

    // Assertions: All 3 tasks should be ready (no dependencies)
    try std.testing.expectEqual(@as(usize, 3), ready_tasks.len);
    try std.testing.expectEqual(task1, ready_tasks[0].id);
    try std.testing.expectEqual(types.TaskStatus.open, ready_tasks[0].status);
}

test "getReadyTasks: excludes tasks with incomplete dependencies" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_ready_tasks_with_blockers.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("api", "API", "API development", null);
    const task1: u32 = try storage.createTask("api", "Task 1", "Blocker task");
    const task2: u32 = try storage.createTask("api", "Task 2", "Blocked task");
    const task3: u32 = try storage.createTask("api", "Task 3", "Independent task");

    // Add dependency: task2 blocks on task1
    try storage.addDependency(task2, task1);

    // Get ready tasks
    const ready_tasks = try storage.getReadyTasks(10);
    defer {
        for (ready_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(ready_tasks);
    }

    // Assertions: Only task1 and task3 should be ready (task2 is blocked)
    try std.testing.expectEqual(@as(usize, 2), ready_tasks.len);
    // Should contain task1 and task3, but not task2
    var found_task1 = false;
    var found_task3 = false;
    for (ready_tasks) |task| {
        if (task.id == task1) found_task1 = true;
        if (task.id == task3) found_task3 = true;
    }
    try std.testing.expect(found_task1);
    try std.testing.expect(found_task3);
}

test "getReadyTasks: includes tasks when blockers are completed" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_ready_tasks_completed_blockers.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("deploy", "Deploy", "Deployment tasks", null);
    const task1: u32 = try storage.createTask("deploy", "Task 1", "Blocker task");
    const task2: u32 = try storage.createTask("deploy", "Task 2", "Blocked task");

    // Add dependency: task2 blocks on task1
    try storage.addDependency(task2, task1);

    // Complete task1 (the blocker)
    try storage.startTask(task1);
    try storage.completeTask(task1);

    // Get ready tasks
    const ready_tasks = try storage.getReadyTasks(10);
    defer {
        for (ready_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(ready_tasks);
    }

    // Assertions: task2 should now be ready since task1 is completed
    try std.testing.expectEqual(@as(usize, 1), ready_tasks.len);
    try std.testing.expectEqual(task2, ready_tasks[0].id);
}

test "getReadyTasks: respects limit parameter" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_ready_tasks_limit.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and 5 tasks
    try storage.createPlan("test", "Test", "Test tasks", null);
    _ = try storage.createTask("test", "Task 1", "First task");
    _ = try storage.createTask("test", "Task 2", "Second task");
    _ = try storage.createTask("test", "Task 3", "Third task");
    _ = try storage.createTask("test", "Task 4", "Fourth task");
    _ = try storage.createTask("test", "Task 5", "Fifth task");

    // Get ready tasks with limit of 3
    const ready_tasks = try storage.getReadyTasks(3);
    defer {
        for (ready_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(ready_tasks);
    }

    // Assertions: Should return exactly 3 tasks (respecting limit)
    try std.testing.expectEqual(@as(usize, 3), ready_tasks.len);
}

test "getReadyTasks: empty result when no tasks exist" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_ready_tasks_empty.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan but no tasks
    try storage.createPlan("empty", "Empty", "No tasks", null);

    // Get ready tasks
    const ready_tasks = try storage.getReadyTasks(10);
    defer allocator.free(ready_tasks);

    // Assertions: Should return empty slice
    try std.testing.expectEqual(@as(usize, 0), ready_tasks.len);
}

test "getReadyTasks: empty result when all tasks completed" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_ready_tasks_all_completed.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("done", "Done", "Completed tasks", null);
    const task1: u32 = try storage.createTask("done", "Task 1", "First task");
    const task2: u32 = try storage.createTask("done", "Task 2", "Second task");

    // Complete all tasks
    try storage.startTask(task1);
    try storage.completeTask(task1);
    try storage.startTask(task2);
    try storage.completeTask(task2);

    // Get ready tasks
    const ready_tasks = try storage.getReadyTasks(10);
    defer allocator.free(ready_tasks);

    // Assertions: Should return empty slice (no open tasks)
    try std.testing.expectEqual(@as(usize, 0), ready_tasks.len);
}

test "getBlockedTasks: returns tasks with incomplete dependencies" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_blocked_tasks_basic.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("feature", "Feature", "Feature work", null);
    const task1: u32 = try storage.createTask("feature", "Task 1", "Blocker task");
    const task2: u32 = try storage.createTask("feature", "Task 2", "Blocked task");
    _ = try storage.createTask("feature", "Task 3", "Ready task");

    // Add dependency: task2 blocks on task1
    try storage.addDependency(task2, task1);

    // Get blocked tasks
    var blocked_tasks = try storage.getBlockedTasks();
    defer blocked_tasks.deinit(allocator);

    // Assertions: Only task2 should be blocked
    try std.testing.expectEqual(@as(usize, 1), blocked_tasks.tasks.len);
    try std.testing.expectEqual(task2, blocked_tasks.tasks[0].id);
    try std.testing.expectEqual(types.TaskStatus.open, blocked_tasks.tasks[0].status);
}

test "getBlockedTasks: empty result when no blocked tasks" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_blocked_tasks_empty.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks with no dependencies
    try storage.createPlan("ready", "Ready", "All ready", null);
    _ = try storage.createTask("ready", "Task 1", "First task");
    _ = try storage.createTask("ready", "Task 2", "Second task");

    // Get blocked tasks
    var blocked_tasks = try storage.getBlockedTasks();
    defer blocked_tasks.deinit(allocator);

    // Assertions: Should return empty slice (no blocked tasks)
    try std.testing.expectEqual(@as(usize, 0), blocked_tasks.tasks.len);
}

test "getBlockedTasks: excludes tasks when blockers are completed" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_blocked_tasks_completed_blocker.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("unblock", "Unblock", "Unblocking tasks", null);
    const task1: u32 = try storage.createTask("unblock", "Task 1", "Blocker task");
    const task2: u32 = try storage.createTask("unblock", "Task 2", "Blocked task");

    // Add dependency: task2 blocks on task1
    try storage.addDependency(task2, task1);

    // Complete the blocker task
    try storage.startTask(task1);
    try storage.completeTask(task1);

    // Get blocked tasks
    var blocked_tasks = try storage.getBlockedTasks();
    defer blocked_tasks.deinit(allocator);

    // Assertions: Should return empty slice (blocker is completed)
    try std.testing.expectEqual(@as(usize, 0), blocked_tasks.tasks.len);
}

test "getBlockedTasks: orders by blocker count descending" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_blocked_tasks_ordering.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("ordering", "Ordering", "Test ordering", null);
    const blocker1: u32 = try storage.createTask("ordering", "Blocker 1", "First blocker");
    const blocker2: u32 = try storage.createTask("ordering", "Blocker 2", "Second blocker");
    const blocker3: u32 = try storage.createTask("ordering", "Blocker 3", "Third blocker");
    const task_one_blocker: u32 = try storage.createTask("ordering", "Task 1 Blocker", "Has 1 blocker");
    const task_two_blockers: u32 = try storage.createTask("ordering", "Task 2 Blockers", "Has 2 blockers");
    const task_three_blockers: u32 = try storage.createTask("ordering", "Task 3 Blockers", "Has 3 blockers");

    // Add dependencies: different blocker counts
    try storage.addDependency(task_one_blocker, blocker1);
    try storage.addDependency(task_two_blockers, blocker1);
    try storage.addDependency(task_two_blockers, blocker2);
    try storage.addDependency(task_three_blockers, blocker1);
    try storage.addDependency(task_three_blockers, blocker2);
    try storage.addDependency(task_three_blockers, blocker3);

    // Get blocked tasks
    var blocked_tasks = try storage.getBlockedTasks();
    defer blocked_tasks.deinit(allocator);

    // Assertions: Should return 3 tasks, ordered by blocker count DESC
    try std.testing.expectEqual(@as(usize, 3), blocked_tasks.tasks.len);
    try std.testing.expectEqual(task_three_blockers, blocked_tasks.tasks[0].id);
    try std.testing.expectEqual(task_two_blockers, blocked_tasks.tasks[1].id);
    try std.testing.expectEqual(task_one_blocker, blocked_tasks.tasks[2].id);
}

test "listTasks: no filters returns all tasks" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_list_tasks_no_filter.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks with different statuses
    try storage.createPlan("all", "All", "All tasks", null);
    _ = try storage.createTask("all", "Task 1", "Open task");
    const task2: u32 = try storage.createTask("all", "Task 2", "In progress task");
    const task3: u32 = try storage.createTask("all", "Task 3", "Completed task");

    // Change statuses
    try storage.startTask(task2);
    try storage.startTask(task3);
    try storage.completeTask(task3);

    // List all tasks (no filters)
    const all_tasks = try storage.listTasks(null, null);
    defer {
        for (all_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(all_tasks);
    }

    // Assertions: Should return all 3 tasks
    try std.testing.expectEqual(@as(usize, 3), all_tasks.len);
}

test "listTasks: filters by in_progress status" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_list_tasks_in_progress.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks with different statuses
    try storage.createPlan("work", "Work", "Work tasks", null);
    _ = try storage.createTask("work", "Task 1", "Open task");
    const task2: u32 = try storage.createTask("work", "Task 2", "In progress 1");
    const task3: u32 = try storage.createTask("work", "Task 3", "In progress 2");

    // Set statuses
    try storage.startTask(task2);
    try storage.startTask(task3);

    // List only in_progress tasks
    const in_progress_tasks = try storage.listTasks(types.TaskStatus.in_progress, null);
    defer {
        for (in_progress_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(in_progress_tasks);
    }

    // Assertions: Should return only 2 in_progress tasks
    try std.testing.expectEqual(@as(usize, 2), in_progress_tasks.len);
    try std.testing.expectEqual(types.TaskStatus.in_progress, in_progress_tasks[0].status);
    try std.testing.expectEqual(types.TaskStatus.in_progress, in_progress_tasks[1].status);
}

test "listTasks: filters by completed status" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_list_tasks_completed.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks
    try storage.createPlan("finish", "Finish", "Finished tasks", null);
    _ = try storage.createTask("finish", "Task 1", "Open task");
    const task2: u32 = try storage.createTask("finish", "Task 2", "Completed task");

    // Complete task2
    try storage.startTask(task2);
    try storage.completeTask(task2);

    // List only completed tasks
    const completed_tasks = try storage.listTasks(types.TaskStatus.completed, null);
    defer {
        for (completed_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(completed_tasks);
    }

    // Assertions: Should return only 1 completed task
    try std.testing.expectEqual(@as(usize, 1), completed_tasks.len);
    try std.testing.expectEqual(task2, completed_tasks[0].id);
    try std.testing.expectEqual(types.TaskStatus.completed, completed_tasks[0].status);
}

test "listTasks: combines status and plan filters" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_list_tasks_combined.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create two plans with tasks
    try storage.createPlan("ui", "UI", "UI work", null);
    try storage.createPlan("api", "API", "API work", null);

    _ = try storage.createTask("ui", "UI Task 1", "UI open");
    const ui_task2: u32 = try storage.createTask("ui", "UI Task 2", "UI in progress");
    _ = try storage.createTask("api", "API Task 1", "API open");
    const api_task2: u32 = try storage.createTask("api", "API Task 2", "API in progress");

    // Set statuses
    try storage.startTask(ui_task2);
    try storage.startTask(api_task2);

    // List only in_progress tasks for UI plan
    const filtered_tasks = try storage.listTasks(types.TaskStatus.in_progress, "ui");
    defer {
        for (filtered_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(filtered_tasks);
    }

    // Assertions: Should return only 1 task (UI + in_progress)
    try std.testing.expectEqual(@as(usize, 1), filtered_tasks.len);
    try std.testing.expectEqual(ui_task2, filtered_tasks[0].id);
    try std.testing.expectEqualStrings("ui", filtered_tasks[0].plan.?);
    try std.testing.expectEqual(types.TaskStatus.in_progress, filtered_tasks[0].status);
}

test "listTasks: empty result when filter matches nothing" {
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_list_tasks_empty_filter.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    // Create plan and tasks (all open)
    try storage.createPlan("none", "None", "No completed", null);
    _ = try storage.createTask("none", "Task 1", "Open task");
    _ = try storage.createTask("none", "Task 2", "Open task 2");

    // List completed tasks (none exist)
    const completed_tasks = try storage.listTasks(types.TaskStatus.completed, null);
    defer allocator.free(completed_tasks);

    // Assertions: Should return empty slice
    try std.testing.expectEqual(@as(usize, 0), completed_tasks.len);
}

// ============================================================================
// Ready Command Tests (merged from commands/ready_test.zig)
// ============================================================================

test "getReadyTasks: returns unblocked open tasks" {
    // Methodology: Test that ready tasks query returns only unblocked, open tasks.
    const allocator = std.testing.allocator;

    const temp_path = "/tmp/test_ready_unblocked.db";
    std.fs.deleteFileAbsolute(temp_path) catch {};

    var storage = try Storage.init(allocator, temp_path);
    defer storage.deinit();
    defer std.fs.deleteFileAbsolute(temp_path) catch {};

    try storage.createPlan("test", "Test", "", null);
    const task1 = try storage.createTask("test", "Ready task", "");
    const task2 = try storage.createTask("test", "Blocked task", "");

    // Add dependency: task2 depends on task1
    try storage.addDependency(task2, task1);

    const ready = try storage.getReadyTasks(100);
    defer {
        for (ready) |*t| t.deinit(allocator);
        allocator.free(ready);
    }

    // Only task1 should be ready (task2 is blocked)
    try std.testing.expectEqual(@as(usize, 1), ready.len);
    try std.testing.expectEqual(task1, ready[0].id);
}
