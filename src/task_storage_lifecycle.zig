//! Task lifecycle operations for Guerilla Graph.
//!
//! Handles task state transitions and plan execution tracking:
//! - startTask: Transition from 'open' to 'in_progress'
//! - completeTask: Transition from 'in_progress' to 'completed'
//! - completeTasksBulk: Batch completion with transaction
//!
//! All operations cascade to parent plan execution timestamps.

const std = @import("std");
const c_imports = @import("c_imports.zig");
const c = c_imports.c;
const storage = @import("storage.zig");
const types = @import("types.zig");
const sql_executor = @import("sql_executor.zig");

pub const LifecycleOperations = struct {
    executor: sql_executor.Executor,
    allocator: std.mem.Allocator,

    pub fn init(executor: sql_executor.Executor, allocator: std.mem.Allocator) LifecycleOperations {
        return LifecycleOperations{
            .executor = executor,
            .allocator = allocator,
        };
    }

    /// Start a task by updating its status to in_progress and setting started_at timestamp.
    /// Also updates parent plan's execution_started_at if this is the first task in that plan to start.
    /// Only allows transition from 'open' to 'in_progress'.
    ///
    /// Rationale: Refactored to use SQL executor pattern (task 057).
    /// Multi-step transaction: UPDATE task status, query plan_id, UPDATE plan execution_started_at.
    /// Uses executor.exec() and executor.queryOne() to eliminate SQLite C API boilerplate.
    pub fn startTask(self: *LifecycleOperations, task_id: u32) !void {
        // Assertions: Validate inputs (Tiger Style: 2+ per function)
        std.debug.assert(task_id > 0);

        const utils = @import("utils.zig");
        const current_timestamp = utils.unixTimestamp();

        // Step 1: Update task status from 'open' to 'in_progress'
        // Rationale: WHERE clause enforces transition only from 'open' state.
        // This prevents re-starting a task that's already in_progress or completed.
        const update_task_sql =
            \\UPDATE tasks
            \\SET status = 'in_progress', started_at = ?, updated_at = ?
            \\WHERE id = ? AND status = 'open'
        ;

        try self.executor.exec(update_task_sql, .{ current_timestamp, current_timestamp, task_id });

        // Rationale: Verify that update affected exactly one row.
        // If 0 rows changed, task was either not found or not in 'open' status.
        const changed_rows = c.sqlite3_changes(self.executor.database);
        if (changed_rows == 0) {
            return storage.SqliteError.InvalidData; // Task not found or already started
        }

        // Assertion: Exactly one row was updated
        std.debug.assert(changed_rows == 1);

        // Step 2: Query task's plan_id so we can update plan execution tracking
        // Rationale: Need plan ID to update plans.execution_started_at.
        // All tasks have a plan_id (NOT NULL constraint).
        const PlanRow = struct {
            plan_id: u32,
        };

        const query_plan_sql = "SELECT plan_id FROM tasks WHERE id = ?";
        const plan_row = try self.executor.queryOne(PlanRow, self.allocator, query_plan_sql, .{task_id}) orelse return storage.SqliteError.InvalidData;
        const plan_id = plan_row.plan_id;

        // Assertion: Plan ID is valid
        std.debug.assert(plan_id > 0);

        // Step 3: Update plan execution_started_at if this is first task starting
        // Rationale: execution_started_at tracks when first task in plan began.
        // WHERE clause with IS NULL ensures we only set this once.
        const plan_update_sql =
            \\UPDATE plans
            \\SET execution_started_at = ?, updated_at = ?
            \\WHERE id = ? AND execution_started_at IS NULL
        ;

        try self.executor.exec(plan_update_sql, .{ current_timestamp, current_timestamp, plan_id });

        // Note: No need to verify changed_rows for plan update.
        // It's valid for 0 rows to change if execution_started_at was already set.
    }

    /// Complete a task by setting status to completed and recording completed_at timestamp.
    /// Updates task's updated_at and completed_at fields.
    /// Returns error if task does not exist or is not in 'in_progress' status.
    ///
    /// Rationale: Refactored to use SQL executor pattern (task 058).
    /// Multi-step transaction: UPDATE task status, query plan_id, UPDATE plan completion status.
    /// Uses executor.exec() and executor.queryOne() to eliminate SQLite C API boilerplate.
    pub fn completeTask(self: *LifecycleOperations, task_id: u32) !void {
        // Assertions: Validate inputs (Tiger Style: 2+ per function)
        std.debug.assert(task_id > 0);

        const utils = @import("utils.zig");
        const current_timestamp = utils.unixTimestamp();

        // Step 1: Update task status from 'in_progress' to 'completed'
        // Rationale: WHERE clause enforces transition only from 'in_progress' state.
        // This prevents completing a task that's not in_progress.
        const update_task_sql =
            \\UPDATE tasks
            \\SET status = 'completed', completed_at = ?, updated_at = ?
            \\WHERE id = ? AND status = 'in_progress'
        ;

        try self.executor.exec(update_task_sql, .{ current_timestamp, current_timestamp, task_id });

        // Rationale: Verify that update affected exactly one row.
        // If 0 rows changed, task was either not found or not in 'in_progress' status.
        const changed_rows = c.sqlite3_changes(self.executor.database);
        if (changed_rows == 0) {
            return storage.SqliteError.InvalidData; // Task not found or not in progress
        }

        // Assertion: Exactly one row was updated
        std.debug.assert(changed_rows == 1);

        // Step 2: Query task's plan_id so we can update plan completion status
        // Rationale: Need plan ID to check if all plan tasks are complete.
        // All tasks have a plan_id (NOT NULL constraint).
        const PlanRow = struct {
            plan_id: u32,
        };

        const query_plan_sql = "SELECT plan_id FROM tasks WHERE id = ?";
        const plan_row = try self.executor.queryOne(PlanRow, self.allocator, query_plan_sql, .{task_id}) orelse return storage.SqliteError.InvalidData;
        const plan_id = plan_row.plan_id;

        // Assertion: Plan ID is valid
        std.debug.assert(plan_id > 0);

        // Step 3: Update plan status to completed if all tasks are complete
        // Rationale: Uses NOT EXISTS subquery to check if all plan tasks are done.
        // WHERE clause ensures we only mark plan complete when zero incomplete tasks remain.
        const plan_update_sql =
            \\UPDATE plans
            \\SET status = 'completed', completed_at = ?, updated_at = ?
            \\WHERE id = ?
            \\  AND NOT EXISTS (
            \\      SELECT 1 FROM tasks
            \\      WHERE plan_id = plans.id
            \\        AND status != 'completed'
            \\  )
        ;

        try self.executor.exec(plan_update_sql, .{ current_timestamp, current_timestamp, plan_id });

        // Note: No need to verify changed_rows for plan update.
        // It's valid for 0 rows to change if not all tasks are complete yet.
    }

    /// Complete multiple tasks in a single transaction.
    /// All tasks must be in 'in_progress' status. If any task is not in the correct status,
    /// the entire operation fails and no tasks are updated.
    ///
    /// Rationale: Refactored to use SQL executor pattern (task 059).
    /// Bulk operations improve performance when completing many tasks at once.
    /// Transaction ensures atomicity - either all tasks complete or none do.
    /// Uses executor.exec() in loop to eliminate prepare/bind/step/finalize boilerplate.
    pub fn completeTasksBulk(self: *LifecycleOperations, task_ids: []const u32) !void {
        // Assertions: Validate inputs (Tiger Style: 2+ per function)
        std.debug.assert(task_ids.len > 0);
        // Task limit: 1000 tasks per bulk operation.
        // Rationale: Prevents memory exhaustion and ensures reasonable transaction size.
        // At ~1KB per task update overhead, 1000 tasks = ~1MB transaction log.
        std.debug.assert(task_ids.len <= 1000);

        // Rationale: Get current timestamp once for all tasks
        const utils = @import("utils.zig");
        const current_timestamp = utils.unixTimestamp();

        // Rationale: Begin explicit transaction for atomicity.
        // Using executor methods for consistency with other storage modules.
        try self.executor.beginTransaction();
        errdefer self.executor.rollback();

        // Rationale: Update each task individually within the transaction.
        // Could use IN clause, but this gives better error reporting for specific task failures.
        // Uses executor.exec() to eliminate prepare/bind/step/finalize boilerplate.
        const update_sql =
            \\UPDATE tasks
            \\SET status = 'completed', completed_at = ?, updated_at = ?
            \\WHERE id = ? AND status = 'in_progress'
        ;

        for (task_ids) |task_id| {
            // Assertion: Task ID is valid
            std.debug.assert(task_id > 0);

            // Rationale: Execute UPDATE statement with executor.exec() for this task
            try self.executor.exec(update_sql, .{ current_timestamp, current_timestamp, task_id });

            // Rationale: Verify each task was updated
            const changed_rows = c.sqlite3_changes(self.executor.database);
            if (changed_rows == 0) {
                return storage.SqliteError.InvalidData; // Task not found or wrong status
            }
            std.debug.assert(changed_rows == 1);
        }

        // Rationale: Commit transaction if all updates succeeded.
        // Using executor method for consistency with other storage modules.
        try self.executor.commit();
    }
};
