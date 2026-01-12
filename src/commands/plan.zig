//! Plan command handlers for Guerilla Graph CLI.
//!
//! This module contains all plan-specific command handler implementations
//! that process parsed CLI arguments and interact with Storage to execute
//! plan operations.
//!
//! Each command handler follows the pattern:
//! 1. Parse and validate arguments
//! 2. Call Storage operations
//! 3. Format output (text or JSON)
//!
//! Tiger Style: Full names, 2+ assertions per function, rationale comments.

const std = @import("std");
const builtin = @import("builtin");
const types = @import("../types.zig");
const utils = @import("../utils.zig");
const format = @import("../format.zig");
const Storage = @import("../storage.zig").Storage;

/// Error types for command execution.
/// These errors provide user-friendly feedback when command arguments are invalid.
pub const CommandError = error{
    /// A required positional argument was not provided.
    /// Example: Running 'gg plan show' without specifying a plan ID.
    MissingArgument,

    /// An argument value is invalid or malformed.
    /// Example: Providing an uppercase letter in a kebab-case ID.
    InvalidArgument,

    /// A required flag (--flag) was not provided.
    /// Example: Running 'gg plan new auth' without --title flag.
    MissingRequiredFlag,

    /// Plan was not found in the database.
    /// Example: Trying to show or update a plan that doesn't exist.
    PlanNotFound,
};

// ============================================================================
// Plan Creation Command
// ============================================================================

/// Parsed arguments for plan new command
const PlanNewArgs = struct {
    id: []const u8, // Kebab-case plan ID
    title: []const u8,
    description: []const u8,
    description_owned: bool, // true if description is allocated
    created_at: ?i64, // Optional epoch timestamp for backdating plan creation.
};

/// Parse plan new command arguments
/// Command format: gg plan new <id> --title <text> [--description <text>] [--description-file <path>]
pub fn parsePlanNewArgs(io: std.Io, allocator: std.mem.Allocator, arguments: []const []const u8) !PlanNewArgs {
    // Assertions: Validate inputs

    // Rationale: First argument is the plan ID (positional argument).
    // User provides this directly without a flag (e.g., "auth", "tech-debt").
    if (arguments.len == 0) {
        return CommandError.MissingArgument;
    }

    const plan_id = arguments[0];

    // Rationale: Validate kebab-case format early to provide clear error messages.
    // This prevents invalid IDs from reaching the storage layer.
    try utils.validateKebabCase(plan_id);

    // Parse flags: --title, --description, and --description-file
    var title: ?[]const u8 = null;
    var description: []const u8 = "";
    var description_owned: bool = false;
    var created_at: ?i64 = null;
    var index: usize = 1;

    // Rationale: Iterate through remaining arguments to find --title and --description flags.
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
            // Rationale: Free previously allocated description if overwriting
            if (description_owned) {
                allocator.free(description);
            }
            description = arguments[index + 1];
            description_owned = false; // Borrowed from argv
            index += 2;
        } else if (std.mem.eql(u8, argument, "--description-file")) {
            // Rationale: --description-file flag must be followed by a file path
            if (index + 1 >= arguments.len) {
                return CommandError.MissingArgument;
            }
            // Rationale: Free previously allocated description if overwriting
            if (description_owned) {
                allocator.free(description);
            }
            const file_path = arguments[index + 1];
            const max_size = std.Io.Limit.limited(10 * 1024 * 1024); // 10MB max

            // Rationale: "-" is Unix convention for stdin (cat, grep, etc.)
            if (std.mem.eql(u8, file_path, "-")) {
                // Read from stdin with same size limit as file.
                var stdin_buffer: [8192]u8 = undefined;
                var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buffer);
                description = try stdin_reader.interface.allocRemaining(allocator, max_size);
            } else {
                // Read from file.
                const cwd = std.Io.Dir.cwd();
                description = try cwd.readFileAlloc(io, file_path, allocator, max_size);
            }
            description_owned = true; // Allocated, must free
            index += 2;
        } else if (std.mem.eql(u8, argument, "--created-at")) {
            // Rationale: --created-at accepts epoch timestamp for backdating plan creation.
            if (index + 1 >= arguments.len) {
                return CommandError.MissingArgument;
            }
            const ts = std.fmt.parseInt(i64, arguments[index + 1], 10) catch {
                return CommandError.InvalidArgument;
            };
            // Validate timestamp is within reasonable range.
            if (ts < 0 or ts > 4102444800) { // Before 1970 or after 2100
                return CommandError.InvalidArgument;
            }
            created_at = ts;
            index += 2;
        } else {
            // Unknown flag or extra argument
            return CommandError.InvalidArgument;
        }
    }

    // Rationale: Title is optional, defaults to empty string if not provided
    // (Removed required check - title can be null)

    // Assertions: Postconditions
    std.debug.assert(plan_id.len > 0);
    // Note: title can be empty (optional), so no length assertion

    return PlanNewArgs{
        .id = plan_id,
        .title = title orelse "", // Empty string if title not provided
        .description = description,
        .description_owned = description_owned,
        .created_at = created_at,
    };
}

