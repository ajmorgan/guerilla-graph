//! List command handler for Guerilla Graph CLI.
//!
//! This module contains the list command handler that displays the hierarchical
//! task structure organized by plans.
//! - handleQueryList: Display plans and their tasks with status indicators
//!
//! This command is read-only and displays a hierarchical view of all plans
//! and tasks, or filtered by specific plan/task ID.
//! Tiger Style: Full names, 2+ assertions per function, rationale comments.

const std = @import("std");
const types = @import("../types.zig");
const format = @import("../format.zig");
const Storage = @import("../storage.zig").Storage;

pub fn handleQueryList(io: std.Io, allocator: std.mem.Allocator, arguments: []const []const u8, json_output: bool, storage: *Storage) !void {
    std.debug.assert(storage.database != null);

    // Parse filter argument
    const filter = try handleQueryList_parseFilter(arguments);

    // Fetch data from storage
    const plan_summaries = try handleQueryList_fetchPlans(allocator, storage, filter.plan);
    defer {
        for (plan_summaries) |*summary| {
            summary.deinit(allocator);
        }
        allocator.free(plan_summaries);
    }

    const all_tasks = try storage.listTasks(null, filter.plan);
    defer {
        for (all_tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(all_tasks);
    }

    const blocked_result = try storage.getBlockedTasks();
    defer {
        for (blocked_result.tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(blocked_result.tasks);
        allocator.free(blocked_result.blocker_counts);
    }

    var blocked_set = try handleQueryList_buildBlockedSet(allocator, blocked_result.tasks);
    defer blocked_set.deinit();

    // Setup output
    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, stdout_buffer[0..]);
    const stdout = &stdout_writer.interface;

    // Handle JSON output
    if (json_output) {
        const filtered_tasks = try handleQueryList_filterForJson(allocator, all_tasks, filter.task_id);
        defer if (filter.task_id != null) allocator.free(filtered_tasks);

        try format.formatHierarchicalListJson(allocator, stdout, plan_summaries, filtered_tasks);
        try stdout.flush();
        return;
    }

    // Handle text output
    const current_time = @import("../utils.zig").unixTimestamp();
    try handleQueryList_displayPlans(stdout, allocator, plan_summaries, all_tasks, filter.task_id, &blocked_set, current_time, filter.short_mode);
    try stdout.flush();
}

/// Filter result from parsing command-line arguments.
const FilterResult = struct {
    plan: ?[]const u8,
    task_id: ?u32,
    short_mode: bool,
};

/// Parse filter argument to extract plan ID, optional task ID, and flags.
/// Rationale: Extracted from handleQueryList to reduce function length.
fn handleQueryList_parseFilter(arguments: []const []const u8) !FilterResult {
    std.debug.assert(arguments.len <= 10);

    var filter_plan: ?[]const u8 = null;
    var filter_task_id: ?u32 = null;
    var short_mode: bool = false;

    for (arguments) |arg| {
        std.debug.assert(arg.len > 0);

        // Check for --short flag.
        if (std.mem.eql(u8, arg, "--short")) {
            short_mode = true;
            continue;
        }

        // Skip if we already have a plan filter (only process first positional).
        if (filter_plan != null) continue;

        // Check if it's a task ID (contains ':') or a plan ID.
        if (std.mem.indexOf(u8, arg, ":") != null) {
            // It's a task ID, parse it and extract plan_id.
            const parsed = try @import("../utils.zig").parseTaskId(arg);
            filter_plan = parsed.plan_id;
            filter_task_id = parsed.number;
        } else {
            // It's a plan ID.
            filter_plan = arg;
        }
    }

    return FilterResult{
        .plan = filter_plan,
        .task_id = filter_task_id,
        .short_mode = short_mode,
    };
}

/// Fetch plans from storage (filtered by plan ID if specified, or all).
/// Rationale: Extracted from handleQueryList to reduce function length.
fn handleQueryList_fetchPlans(
    allocator: std.mem.Allocator,
    storage: *Storage,
    filter_plan: ?[]const u8,
) ![]types.PlanSummary {
    std.debug.assert(storage.database != null);

    if (filter_plan) |plan_id| {
        std.debug.assert(plan_id.len > 0);
        // Get specific plan
        const maybe_summary = try storage.getPlanSummary(plan_id);
        if (maybe_summary) |summary| {
            const summaries = try allocator.alloc(types.PlanSummary, 1);
            summaries[0] = summary;
            return summaries;
        } else {
            // Plan not found - return empty array
            return try allocator.alloc(types.PlanSummary, 0);
        }
    }

    return try storage.listPlans(null);
}

/// Build set of blocked task IDs for O(1) lookup during display.
/// Rationale: Extracted from handleQueryList to reduce function length.
fn handleQueryList_buildBlockedSet(
    allocator: std.mem.Allocator,
    blocked_tasks: []const types.Task,
) !std.AutoHashMap(u32, void) {
    // Assertions: Validate inputs (sanity check for query result size)
    std.debug.assert(blocked_tasks.len <= 1000);

    var blocked_set = std.AutoHashMap(u32, void).init(allocator);
    errdefer blocked_set.deinit();

    for (blocked_tasks) |task| {
        std.debug.assert(task.id > 0);
        try blocked_set.put(task.id, {});
    }

    return blocked_set;
}

/// Filter tasks for JSON output when specific task ID requested.
/// Rationale: Extracted from handleQueryList for clarity.
fn handleQueryList_filterForJson(
    allocator: std.mem.Allocator,
    all_tasks: []const types.Task,
    filter_task_id: ?u32,
) ![]const types.Task {
    std.debug.assert(all_tasks.len <= 1000);

    if (filter_task_id) |specific_id| {
        std.debug.assert(specific_id > 0);
        var filtered: std.ArrayList(types.Task) = .empty;
        defer filtered.deinit(allocator);
        for (all_tasks) |task| {
            if (task.id == specific_id) {
                try filtered.append(allocator, task);
                break;
            }
        }
        return try filtered.toOwnedSlice(allocator);
    }
    return all_tasks;
}

/// Display plans with their tasks in text format.
/// Rationale: Extracted from handleQueryList to reduce function length.
fn handleQueryList_displayPlans(
    stdout: anytype,
    allocator: std.mem.Allocator,
    plan_summaries: []const types.PlanSummary,
    all_tasks: []const types.Task,
    filter_task_id: ?u32,
    blocked_set: *const std.AutoHashMap(u32, void),
    current_time: i64,
    short_mode: bool,
) !void {
    // Assertions
    std.debug.assert(plan_summaries.len <= 1000);
    std.debug.assert(current_time > 0);

    for (plan_summaries) |plan| {
        // When filtering for a specific task, check if any tasks will be displayed
        // before printing the plan header
        if (filter_task_id != null) {
            var has_matching_task = false;
            for (all_tasks) |task| {
                // Check if task belongs to this plan (compare numeric IDs)
                if (task.plan_id != plan.id) continue;
                if (filter_task_id) |specific_id| {
                    if (task.id == specific_id) {
                        has_matching_task = true;
                        break;
                    }
                }
            }
            // Skip this plan if no matching tasks found
            if (!has_matching_task) continue;
        }

        // Plan status symbol
        const plan_symbol = if (plan.completed_at != null) "✓" else if (plan.execution_started_at != null) "→" else "○";

        try stdout.print("{s} {s} ({d}/{d} done", .{
            plan_symbol,
            plan.slug,
            plan.completed_tasks,
            plan.total_tasks,
        });

        if (plan.completed_at) |completed| {
            // Database constraint guarantees execution_started_at is set when completed_at is set.
            // See src/storage.zig:108 CHECK constraint.
            const started = plan.execution_started_at.?;

            const metrics_str = try formatPlanTimeMetrics(allocator, plan.created_at, started, completed);
            defer allocator.free(metrics_str);
            try stdout.print(", {s}", .{metrics_str});
        } else if (plan.execution_started_at) |started| {
            const delta = current_time - started;
            try stdout.print(", active {s}", .{formatRelativeTime(delta)});
        }
        try stdout.print(")\n", .{});

        // Skip task display for completed plans in short mode.
        // Check completed_at (source of truth for completion status in display logic).
        if (!short_mode or plan.completed_at == null) {
            // Tasks for this plan
            for (all_tasks) |task| {
                // Check if task belongs to this plan (compare numeric IDs)
                if (task.plan_id != plan.id) continue;

                // If filtering for a specific task, skip others
                if (filter_task_id) |specific_id| {
                    if (task.id != specific_id) continue;
                }

                // Task status symbol
                const task_symbol = if (task.completed_at != null) "✓" else if (task.started_at != null) "→" else if (blocked_set.contains(task.id)) "✗" else "○";

                try stdout.print("  {s} {s}:{d:0>3} {s}", .{ task_symbol, task.plan_slug, task.plan_task_number, task.title });

                if (task.completed_at) |completed| {
                    const delta_work = if (task.started_at) |started| completed - started else 0;
                    const duration_str = try formatDuration(allocator, delta_work);
                    defer allocator.free(duration_str);
                    try stdout.print(" ({s})", .{duration_str});
                } else if (task.started_at) |started| {
                    const delta = current_time - started;
                    try stdout.print(" (active {s})", .{formatRelativeTime(delta)});
                }
                try stdout.print("\n", .{});
            }
        }
        try stdout.print("\n", .{}); // Blank line between plans
    }

    // Note: Orphan tasks (tasks with NULL plan) are no longer supported in the new data model.
    // All tasks must belong to a plan (plan_id is NOT NULL).
}

/// Format duration for work time (e.g., "10m", "1h 9m")
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

/// Format time metrics string for completed plan.
/// Returns allocated string like "total: 2h 3m, planning: 18m, exec: 1h 45m".
/// Caller must free returned string.
fn formatPlanTimeMetrics(
    allocator: std.mem.Allocator,
    created_at: i64,
    execution_started_at: i64,
    completed_at: i64,
) ![]u8 {
    // Assertions: Validate timestamp ordering (Tiger Style).
    std.debug.assert(created_at > 0);
    std.debug.assert(created_at <= execution_started_at);
    std.debug.assert(execution_started_at <= completed_at);

    // Calculate all three time metrics.
    const total_time = completed_at - created_at;
    const planning_time = execution_started_at - created_at;
    const exec_time = completed_at - execution_started_at;

    // Format each duration.
    const total_str = try formatDuration(allocator, total_time);
    defer allocator.free(total_str);
    const planning_str = try formatDuration(allocator, planning_time);
    defer allocator.free(planning_str);
    const exec_str = try formatDuration(allocator, exec_time);
    defer allocator.free(exec_str);

    // Build combined result string.
    return try std.fmt.allocPrint(
        allocator,
        "total: {s}, planning: {s}, exec: {s}",
        .{ total_str, planning_str, exec_str },
    );
}

/// Format time delta as relative time string (e.g., "5m", "2h", "3d")
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
