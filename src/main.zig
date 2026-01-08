const std = @import("std");
const gg = @import("guerilla_graph");
const cli = gg.cli;

// Resource-based command modules
const plan_commands = gg.plan_commands;
const task_commands = gg.task_commands;
const dep_commands = gg.dep_commands;
const doctor_commands = gg.doctor_commands;

// Individual command modules
const ready_commands = gg.ready_commands;
const blocked_commands = gg.blocked_commands;
const list_commands = gg.list_commands;
const workflow_commands = gg.workflow_commands;
const init_commands = gg.init_commands;
const help_commands = gg.help_commands;

pub fn main(init: std.process.Init) !void {
    mainImpl(init) catch |err| {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(init.io, stderr_buffer[0..]);
        const stderr = &stderr_writer.interface;

        // Print user-friendly error message based on error type
        const error_name = @errorName(err);
        if (std.mem.eql(u8, error_name, "UnknownResource")) {
            try stderr.print("Error: Unknown resource.\n", .{});
            try stderr.print("Valid resources: plan, task, dep, query\n", .{});
            try stderr.print("Run 'gg help' to see available commands.\n", .{});
        } else if (std.mem.eql(u8, error_name, "UnknownAction")) {
            try stderr.print("Error: Unknown action.\n", .{});
            try stderr.print("Run 'gg help' to see available actions for each resource.\n", .{});
        } else if (std.mem.eql(u8, error_name, "MissingAction")) {
            try stderr.print("Error: Missing action.\n", .{});
            try stderr.print("Format: gg <resource> <action> [args]\n", .{});
            try stderr.print("Run 'gg help' to see available commands.\n", .{});
        } else if (std.mem.eql(u8, error_name, "InvalidCommand")) {
            try stderr.print("Error: Invalid command.\n", .{});
            try stderr.print("Run 'gg help' to see available commands.\n", .{});
        } else if (std.mem.eql(u8, error_name, "InvalidArgument")) {
            try stderr.print("Error: Invalid argument provided.\n", .{});
            try stderr.print("Run 'gg <command> --help' for usage information.\n", .{});
        } else if (std.mem.eql(u8, error_name, "OutOfMemory")) {
            try stderr.print("Error: Out of memory.\n", .{});
            try stderr.print("The system has run out of available memory. Try closing other applications.\n", .{});
        } else if (std.mem.eql(u8, error_name, "FileNotFound")) {
            try stderr.print("Error: File not found.\n", .{});
            try stderr.print("Make sure the file path is correct and the file exists.\n", .{});
        } else if (std.mem.eql(u8, error_name, "PermissionDenied")) {
            try stderr.print("Error: Permission denied.\n", .{});
            try stderr.print("Check file permissions or run with appropriate access rights.\n", .{});
        } else if (std.mem.eql(u8, error_name, "MissingArgument")) {
            try stderr.print("Error: Missing required argument.\n", .{});
            try stderr.print("Run 'gg <command> --help' to see required arguments.\n", .{});
        } else if (std.mem.eql(u8, error_name, "MissingRequiredFlag")) {
            try stderr.print("Error: Missing required flag.\n", .{});
            try stderr.print("Run 'gg <command> --help' to see required flags.\n", .{});
        } else if (std.mem.eql(u8, error_name, "NotAWorkspace")) {
            try stderr.print("Error: Not in a Guerilla Graph workspace.\n", .{});
            try stderr.print("Run 'gg init' in your project directory to create a workspace, or\n", .{});
            try stderr.print("navigate to an existing workspace (directory with .gg folder).\n", .{});
        } else if (std.mem.eql(u8, error_name, "InvalidKebabCase")) {
            try stderr.print("Error: Invalid ID format.\n", .{});
            try stderr.print("IDs must use kebab-case: lowercase letters and hyphens only.\n", .{});
            try stderr.print("Examples: 'auth', 'tech-debt', 'my-feature'\n", .{});
        } else if (std.mem.eql(u8, error_name, "EmptyId")) {
            try stderr.print("Error: Empty ID provided.\n", .{});
            try stderr.print("IDs must contain at least one character.\n", .{});
        } else if (std.mem.eql(u8, error_name, "InvalidTaskId")) {
            try stderr.print("Error: Invalid task ID format.\n", .{});
            try stderr.print("Task IDs must be in format 'plan:number' (e.g., 'auth:001').\n", .{});
        } else if (std.mem.eql(u8, error_name, "AlreadyInWorkspace")) {
            try stderr.print("Error: Already in a Guerilla Graph workspace.\n", .{});
            try stderr.print("Use 'gg init --force' to reinitialize (destroys existing data).\n", .{});
        } else if (std.mem.eql(u8, error_name, "OpenFailed")) {
            try stderr.print("Error: Failed to open database.\n", .{});
            try stderr.print("The database file may be corrupted or locked by another process.\n", .{});
            try stderr.print("Run 'gg doctor' to check workspace health.\n", .{});
        } else if (std.mem.eql(u8, error_name, "DatabaseClosed")) {
            try stderr.print("Error: Database connection closed unexpectedly.\n", .{});
            try stderr.print("This is an internal error. Please report this issue.\n", .{});
        } else if (std.mem.eql(u8, error_name, "CycleDetected")) {
            try stderr.print("Error: Cycle detected in task dependencies.\n", .{});
            try stderr.print("Adding this dependency would create a circular reference.\n", .{});
            try stderr.print("Use 'gg blockers <task>' to see the dependency chain.\n", .{});
        } else if (std.mem.eql(u8, error_name, "InvalidData")) {
            try stderr.print("Error: Invalid data or operation.\n", .{});
            try stderr.print("The requested resource may not exist or the operation is not allowed.\n", .{});
        } else {
            try stderr.print("Error: {s}\n", .{error_name});
            try stderr.print("Run 'gg help' for usage information, or 'gg <command> --help' for command-specific help.\n", .{});
            try stderr.print("Run 'gg doctor' to check workspace health.\n", .{});
        }
        std.process.exit(1);
    };
}

