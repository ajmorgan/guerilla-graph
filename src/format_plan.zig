const std = @import("std");
const types = @import("types.zig");

// ========== Text Formatting Functions ==========
// These functions format plan data structures for human-readable terminal output.

/// Format a single plan with task summary
/// Used by the `gg show <plan-id>` command
pub fn formatPlan(writer: anytype, summary: types.PlanSummary) !void {
    // Assertions: Validate inputs
    std.debug.assert(summary.slug.len > 0);
    std.debug.assert(summary.total_tasks >= 0);
    std.debug.assert(summary.completed_tasks >= 0);
    std.debug.assert(summary.completed_tasks <= summary.total_tasks);
    // Note: title can be empty (optional), so no length assertion

    try writer.print("Plan: {s}\n", .{summary.slug});
    try writer.print("Title: {s}\n", .{summary.title});

    const plan_status = summary.status;
    try writer.print("Status: {s} ({d}/{d} tasks completed)\n", .{
        plan_status.toString(),
        summary.completed_tasks,
        summary.total_tasks,
    });

    if (summary.description.len > 0) {
        try writer.print("\nDescription:\n{s}\n", .{summary.description});
    }

    try writer.writeAll("\n");

    // Task breakdown
    try writer.print("Tasks:\n", .{});
    try writer.print("  Open: {d}\n", .{summary.open_tasks});
    try writer.print("  In Progress: {d}\n", .{summary.in_progress_tasks});
    try writer.print("  Completed: {d}\n", .{summary.completed_tasks});
    try writer.print("  Total: {d}\n", .{summary.total_tasks});
}

/// Format a list of plans in compact format
/// Used by `gg list-plans` command
pub fn formatPlanList(writer: anytype, summaries: []const types.PlanSummary) !void {
    // Assertions: Validate inputs (empty slice is valid)
    for (summaries) |summary| {
        std.debug.assert(summary.slug.len > 0);
        std.debug.assert(summary.total_tasks >= 0);
        std.debug.assert(summary.completed_tasks >= 0);
        std.debug.assert(summary.completed_tasks <= summary.total_tasks);
    }

    if (summaries.len == 0) {
        try writer.writeAll("No plans found.\n");
        return;
    }

    for (summaries) |summary| {
        const plan_status = summary.status;
        const status_symbol = switch (plan_status) {
            .completed => "[✓]",
            .in_progress => "[→]",
            .open => "[ ]",
        };

        try writer.print("  {s} {s}: {s} ({d}/{d} tasks)\n", .{
            status_symbol,
            summary.slug,
            summary.title,
            summary.completed_tasks,
            summary.total_tasks,
        });
    }

    try writer.print("\n{d} plan(s) listed\n", .{summaries.len});
}

// ========== JSON Formatting Functions ==========
// These functions serialize data structures to JSON format for programmatic consumption.
// Used when --json flag is provided in CLI commands.

/// Format a single plan as JSON with task summary
/// Used by the `gg show <plan-id> --json` command
pub fn formatPlanJson(writer: anytype, summary: types.PlanSummary) !void {
    // Assertions: Validate inputs
    std.debug.assert(summary.slug.len > 0);
    std.debug.assert(summary.total_tasks >= 0);
    std.debug.assert(summary.completed_tasks >= 0);
    std.debug.assert(summary.completed_tasks <= summary.total_tasks);
    // Note: title can be empty (optional), so no length assertion

    try writer.writeAll("{\n");
    try writer.writeAll("  \"plan\": {\n");

    try writer.writeAll("    \"slug\": ");
    try std.json.Stringify.value(summary.slug, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"numeric_id\": ");
    try std.json.Stringify.value(summary.id, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"title\": ");
    try std.json.Stringify.value(summary.title, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"description\": ");
    try std.json.Stringify.value(summary.description, .{}, writer);
    try writer.writeAll(",\n");

    const plan_status = summary.status;
    try writer.writeAll("    \"status\": ");
    try std.json.Stringify.value(plan_status.toString(), .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"total_tasks\": ");
    try std.json.Stringify.value(summary.total_tasks, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"open_tasks\": ");
    try std.json.Stringify.value(summary.open_tasks, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"in_progress_tasks\": ");
    try std.json.Stringify.value(summary.in_progress_tasks, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"completed_tasks\": ");
    try std.json.Stringify.value(summary.completed_tasks, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"execution_started_at\": ");
    try std.json.Stringify.value(summary.execution_started_at, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeAll("    \"completed_at\": ");
    try std.json.Stringify.value(summary.completed_at, .{}, writer);
    try writer.writeAll("\n");

    try writer.writeAll("  }\n");
    try writer.writeAll("}\n");
}

/// Format a list of plans in JSON format
/// Used by `gg list-plans --json` command
pub fn formatPlanListJson(writer: anytype, summaries: []const types.PlanSummary) !void {
    // Assertions: Validate inputs (empty slice is valid)
    for (summaries) |summary| {
        std.debug.assert(summary.slug.len > 0);
        std.debug.assert(summary.total_tasks >= 0);
        std.debug.assert(summary.completed_tasks >= 0);
        std.debug.assert(summary.completed_tasks <= summary.total_tasks);
    }

    try writer.writeAll("{\n");
    try writer.writeAll("  \"plans\": [\n");

    for (summaries, 0..) |summary, index| {
        try writer.writeAll("    {\n");

        try writer.writeAll("      \"slug\": ");
        try std.json.Stringify.value(summary.slug, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"numeric_id\": ");
        try std.json.Stringify.value(summary.id, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"title\": ");
        try std.json.Stringify.value(summary.title, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"description\": ");
        try std.json.Stringify.value(summary.description, .{}, writer);
        try writer.writeAll(",\n");

        const plan_status = summary.status;
        try writer.writeAll("      \"status\": ");
        try std.json.Stringify.value(plan_status.toString(), .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"total_tasks\": ");
        try std.json.Stringify.value(summary.total_tasks, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"open_tasks\": ");
        try std.json.Stringify.value(summary.open_tasks, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"in_progress_tasks\": ");
        try std.json.Stringify.value(summary.in_progress_tasks, .{}, writer);
        try writer.writeAll(",\n");

        try writer.writeAll("      \"completed_tasks\": ");
        try std.json.Stringify.value(summary.completed_tasks, .{}, writer);
        try writer.writeAll("\n");

        if (index < summaries.len - 1) {
            try writer.writeAll("    },\n");
        } else {
            try writer.writeAll("    }\n");
        }
    }

    try writer.writeAll("  ],\n");
    try writer.writeAll("  \"count\": ");
    try std.json.Stringify.value(summaries.len, .{}, writer);
    try writer.writeAll("\n}\n");
}
