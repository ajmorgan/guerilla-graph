const std = @import("std");
const types = @import("types.zig");
const utils = @import("utils.zig");

// ========== Task Text Formatting Functions ==========
// These functions format task data structures for human-readable terminal output.

/// Format a single task with full details for display
/// Used by the `gg show <task-id>` command
pub fn formatTask(allocator: std.mem.Allocator, writer: anytype, task: types.Task, plan_title: ?[]const u8, blockers: []const types.BlockerInfo, dependents: []const types.BlockerInfo) !void {
    // Assertions: Validate inputs
    std.debug.assert(task.id > 0);
    std.debug.assert(task.plan_slug.len > 0);
    std.debug.assert(task.title.len <= 500); // Database constraint

    // Header - format task ID as "plan:NNN"
    const formatted_id = try utils.formatTaskId(allocator, task.plan_slug, task.plan_task_number);
    defer allocator.free(formatted_id);
    try writer.print("Task: {s}\n", .{formatted_id});

    // Show plan title
    if (plan_title) |title| {
        try writer.print("Plan: {s} ({s})\n", .{ task.plan_slug, title });
    } else {
        try writer.print("Plan: {s}\n", .{task.plan_slug});
    }

    try writer.print("Title: {s}\n", .{task.title});
    try writer.print("Status: {s}\n", .{task.status.toString()});

    // Timestamps
    try formatTimestamp(writer, "Created", task.created_at);
    try formatTimestamp(writer, "Updated", task.updated_at);
    if (task.completed_at) |completed| {
        try formatTimestamp(writer, "Completed", completed);
    }

    try writer.writeAll("\n");

    // Description (if present)
    if (task.description.len > 0) {
        try writer.writeAll("Description:\n");
        try writer.print("{s}\n", .{task.description});
        try writer.writeAll("\n");
    }

    // Blocking information
    if (dependents.len > 0) {
        try writer.print("Blocking: ", .{});
        for (dependents, 0..) |dep, index| {
            if (index > 0) try writer.writeAll(", ");
            try writer.print("{d}", .{dep.id});
        }
        try writer.writeAll("\n");
    }

    if (blockers.len > 0) {
        try writer.print("Blocked by: ", .{});
        for (blockers, 0..) |blocker, index| {
            if (index > 0) try writer.writeAll(", ");
            try writer.print("{d}", .{blocker.id});
        }
        try writer.writeAll("\n");
    } else {
        try writer.writeAll("Blocked by: (none - ready to work!)\n");
    }
}

/// Format a list of tasks in compact format
/// Used by `gg ready`, `gg list`, `gg blocked` commands
pub fn formatTaskList(allocator: std.mem.Allocator, writer: anytype, tasks: []const types.Task, show_plan: bool) !void {
    // Assertions: Validate inputs
    std.debug.assert(tasks.len <= 10000); // Reasonable upper bound for display

    if (tasks.len == 0) {
        try writer.writeAll("No tasks found.\n");
        return;
    }

    for (tasks) |task| {
        // Status indicator
        const status_symbol = switch (task.status) {
            .completed => "[✓]",
            .in_progress => "[→]",
            .open => "[ ]",
        };

        // Format task ID as "plan:NNN"
        const formatted_id = try utils.formatTaskId(allocator, task.plan_slug, task.plan_task_number);
        defer allocator.free(formatted_id);

        if (show_plan) {
            try writer.print("  {s} {s}: {s} ({s})\n", .{
                status_symbol,
                formatted_id,
                task.title,
                task.plan_slug,
            });
        } else {
            try writer.print("  {s} {s}: {s}\n", .{
                status_symbol,
                formatted_id,
                task.title,
            });
        }
    }

    try writer.print("\n{d} task(s) listed\n", .{tasks.len});
}

/// Format ready tasks with additional context
/// Used by `gg ready` command
pub fn formatReadyTasks(allocator: std.mem.Allocator, writer: anytype, tasks: []const types.Task) !void {
    // Assertions: Validate inputs
    std.debug.assert(tasks.len <= 10000); // Reasonable upper bound for display

    try writer.writeAll("Ready tasks (unblocked):\n");

    if (tasks.len == 0) {
        try writer.writeAll("  No tasks ready - all tasks are blocked or completed.\n");
        return;
    }

    for (tasks) |task| {
        // Format task ID as "plan:NNN"
        const formatted_id = try utils.formatTaskId(allocator, task.plan_slug, task.plan_task_number);
        defer allocator.free(formatted_id);

        try writer.print("  {s}: {s} ({s})\n", .{
            formatted_id,
            task.title,
            task.plan_slug,
        });
    }

    try writer.print("\n{d} task(s) ready for parallel execution\n", .{tasks.len});
}

