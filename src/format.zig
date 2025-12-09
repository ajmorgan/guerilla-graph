//! Format module aggregator for Guerilla Graph CLI.
//!
//! Re-exports all formatting functions for backward compatibility.
//! This module was split into specialized modules for maintainability:
//! - format_task: Task display and JSON formatting
//! - format_plan: Plan display and JSON formatting
//! - format_system: System stats and blocker info formatting
//! - format_common: Shared utilities (timestamps, elapsed time)

const format_task = @import("format_task.zig");
const format_plan = @import("format_plan.zig");
const format_system = @import("format_system.zig");
const format_common = @import("format_common.zig");

// Re-export task formatters (text display)
pub const formatTask = format_task.formatTask;
pub const formatTaskList = format_task.formatTaskList;
pub const formatReadyTasks = format_task.formatReadyTasks;
pub const formatBlockedTasks = format_task.formatBlockedTasks;

// Re-export task formatters (JSON)
pub const formatTaskJson = format_task.formatTaskJson;
pub const formatTaskListJson = format_task.formatTaskListJson;
pub const formatReadyTasksJson = format_task.formatReadyTasksJson;
pub const formatBlockedTasksJson = format_task.formatBlockedTasksJson;

// Re-export plan formatters (text display)
pub const formatPlan = format_plan.formatPlan;
pub const formatPlanList = format_plan.formatPlanList;

// Re-export plan formatters (JSON)
pub const formatPlanJson = format_plan.formatPlanJson;
pub const formatPlanListJson = format_plan.formatPlanListJson;

// Re-export system formatters (text display)
pub const formatStats = format_system.formatStats;
pub const formatBlockerInfo = format_system.formatBlockerInfo;

// Re-export system formatters (JSON)
pub const formatStatsJson = format_system.formatStatsJson;
pub const formatBlockerInfoJson = format_system.formatBlockerInfoJson;
pub const formatHierarchicalListJson = format_system.formatHierarchicalListJson;

// Re-export common helper functions
pub const formatTimestamp = format_common.formatTimestamp;
pub const formatElapsedTime = format_common.formatElapsedTime;
