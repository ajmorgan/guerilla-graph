const std = @import("std");

/// Resource types for resource-oriented CLI pattern
pub const Resource = enum {
    plan,
    task,
    dep,
    query,
};

/// Plan actions
pub const PlanAction = enum {
    new,
    show,
    ls,
    update,
    delete,
};

/// Task actions
pub const TaskAction = enum {
    new,
    show,
    ls,
    start,
    complete,
    update,
    delete,
};

/// Dependency actions
pub const DepAction = enum {
    add,
    remove,
    blockers,
    dependents,
};

/// Parsed command with resource-action structure
pub const ParsedCommand = union(enum) {
    // Resource-action patterns
    plan: PlanAction,
    task: TaskAction,
    dep: DepAction,

    // Direct commands (no resource prefix)
    ready,
    blocked,
    ls,
    show, // Smart show: detects task vs plan based on ID format
    update, // Smart update: detects task vs plan based on ID format
    new, // Smart new: detects plan vs task based on ':' suffix
    workflow,
    init,
    doctor,
    help,
};

/// Parsed command line arguments
pub const ParsedArgs = struct {
    command: ParsedCommand,
    arguments: []const []const u8,
    json_output: bool,

    pub fn deinit(self: *ParsedArgs, allocator: std.mem.Allocator) void {
        // Free the arguments array
        allocator.free(self.arguments);
    }
};

/// Parse command line arguments with resource-action structure
pub fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !ParsedArgs {
    // Assertions: Validate inputs
    std.debug.assert(args.len >= 1); // At least program name

    // If no command provided, default to help
    if (args.len == 1) {
        return ParsedArgs{
            .command = .help,
            .arguments = &[_][]const u8{},
            .json_output = false,
        };
    }

    // Parse command using two-level structure
    const resource_str = args[1];
    const remaining_args = args[2..];

    // Parse the command (resource-action or shortcut)
    const command = try parseCommand(resource_str, remaining_args);

    // Determine how many args were consumed by command parsing
    // Shortcuts (ready, blocked, ls as standalone commands) consume 0 args
    // Resource-action patterns (plan new, task ls, etc.) consume 1 arg (the action)
    const is_shortcut = std.mem.eql(u8, resource_str, "ready") or
        std.mem.eql(u8, resource_str, "blocked") or
        std.mem.eql(u8, resource_str, "ls") or
        std.mem.eql(u8, resource_str, "workflow") or
        std.mem.eql(u8, resource_str, "init") or
        std.mem.eql(u8, resource_str, "doctor") or
        std.mem.eql(u8, resource_str, "help") or
        std.mem.eql(u8, resource_str, "start") or
        std.mem.eql(u8, resource_str, "complete") or
        std.mem.eql(u8, resource_str, "show") or
        std.mem.eql(u8, resource_str, "update") or
        std.mem.eql(u8, resource_str, "new");

    const args_consumed: usize = if (is_shortcut) 0 else switch (command) {
        .plan, .task, .dep => 1, // Consumed the action arg
        .ready, .blocked, .ls, .show, .update, .new, .workflow, .init, .doctor, .help => 0, // No action arg
    };

    // Parse remaining arguments, filtering out flags
    var arguments_list: std.ArrayList([]const u8) = .empty;
    defer arguments_list.deinit(allocator);

    var json_output = false;
    var index: usize = 2 + args_consumed; // Start after resource and action

    while (index < args.len) : (index += 1) {
        const argument = args[index];

        // Check for --json flag
        if (std.mem.eql(u8, argument, "--json")) {
            json_output = true;
            continue;
        }

        // All other arguments are collected
        try arguments_list.append(allocator, argument);
    }

    // Copy arguments to owned slice
    const arguments = try allocator.dupe([]const u8, arguments_list.items);
    // Postcondition: Arguments array matches list length.
    std.debug.assert(arguments.len == arguments_list.items.len);

    return ParsedArgs{
        .command = command,
        .arguments = arguments,
        .json_output = json_output,
    };
}