/// Format blocked tasks with blocker counts
/// Used by `gg blocked` command
pub fn formatBlockedTasks(allocator: std.mem.Allocator, writer: anytype, tasks: []const types.Task, blocker_counts: []const u32) !void {
    // Assertions: Validate inputs
    std.debug.assert(tasks.len == blocker_counts.len);
    std.debug.assert(tasks.len <= 10000); // Reasonable upper bound for display

    try writer.writeAll("Blocked tasks:\n");

    if (tasks.len == 0) {
        try writer.writeAll("  No blocked tasks - everything is ready or completed!\n");
        return;
    }

    for (tasks, blocker_counts) |task, count| {
        // Format task ID as "plan:NNN"
        const formatted_id = try utils.formatTaskId(allocator, task.plan_slug, task.plan_task_number);
        defer allocator.free(formatted_id);

        try writer.print("  {s}: {s} (blocked by {d} task(s))\n", .{
            formatted_id,
            task.title,
            count,
        });
    }

    try writer.print("\n{d} task(s) currently blocked\n", .{tasks.len});
}

/// Helper function to format timestamps in human-readable format
fn formatTimestamp(writer: anytype, field_name: []const u8, timestamp: i64) !void {
    // For now, just print the Unix timestamp
    // Future enhancement: Convert to human-readable format (YYYY-MM-DD HH:MM:SS)
    try writer.print("{s}: {d}\n", .{ field_name, timestamp });
}

// ========== Task JSON Formatting Functions ==========
// These functions serialize task data structures to JSON format for programmatic consumption.
// Used when --json flag is provided in CLI commands.

/// Format a single task as JSON with full details
/// Used by the `gg show <task-id> --json` command
pub fn formatTaskJson(allocator: std.mem.Allocator, writer: anytype, task: types.Task, plan_title: ?[]const u8, blockers: []const types.BlockerInfo, dependents: []const types.BlockerInfo) !void {
    // Assertions: Validate inputs
    std.debug.assert(task.id > 0);
    std.debug.assert(task.plan_slug.len > 0);
    std.debug.assert(task.title.len <= 500); // Database constraint

    // Format task ID as "plan:NNN"
    const formatted_id = try utils.formatTaskId(allocator, task.plan_slug, task.plan_task_number);
    defer allocator.free(formatted_id);

    // Rationale: We use std.json.Stringify.value with a custom structure rather than
    // serializing the Task struct directly, because we need to include additional
    // context (plan_title, blockers, dependents) in the JSON output.
    try writer.writeAll("{\n");
    try writer.writeAll("  \"task\": {\n");

    // Basic task fields - use formatted task ID
    try writer.writeAll("    \"id\": ");
    try std.json.Stringify.value(formatted_id, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"internal_id\": ");
    try std.json.Stringify.value(task.id, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"plan\": ");
    try std.json.Stringify.value(task.plan_slug, .{}, writer);
    try writer.writeAll(",\n");

    if (plan_title) |title| {
        try writer.writeAll("    \"plan_title\": ");
        try std.json.Stringify.value(title, .{}, writer);
        try writer.writeAll(",\n");
    }

    try writer.writeAll("    \"title\": ");
    try std.json.Stringify.value(task.title, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"description\": ");
    try std.json.Stringify.value(task.description, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"status\": ");
    try std.json.Stringify.value(task.status.toString(), .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"created_at\": ");
    try std.json.Stringify.value(task.created_at, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"updated_at\": ");
    try std.json.Stringify.value(task.updated_at, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"started_at\": ");
    try std.json.Stringify.value(task.started_at, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"completed_at\": ");
    try std.json.Stringify.value(task.completed_at, .{}, writer);
    try writer.writeAll(",\n");

    // Blockers array
    try writer.writeAll("    \"blockers\": ");
    try formatBlockerInfoArrayJson(writer, blockers);
    try writer.writeAll(",\n");

    // Dependents array
    try writer.writeAll("    \"dependents\": ");
    try formatBlockerInfoArrayJson(writer, dependents);
    try writer.writeAll("\n");

    try writer.writeAll("  }\n");
    try writer.writeAll("}\n");
}

/// Format a list of tasks in JSON format (compact, no descriptions)
/// Used by `gg ready --json`, `gg list --json`, `gg blocked --json` commands
pub fn formatTaskListJson(allocator: std.mem.Allocator, writer: anytype, tasks: []const types.Task) !void {
    // Assertions: Validate inputs
    std.debug.assert(tasks.len <= 10000); // Reasonable upper bound for display

    try writer.writeAll("{\n");
    try writer.writeAll("  \"tasks\": [\n");

    for (tasks, 0..) |task, index| {
        // Format task ID as "plan:NNN"
        const formatted_id = try utils.formatTaskId(allocator, task.plan_slug, task.plan_task_number);
        defer allocator.free(formatted_id);

        try writer.writeAll("    {\n");

        try writer.writeAll("      \"id\": ");
        try std.json.Stringify.value(formatted_id, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"internal_id\": ");
        try std.json.Stringify.value(task.id, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"plan\": ");
        try std.json.Stringify.value(task.plan_slug, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"title\": ");
        try std.json.Stringify.value(task.title, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"status\": ");
        try std.json.Stringify.value(task.status.toString(), .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"created_at\": ");
        try std.json.Stringify.value(task.created_at, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"updated_at\": ");
        try std.json.Stringify.value(task.updated_at, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"completed_at\": ");
        try std.json.Stringify.value(task.completed_at, .{}, writer);
        try writer.writeAll("\n");

        if (index < tasks.len - 1) {
            try writer.writeAll("    },\n");
        } else {
            try writer.writeAll("    }\n");
        }
    }

    try writer.writeAll("  ],\n");
    try writer.writeAll("  \"count\": ");
    try std.json.Stringify.value(tasks.len, .{}, writer);
    try writer.writeAll("\n}\n");
}

