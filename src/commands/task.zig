//! Task command aggregator for Guerilla Graph CLI.
//!
//! Re-exports all task command handlers for backward compatibility.
//! This file was converted from a monolithic 987-line file to a thin
//! aggregator after extracting 7 command files (tiger-refactor tasks 004-010).

const task_new = @import("task_new.zig");
const task_start = @import("task_start.zig");
const task_complete = @import("task_complete.zig");
const task_show = @import("task_show.zig");
const task_update = @import("task_update.zig");
const task_delete = @import("task_delete.zig");
const task_list = @import("task_list.zig");

// Re-export command handlers (used by main.zig)
pub const handleTaskNew = task_new.handleTaskNew;
pub const handleTaskStart = task_start.handleTaskStart;
pub const handleTaskComplete = task_complete.handleTaskComplete;
pub const handleTaskShow = task_show.handleTaskShow;
pub const handleTaskUpdate = task_update.handleTaskUpdate;
pub const handleTaskDelete = task_delete.handleTaskDelete;
pub const handleTaskList = task_list.handleTaskList;

// Re-export parsing functions (used by tests and other modules)
pub const parseCreateArgs = task_new.parseCreateArgs;
pub const parseUpdateArgs = task_update.parseUpdateArgs;
pub const parseListArgs = task_list.parseListArgs;

// Re-export error type (all command files define this, use task_new as canonical source)
pub const CommandError = task_new.CommandError;
