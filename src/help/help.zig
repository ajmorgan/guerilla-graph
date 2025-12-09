//! Help system coordinator for Guerilla Graph CLI.
//!
//! This module provides centralized help routing for all commands and resources.
//! It defines the HelpContext enum with all 26 command variants and coordinates
//! displaying help text based on parsed arguments.
//!
//! Architecture:
//! - HelpContext enum: Exhaustive list of all help contexts in the CLI
//! - displayHelp(): EXHAUSTIVE switch that delegates to content modules
//! - determineContextFromArgs(): Maps parsed commands to help contexts
//!
//! Usage:
//!   const context = try determineContextFromArgs(parsed_args);
//!   try displayHelp(context, allocator, json_output);

const std = @import("std");
const cli = @import("../cli.zig");

// Import help content modules
const top_level_help = @import("content/top_level.zig");
const plan_help = @import("content/plan.zig");
const task_help = @import("content/task.zig");
const dep_help = @import("content/dep.zig");
const shortcuts_help = @import("content/shortcuts.zig");
const system_help = @import("content/system.zig");

/// All possible help contexts in the system.
/// Each variant corresponds to a unique help page.
pub const HelpContext = enum {
    // General help
    general,

    // System commands
    init,
    doctor,
    workflow,

    // Plan resource and actions
    plan_resource,
    plan_new,
    plan_show,
    plan_ls,
    plan_update,
    plan_delete,

    // Task resource and actions
    task_resource,
    task_new,
    task_show,
    task_ls,
    task_start,
    task_complete,
    task_update,
    task_delete,

    // Dependency resource and actions
    dep_resource,
    dep_add,
    dep_remove,
    dep_blockers,
    dep_dependents,

    // Shortcut commands
    ready,
    blocked,
    ls,
    show,
    update,
    new,
};

/// Display help text for the given context.
/// Rationale: EXHAUSTIVE switch ensures compiler catches missing help pages.
pub fn displayHelp(context: HelpContext, allocator: std.mem.Allocator, json_output: bool) !void {
    // Rationale: Help is read-only, no storage needed
    _ = allocator;
    _ = json_output; // TODO: Phase 2 - JSON help output

    // Rationale: Get stdout writer for formatted output
    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    // Rationale: EXHAUSTIVE switch - compiler error if new context added without help
    switch (context) {
        // General help
        .general => try stdout.writeAll(top_level_help.help_text),

        // System commands
        .init => try stdout.writeAll(system_help.init_help),
        .doctor => try stdout.writeAll(system_help.doctor_help),
        .workflow => try stdout.writeAll(system_help.workflow_help),

        // Plan resource and actions
        .plan_resource => try stdout.writeAll(plan_help.resource_help),
        .plan_new => try stdout.writeAll(plan_help.action_new_help),
        .plan_show => try stdout.writeAll(plan_help.action_show_help),
        .plan_ls => try stdout.writeAll(plan_help.action_list_help),
        .plan_update => try stdout.writeAll(plan_help.action_update_help),
        .plan_delete => try stdout.writeAll(plan_help.action_delete_help),

        // Task resource and actions
        .task_resource => try stdout.writeAll(task_help.resource_help),
        .task_new => try stdout.writeAll(task_help.action_new_help),
        .task_show => try stdout.writeAll(task_help.action_show_help),
        .task_ls => try stdout.writeAll(task_help.action_list_help),
        .task_start => try stdout.writeAll(task_help.action_start_help),
        .task_complete => try stdout.writeAll(task_help.action_complete_help),
        .task_update => try stdout.writeAll(task_help.action_update_help),
        .task_delete => try stdout.writeAll(task_help.action_delete_help),

        // Dependency resource and actions
        .dep_resource => try stdout.writeAll(dep_help.resource_help),
        .dep_add => try stdout.writeAll(dep_help.action_add_help),
        .dep_remove => try stdout.writeAll(dep_help.action_remove_help),
        .dep_blockers => try stdout.writeAll(dep_help.action_blockers_help),
        .dep_dependents => try stdout.writeAll(dep_help.action_dependents_help),

        // Shortcut commands
        .ready => try stdout.writeAll(shortcuts_help.ready_help),
        .blocked => try stdout.writeAll(shortcuts_help.blocked_help),
        .ls => try stdout.writeAll(shortcuts_help.ls_help),
        .show => try stdout.writeAll(shortcuts_help.show_help),
        .update => try stdout.writeAll(shortcuts_help.update_help),
        .new => try stdout.writeAll(shortcuts_help.new_help),
    }

    try stdout.flush();
}

/// Determine help context from parsed arguments.
/// Rationale: Separate function for testability and clarity.
/// Returns the appropriate HelpContext based on command structure.
pub fn determineContextFromArgs(parsed_args: cli.ParsedArgs) !HelpContext {
    // Rationale: Assertions validate expected help invocation patterns
    std.debug.assert(parsed_args.arguments.len <= 1); // At most one --help argument expected

    // Rationale: Check if --help was requested for a specific action
    const is_help_for_action = parsed_args.arguments.len == 1 and
        std.mem.eql(u8, parsed_args.arguments[0], "--help");

    // Rationale: Map command to help context
    return switch (parsed_args.command) {
        .help => .general,
        .init => if (is_help_for_action) .init else .general,
        .doctor => if (is_help_for_action) .doctor else .general,
        .workflow => if (is_help_for_action) .workflow else .general,

        // Plan resource
        .plan => |action| switch (action) {
            .new => if (is_help_for_action) .plan_new else .plan_resource,
            .show => if (is_help_for_action) .plan_show else .plan_resource,
            .ls => if (is_help_for_action) .plan_ls else .plan_resource,
            .update => if (is_help_for_action) .plan_update else .plan_resource,
            .delete => if (is_help_for_action) .plan_delete else .plan_resource,
        },

        // Task resource (includes start/complete shortcuts which parse as .task)
        .task => |action| switch (action) {
            .new => if (is_help_for_action) .task_new else .task_resource,
            .show => if (is_help_for_action) .task_show else .task_resource,
            .ls => if (is_help_for_action) .task_ls else .task_resource,
            // start and complete shortcuts map to their own help, not task resource
            .start => .task_start,
            .complete => .task_complete,
            .update => if (is_help_for_action) .task_update else .task_resource,
            .delete => if (is_help_for_action) .task_delete else .task_resource,
        },

        // Dependency resource
        .dep => |action| switch (action) {
            .add => if (is_help_for_action) .dep_add else .dep_resource,
            .remove => if (is_help_for_action) .dep_remove else .dep_resource,
            .blockers => if (is_help_for_action) .dep_blockers else .dep_resource,
            .dependents => if (is_help_for_action) .dep_dependents else .dep_resource,
        },

        // Shortcut commands
        .ready => if (is_help_for_action) .ready else .general,
        .blocked => if (is_help_for_action) .blocked else .general,
        .ls => if (is_help_for_action) .ls else .general,

        // Smart commands
        .show => if (is_help_for_action) .show else .general,
        .update => if (is_help_for_action) .update else .general,
        .new => if (is_help_for_action) .new else .general,
    };
}