fn mainImpl(init: std.process.Init) !void {
    // Use allocators from init struct (new Zig API)
    const allocator = init.gpa;
    const arena = init.arena.allocator();

    // Get command line arguments using arena allocator
    const args = try init.minimal.args.toSlice(arena);

    // Check for --help flag early with context awareness
    const help_system = gg.help;
    for (args[1..], 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            const context_args = args[1 .. 1 + i];

            // Determine help context from args before --help
            const help_context = if (context_args.len == 0)
                help_system.HelpContext.general
            else blk: {
                // Parse command to determine context (handle partial commands gracefully)
                const parsed_command = cli.parseCommand(context_args[0], context_args[1..]) catch |err| {
                    // If parsing fails (e.g., missing action for resource), show resource-level help
                    if (err == error.MissingAction) {
                        // Map resource to resource-level help context
                        if (std.mem.eql(u8, context_args[0], "plan")) break :blk help_system.HelpContext.plan_resource;
                        if (std.mem.eql(u8, context_args[0], "task")) break :blk help_system.HelpContext.task_resource;
                        if (std.mem.eql(u8, context_args[0], "dep")) break :blk help_system.HelpContext.dep_resource;
                    }
                    // Unknown command, show general help
                    break :blk help_system.HelpContext.general;
                };
                // Pass --help marker in arguments to indicate action-level help
                const help_marker = [_][]const u8{"--help"};
                const parsed_args = cli.ParsedArgs{
                    .command = parsed_command,
                    .arguments = &help_marker,
                    .json_output = false,
                };
                break :blk try help_system.determineContextFromArgs(parsed_args);
            };

            try help_system.displayHelp(init.io, help_context, allocator, false);
            return;
        }
    }

    // Parse command line arguments
    var parsed_args = cli.parseArgs(allocator, args) catch |err| {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(init.io, stderr_buffer[0..]);
        const stderr = &stderr_writer.interface;
        switch (err) {
            error.UnknownResource => {
                if (args.len > 1) {
                    try stderr.print("Error: Unknown resource '{s}'.\n", .{args[1]});
                } else {
                    try stderr.print("Error: No resource provided.\n", .{});
                }
                try stderr.print("\nRun 'gg help' to see all available commands.\n", .{});
                try stderr.print("Valid resources: plan, task, dep, query\n", .{});
                try stderr.print("Common shortcuts: ready, blocked, workflow, init, doctor, help\n", .{});
                std.process.exit(1);
            },
            error.UnknownAction, error.MissingAction => {
                try stderr.print("Error: {s}\n", .{@errorName(err)});
                try stderr.print("\nRun 'gg help' to see all available commands.\n", .{});
                std.process.exit(1);
            },
            else => return err,
        }
    };
    defer parsed_args.deinit(allocator);

    // Commands that don't require Storage/TaskManager (early exit for efficiency)
    switch (parsed_args.command) {
        .help => {
            try help_commands.handleHelp(init.io, allocator, parsed_args.json_output);
            return;
        },
        .workflow => {
            try workflow_commands.handleWorkflow(init.io, allocator, parsed_args.json_output);
            return;
        },
        .init => {
            try init_commands.handleInit(init.io, allocator, parsed_args.arguments, parsed_args.json_output);
            return;
        },
        else => {}, // Continue to workspace discovery and storage initialization
    }

    // Discover workspace by walking up directory tree to find .gg directory
    const workspace_root = try discoverWorkspace(init.io, allocator);
    defer allocator.free(workspace_root);
    // Assertion: Workspace root must be non-empty valid path.
    std.debug.assert(workspace_root.len > 0);

    // Build database path: <workspace_root>/.gg/tasks.db
    const database_path = try std.fs.path.join(allocator, &[_][]const u8{ workspace_root, ".gg", "tasks.db" });
    defer allocator.free(database_path);

    // Initialize Storage (RAII pattern with defer for proper cleanup)
    var storage = try gg.storage.Storage.init(allocator, database_path);
    defer storage.deinit();

    // Initialize TaskManager (RAII pattern with defer for proper cleanup)
    var task_manager = gg.task_manager.TaskManager.init(allocator, &storage);
    defer task_manager.deinit();

    // Route command to appropriate handler with Storage and TaskManager available
    switch (parsed_args.command) {
        .plan => |action| {
            switch (action) {
                .new => try plan_commands.handlePlanNew(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage),
                .show => try plan_commands.handlePlanShow(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage),
                .ls => try plan_commands.handlePlanList(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage),
                .update => try plan_commands.handlePlanUpdate(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage),
                .delete => try plan_commands.handlePlanDelete(init.io, parsed_args.arguments, parsed_args.json_output, &storage),
            }
        },
        .task => |action| {
            switch (action) {
                .new => try task_commands.handleTaskNew(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage, &task_manager),
                .show => try task_commands.handleTaskShow(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage),
                .ls => try task_commands.handleTaskList(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage),
                .start => try task_commands.handleTaskStart(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage),
                .complete => try task_commands.handleTaskComplete(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage),
                .update => try task_commands.handleTaskUpdate(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage),
                .delete => try task_commands.handleTaskDelete(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage),
            }
        },
        .dep => |action| {
            switch (action) {
                .add => try dep_commands.handleDepAdd(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage),
                .remove => try dep_commands.handleDepRemove(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage),
                .blockers => try dep_commands.handleDepBlockers(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage),
                .dependents => try dep_commands.handleDepDependents(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage),
            }
        },
        .ready => try ready_commands.handleQueryReady(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage),
        .blocked => try blocked_commands.handleQueryBlocked(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage),
        .ls => try list_commands.handleQueryList(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage),
        .show => {
            // Smart show: detect task vs plan by trying to parse as task ID
            if (parsed_args.arguments.len < 1) {
                return error.MissingArgument;
            }
            const id = parsed_args.arguments[0];

            _ = gg.utils.parseTaskIdFlexible(id) catch {
                try plan_commands.handlePlanShow(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage);
                return;
            };

            try task_commands.handleTaskShow(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage);
        },
        .update => {
            // Smart update: detect task vs plan by trying to parse as task ID
            if (parsed_args.arguments.len < 1) {
                return error.MissingArgument;
            }
            const id = parsed_args.arguments[0];

            _ = gg.utils.parseTaskIdFlexible(id) catch {
                try plan_commands.handlePlanUpdate(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage);
                return;
            };

            try task_commands.handleTaskUpdate(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage);
        },
        .new => {
            if (parsed_args.arguments.len < 1) return error.MissingArgument;

            const first_arg = parsed_args.arguments[0];
            std.debug.assert(first_arg.len > 0);
            std.debug.assert(first_arg.len < 200);

            if (std.mem.endsWith(u8, first_arg, ":")) {
                // Task creation
                if (first_arg.len == 1) return error.InvalidArgument;

                const plan_slug = first_arg[0 .. first_arg.len - 1];
                try gg.utils.validateKebabCase(plan_slug);

                var new_args: std.ArrayList([]const u8) = .empty;
                defer new_args.deinit(allocator);

                try new_args.append(allocator, "--plan");
                try new_args.append(allocator, plan_slug);
                for (parsed_args.arguments[1..]) |arg| {
                    try new_args.append(allocator, arg);
                }

                try task_commands.handleTaskNew(init.io, allocator, new_args.items, parsed_args.json_output, &storage, &task_manager);
            } else {
                // Plan creation
                try gg.utils.validateKebabCase(first_arg);
                try plan_commands.handlePlanNew(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage);
            }
        },
        .doctor => {
            try doctor_commands.handleDoctor(init.io, allocator, parsed_args.arguments, parsed_args.json_output, &storage);
        },
        .workflow, .help, .init => unreachable, // Already handled above
    }
}

