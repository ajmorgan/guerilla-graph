//! Task update command handler for Guerilla Graph CLI.
//!
//! This module contains the task update command implementation that allows
//! modifying task fields (title, description, status).
//!
//! Command: gg update <task-id> [--title <text>] [--description <text>] [--description-file <path>] [--status <status>]
//!
//! At least one optional flag must be provided.
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
    MissingRequiredFlag,
    TaskNotFound,
};

/// Parsed arguments for update command
const UpdateArgs = struct {
    task_id_input: types.TaskIdInput,
    title: ?[]const u8,
    description: ?[]const u8,
    description_owned: bool, // true if description is allocated
    status: ?types.TaskStatus,
};

/// Parse update command arguments
/// Command format: gg update <task-id> [--title <text>] [--description <text>] [--description-file <path>] [--status <status>]
/// At least one optional flag must be provided.
/// Note: Returns the raw parsed input - caller must resolve formatted IDs to internal IDs.
pub fn parseUpdateArgs(allocator: std.mem.Allocator, arguments: []const []const u8) !struct {
    task_id_input: types.TaskIdInput,
    title: ?[]const u8,
    description: ?[]const u8,
    description_owned: bool,
    status: ?types.TaskStatus,
} {
    // Rationale: First argument is the task ID (positional argument).
    // User provides this directly without a flag (e.g., "123" or "auth:001").
    if (arguments.len == 0) {
        return CommandError.MissingArgument;
    }

    // Parse task ID from CLI argument (accepts both numeric "19" and formatted "auth:019")
    const task_id_input = utils.parseTaskInput(arguments[0]) catch {
        return CommandError.InvalidArgument;
    };

    // Parse optional flags: --title, --description, --description-file, --status
    var title: ?[]const u8 = null;
    var description: ?[]const u8 = null;
    var description_owned: bool = false;
    var status: ?types.TaskStatus = null;
    var index: usize = 1;

    // Rationale: Iterate through remaining arguments to find flags.
    // Each flag is followed by its value as the next argument.
    while (index < arguments.len) {
        const argument = arguments[index];

        if (std.mem.eql(u8, argument, "--title")) {
            // Rationale: --title flag must be followed by a value
            if (index + 1 >= arguments.len) {
                return CommandError.MissingArgument;
            }
            title = arguments[index + 1];
            index += 2;
        } else if (std.mem.eql(u8, argument, "--description")) {
            // Rationale: --description flag must be followed by a value
            if (index + 1 >= arguments.len) {
                return CommandError.MissingArgument;
            }
            description = arguments[index + 1];
            description_owned = false; // Borrowed from argv
            index += 2;
        } else if (std.mem.eql(u8, argument, "--description-file")) {
            // Rationale: --description-file flag must be followed by a file path
            if (index + 1 >= arguments.len) {
                return CommandError.MissingArgument;
            }
            const file_path = arguments[index + 1];
            const cwd = std.fs.cwd();
            const max_size = std.Io.Limit.limited(10 * 1024 * 1024); // 10MB max
            description = try cwd.readFileAlloc(file_path, allocator, max_size);
            description_owned = true; // Allocated, must free
            index += 2;
        } else if (std.mem.eql(u8, argument, "--status")) {
            // Rationale: --status flag must be followed by a valid status value
            if (index + 1 >= arguments.len) {
                return CommandError.MissingArgument;
            }
            const status_string = arguments[index + 1];
            status = try types.TaskStatus.fromString(status_string);
            index += 2;
        } else {
            // Unknown flag or extra argument
            return CommandError.InvalidArgument;
        }
    }

    // Rationale: At least one update field must be provided.
    // If all are null, this is a no-op and should be caught early.
    if (title == null and description == null and status == null) {
        return CommandError.MissingRequiredFlag;
    }

    // Assertions: Postconditions
    std.debug.assert(title != null or description != null or status != null);

    return .{
        .task_id_input = task_id_input,
        .title = title,
        .description = description,
        .description_owned = description_owned,
        .status = status,
    };
}

/// Handle update command (renamed from handleUpdate)
/// Updates task fields (title, description, and/or status).
/// At least one field must be provided.
///
/// Command: gg update <task-id> [--title <text>] [--description <text>] [--description-file <path>] [--status <status>]
/// Example: gg update 1 --title "Updated title"
/// Example: gg update 1 --description "New description"
/// Example: gg update 1 --description-file updated.md
/// Example: gg update 1 --status in_progress
/// Example: gg update 1 --title "New title" --status completed
///
/// Rationale: Provides a general-purpose update command for modifying any task field.
/// This is more flexible than separate commands for each field type.
pub fn handleTaskUpdate(
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    // Assertions: Validate inputs
    std.debug.assert(arguments.len >= 1);

    // Parse command arguments
    const args = try parseUpdateArgs(allocator, arguments);
    defer {
        if (args.description_owned and args.description != null) {
            allocator.free(args.description.?);
        }
    }

    // Resolve task ID from input (supports both numeric and formatted IDs)
    const task_id = switch (args.task_id_input) {
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

    // Rationale: Validate title length if provided (1-500 characters per schema constraint).
    // This catches user errors before attempting database operations.
    if (args.title) |t| {
        if (t.len == 0 or t.len > types.MAX_TITLE_LENGTH) {
            return CommandError.InvalidArgument;
        }
    }

    // Rationale: updateTask() modifies specified fields and updates updated_at timestamp.
    // If task doesn't exist, Storage will return appropriate error.
    try storage.updateTask(task_id, args.title, args.description, args.status);

    // Rationale: After successful update, retrieve updated task for display.
    // This provides user feedback confirming the changes.
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

    // Rationale: Task update doesn't involve blockers/dependents, so we pass empty arrays.
    // Only show command needs full blocker/dependent information.
    const empty_blockers: []const types.BlockerInfo = &[_]types.BlockerInfo{};

    if (!builtin.is_test) {
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;

        if (json_output) {
            // Rationale: JSON output uses standard formatTaskJson for consistency.
            // Callers can parse fields to confirm updates.
            try format.formatTaskJson(allocator, stdout, task, plan_title, empty_blockers, empty_blockers);
        } else {
            // Rationale: Text output shows brief confirmation with task details using formatted ID.
            // User sees formatted task ID (plan:NNN), title, and updated fields.
            const formatted_id = try utils.formatTaskId(allocator, task.plan_slug, task.plan_task_number);
            defer allocator.free(formatted_id);
            try stdout.print("Updated task {s}: {s}\n", .{ formatted_id, task.title });
            try stdout.print("Status: {s}\n", .{task.status.toString()});
        }

        stdout.flush() catch {};
    }
}
