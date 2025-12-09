//! Ready command handler for Guerilla Graph CLI.
//!
//! Shows ready tasks (unblocked, status='open') in hierarchical plan+task view.
//! Tiger Style: Full names, 2+ assertions per function, rationale comments.

const std = @import("std");
const types = @import("../types.zig");
const format = @import("../format.zig");
const Storage = @import("../storage.zig").Storage;

/// Error types for command execution.
pub const CommandError = error{
    MissingArgument,
    InvalidArgument,
    StorageNotInitialized,
};

// ============================================================================
// Ready Command (Query for unblocked tasks)
// ============================================================================

/// Get plan summaries for a set of tasks
fn getPlansForTasks(
    allocator: std.mem.Allocator,
    storage: *Storage,
    tasks: []const types.Task,
    filter_plan: ?[]const u8,
) ![]types.PlanSummary {
    // Build set of unique plan slugs from tasks
    var plan_ids = std.StringHashMap(void).init(allocator);
    defer plan_ids.deinit();

    for (tasks) |task| {
        try plan_ids.put(task.plan_slug, {});
    }

    // Get plan summaries (filtered or all matching task plans)
    var summaries: std.ArrayList(types.PlanSummary) = .empty;
    defer summaries.deinit(allocator);

    if (filter_plan) |plan_id| {
        if (plan_ids.contains(plan_id)) {
            const maybe_summary = try storage.getPlanSummary(plan_id);
            if (maybe_summary) |summary| {
                try summaries.append(allocator, summary);
            }
        }
    } else {
        var iter = plan_ids.keyIterator();
        while (iter.next()) |plan_id| {
            const maybe_summary = try storage.getPlanSummary(plan_id.*);
            if (maybe_summary) |summary| {
                try summaries.append(allocator, summary);
            }
        }
    }

    return try summaries.toOwnedSlice(allocator);
}

/// Format ready tasks in hierarchical view (reuses list formatting logic)
fn formatReadyTasksHierarchical(
    stdout: anytype,
    allocator: std.mem.Allocator,
    plan_summaries: []const types.PlanSummary,
    ready_tasks: []const types.Task,
) !void {
    const current_time = @import("../utils.zig").unixTimestamp();

    // Sort alphabetically by slug (no special inbox handling)
    const PlanSort = struct {
        pub fn lessThan(_: void, a: types.PlanSummary, b: types.PlanSummary) bool {
            return std.mem.lessThan(u8, a.slug, b.slug);
        }
    };

    const sorted_plans = try allocator.dupe(types.PlanSummary, plan_summaries);
    defer allocator.free(sorted_plans);
    std.mem.sort(types.PlanSummary, sorted_plans, {}, PlanSort.lessThan);

    // Display plans with ready tasks
    for (sorted_plans) |plan| {
        const plan_symbol = if (plan.completed_at != null) "✓" else if (plan.execution_started_at != null) "→" else "○";

        try stdout.print("{s} {s} ({d}/{d} done", .{
            plan_symbol,
            plan.slug,
            plan.completed_tasks,
            plan.total_tasks,
        });

        if (plan.completed_at) |completed| {
            const delta_work = if (plan.execution_started_at) |started| completed - started else 0;
            const duration_str = try formatDuration(allocator, delta_work);
            defer allocator.free(duration_str);
            try stdout.print(", took {s}", .{duration_str});
        } else if (plan.execution_started_at) |started| {
            const delta = current_time - started;
            try stdout.print(", active {s}", .{formatRelativeTime(delta)});
        }
        try stdout.print(")\n", .{});

        // Display ready tasks for this plan
        for (ready_tasks) |task| {
            if (!std.mem.eql(u8, task.plan_slug, plan.slug)) continue;

            try stdout.print("  ○ {s}:{d:0>3} {s}", .{ task.plan_slug, task.plan_task_number, task.title });
            try stdout.print("\n", .{});
        }
        try stdout.print("\n", .{});
    }
}

