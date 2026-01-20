//! Tests for JSON formatting functions (format_*.zig modules).
//!
//! Covers: formatTaskJson, formatPlanJson, formatStatsJson, etc.

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const format = guerilla_graph.format;
const types = guerilla_graph.types;

test "formatTaskJson: produces valid JSON with all fields" {
    const allocator = std.testing.allocator;

    // Create test task
    const task = types.Task{
        .id = 1,
        .plan_id = 10,
        .plan_slug = "auth",
        .plan_task_number = 1,
        .title = "Add login endpoint",
        .description = "Implement POST /api/login with JWT",
        .status = .in_progress,
        .created_at = 1705320600,
        .updated_at = 1705320700,
        .started_at = null,
        .completed_at = null,
    };

    // Create test blockers
    const blockers = [_]types.BlockerInfo{
        .{
            .id = 5,
            .plan_slug = "auth",
            .plan_task_number = 5,
            .title = "Setup database",
            .status = .completed,
            .depth = 1,
        },
    };

    // Create test dependents
    const dependents = [_]types.BlockerInfo{
        .{
            .id = 2,
            .plan_slug = "auth",
            .plan_task_number = 2,
            .title = "Add logout endpoint",
            .status = .open,
            .depth = 1,
        },
    };

    // Format to writer
    var writer_alloc = std.Io.Writer.Allocating.init(allocator);
    defer writer_alloc.deinit();

    try format.formatTaskJson(allocator, &writer_alloc.writer, task, "Authentication", &blockers, &dependents);

    // Parse JSON to validate structure
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, writer_alloc.written(), .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expect(root.contains("task"));

    const task_obj = root.get("task").?.object;
    try std.testing.expectEqualStrings("auth:001", task_obj.get("id").?.string);
    try std.testing.expectEqual(@as(i64, 1), task_obj.get("internal_id").?.integer);
    try std.testing.expectEqualStrings("auth", task_obj.get("plan").?.string);
    try std.testing.expectEqualStrings("Authentication", task_obj.get("plan_title").?.string);
    try std.testing.expectEqualStrings("Add login endpoint", task_obj.get("title").?.string);
    try std.testing.expectEqualStrings("Implement POST /api/login with JWT", task_obj.get("description").?.string);
    try std.testing.expectEqualStrings("in_progress", task_obj.get("status").?.string);
    try std.testing.expectEqual(@as(i64, 1705320600), task_obj.get("created_at").?.integer);
    try std.testing.expectEqual(@as(i64, 1705320700), task_obj.get("updated_at").?.integer);
    try std.testing.expect(task_obj.get("completed_at").? == .null);

    // Validate blockers array
    const blockers_arr = task_obj.get("blockers").?.array;
    try std.testing.expectEqual(@as(usize, 1), blockers_arr.items.len);
    try std.testing.expectEqual(@as(i64, 5), blockers_arr.items[0].object.get("id").?.integer);
    try std.testing.expectEqualStrings("completed", blockers_arr.items[0].object.get("status").?.string);
    try std.testing.expectEqual(@as(i64, 1), blockers_arr.items[0].object.get("depth").?.integer);

    // Validate dependents array
    const dependents_arr = task_obj.get("dependents").?.array;
    try std.testing.expectEqual(@as(usize, 1), dependents_arr.items.len);
    try std.testing.expectEqual(@as(i64, 2), dependents_arr.items[0].object.get("id").?.integer);
    try std.testing.expectEqualStrings("open", dependents_arr.items[0].object.get("status").?.string);
}

test "formatPlanJson: produces valid JSON with task summary" {
    const allocator = std.testing.allocator;

    // Create test plan summary
    const summary = types.PlanSummary{
        .id = 1,
        .slug = "auth",
        .title = "Authentication System",
        .description = "User authentication and authorization",
        .status = .in_progress,
        .created_at = 1705320600,
        .execution_started_at = 1705320600,
        .completed_at = null,
        .task_counter = 10,
        .total_tasks = 10,
        .open_tasks = 5,
        .in_progress_tasks = 3,
        .completed_tasks = 2,
    };

    // Format to writer
    var writer_alloc = std.Io.Writer.Allocating.init(allocator);
    defer writer_alloc.deinit();

    try format.formatPlanJson(&writer_alloc.writer, summary);

    // Parse JSON to validate structure
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, writer_alloc.written(), .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expect(root.contains("plan"));

    const plan_obj = root.get("plan").?.object;
    try std.testing.expectEqualStrings("auth", plan_obj.get("slug").?.string);
    try std.testing.expectEqualStrings("Authentication System", plan_obj.get("title").?.string);
    try std.testing.expectEqualStrings("User authentication and authorization", plan_obj.get("description").?.string);
    try std.testing.expectEqualStrings("in_progress", plan_obj.get("status").?.string);
    try std.testing.expectEqual(@as(i64, 10), plan_obj.get("total_tasks").?.integer);
    try std.testing.expectEqual(@as(i64, 5), plan_obj.get("open_tasks").?.integer);
    try std.testing.expectEqual(@as(i64, 3), plan_obj.get("in_progress_tasks").?.integer);
    try std.testing.expectEqual(@as(i64, 2), plan_obj.get("completed_tasks").?.integer);
}

