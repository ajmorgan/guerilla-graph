//! Core data structures for Guerilla Graph task dependency system.
//!
//! This module defines all types used across the system:
//! - TaskStatus: Enum for task states
//! - Plan, Task: Core data structures
//! - PlanSummary: Aggregate plan information
//! - BlockerInfo: Transitive dependency information
//! - HealthReport, SystemStats: Diagnostic types
//!
//! Tiger Style: All types use full names (no abbreviations),
//! include deinit() for memory safety, and have test coverage.

const std = @import("std");

// Rationale: System-wide limits as named constants (Tiger Style: no magic numbers).
// These values balance usability with safety constraints.

/// Maximum length for plan IDs (e.g., "auth", "payments").
/// Rationale: Kebab-case identifiers rarely exceed 50 chars; 100 provides headroom.
pub const MAX_PLAN_ID_LENGTH: usize = 100;

/// Maximum length for task titles.
/// Rationale: GitHub issue titles max at 256; 500 allows descriptive titles.
pub const MAX_TITLE_LENGTH: usize = 500;

/// Maximum task ID number within a plan (plan:001 to plan:999).
/// Rationale: 999 tasks per plan balances human readability with scale.
pub const MAX_TASK_ID_NUMBER: u32 = 999;

/// Maximum number of task IDs in bulk operations (e.g., bulk complete).
/// Rationale: Prevents accidentally completing thousands of tasks; use scripts for larger batches.
pub const MAX_BULK_TASK_IDS: usize = 100;

/// Maximum dependency chain depth (prevents cycles, stack overflow).
/// Rationale: Real projects rarely exceed 10-20 levels; 100 is safety margin.
pub const MAX_DEPENDENCY_DEPTH: u32 = 100;

/// Reasonable maximum number of plans in a workspace.
/// Rationale: Sanity check for queries; most projects have 10-50 plans.
pub const REASONABLE_MAX_PLANS: usize = 1000;

/// TaskIdInput: Represents either a numeric internal ID or a plan:number formatted ID
/// This union supports flexible task identification for backwards compatibility.
pub const TaskIdInput = union(enum) {
    internal_id: u32,
    plan_task: struct { slug: []const u8, number: u32 },
};

/// CreateTaskResult: Return type for createTask operations
/// Rationale: Shared type between task_storage and task_storage_crud to avoid
/// anonymous struct type mismatches during delegation.
pub const CreateTaskResult = struct {
    task_id: u32,
    plan_task_number: u32,
};

/// Task status: open, in_progress, or completed
pub const TaskStatus = enum {
    open,
    in_progress,
    completed,

    /// Convert TaskStatus enum to string
    pub fn toString(self: TaskStatus) []const u8 {
        return switch (self) {
            .open => "open",
            .in_progress => "in_progress",
            .completed => "completed",
        };
    }

    /// Convert string to TaskStatus enum.
    /// Valid status strings: "open", "in_progress", "completed".
    ///
    /// Returns error.InvalidTaskStatus if the input string does not match
    /// any of the valid status values.
    pub fn fromString(input: []const u8) !TaskStatus {
        // Assertions: Input validation (Tiger Style: 2+ per function)
        std.debug.assert(input.len > 0);
        std.debug.assert(input.len < 100); // Reasonable status string length

        if (std.mem.eql(u8, input, "open")) return .open;
        if (std.mem.eql(u8, input, "in_progress")) return .in_progress;
        if (std.mem.eql(u8, input, "completed")) return .completed;
        return error.InvalidTaskStatus;
    }
};

/// Plan: Top-level organizational unit (kebab-case ID)
pub const Plan = struct {
    id: u32, // Numeric ID from AUTOINCREMENT
    slug: []const u8, // Kebab-case: "auth", "tech-debt"
    task_counter: u32, // Next task number for this plan
    title: []const u8,
    description: []const u8,
    status: TaskStatus, // open, in_progress, or completed
    created_at: i64,
    updated_at: i64,
    execution_started_at: ?i64, // When first task started (actual work begins, null if never started)
    completed_at: ?i64, // When all tasks completed (null if not complete)

    /// Free all allocated memory for this plan
    /// Rationale: Ensures no memory leaks when plans are no longer needed.
    /// Caller is responsible for ensuring plan is not used after deinit.
    pub fn deinit(self: *Plan, allocator: std.mem.Allocator) void {
        // Assertions: Validate state before cleanup
        std.debug.assert(self.id > 0);
        std.debug.assert(self.slug.len > 0);
        // Note: title can be empty (optional), so no length assertion

        allocator.free(self.slug);
        allocator.free(self.title);
        allocator.free(self.description);
        // No free for status, execution_started_at, completed_at - all value types
    }
};

/// Task: Work item under a plan (format: "plan:NNN")
pub const Task = struct {
    id: u32, // Numeric ID from AUTOINCREMENT
    plan_id: u32, // Foreign key to plans table (NOT NULL)
    plan_slug: []const u8, // Plan slug for display (e.g., "auth")
    plan_task_number: u32, // Task number within plan (e.g., 1 for "auth:001")
    title: []const u8,
    description: []const u8,
    status: TaskStatus,
    created_at: i64,
    updated_at: i64,
    started_at: ?i64,
    completed_at: ?i64,

    /// Free all allocated memory for this task
    /// Rationale: Ensures no memory leaks when tasks are no longer needed.
    /// Caller is responsible for ensuring task is not used after deinit.
    pub fn deinit(self: *Task, allocator: std.mem.Allocator) void {
        // Assertions: Validate state before cleanup
        std.debug.assert(self.id > 0);
        std.debug.assert(self.plan_id > 0);
        std.debug.assert(self.plan_slug.len > 0);
        std.debug.assert(self.plan_task_number > 0);
        // Note: title can be empty (optional)

        // No free(self.id) - value type!
        allocator.free(self.plan_slug);
        allocator.free(self.title);
        allocator.free(self.description);
    }
};

