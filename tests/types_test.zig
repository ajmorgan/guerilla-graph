//! Tests for core data structures (types.zig).
//!
//! Covers: TaskStatus enum, Task/Plan structs, memory management (deinit).

const std = @import("std");
const guerilla_graph = @import("guerilla_graph");
const types = guerilla_graph.types;
const TaskStatus = types.TaskStatus;
const Task = types.Task;
const Plan = types.Plan;
const Dependency = types.Dependency;
const PlanSummary = types.PlanSummary;
const BlockerInfo = types.BlockerInfo;
const HealthIssue = types.HealthIssue;
const HealthReport = types.HealthReport;
const SystemStats = types.SystemStats;

test "TaskStatus: fromString and toString conversions" {
    // Test valid conversions
    try std.testing.expectEqual(TaskStatus.open, try TaskStatus.fromString("open"));
    try std.testing.expectEqual(TaskStatus.in_progress, try TaskStatus.fromString("in_progress"));
    try std.testing.expectEqual(TaskStatus.completed, try TaskStatus.fromString("completed"));

    // Test toString
    try std.testing.expectEqualStrings("open", TaskStatus.open.toString());
    try std.testing.expectEqualStrings("in_progress", TaskStatus.in_progress.toString());
    try std.testing.expectEqualStrings("completed", TaskStatus.completed.toString());

    // Test invalid input
    try std.testing.expectError(error.InvalidTaskStatus, TaskStatus.fromString("invalid"));
}

test "Plan: memory safety with deinit" {
    const allocator = std.testing.allocator;

    var plan = Plan{
        .id = 1,
        .slug = try allocator.dupe(u8, "auth"),
        .task_counter = 0,
        .title = try allocator.dupe(u8, "Authentication System"),
        .description = try allocator.dupe(u8, "User authentication and authorization"),
        .status = .open,
        .created_at = 1705320600,
        .updated_at = 1705320600,
        .execution_started_at = null,
        .completed_at = null,
    };

    // Assertions: Verify plan was created correctly
    try std.testing.expectEqual(@as(u32, 1), plan.id);
    try std.testing.expectEqualStrings("auth", plan.slug);
    try std.testing.expectEqualStrings("Authentication System", plan.title);

    // Cleanup - this should not leak memory
    plan.deinit(allocator);
}

test "Task: memory safety with deinit" {
    const allocator = std.testing.allocator;

    var task = Task{
        .id = 1,
        .plan_id = 1,
        .plan_slug = try allocator.dupe(u8, "auth"),
        .plan_task_number = 1,
        .title = try allocator.dupe(u8, "Add login endpoint"),
        .description = try allocator.dupe(u8, "Implement POST /api/login"),
        .status = .open,
        .created_at = 1705320600,
        .updated_at = 1705320600,
        .started_at = null,
        .completed_at = null,
    };

    // Assertions: Verify task was created correctly
    try std.testing.expectEqual(@as(u32, 1), task.id);
    try std.testing.expectEqual(@as(u32, 1), task.plan_id);
    try std.testing.expectEqualStrings("auth", task.plan_slug);
    try std.testing.expectEqual(TaskStatus.open, task.status);
    try std.testing.expect(task.completed_at == null);

    // Cleanup - this should not leak memory
    task.deinit(allocator);
}

test "Dependency: memory safety with deinit" {
    const allocator = std.testing.allocator;

    var dependency = Dependency{
        .task_id = 2,
        .blocks_on_id = 1,
        .created_at = 1705320600,
    };

    // Assertions: Verify dependency was created correctly
    try std.testing.expectEqual(@as(u32, 2), dependency.task_id);
    try std.testing.expectEqual(@as(u32, 1), dependency.blocks_on_id);

    // Note: Dependency has no deinit() - all fields are value types
    _ = allocator; // Suppress unused variable warning
}