/// Format ready tasks with additional context as JSON
/// Used by `gg ready --json` command
pub fn formatReadyTasksJson(allocator: std.mem.Allocator, writer: anytype, tasks: []const types.Task) !void {
    // Assertions: Validate inputs
    std.debug.assert(tasks.len <= 10000); // Reasonable upper bound for display

    try writer.writeAll("{\n");
    try writer.writeAll("  \"ready_tasks\": [\n");

    for (tasks, 0..) |task, index| {
        // Format task ID as "plan:NNN"
        const formatted_id = try utils.formatTaskId(allocator, task.plan_slug, task.plan_task_number);
        defer allocator.free(formatted_id);

        try writer.writeAll("    {\n");

        try writer.writeAll("      \"id\": ");
        try std.json.Stringify.value(formatted_id, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"internal_id\": ");
        try std.json.Stringify.value(task.id, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"plan\": ");
        try std.json.Stringify.value(task.plan_slug, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"title\": ");
        try std.json.Stringify.value(task.title, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"status\": ");
        try std.json.Stringify.value(task.status.toString(), .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"created_at\": ");
        try std.json.Stringify.value(task.created_at, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"updated_at\": ");
        try std.json.Stringify.value(task.updated_at, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"completed_at\": ");
        try std.json.Stringify.value(task.completed_at, .{}, writer);
        try writer.writeAll("\n");

        if (index < tasks.len - 1) {
            try writer.writeAll("    },\n");
        } else {
            try writer.writeAll("    }\n");
        }
    }

    try writer.writeAll("  ],\n");
    try writer.writeAll("  \"count\": ");
    try std.json.Stringify.value(tasks.len, .{}, writer);
    try writer.writeAll("\n}\n");
}

/// Format blocked tasks with blocker counts as JSON
/// Used by `gg blocked --json` command
pub fn formatBlockedTasksJson(allocator: std.mem.Allocator, writer: anytype, tasks: []const types.Task, blocker_counts: []const u32) !void {
    // Assertions: Validate inputs
    std.debug.assert(tasks.len == blocker_counts.len);
    std.debug.assert(tasks.len <= 10000); // Reasonable upper bound for display

    try writer.writeAll("{\n");
    try writer.writeAll("  \"blocked_tasks\": [\n");

    for (tasks, blocker_counts, 0..) |task, count, index| {
        // Format task ID as "plan:NNN"
        const formatted_id = try utils.formatTaskId(allocator, task.plan_slug, task.plan_task_number);
        defer allocator.free(formatted_id);

        try writer.writeAll("    {\n");

        try writer.writeAll("      \"id\": ");
        try std.json.Stringify.value(formatted_id, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"internal_id\": ");
        try std.json.Stringify.value(task.id, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"plan\": ");
        try std.json.Stringify.value(task.plan_slug, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"title\": ");
        try std.json.Stringify.value(task.title, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"status\": ");
        try std.json.Stringify.value(task.status.toString(), .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"blocker_count\": ");
        try std.json.Stringify.value(count, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"created_at\": ");
        try std.json.Stringify.value(task.created_at, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"updated_at\": ");
        try std.json.Stringify.value(task.updated_at, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"completed_at\": ");
        try std.json.Stringify.value(task.completed_at, .{}, writer);
        try writer.writeAll("\n");

        if (index < tasks.len - 1) {
            try writer.writeAll("    },\n");
        } else {
            try writer.writeAll("    }\n");
        }
    }

    try writer.writeAll("  ],\n");
    try writer.writeAll("  \"count\": ");
    try std.json.Stringify.value(tasks.len, .{}, writer);
    try writer.writeAll("\n}\n");
}

/// Helper function to format an array of BlockerInfo as JSON
fn formatBlockerInfoArrayJson(writer: anytype, blockers: []const types.BlockerInfo) !void {
    // Assertions: Validate inputs
    std.debug.assert(blockers.len <= 1000); // Reasonable upper bound for blockers

    try writer.writeAll("[\n");

    for (blockers, 0..) |blocker, index| {
        try writer.writeAll("      {\n");

        try writer.writeAll("        \"id\": ");
        try std.json.Stringify.value(blocker.id, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("        \"title\": ");
        try std.json.Stringify.value(blocker.title, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("        \"status\": ");
        try std.json.Stringify.value(blocker.status.toString(), .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("        \"depth\": ");
        try std.json.Stringify.value(blocker.depth, .{}, writer);
        try writer.writeAll("\n");

        if (index < blockers.len - 1) {
            try writer.writeAll("      },\n");
        } else {
            try writer.writeAll("      }\n");
        }
    }

    try writer.writeAll("    ]");
}