/// Discover workspace root by walking up directory tree to find .gg directory.
/// Returns allocated path string that caller must free.
///
/// Rationale: Similar to git, we walk up from current directory looking for .gg/
/// This allows running gg commands from any subdirectory within a workspace.
/// Tiger Style: Full names, 2+ assertions, rationale comments.
pub fn discoverWorkspace(io: std.Io, allocator: std.mem.Allocator) ![]const u8 {
    // Assertions: Validate inputs (Tiger Style: 2+ per function)
    std.debug.assert(@intFromPtr(allocator.vtable) != 0);

    // Start from current working directory
    const current_dir = try std.process.getCwdAlloc(allocator);
    defer allocator.free(current_dir);

    // Walk up directory tree looking for .gg directory
    var search_path = try allocator.dupe(u8, current_dir);
    errdefer allocator.free(search_path);

    // Rationale: We use an infinite loop with explicit exit conditions for clarity.
    // Either we find .gg directory (return), reach filesystem root (error), or hit filesystem error.
    while (true) {
        // Assertion: search_path must be non-empty during iteration
        std.debug.assert(search_path.len > 0);

        // Check if .gg directory exists at this level
        const gg_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ search_path, ".gg" });
        defer allocator.free(gg_dir_path);

        // Try to access .gg directory (check if it exists and is accessible)
        std.Io.Dir.accessAbsolute(io, gg_dir_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Move to parent directory
                const parent = std.fs.path.dirname(search_path) orelse {
                    // Reached filesystem root without finding .gg
                    return error.NotAWorkspace;
                };

                // Update search_path to parent
                const parent_copy = try allocator.dupe(u8, parent);
                allocator.free(search_path);
                search_path = parent_copy;
                continue;
            } else {
                // Other error accessing .gg directory (permissions, etc.)
                return err;
            }
        };

        // Found .gg directory! Return the workspace root path
        return search_path;
    }
}
