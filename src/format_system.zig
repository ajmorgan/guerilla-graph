const std = @import("std");
const types = @import("types.zig");
const utils = @import("utils.zig");

// ========== Text Formatting Functions ==========
// These functions format system/query data for human-readable text output.

/// Format system statistics
/// Used by `gg stats` command
pub fn formatStats(writer: anytype, stats: types.SystemStats) !void {
    try writer.writeAll("Overall:\n");
    try writer.print("  Plans: {d} ({d} open, {d} completed)\n", .{
        stats.total_plans,
        stats.total_plans - stats.completed_plans,
        stats.completed_plans,
    });
    try writer.print("  Tasks: {d} ({d} open, {d} in_progress, {d} completed)\n", .{
        stats.total_tasks,
        stats.open_tasks,
        stats.in_progress_tasks,
        stats.completed_tasks,
    });
    try writer.print("  Ready: {d} tasks available for work\n", .{stats.ready_tasks});
    try writer.print("  Blocked: {d} tasks waiting on dependencies\n", .{stats.blocked_tasks});

    // Parallelism indicator
    if (stats.ready_tasks > 0) {
        try writer.print("\n{d} agent(s) can work in parallel\n", .{stats.ready_tasks});
    }
}

/// Format blocker or dependent information (transitive dependencies)
/// Used by `gg blockers <task-id>` and `gg dependents <task-id>` commands
pub fn formatBlockerInfo(writer: anytype, blockers: []const types.BlockerInfo, is_blocker: bool) !void {
    if (blockers.len == 0) {
        if (is_blocker) {
            try writer.writeAll("No blockers found - task is ready to work!\n");
        } else {
            try writer.writeAll("No dependents found - no tasks depend on this one.\n");
        }
        return;
    }

    const header = if (is_blocker) "Blockers:" else "Dependents:";
    try writer.print("{s}\n", .{header});

    for (blockers) |blocker| {
        const status_indicator = switch (blocker.status) {
            .completed => "✓",
            .in_progress => "→",
            .open => " ",
        };

        // Display formatted task ID (slug:NNN) instead of internal ID.
        try writer.print("  [{s}] [depth {d}] {s}:{d:0>3}: {s} ({s})\n", .{
            status_indicator,
            blocker.depth,
            blocker.plan_slug,
            blocker.plan_task_number,
            blocker.title,
            blocker.status.toString(),
        });
    }
}

// ========== JSON Formatting Functions ==========
// These functions serialize system/query data to JSON format for programmatic consumption.
// Used when --json flag is provided in CLI commands.

/// Format system statistics as JSON
/// Used by `gg stats --json` command
pub fn formatStatsJson(writer: anytype, stats: types.SystemStats) !void {
    try writer.writeAll("{\n");
    try writer.writeAll("  \"stats\": {\n");

    try writer.writeAll("    \"total_plans\": ");
    try std.json.Stringify.value(stats.total_plans, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"completed_plans\": ");
    try std.json.Stringify.value(stats.completed_plans, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"total_tasks\": ");
    try std.json.Stringify.value(stats.total_tasks, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"open_tasks\": ");
    try std.json.Stringify.value(stats.open_tasks, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"in_progress_tasks\": ");
    try std.json.Stringify.value(stats.in_progress_tasks, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"completed_tasks\": ");
    try std.json.Stringify.value(stats.completed_tasks, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"ready_tasks\": ");
    try std.json.Stringify.value(stats.ready_tasks, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"blocked_tasks\": ");
    try std.json.Stringify.value(stats.blocked_tasks, .{}, writer);
    try writer.writeAll("\n");

    try writer.writeAll("  }\n");
    try writer.writeAll("}\n");
}

/// Format blocker or dependent information as JSON (transitive dependencies)
/// Used by `gg blockers <task-id> --json` and `gg dependents <task-id> --json` commands
pub fn formatBlockerInfoJson(writer: anytype, blockers: []const types.BlockerInfo, is_blocker: bool) !void {
    const field_name = if (is_blocker) "blockers" else "dependents";

    try writer.writeAll("{\n");
    try writer.writeAll("  \"");
    try writer.writeAll(field_name);
    try writer.writeAll("\": ");
    try formatBlockerInfoArrayJson(writer, blockers);
    try writer.writeAll(",\n");

    try writer.writeAll("  \"count\": ");
    try std.json.Stringify.value(blockers.len, .{}, writer);
    try writer.writeAll("\n}\n");
}

