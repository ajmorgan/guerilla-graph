//! Tests for text formatting functions (format_*.zig modules).
//!
//! Covers: formatTask, formatPlan, formatTaskList, formatStats

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const format = guerilla_graph.format;
const types = guerilla_graph.types;

test "formatTask basic" {
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

    try format.formatTask(allocator, &writer_alloc.writer, task, "Authentication", &blockers, &dependents);

    const output = writer_alloc.written();
    try std.testing.expect(std.mem.indexOf(u8, output, "auth:001") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Authentication") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Add login endpoint") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "in_progress") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Blocked by: 5") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Blocking: 2") != null);
}

test "formatPlan basic" {
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

    try format.formatPlan(&writer_alloc.writer, summary);

    const output = writer_alloc.written();
    try std.testing.expect(std.mem.indexOf(u8, output, "auth") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Authentication System") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "in_progress") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "2/10") != null or std.mem.indexOf(u8, output, "2 / 10") != null);
}

test "formatTaskList empty" {
    const allocator = std.testing.allocator;

    const tasks: []const types.Task = &[_]types.Task{};

    // Format to writer
    var writer_alloc = std.Io.Writer.Allocating.init(allocator);
    defer writer_alloc.deinit();

    try format.formatTaskList(allocator, &writer_alloc.writer, tasks, true);

    const output = writer_alloc.written();
    try std.testing.expect(std.mem.indexOf(u8, output, "No tasks found.") != null);
}

test "formatStats basic" {
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

    try format.formatStats(&writer_alloc.writer, stats);

    const output = writer_alloc.written();
    try std.testing.expect(std.mem.indexOf(u8, output, "Overall:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Plans: 5 (3 open, 2 completed)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Tasks: 20 (10 open, 5 in_progress, 5 completed)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Ready: 7 tasks available for work") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Blocked: 3 tasks waiting on dependencies") != null);
}