/// Handle ready command
/// Shows ready tasks (unblocked, status='open') in hierarchical plan+task view.
///
/// Usage:
/// - gg ready           # Show all ready tasks
/// - gg ready <plan>    # Show ready tasks for specific plan
/// - gg ready <task>    # Show if specific task is ready
///
/// Rationale: Core query for agent work coordination. Shows tasks agents can
/// immediately start without waiting for dependencies.
pub fn handleQueryReady(
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    std.debug.assert(storage.database != null);

    // Parse filter argument if provided (plan or task ID)
    var filter_plan: ?[]const u8 = null;
    var filter_task_id: ?u32 = null;

    if (arguments.len > 0) {
        const arg = arguments[0];
        // Check if it's a task ID (contains ':') or a plan ID
        if (std.mem.indexOf(u8, arg, ":") != null) {
            const parsed = try @import("../utils.zig").parseTaskId(arg);
            filter_plan = parsed.plan_id;
            filter_task_id = parsed.number;
        } else {
            filter_plan = arg;
        }
    }

    // Get all ready tasks (unblocked, status='open')
    const all_ready_tasks = try storage.getReadyTasks(1000);
    defer {
        for (all_ready_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(all_ready_tasks);
    }

    // Filter by plan and/or task if specified
    var filtered_tasks: std.ArrayList(types.Task) = .empty;
    defer filtered_tasks.deinit(allocator);

    for (all_ready_tasks) |task| {
        // Filter by plan if specified
        if (filter_plan) |plan| {
            if (!std.mem.eql(u8, task.plan_slug, plan)) continue;
        }
        // Filter by specific task number if specified
        if (filter_task_id) |specific_number| {
            if (task.plan_task_number != specific_number) continue;
        }
        try filtered_tasks.append(allocator, task);
    }

    const tasks_to_display = try filtered_tasks.toOwnedSlice(allocator);
    // Postcondition: Filtered tasks cannot exceed source tasks
    std.debug.assert(tasks_to_display.len <= all_ready_tasks.len);
    defer allocator.free(tasks_to_display);

    // Get plans for the ready tasks
    const plans_for_ready = try getPlansForTasks(allocator, storage, tasks_to_display, filter_plan);
    // Postcondition: Plans returned cannot exceed tasks (each task has one plan)
    std.debug.assert(plans_for_ready.len <= tasks_to_display.len);
    defer {
        for (plans_for_ready) |*summary| {
            summary.deinit(allocator);
        }
        allocator.free(plans_for_ready);
    }

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(stdout_buffer[0..]);
    const stdout = &stdout_writer.interface;

    // Use hierarchical list format
    if (json_output) {
        try format.formatHierarchicalListJson(allocator, stdout, plans_for_ready, tasks_to_display);
    } else {
        try formatReadyTasksHierarchical(stdout, allocator, plans_for_ready, tasks_to_display);
    }

    try stdout.flush();
}

/// Format duration for work time (e.g., "10m", "1h 9m")
/// Rationale: Duplicated from query.zig and list.zig for module independence.
/// Small helper function (~20 lines), duplication simpler than creating shared module.
fn formatDuration(allocator: std.mem.Allocator, seconds: i64) ![]u8 {
    const abs_seconds: u64 = if (seconds < 0) @intCast(-seconds) else @intCast(seconds);

    if (abs_seconds < 60) return try allocator.dupe(u8, "0m");

    const total_minutes = abs_seconds / 60;
    const hours = total_minutes / 60;
    const minutes = total_minutes % 60;

    if (hours == 0) {
        // Just minutes: "10m", "59m"
        return try std.fmt.allocPrint(allocator, "{d}m", .{minutes});
    } else if (minutes == 0) {
        // Just hours: "1h", "2h"
        return try std.fmt.allocPrint(allocator, "{d}h", .{hours});
    } else {
        // Hours and minutes: "1h 9m", "2h 30m"
        return try std.fmt.allocPrint(allocator, "{d}h {d}m", .{ hours, minutes });
    }
}

/// Format time delta as relative time string (e.g., "5m", "2h", "3d")
/// Rationale: Duplicated from query.zig and list.zig for module independence.
/// Small helper function (~35 lines), duplication simpler than creating shared module.
fn formatRelativeTime(seconds: i64) []const u8 {
    const abs_seconds: u64 = if (seconds < 0) @intCast(-seconds) else @intCast(seconds);

    if (abs_seconds < 60) return "just now";
    if (abs_seconds < 3600) {
        // Minutes
        const minutes = abs_seconds / 60;
        if (minutes == 1) return "1m";
        if (minutes < 10) return "few min";
        if (minutes < 60) return "~1h";
        return "1h";
    }
    if (abs_seconds < 86400) {
        // Hours
        const hours = abs_seconds / 3600;
        if (hours == 1) return "1h";
        if (hours < 24) return "few hr";
        return "1d";
    }
    if (abs_seconds < 604800) {
        // Days
        const days = abs_seconds / 86400;
        if (days == 1) return "1d";
        if (days < 7) return "few days";
        return "1w";
    }
    // Weeks
    const weeks = abs_seconds / 604800;
    if (weeks == 1) return "1w";
    if (weeks < 4) return "few wk";
    return "1mo+";
}

// ============================================================================
// Tests for ready command
// ============================================================================