test "formatTaskListJson: produces valid JSON for empty list" {
    const allocator = std.testing.allocator;

    const tasks: []const types.Task = &[_]types.Task{};

    // Format to writer
    var writer_alloc = std.Io.Writer.Allocating.init(allocator);
    defer writer_alloc.deinit();

    try format.formatTaskListJson(allocator, &writer_alloc.writer, tasks);

    // Parse JSON to validate structure
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, writer_alloc.written(), .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expect(root.contains("tasks"));
    try std.testing.expect(root.contains("count"));

    const tasks_arr = root.get("tasks").?.array;
    try std.testing.expectEqual(@as(usize, 0), tasks_arr.items.len);
    try std.testing.expectEqual(@as(i64, 0), root.get("count").?.integer);
}

test "formatTaskListJson: produces valid JSON for multiple tasks" {
    const allocator = std.testing.allocator;

    const tasks = [_]types.Task{
        .{
            .id = 1,
            .plan_id = 10,
            .plan_slug = "auth",
            .plan_task_number = 1,
            .title = "Add login endpoint",
            .description = "",
            .status = .open,
            .created_at = 1705320600,
            .updated_at = 1705320600,
            .started_at = null,
            .completed_at = null,
        },
        .{
            .id = 2,
            .plan_id = 10,
            .plan_slug = "auth",
            .plan_task_number = 2,
            .title = "Add logout endpoint",
            .description = "",
            .status = .in_progress,
            .created_at = 1705320700,
            .updated_at = 1705320800,
            .started_at = null,
            .completed_at = null,
        },
    };

    // Format to writer
    var writer_alloc = std.Io.Writer.Allocating.init(allocator);
    defer writer_alloc.deinit();

    try format.formatTaskListJson(allocator, &writer_alloc.writer, &tasks);

    // Parse JSON to validate structure
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, writer_alloc.written(), .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const tasks_arr = root.get("tasks").?.array;
    try std.testing.expectEqual(@as(usize, 2), tasks_arr.items.len);
    try std.testing.expectEqual(@as(i64, 2), root.get("count").?.integer);

    // Validate first task
    try std.testing.expectEqualStrings("auth:001", tasks_arr.items[0].object.get("id").?.string);
    try std.testing.expectEqualStrings("open", tasks_arr.items[0].object.get("status").?.string);

    // Validate second task
    try std.testing.expectEqualStrings("auth:002", tasks_arr.items[1].object.get("id").?.string);
    try std.testing.expectEqualStrings("in_progress", tasks_arr.items[1].object.get("status").?.string);
}

test "formatPlanListJson: produces valid JSON for empty list" {
    const allocator = std.testing.allocator;

    const summaries: []const types.PlanSummary = &[_]types.PlanSummary{};

    // Format to writer
    var writer_alloc = std.Io.Writer.Allocating.init(allocator);
    defer writer_alloc.deinit();

    try format.formatPlanListJson(&writer_alloc.writer, summaries);

    // Parse JSON to validate structure
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, writer_alloc.written(), .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expect(root.contains("plans"));
    try std.testing.expect(root.contains("count"));

    const plans_arr = root.get("plans").?.array;
    try std.testing.expectEqual(@as(usize, 0), plans_arr.items.len);
    try std.testing.expectEqual(@as(i64, 0), root.get("count").?.integer);
}

