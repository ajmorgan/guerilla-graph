//! Task creation command handler for Guerilla Graph CLI.
//!
//! This module contains the task creation logic extracted from task.zig.
//! It handles the 'task new' command that creates new tasks under a plan.
//!
//! Tiger Style: Full names, 2+ assertions per function, rationale comments.

const std = @import("std");
const builtin = @import("builtin");
const types = @import("../types.zig");
const utils = @import("../utils.zig");
const format = @import("../format.zig");
const Storage = @import("../storage.zig").Storage;
const TaskManager = @import("../task_manager.zig").TaskManager;

/// Error types for command execution.
pub const CommandError = error{
    MissingArgument,
    InvalidArgument,
    MissingRequiredFlag,
    TaskNotFound,
};

// ============================================================================
// Task Creation Command
// ============================================================================

/// Parsed arguments for create command
const CreateArgs = struct {
    title: []const u8,
    plan: ?[]const u8, // Plan slug (required by storage, validated before createTask call)
    description: []const u8,
    description_owned: bool, // true if description is allocated, false if borrowed
};

/// Parse flags from command line arguments for task creation.
/// Returns struct with title, plan, and description fields.
///
/// Rationale: Extracted from parseCreateArgs to reduce function length.
/// Handles --title, --plan, --description, --description-file flags.
fn parseCreateArgsParseFlags(allocator: std.mem.Allocator, arguments: []const []const u8, start_index: usize) !struct {
    title: []const u8, // Task title (optional, may be empty)
    plan: ?[]const u8, // Plan slug (required by storage, optional flag for parsing)
    description: []const u8,
    description_owned: bool,
} {
    // Assertions: Validate inputs
    std.debug.assert(start_index <= arguments.len);

    var title: []const u8 = "";
    var plan: ?[]const u8 = null;
    var description: []const u8 = "";
    var description_owned: bool = false;
    var index: usize = start_index;

    // Rationale: Iterate through remaining arguments to find flags.
    while (index < arguments.len) {
        const argument = arguments[index];

        if (std.mem.eql(u8, argument, "--title")) {
            if (index + 1 >= arguments.len) {
                return CommandError.MissingArgument;
            }
            title = arguments[index + 1];
            index += 2;
        } else if (std.mem.eql(u8, argument, "--plan")) {
            if (index + 1 >= arguments.len) {
                return CommandError.MissingArgument;
            }
            plan = arguments[index + 1];
            index += 2;
        } else if (std.mem.eql(u8, argument, "--description")) {
            if (index + 1 >= arguments.len) {
                return CommandError.MissingArgument;
            }
            description = arguments[index + 1];
            description_owned = false; // Borrowed from argv
            index += 2;
        } else if (std.mem.eql(u8, argument, "--description-file")) {
            if (index + 1 >= arguments.len) {
                return CommandError.MissingArgument;
            }
            const file_path = arguments[index + 1];
            const cwd = std.fs.cwd();
            const max_size = std.Io.Limit.limited(10 * 1024 * 1024); // 10MB max
            description = try cwd.readFileAlloc(file_path, allocator, max_size);
            description_owned = true; // Allocated, must free
            index += 2;
        } else {
            return CommandError.InvalidArgument;
        }
    }

    // Assertion: Postconditions
    if (plan) |p| {
        std.debug.assert(p.len > 0);
    }

    return .{
        .title = title,
        .plan = plan,
        .description = description,
        .description_owned = description_owned,
    };
}

/// Parse create command arguments
/// Command format: gg create --title <title> --plan <id> [--description <text>] [--description-file <path>]
pub fn parseCreateArgs(allocator: std.mem.Allocator, arguments: []const []const u8) !CreateArgs {
    // Assertions: Validate inputs (arguments may be empty if all flags)
    std.debug.assert(arguments.len >= 0);

    // Rationale: Parse flags using helper (starts at index 0 - no positional title)
    const flags = try parseCreateArgsParseFlags(allocator, arguments, 0);

    // Assertions: Postconditions (title may be empty - validation happens in handleTaskNew)
    if (flags.plan) |p| {
        std.debug.assert(p.len > 0);
    }

    return CreateArgs{
        .title = flags.title,
        .plan = flags.plan, // null = orphan task
        .description = flags.description,
        .description_owned = flags.description_owned,
    };
}