/// Handle plan new command
/// Creates a new top-level plan in the system.
///
/// Command: gg plan new <id> --title <text> [--description <text>]
/// Example: gg plan new auth --title "Authentication System"
///
/// Rationale: Renamed from handleCreatePlan to fit resource-action CLI pattern.
/// This command creates a plan with validation of kebab-case ID and title length.
pub fn handlePlanNew(
    io: std.Io,
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    // Assertions: Validate inputs
    std.debug.assert(arguments.len >= 1);

    // Parse command arguments
    const args = try parsePlanNewArgs(io, allocator, arguments);
    defer {
        if (args.description_owned) {
            allocator.free(args.description);
        }
    }

    // Rationale: Validate title length (0-500 characters, empty allowed).
    // This catches user errors before attempting database operations.
    if (args.title.len > 500) {
        return CommandError.InvalidArgument;
    }

    // Create plan in database
    try storage.createPlan(args.id, args.title, args.description, args.created_at);

    // Fetch created plan for display (user feedback)
    var plan_summary = try storage.getPlanSummary(args.id) orelse {
        return CommandError.PlanNotFound;
    };
    defer plan_summary.deinit(allocator);

    // Format and display (skip in test mode to avoid stdout buffering issues)
    if (!builtin.is_test) {
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(io, stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;

        if (json_output) {
            try format.formatPlanJson(stdout, plan_summary);
        } else {
            try format.formatPlan(stdout, plan_summary);
        }

        stdout.flush() catch {};
    }
}

// ============================================================================
// Plan Show Command
// ============================================================================

/// Handle plan show command
/// Displays a plan with task counts and status summary.
///
/// Command: gg plan show <id>
/// Example: gg plan show auth
///
/// Rationale: Renamed from handleShowPlan to fit resource-action CLI pattern.
/// Shows plan details with aggregated task counts, allowing users to quickly
/// understand the status of a plan without listing all tasks.
pub fn handlePlanShow(
    io: std.Io,
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    // Rationale: User must provide plan ID as first positional argument.
    // This matches the pattern from handlePlanNew where ID is positional.
    if (arguments.len == 0) {
        return CommandError.MissingArgument;
    }

    const plan_id = arguments[0];

    // Rationale: Validate kebab-case format early to provide clear error messages.
    // This prevents invalid IDs from reaching the storage layer.
    try utils.validateKebabCase(plan_id);

    // Assertions: Postcondition - plan_id is valid
    std.debug.assert(plan_id.len > 0);

    var plan_summary = try storage.getPlanSummary(plan_id) orelse {
        return CommandError.PlanNotFound;
    };
    defer plan_summary.deinit(allocator);

    if (!builtin.is_test) {
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(io, stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;

        if (json_output) {
            try format.formatPlanJson(stdout, plan_summary);
        } else {
            try format.formatPlan(stdout, plan_summary);
        }

        stdout.flush() catch {};
    }
}

// ============================================================================
// Plan List Command
// ============================================================================

/// Parse plan list command arguments
/// Command format: gg plan list [--status <status>]
pub fn parsePlanListArgs(arguments: []const []const u8) !?types.TaskStatus {
    // Assertions: Validate inputs

    // Parse optional --status flag
    var status_filter: ?types.TaskStatus = null;
    var index: usize = 0;

    // Rationale: Iterate through arguments to find --status flag.
    while (index < arguments.len) {
        const argument = arguments[index];

        if (std.mem.eql(u8, argument, "--status")) {
            // Rationale: --status flag must be followed by a value
            if (index + 1 >= arguments.len) {
                return CommandError.MissingArgument;
            }

            const status_string = arguments[index + 1];
            // Rationale: Convert InvalidTaskStatus error to InvalidArgument for consistent error handling
            status_filter = types.TaskStatus.fromString(status_string) catch {
                return CommandError.InvalidArgument;
            };
            index += 2;
        } else {
            // Unknown flag or extra argument
            return CommandError.InvalidArgument;
        }
    }

    return status_filter;
}

/// Handle plan list command
/// Lists all plans with optional status filter.
///
/// Command: gg plan list [--status <status>]
/// Example: gg plan list
/// Example: gg plan list --status completed
///
/// Rationale: Renamed from handleListPlans to fit resource-action CLI pattern.
/// Provides a way to see all plans (features) in the system with their task
/// counts and computed status. The --status filter allows users to focus on
/// completed vs incomplete features.
pub fn handlePlanList(
    io: std.Io,
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    // Assertions: Validate inputs

    // Parse command arguments
    const status_filter = try parsePlanListArgs(arguments);

    const plan_summaries = try storage.listPlans(status_filter);
    defer {
        for (plan_summaries) |*summary| {
            summary.deinit(allocator);
        }
        allocator.free(plan_summaries);
    }

    if (!builtin.is_test) {
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(io, stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;

        if (json_output) {
            try format.formatPlanListJson(stdout, plan_summaries);
        } else {
            try format.formatPlanList(stdout, plan_summaries);
        }

        stdout.flush() catch {};
    }
}

// ============================================================================
// Plan Update Command
// ============================================================================

/// Parsed arguments for plan update command
const PlanUpdateArgs = struct {
    id: []const u8,
    title: ?[]const u8,
    description: ?[]const u8,
    description_owned: bool, // true if description is allocated
};

/// Parse plan update command arguments
/// Command format: gg plan update <id> [--title <text>] [--description <text>] [--description-file <path>]
/// At least one optional flag must be provided.
pub fn parsePlanUpdateArgs(io: std.Io, allocator: std.mem.Allocator, arguments: []const []const u8) !PlanUpdateArgs {
    // Rationale: First argument is the plan ID (positional argument).
    // User provides this directly without a flag (e.g., "auth").
    if (arguments.len == 0) {
        return CommandError.MissingArgument;
    }

    const plan_id = arguments[0];

    // Rationale: Validate kebab-case format early to provide clear error messages.
    try utils.validateKebabCase(plan_id);

    // Parse optional flags: --title, --description, --description-file
    var title: ?[]const u8 = null;
    var description: ?[]const u8 = null;
    var description_owned: bool = false;
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
            // Rationale: Free previously allocated description if overwriting
            if (description_owned and description != null) {
                allocator.free(description.?);
            }
            description = arguments[index + 1];
            description_owned = false; // Borrowed from argv
            index += 2;
        } else if (std.mem.eql(u8, argument, "--description-file")) {
            // Rationale: --description-file flag must be followed by a file path
            if (index + 1 >= arguments.len) {
                return CommandError.MissingArgument;
            }
            // Rationale: Free previously allocated description if overwriting
            if (description_owned and description != null) {
                allocator.free(description.?);
            }
            const file_path = arguments[index + 1];
            const max_size = std.Io.Limit.limited(10 * 1024 * 1024); // 10MB max

            // Rationale: "-" is Unix convention for stdin (cat, grep, etc.)
            if (std.mem.eql(u8, file_path, "-")) {
                // Read from stdin with same size limit as file.
                var stdin_buffer: [8192]u8 = undefined;
                var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buffer);
                description = try stdin_reader.interface.allocRemaining(allocator, max_size);
            } else {
                // Read from file.
                const cwd = std.Io.Dir.cwd();
                description = try cwd.readFileAlloc(io, file_path, allocator, max_size);
            }
            description_owned = true; // Allocated, must free
            index += 2;
        } else {
            // Unknown flag or extra argument
            return CommandError.InvalidArgument;
        }
    }

    // Rationale: At least one update field must be provided.
    // If both are null, this is a no-op and should be caught early.
    if (title == null and description == null) {
        return CommandError.MissingRequiredFlag;
    }

    // Assertions: Postconditions
    std.debug.assert(plan_id.len > 0);
    std.debug.assert(title != null or description != null);

    return PlanUpdateArgs{
        .id = plan_id,
        .title = title,
        .description = description,
        .description_owned = description_owned,
    };
}