test "formatPlanListJson: produces valid JSON for multiple plans" {
    const allocator = std.testing.allocator;

    const summaries = [_]types.PlanSummary{
        .{
            .id = 1,
            .slug = "auth",
            .title = "Authentication",
            .description = "Auth system",
            .status = .in_progress,
            .created_at = 1705320600,
            .execution_started_at = 1705320600,
            .completed_at = null,
            .task_counter = 5,
            .total_tasks = 5,
            .open_tasks = 3,
            .in_progress_tasks = 2,
            .completed_tasks = 0,
        },
        .{
            .id = 2,
            .slug = "payments",
            .title = "Payments",
            .description = "Payment processing",
            .status = .completed,
            .created_at = 1705320600,
            .execution_started_at = 1705320600,
            .completed_at = 1705330000,
            .task_counter = 3,
            .total_tasks = 3,
            .open_tasks = 0,
            .in_progress_tasks = 0,
            .completed_tasks = 3,
        },
    };

    // Format to writer
    var writer_alloc = std.Io.Writer.Allocating.init(allocator);
    defer writer_alloc.deinit();

    try format.formatPlanListJson(&writer_alloc.writer, &summaries);

    // Parse JSON to validate structure
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, writer_alloc.written(), .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const plans_arr = root.get("plans").?.array;
    try std.testing.expectEqual(@as(usize, 2), plans_arr.items.len);
    try std.testing.expectEqual(@as(i64, 2), root.get("count").?.integer);

    // Validate first plan
    try std.testing.expectEqualStrings("auth", plans_arr.items[0].object.get("slug").?.string);
    try std.testing.expectEqualStrings("in_progress", plans_arr.items[0].object.get("status").?.string);
    try std.testing.expectEqual(@as(i64, 5), plans_arr.items[0].object.get("total_tasks").?.integer);

    // Validate second plan (should be completed)
    try std.testing.expectEqualStrings("payments", plans_arr.items[1].object.get("slug").?.string);
    try std.testing.expectEqualStrings("completed", plans_arr.items[1].object.get("status").?.string);
}

test "formatStatsJson: produces valid JSON with all stats fields" {
    const allocator = std.testing.allocator;

    const stats = types.SystemStats{
        .total_plans = 5,
        .completed_plans = 2,
        .total_tasks = 20,
        .open_tasks = 10,
        .in_progress_tasks = 5,
        .completed_tasks = 5,
        .ready_tasks = 7,
        .blocked_tasks = 3,
    };

    // Format to writer
    var writer_alloc = std.Io.Writer.Allocating.init(allocator);
    defer writer_alloc.deinit();

    try format.formatStatsJson(&writer_alloc.writer, stats);

    // Parse JSON to validate structure
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, writer_alloc.written(), .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expect(root.contains("stats"));

    const stats_obj = root.get("stats").?.object;
    try std.testing.expectEqual(@as(i64, 5), stats_obj.get("total_plans").?.integer);
    try std.testing.expectEqual(@as(i64, 2), stats_obj.get("completed_plans").?.integer);
    try std.testing.expectEqual(@as(i64, 20), stats_obj.get("total_tasks").?.integer);
    try std.testing.expectEqual(@as(i64, 10), stats_obj.get("open_tasks").?.integer);
    try std.testing.expectEqual(@as(i64, 5), stats_obj.get("in_progress_tasks").?.integer);
    try std.testing.expectEqual(@as(i64, 5), stats_obj.get("completed_tasks").?.integer);
    try std.testing.expectEqual(@as(i64, 7), stats_obj.get("ready_tasks").?.integer);
    try std.testing.expectEqual(@as(i64, 3), stats_obj.get("blocked_tasks").?.integer);
}

test "formatReadyTasksJson: produces valid JSON for ready tasks" {
    const allocator = std.testing.allocator;

    const tasks = [_]types.Task{
        .{
            .id = 1,
            .plan_id = 10,
            .plan_slug = "auth",
            .plan_task_number = 1,
            .title = "Add login endpoint",
            .description = "",
            .status = .open,
            .created_at = 1705320600,
            .updated_at = 1705320600,
            .started_at = null,
            .completed_at = null,
        },
        .{
            .id = 2,
            .plan_id = 20,
            .plan_slug = "payments",
            .plan_task_number = 1,
            .title = "Setup payment gateway",
            .description = "",
            .status = .open,
            .created_at = 1705320700,
            .updated_at = 1705320700,
            .started_at = null,
            .completed_at = null,
        },
    };

    // Format to writer
    var writer_alloc = std.Io.Writer.Allocating.init(allocator);
    defer writer_alloc.deinit();

    try format.formatReadyTasksJson(allocator, &writer_alloc.writer, &tasks);

    // Parse JSON to validate structure
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, writer_alloc.written(), .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expect(root.contains("ready_tasks"));
    try std.testing.expect(root.contains("count"));

    const ready_arr = root.get("ready_tasks").?.array;
    try std.testing.expectEqual(@as(usize, 2), ready_arr.items.len);
    try std.testing.expectEqual(@as(i64, 2), root.get("count").?.integer);

    // Validate task structure
    try std.testing.expectEqualStrings("auth:001", ready_arr.items[0].object.get("id").?.string);
    try std.testing.expectEqualStrings("auth", ready_arr.items[0].object.get("plan").?.string);
    try std.testing.expectEqualStrings("Add login endpoint", ready_arr.items[0].object.get("title").?.string);
}

