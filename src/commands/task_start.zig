//! Task start command handler for Guerilla Graph CLI.
//!
//! This module contains the start command handler implementation that
//! processes parsed CLI arguments and marks tasks as in_progress.
//!
//! Tiger Style: Full names, 2+ assertions per function, rationale comments.

const std = @import("std");
const builtin = @import("builtin");
const types = @import("../types.zig");
const utils = @import("../utils.zig");
const format = @import("../format.zig");
const Storage = @import("../storage.zig").Storage;

/// Error types for command execution.
pub const CommandError = error{
    MissingArgument,
    InvalidArgument,
    TaskNotFound,
};

// ============================================================================
// Task Start Command
// ============================================================================

/// Handle start command (renamed from handleStart)
/// Marks a task as in_progress by changing its status.
///
/// Command: gg start <task-id>
/// Example: gg start 1
///
/// Rationale: Agents claim tasks via start command to signal they are working on them.
/// This prevents multiple agents from working on the same task simultaneously.
pub fn handleTaskStart(
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    // Rationale: User must provide task ID as first positional argument.
    // Command format: gg start <task-id>
    if (arguments.len == 0) {
        return CommandError.MissingArgument;
    }

    // Parse task ID from CLI argument (accepts both numeric "19" and formatted "auth:019")
    const parsed_input = utils.parseTaskInput(arguments[0]) catch {
        return CommandError.InvalidArgument;
    };

    const task_id = switch (parsed_input) {
        .internal_id => |id| id,
        .plan_task => |pt| blk: {
            // Resolve plan:number to internal ID
            const resolved_id = try storage.tasks.getTaskByPlanAndNumber(pt.slug, pt.number);
            if (resolved_id == null) {
                return CommandError.TaskNotFound;
            }
            break :blk resolved_id.?;
        },
    };

    // Assertions: Task ID must be positive
    std.debug.assert(task_id > 0);

    // Rationale: startTask() changes status to 'in_progress' and updates updated_at.
    // If task doesn't exist or is already started, Storage will return appropriate error.
    try storage.startTask(task_id);

    // Rationale: After successful start, retrieve updated task for display.
    // This provides user feedback confirming the status change.
    var task = try storage.getTask(task_id) orelse {
        return CommandError.TaskNotFound;
    };
    defer task.deinit(allocator);

    // Rationale: Get plan title for display using plan_slug from task
    var plan_summary = try storage.getPlanSummary(task.plan_slug);
    defer if (plan_summary) |*summary| {
        summary.deinit(allocator);
    };
    const plan_title = if (plan_summary) |summary| summary.title else null;

    // Rationale: Task start doesn't involve blockers/dependents, so we pass empty arrays.
    // Only show command needs full blocker/dependent information.
    const empty_blockers: []const types.BlockerInfo = &[_]types.BlockerInfo{};

    if (!builtin.is_test) {
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;

        if (json_output) {
            // Rationale: JSON output uses standard formatTaskJson for consistency.
            // Callers can parse status field to confirm it's now 'in_progress'.
            try format.formatTaskJson(allocator, stdout, task, plan_title, empty_blockers, empty_blockers);
        } else {
            // Rationale: Text output shows brief confirmation with task details using formatted ID.
            // User sees formatted task ID (plan:NNN), title, and new status (in_progress).
            const formatted_id = try utils.formatTaskId(allocator, task.plan_slug, task.plan_task_number);
            defer allocator.free(formatted_id);
            try stdout.print("Started task {s}: {s}\n", .{ formatted_id, task.title });
            try stdout.print("Status: {s}\n", .{task.status.toString()});
        }

        stdout.flush() catch {};
    }
}