/// Handle create command (renamed from handleCreate)
/// Creates a new task under a plan.
///
/// Command: gg create <title> --plan <id> [--description <text>] [--description-file <path>]
/// Example: gg create "Add login endpoint" --plan auth
///
/// Rationale: Task creation requires validation of plan existence.
/// Dependencies should be added separately using 'gg dep add'.
/// Uses TaskManager for business logic and Storage for data access.
pub fn handleTaskNew(
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
    task_manager: *TaskManager,
) !void {
    // Assertions: Validate inputs (Tiger Style: 2+ per function)
    std.debug.assert(arguments.len >= 1);
    std.debug.assert(storage.database != null);

    // Parse command arguments
    const args = try parseCreateArgs(allocator, arguments);
    defer {
        if (args.description_owned) {
            allocator.free(args.description);
        }
    }

    // Rationale: Validate title length (0-MAX_TITLE_LENGTH characters per schema constraint).
    // Empty title is allowed (smart new command will populate it later).
    if (args.title.len > types.MAX_TITLE_LENGTH) {
        return CommandError.InvalidArgument;
    }

    // Rationale: After schema migration, plan is required (no orphan tasks)
    if (args.plan == null) {
        return CommandError.MissingRequiredFlag;
    }

    // Rationale: Validate plan format (kebab-case)
    const plan_id = args.plan.?;
    try utils.validateKebabCase(plan_id);

    // Rationale: Create task via TaskManager with no dependencies.
    // Dependencies should be added separately using 'gg dep add' command.
    const task_id = try task_manager.createTask(
        plan_id, // Use unwrapped plan_id (guaranteed non-null after validation above)
        args.title,
        args.description,
        &[_]u32{}, // Empty dependencies - use 'gg dep add' separately
    );

    // Assertion: Created task ID must be positive
    std.debug.assert(task_id > 0);

    // Rationale: Fetch created task for display (provides user feedback).
    // This confirms the task was successfully persisted with correct data.
    var task = try storage.getTask(task_id) orelse {
        return error.TaskNotFound;
    };
    defer task.deinit(allocator);

    // Rationale: Format and display result based on output mode.
    // Text mode: human-readable with plan context.
    // JSON mode: structured data for programmatic consumption.
    if (!builtin.is_test) {
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;

        if (json_output) {
            try handleTaskNew_formatJson(allocator, stdout, task, storage);
        } else {
            try handleTaskNew_formatText(allocator, stdout, task);
        }

        stdout.flush() catch {};
    }
}

/// Format task creation result as JSON output.
/// Rationale: Extracted from handleTaskNew to reduce function length.
/// Note: Requires storage for fetching plan title, blockers, and dependents.
fn handleTaskNew_formatJson(
    allocator: std.mem.Allocator,
    writer: anytype,
    task: types.Task,
    storage: *Storage,
) !void {
    // Assertions: Validate inputs
    std.debug.assert(task.id > 0);
    std.debug.assert(task.plan_slug.len > 0);

    // Fetch plan title for context in JSON output
    const plan_title = blk: {
        const plan_summary = try storage.getPlanSummary(task.plan_slug);
        if (plan_summary) |summary| {
            defer {
                var mutable_summary = summary;
                mutable_summary.deinit(allocator);
            }
            const title = try allocator.dupe(u8, summary.title);
            break :blk title;
        }
        break :blk null;
    };
    defer if (plan_title) |title| allocator.free(title);

    // Get blockers and dependents for complete task view
    const blockers = try storage.getBlockers(task.id);
    defer {
        for (blockers) |*blocker| {
            var mutable_blocker = blocker.*;
            mutable_blocker.deinit(allocator);
        }
        allocator.free(blockers);
    }

    const dependents = try storage.getDependents(task.id);
    defer {
        for (dependents) |*dependent| {
            var mutable_dependent = dependent.*;
            mutable_dependent.deinit(allocator);
        }
        allocator.free(dependents);
    }

    try format.formatTaskJson(allocator, writer, task, plan_title, blockers, dependents);
}

/// Format task creation result as text output.
/// Rationale: Extracted from handleTaskNew to reduce function length.
/// Note: Simpler than JSON formatter - no storage queries needed for text output.
fn handleTaskNew_formatText(
    allocator: std.mem.Allocator,
    writer: anytype,
    task: types.Task,
) !void {
    // Assertions: Validate inputs
    std.debug.assert(task.id > 0);
    std.debug.assert(task.plan_slug.len > 0);

    const formatted_id = try utils.formatTaskId(allocator, task.plan_slug, task.plan_task_number);
    defer allocator.free(formatted_id);

    try writer.print("Created task {s}\n", .{formatted_id});
    try writer.print("Plan: {s}\n", .{task.plan_slug});
    try writer.print("Title: {s}\n", .{task.title});
    if (task.description.len > 0) {
        try writer.print("Description: {s}\n", .{task.description});
    }
}