/// Helper function to format an array of BlockerInfo as JSON
pub fn formatBlockerInfoArrayJson(writer: anytype, blockers: []const types.BlockerInfo) !void {
    try writer.writeAll("[\n");

    for (blockers, 0..) |blocker, index| {
        try writer.writeAll("      {\n");

        // Use formatted task ID (slug:NNN) for external consistency.
        try writer.writeAll("        \"id\": \"");
        try writer.writeAll(blocker.plan_slug);
        try writer.print(":{d:0>3}\",\n", .{blocker.plan_task_number});

        try writer.writeAll("        \"internal_id\": ");
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

/// Format hierarchical list view as JSON (plans with nested tasks)
/// Used by: gg list --json, gg list <plan> --json, gg list <task> --json
pub fn formatHierarchicalListJson(
    allocator: std.mem.Allocator,
    writer: anytype,
    plan_summaries: []const types.PlanSummary,
    all_tasks: []const types.Task,
) !void {
    try writer.writeAll("{\n");
    try writer.writeAll("  \"plans\": [\n");

    for (plan_summaries, 0..) |plan, plan_index| {
        try writer.writeAll("    {\n");

        // Plan fields (all PlanSummary fields)
        try writer.writeAll("      \"slug\": ");
        try std.json.Stringify.value(plan.slug, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"numeric_id\": ");
        try std.json.Stringify.value(plan.id, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"title\": ");
        try std.json.Stringify.value(plan.title, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"description\": ");
        try std.json.Stringify.value(plan.description, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"status\": ");
        try std.json.Stringify.value(plan.status.toString(), .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"execution_started_at\": ");
        try std.json.Stringify.value(plan.execution_started_at, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"completed_at\": ");
        try std.json.Stringify.value(plan.completed_at, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"total_tasks\": ");
        try std.json.Stringify.value(plan.total_tasks, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"completed_tasks\": ");
        try std.json.Stringify.value(plan.completed_tasks, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"in_progress_tasks\": ");
        try std.json.Stringify.value(plan.in_progress_tasks, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"open_tasks\": ");
        try std.json.Stringify.value(plan.open_tasks, .{}, writer);
        try writer.writeAll(",\n");

        // Nested tasks array (all Task fields)
        try writer.writeAll("      \"tasks\": [\n");

        var task_count: usize = 0;
        for (all_tasks) |task| {
            // Only include tasks belonging to this plan
            if (!std.mem.eql(u8, task.plan_slug, plan.slug)) continue;

            if (task_count > 0) try writer.writeAll(",\n");

            // Format task ID as "plan:NNN"
            const formatted_id = try utils.formatTaskId(allocator, task.plan_slug, task.plan_task_number);
            defer allocator.free(formatted_id);

            try writer.writeAll("        {\n");

            try writer.writeAll("          \"id\": ");
            try std.json.Stringify.value(formatted_id, .{}, writer);
            try writer.writeAll(",\n");

            try writer.writeAll("          \"internal_id\": ");
            try std.json.Stringify.value(task.id, .{}, writer);
            try writer.writeAll(",\n");

            try writer.writeAll("          \"plan\": ");
            try std.json.Stringify.value(task.plan_slug, .{}, writer);
            try writer.writeAll(",\n");

            try writer.writeAll("          \"title\": ");
            try std.json.Stringify.value(task.title, .{}, writer);
            try writer.writeAll(",\n");

            try writer.writeAll("          \"description\": ");
            try std.json.Stringify.value(task.description, .{}, writer);
            try writer.writeAll(",\n");

            try writer.writeAll("          \"status\": ");
            try std.json.Stringify.value(task.status.toString(), .{}, writer);
            try writer.writeAll(",\n");

            try writer.writeAll("          \"created_at\": ");
            try std.json.Stringify.value(task.created_at, .{}, writer);
            try writer.writeAll(",\n");

            try writer.writeAll("          \"updated_at\": ");
            try std.json.Stringify.value(task.updated_at, .{}, writer);
            try writer.writeAll(",\n");

            try writer.writeAll("          \"started_at\": ");
            try std.json.Stringify.value(task.started_at, .{}, writer);
            try writer.writeAll(",\n");

            try writer.writeAll("          \"completed_at\": ");
            try std.json.Stringify.value(task.completed_at, .{}, writer);
            try writer.writeAll("\n");

            try writer.writeAll("        }");

            task_count += 1;
        }

        try writer.writeAll("\n      ]\n");

        if (plan_index < plan_summaries.len - 1) {
            try writer.writeAll("    },\n");
        } else {
            try writer.writeAll("    }\n");
        }
    }

    try writer.writeAll("  ]\n");
    try writer.writeAll("}\n");
}