/// Handle plan update command
/// Updates plan fields (title and/or description).
/// At least one field must be provided.
///
/// Command: gg plan update <id> [--title <text>] [--description <text>] [--description-file <path>]
/// Example: gg plan update auth --title "Updated Authentication System"
/// Example: gg plan update auth --description "New description"
/// Example: gg plan update auth --description-file revised.md
///
/// Rationale: Provides a general-purpose update command for modifying plan fields.
/// This is more flexible than separate commands for each field type.
pub fn handlePlanUpdate(
    io: std.Io,
    allocator: std.mem.Allocator,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    // Assertions: Validate inputs
    std.debug.assert(arguments.len >= 1);

    // Parse command arguments
    const args = try parsePlanUpdateArgs(io, allocator, arguments);
    defer {
        if (args.description_owned and args.description != null) {
            allocator.free(args.description.?);
        }
    }

    // Rationale: Validate title length if provided (1-500 characters per schema constraint).
    // This catches user errors before attempting database operations.
    if (args.title) |t| {
        if (t.len == 0 or t.len > 500) {
            return CommandError.InvalidArgument;
        }
    }

    // Rationale: updatePlan() modifies specified fields and updates updated_at timestamp.
    // If plan doesn't exist, Storage will return appropriate error.
    try storage.updatePlan(args.id, args.title, args.description);

    // Rationale: After successful update, retrieve updated plan for display.
    // This provides user feedback confirming the changes.
    var plan_summary = try storage.getPlanSummary(args.id) orelse {
        return CommandError.PlanNotFound;
    };
    defer plan_summary.deinit(allocator);

    if (!builtin.is_test) {
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(io, stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;

        if (json_output) {
            // Rationale: JSON output uses standard formatPlanJson for consistency.
            // Callers can parse fields to confirm updates.
            try format.formatPlanJson(stdout, plan_summary);
        } else {
            // Rationale: Text output shows brief confirmation with plan details.
            // User sees plan slug, title, and updated fields.
            try stdout.print("Updated plan {s}: {s}\n", .{ plan_summary.slug, plan_summary.title });
        }

        stdout.flush() catch {};
    }
}

// ============================================================================
// Plan Delete Command
// ============================================================================

/// Handle plan delete command
/// Deletes a plan and all associated tasks (cascade deletion).
///
/// Command: gg plan delete <id>
/// Example: gg plan delete auth
///
/// Rationale: When a plan is deleted, all tasks under that plan are
/// permanently removed along with their dependencies. This provides a clean
/// way to remove entire feature branches. Deletion is atomic (transaction-wrapped).
pub fn handlePlanDelete(
    io: std.Io,
    arguments: []const []const u8,
    json_output: bool,
    storage: *Storage,
) !void {
    // Assertions: Validate inputs

    // Rationale: User must provide plan ID as first positional argument.
    // Command format: gg plan delete <id>
    if (arguments.len == 0) {
        return CommandError.MissingArgument;
    }

    const plan_id = arguments[0];

    // Rationale: Validate kebab-case format early to provide clear error messages.
    try utils.validateKebabCase(plan_id);

    // Assertions: Plan ID must be valid
    std.debug.assert(plan_id.len > 0);

    // Rationale: deletePlan() now returns count of cascade-deleted tasks.
    // Capture count to display in output for user awareness.
    const task_count = try storage.deletePlan(plan_id);

    if (!builtin.is_test) {
        var stdout_buffer: [8192]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(io, stdout_buffer[0..]);
        const stdout = &stdout_writer.interface;

        if (json_output) {
            try stdout.writeAll("{\n");
            try stdout.writeAll("  \"status\": \"success\",\n");
            try stdout.print("  \"plan_id\": \"{s}\",\n", .{plan_id});
            try stdout.print("  \"tasks_deleted\": {d},\n", .{task_count});
            try stdout.writeAll("  \"message\": \"Plan deleted successfully\"\n");
            try stdout.writeAll("}\n");
        } else {
            try stdout.print("Deleted plan {s} ({d} tasks deleted)\n", .{ plan_id, task_count });
        }

        stdout.flush() catch {};
    }
}