/// Dependency: Represents "task_id blocks on blocks_on_id"
pub const Dependency = struct {
    task_id: u32,
    blocks_on_id: u32,
    created_at: i64,
};

/// PlanSummary: Aggregate information about a plan and its tasks
pub const PlanSummary = struct {
    id: u32, // Numeric ID from AUTOINCREMENT
    slug: []const u8, // Kebab-case: "auth", "tech-debt"
    title: []const u8,
    description: []const u8,
    status: TaskStatus, // Plan's actual status from database
    created_at: i64, // When plan was created (non-nullable, plans always have creation time)
    execution_started_at: ?i64, // When first task started (actual work begins)
    completed_at: ?i64, // When all tasks completed
    task_counter: u32, // Current task counter for this plan
    total_tasks: u32,
    completed_tasks: u32,
    in_progress_tasks: u32,
    open_tasks: u32,

    /// Free all allocated memory for this plan summary
    /// Rationale: Ensures no memory leaks when summaries are no longer needed.
    /// Caller is responsible for ensuring summary is not used after deinit.
    pub fn deinit(self: *PlanSummary, allocator: std.mem.Allocator) void {
        // Assertions: Validate state before cleanup
        std.debug.assert(self.id > 0);
        std.debug.assert(self.slug.len > 0);
        // Note: title can be empty (optional), so no length assertion

        // No free(self.id) - value type!
        allocator.free(self.slug);
        allocator.free(self.title);
        allocator.free(self.description);
        // No free for status, execution_started_at, completed_at, task_counter - all value types
    }
};

/// BlockerInfo: Information about a blocking task in dependency chain
pub const BlockerInfo = struct {
    id: u32,
    title: []const u8,
    status: TaskStatus,
    depth: u32, // How many hops from original task

    /// Free all allocated memory for this blocker info
    /// Rationale: Ensures no memory leaks when blocker info is no longer needed.
    /// Caller is responsible for ensuring blocker info is not used after deinit.
    pub fn deinit(self: *BlockerInfo, allocator: std.mem.Allocator) void {
        // Assertions: Validate state before cleanup
        std.debug.assert(self.id > 0);
        // Note: title can be empty (optional)
        std.debug.assert(self.depth > 0); // Depth 0 would be the task itself
        std.debug.assert(self.depth <= MAX_DEPENDENCY_DEPTH);

        // No free(self.id) - value type!
        allocator.free(self.title);
    }
};

/// HealthIssue: Individual health check problem
pub const HealthIssue = struct {
    check_name: []const u8,
    message: []const u8,
    details: ?[]const u8,

    /// Free all allocated memory for this health issue
    /// Rationale: Ensures no memory leaks when health issues are no longer needed.
    /// Caller is responsible for ensuring health issue is not used after deinit.
    pub fn deinit(self: *HealthIssue, allocator: std.mem.Allocator) void {
        // Assertions: Validate state before cleanup
        std.debug.assert(self.check_name.len > 0);
        std.debug.assert(self.message.len > 0);

        allocator.free(self.check_name);
        allocator.free(self.message);
        if (self.details) |details| {
            allocator.free(details);
        }
    }
};

/// HealthReport: Results from database health checks
pub const HealthReport = struct {
    errors: []HealthIssue,
    warnings: []HealthIssue,

    /// Free all allocated memory for this health report
    /// Rationale: Ensures no memory leaks when health reports are no longer needed.
    /// Must free all nested HealthIssue structs before freeing the arrays.
    pub fn deinit(self: *HealthReport, allocator: std.mem.Allocator) void {
        // Rationale: Free nested structures first to prevent leaks
        for (self.errors) |*error_item| {
            error_item.deinit(allocator);
        }
        for (self.warnings) |*warning_item| {
            warning_item.deinit(allocator);
        }

        allocator.free(self.errors);
        allocator.free(self.warnings);
    }
};

/// SystemStats: Overall system statistics for workflow command
pub const SystemStats = struct {
    total_plans: u32,
    completed_plans: u32,
    total_tasks: u32,
    open_tasks: u32,
    in_progress_tasks: u32,
    completed_tasks: u32,
    ready_tasks: u32, // Unblocked tasks
    blocked_tasks: u32,

    /// Validate system statistics consistency
    /// Rationale: Ensures stats are internally consistent before use.
    /// This helps catch database corruption or query bugs early.
    pub fn validate(self: SystemStats) bool {
        // Assertions: Validate count relationships
        std.debug.assert(self.completed_plans <= self.total_plans);
        std.debug.assert(self.completed_tasks <= self.total_tasks);
        std.debug.assert(self.in_progress_tasks <= self.total_tasks);
        std.debug.assert(self.open_tasks <= self.total_tasks);

        // Rationale: Task counts should sum to total
        const task_sum = self.open_tasks + self.in_progress_tasks + self.completed_tasks;
        if (task_sum != self.total_tasks) {
            return false;
        }

        // Rationale: Ready + blocked should not exceed open tasks
        if (self.ready_tasks + self.blocked_tasks > self.open_tasks) {
            return false;
        }

        return true;
    }
};