test "BlockerInfo: memory safety with deinit" {
    const allocator = std.testing.allocator;

    var blocker_info = BlockerInfo{
        .id = 1,
        .plan_slug = try allocator.dupe(u8, "auth"),
        .plan_task_number = 1,
        .title = try allocator.dupe(u8, "Add login endpoint"),
        .status = .completed,
        .depth = 1,
    };

    // Assertions: Verify blocker info was created correctly
    try std.testing.expectEqual(@as(u32, 1), blocker_info.id);
    try std.testing.expectEqualStrings("auth", blocker_info.plan_slug);
    try std.testing.expectEqual(@as(u32, 1), blocker_info.plan_task_number);
    try std.testing.expectEqual(TaskStatus.completed, blocker_info.status);
    try std.testing.expectEqual(@as(u32, 1), blocker_info.depth);

    // Cleanup - this should not leak memory
    blocker_info.deinit(allocator);
}

test "HealthIssue: memory safety with deinit" {
    const allocator = std.testing.allocator;

    // Case 1: With details
    var issue_with_details = HealthIssue{
        .check_name = try allocator.dupe(u8, "orphaned_dependencies"),
        .message = try allocator.dupe(u8, "Found orphaned dependencies"),
        .details = try allocator.dupe(u8, "task:auth:001 -> auth:999 (missing)"),
    };

    try std.testing.expectEqualStrings("orphaned_dependencies", issue_with_details.check_name);
    issue_with_details.deinit(allocator);

    // Case 2: Without details
    var issue_without_details = HealthIssue{
        .check_name = try allocator.dupe(u8, "cycle_detected"),
        .message = try allocator.dupe(u8, "Cycle detected in dependency graph"),
        .details = null,
    };

    try std.testing.expect(issue_without_details.details == null);
    issue_without_details.deinit(allocator);
}

test "HealthReport: memory safety with nested structures" {
    const allocator = std.testing.allocator;

    // Create errors array
    var errors = try allocator.alloc(HealthIssue, 1);
    errors[0] = HealthIssue{
        .check_name = try allocator.dupe(u8, "cycle_detected"),
        .message = try allocator.dupe(u8, "Cycle found"),
        .details = null,
    };

    // Create warnings array
    var warnings = try allocator.alloc(HealthIssue, 1);
    warnings[0] = HealthIssue{
        .check_name = try allocator.dupe(u8, "empty_plan"),
        .message = try allocator.dupe(u8, "Plan has no tasks"),
        .details = try allocator.dupe(u8, "auth"),
    };

    var report = HealthReport{
        .errors = errors,
        .warnings = warnings,
    };

    // Assertions: Verify report structure
    try std.testing.expectEqual(@as(usize, 1), report.errors.len);
    try std.testing.expectEqual(@as(usize, 1), report.warnings.len);

    // Cleanup - this should free all nested structures
    report.deinit(allocator);
}

test "SystemStats: validation logic" {
    // Case 1: Valid stats
    const valid_stats = SystemStats{
        .total_plans = 5,
        .completed_plans = 2,
        .total_tasks = 20,
        .open_tasks = 10,
        .in_progress_tasks = 5,
        .completed_tasks = 5,
        .ready_tasks = 7,
        .blocked_tasks = 3,
    };

    try std.testing.expect(valid_stats.validate());

    // Case 2: Invalid stats (tasks don't sum to total)
    const invalid_stats_sum = SystemStats{
        .total_plans = 5,
        .completed_plans = 2,
        .total_tasks = 20,
        .open_tasks = 10,
        .in_progress_tasks = 5,
        .completed_tasks = 10, // Sum is now 25, exceeds total
        .ready_tasks = 7,
        .blocked_tasks = 3,
    };

    try std.testing.expect(!invalid_stats_sum.validate());

    // Case 3: Invalid stats (ready + blocked exceeds open)
    const invalid_stats_blocked = SystemStats{
        .total_plans = 5,
        .completed_plans = 2,
        .total_tasks = 20,
        .open_tasks = 10,
        .in_progress_tasks = 5,
        .completed_tasks = 5,
        .ready_tasks = 8, // 8 + 3 = 11, exceeds 10 open tasks
        .blocked_tasks = 3,
    };

    try std.testing.expect(!invalid_stats_blocked.validate());
}