test "formatBlockedTasksJson: produces valid JSON with blocker counts" {
    const allocator = std.testing.allocator;

    const tasks = [_]types.Task{
        .{
            .id = 2,
            .plan_id = 10,
            .plan_slug = "auth",
            .plan_task_number = 2,
            .title = "Add logout endpoint",
            .description = "",
            .status = .open,
            .created_at = 1705320600,
            .updated_at = 1705320600,
            .started_at = null,
            .completed_at = null,
        },
        .{
            .id = 3,
            .plan_id = 10,
            .plan_slug = "auth",
            .plan_task_number = 3,
            .title = "Add password reset",
            .description = "",
            .status = .open,
            .created_at = 1705320700,
            .updated_at = 1705320700,
            .started_at = null,
            .completed_at = null,
        },
    };

    const blocker_counts = [_]u32{ 1, 2 };

    // Format to writer
    var writer_alloc = std.Io.Writer.Allocating.init(allocator);
    defer writer_alloc.deinit();

    try format.formatBlockedTasksJson(allocator, &writer_alloc.writer, &tasks, &blocker_counts);

    // Parse JSON to validate structure
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, writer_alloc.written(), .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expect(root.contains("blocked_tasks"));
    try std.testing.expect(root.contains("count"));

    const blocked_arr = root.get("blocked_tasks").?.array;
    try std.testing.expectEqual(@as(usize, 2), blocked_arr.items.len);
    try std.testing.expectEqual(@as(i64, 2), root.get("count").?.integer);

    // Validate first blocked task
    try std.testing.expectEqualStrings("auth:002", blocked_arr.items[0].object.get("id").?.string);
    try std.testing.expectEqual(@as(i64, 1), blocked_arr.items[0].object.get("blocker_count").?.integer);

    // Validate second blocked task
    try std.testing.expectEqualStrings("auth:003", blocked_arr.items[1].object.get("id").?.string);
    try std.testing.expectEqual(@as(i64, 2), blocked_arr.items[1].object.get("blocker_count").?.integer);
}

test "formatBlockerInfoJson: produces valid JSON for blockers" {
    const allocator = std.testing.allocator;

    const blockers = [_]types.BlockerInfo{
        .{
            .id = 1,
            .plan_slug = "auth",
            .plan_task_number = 1,
            .title = "Setup database",
            .status = .completed,
            .depth = 1,
        },
        .{
            .id = 5,
            .plan_slug = "auth",
            .plan_task_number = 5,
            .title = "Create schema",
            .status = .in_progress,
            .depth = 2,
        },
    };

    // Format to writer
    var writer_alloc = std.Io.Writer.Allocating.init(allocator);
    defer writer_alloc.deinit();

    try format.formatBlockerInfoJson(&writer_alloc.writer, &blockers, true);

    // Parse JSON to validate structure
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, writer_alloc.written(), .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expect(root.contains("blockers"));
    try std.testing.expect(root.contains("count"));

    const blockers_arr = root.get("blockers").?.array;
    try std.testing.expectEqual(@as(usize, 2), blockers_arr.items.len);
    try std.testing.expectEqual(@as(i64, 2), root.get("count").?.integer);

    // Validate blocker structure - id is now formatted string (slug:NNN)
    try std.testing.expectEqualStrings("auth:001", blockers_arr.items[0].object.get("id").?.string);
    try std.testing.expectEqual(@as(i64, 1), blockers_arr.items[0].object.get("internal_id").?.integer);
    try std.testing.expectEqualStrings("Setup database", blockers_arr.items[0].object.get("title").?.string);
    try std.testing.expectEqualStrings("completed", blockers_arr.items[0].object.get("status").?.string);
    try std.testing.expectEqual(@as(i64, 1), blockers_arr.items[0].object.get("depth").?.integer);
}

test "formatBlockerInfoJson: produces valid JSON for dependents" {
    const allocator = std.testing.allocator;

    const dependents = [_]types.BlockerInfo{
        .{
            .id = 3,
            .plan_slug = "auth",
            .plan_task_number = 3,
            .title = "Add password reset",
            .status = .open,
            .depth = 1,
        },
    };

    // Format to writer
    var writer_alloc = std.Io.Writer.Allocating.init(allocator);
    defer writer_alloc.deinit();

    try format.formatBlockerInfoJson(&writer_alloc.writer, &dependents, false);

    // Parse JSON to validate structure
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, writer_alloc.written(), .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expect(root.contains("dependents"));
    try std.testing.expect(!root.contains("blockers"));
    try std.testing.expect(root.contains("count"));

    const dependents_arr = root.get("dependents").?.array;
    try std.testing.expectEqual(@as(usize, 1), dependents_arr.items.len);
    try std.testing.expectEqual(@as(i64, 1), root.get("count").?.integer);
}