/// Parse command with two-level resource-action structure
/// First arg is resource or shortcut, remaining args are for action parsing
pub fn parseCommand(resource_str: []const u8, remaining_args: []const []const u8) !ParsedCommand {
    // Check shortcuts first (single-word commands)
    if (std.mem.eql(u8, resource_str, "workflow")) return ParsedCommand{ .workflow = {} };
    if (std.mem.eql(u8, resource_str, "init")) return ParsedCommand{ .init = {} };
    if (std.mem.eql(u8, resource_str, "doctor")) return ParsedCommand{ .doctor = {} };
    if (std.mem.eql(u8, resource_str, "help")) return ParsedCommand{ .help = {} };

    // Task operation aliases (shortcuts for task operations)
    if (std.mem.eql(u8, resource_str, "start")) return ParsedCommand{ .task = .start };
    if (std.mem.eql(u8, resource_str, "complete")) return ParsedCommand{ .task = .complete };
    if (std.mem.eql(u8, resource_str, "show")) return ParsedCommand{ .show = {} }; // Smart show: detects task vs plan
    if (std.mem.eql(u8, resource_str, "update")) return ParsedCommand{ .update = {} }; // Smart update: detects task vs plan
    if (std.mem.eql(u8, resource_str, "new")) return ParsedCommand{ .new = {} }; // Smart new: detects plan vs task

    // Parse resource-action pattern
    if (std.mem.eql(u8, resource_str, "plan")) {
        if (remaining_args.len < 1) return error.MissingAction;
        const action = try parsePlanAction(remaining_args[0]);
        return ParsedCommand{ .plan = action };
    }

    if (std.mem.eql(u8, resource_str, "task")) {
        if (remaining_args.len < 1) return error.MissingAction;
        const action = try parseTaskAction(remaining_args[0]);
        return ParsedCommand{ .task = action };
    }

    if (std.mem.eql(u8, resource_str, "dep")) {
        if (remaining_args.len < 1) return error.MissingAction;
        const action = try parseDepAction(remaining_args[0]);
        return ParsedCommand{ .dep = action };
    }

    // Direct commands (no resource prefix)
    if (std.mem.eql(u8, resource_str, "ready")) return ParsedCommand{ .ready = {} };
    if (std.mem.eql(u8, resource_str, "blocked")) return ParsedCommand{ .blocked = {} };
    if (std.mem.eql(u8, resource_str, "ls")) return ParsedCommand{ .ls = {} };

    return error.UnknownResource;
}

/// Parse plan action from string
fn parsePlanAction(action_str: []const u8) !PlanAction {
    // Precondition: Action string must be non-empty.
    std.debug.assert(action_str.len > 0);
    if (std.mem.eql(u8, action_str, "new")) return .new;
    if (std.mem.eql(u8, action_str, "show")) return .show;
    if (std.mem.eql(u8, action_str, "ls")) return .ls;
    if (std.mem.eql(u8, action_str, "update")) return .update;
    if (std.mem.eql(u8, action_str, "delete")) return .delete;
    return error.UnknownAction;
}

/// Parse task action from string
fn parseTaskAction(action_str: []const u8) !TaskAction {
    // Precondition: Action string must be non-empty.
    std.debug.assert(action_str.len > 0);
    if (std.mem.eql(u8, action_str, "new")) return .new;
    if (std.mem.eql(u8, action_str, "show")) return .show;
    if (std.mem.eql(u8, action_str, "ls")) return .ls;
    if (std.mem.eql(u8, action_str, "start")) return .start;
    if (std.mem.eql(u8, action_str, "complete")) return .complete;
    if (std.mem.eql(u8, action_str, "update")) return .update;
    if (std.mem.eql(u8, action_str, "delete")) return .delete;
    return error.UnknownAction;
}

/// Parse dependency action from string
fn parseDepAction(action_str: []const u8) !DepAction {
    // Precondition: Action string must be non-empty.
    std.debug.assert(action_str.len > 0);
    if (std.mem.eql(u8, action_str, "add")) return .add;
    if (std.mem.eql(u8, action_str, "remove")) return .remove;
    if (std.mem.eql(u8, action_str, "blockers")) return .blockers;
    if (std.mem.eql(u8, action_str, "dependents")) return .dependents;
    return error.UnknownAction;
}
