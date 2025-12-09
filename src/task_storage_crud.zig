//! Task CRUD operations for Guerilla Graph.
//!
//! This module handles task Create, Read, Update, Delete operations:
//! - createTask: Create new task with per-plan numbering
//! - listTasks: Query tasks with optional filters
//! - getTask: Fetch single task by internal ID
//! - getTaskByPlanAndNumber: Resolve formatted ID to internal ID
//! - updateTask: Update task fields (title, description, status)
//! - deleteTask: Remove task if no dependents
//!
//! Uses SQL Executor to eliminate SQLite C API boilerplate.

const std = @import("std");
const c_imports = @import("c_imports.zig");
const c = c_imports.c;
const storage = @import("storage.zig");
const types = @import("types.zig");
const sql_executor = @import("sql_executor.zig");

/// Intermediate row struct for SQL executor extraction.
/// Status is stored as string because executor doesn't support custom fromString.
/// Rationale: Module-level struct enables sharing across functions.
const TaskRow = struct {
    id: u32,
    plan_id: u32,
    slug: []const u8,
    plan_task_number: u32,
    title: []const u8,
    description: []const u8,
    status: []const u8, // Raw status string, converted to enum later
    created_at: i64,
    updated_at: i64,
    started_at: ?i64,
    completed_at: ?i64,

    pub fn deinit(row: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(row.slug);
        allocator.free(row.title);
        allocator.free(row.description);
        allocator.free(row.status);
    }
};

/// Convert TaskRow to Task with proper memory allocation.
/// Rationale: Extracted from listTasks to reduce function length and enable reuse.
fn listTasks_rowToTask(allocator: std.mem.Allocator, row: TaskRow) !types.Task {
    // Assertions: Validate row data
    std.debug.assert(row.id > 0);
    std.debug.assert(row.plan_id > 0);
    std.debug.assert(row.slug.len > 0);
    std.debug.assert(row.plan_task_number > 0);

    return types.Task{
        .id = row.id,
        .plan_id = row.plan_id,
        .plan_slug = try allocator.dupe(u8, row.slug),
        .plan_task_number = row.plan_task_number,
        .title = try allocator.dupe(u8, row.title),
        .description = try allocator.dupe(u8, row.description),
        .status = try types.TaskStatus.fromString(row.status),
        .created_at = row.created_at,
        .updated_at = row.updated_at,
        .started_at = row.started_at,
        .completed_at = row.completed_at,
    };
}

/// Get timestamp values for status update.
/// Rationale: Extracted to reduce updateTask length and centralize timestamp logic.
/// Note: Currently unused, kept for potential future refactoring.
fn updateTask_getStatusTimestamps(
    status_string: ?[]const u8,
    current_timestamp: i64,
) struct { started_at: ?i64, completed_at: ?i64 } {
    // Assertion: timestamp should be reasonable (after 2020)
    std.debug.assert(current_timestamp > 1577836800);

    if (status_string) |s| {
        const is_in_progress = std.mem.eql(u8, s, "in_progress");
        const is_completed = std.mem.eql(u8, s, "completed");

        return .{
            .started_at = if (is_in_progress or is_completed) current_timestamp else null,
            .completed_at = if (is_completed) current_timestamp else null,
        };
    }
    return .{ .started_at = null, .completed_at = null };
}

/// CrudOperations struct wraps executor and allocator for CRUD methods.
pub const CrudOperations = struct {
    executor: sql_executor.Executor,
    allocator: std.mem.Allocator,

    pub fn init(executor: sql_executor.Executor, allocator: std.mem.Allocator) CrudOperations {
        return CrudOperations{
            .executor = executor,
            .allocator = allocator,
        };
    }

    /// Create a new task under a plan with per-plan numbering.
    /// Returns struct with both the internal task ID and the plan-relative task number.
    ///
    /// Rationale: Implements atomic counter increment + task insertion.
    /// Uses UPDATE then INSERT with SELECT to atomically assign plan_task_number.
    pub fn createTask(
        self: *CrudOperations,
        plan_slug: []const u8, // Required: plan slug (NOT NULL)
        title: []const u8,
        description: []const u8,
    ) !types.CreateTaskResult {
        // Assertions: Validate inputs (Tiger Style: 2+ per function)
        std.debug.assert(plan_slug.len > 0);
        std.debug.assert(plan_slug.len <= types.MAX_PLAN_ID_LENGTH);
        std.debug.assert(title.len <= 500); // Title can be empty (optional)
        // Note: No max description length - database supports large TEXT fields

        // Step 1: Resolve slug to plan_id and verify plan exists
        const PlanIdRow = struct {
            id: u32,
        };

        const resolve_plan_sql = "SELECT id FROM plans WHERE slug = ?";
        const plan_row = try self.executor.queryOne(PlanIdRow, self.allocator, resolve_plan_sql, .{plan_slug}) orelse return storage.SqliteError.InvalidData;
        const plan_id = plan_row.id;

        // Assertion: Plan ID is valid
        std.debug.assert(plan_id > 0);

        // Step 2: Atomically increment plan's task counter
        const update_counter_sql = "UPDATE plans SET task_counter = task_counter + 1 WHERE id = ?";
        try self.executor.exec(update_counter_sql, .{plan_id});

        // Rationale: Verify counter was incremented (plan must exist)
        const changed_rows = c.sqlite3_changes(self.executor.database);
        if (changed_rows == 0) {
            return storage.SqliteError.InvalidData; // Plan disappeared
        }
        std.debug.assert(changed_rows == 1);

        // Step 3: Get current timestamp for created_at and updated_at
        const utils = @import("utils.zig");
        const current_timestamp = utils.unixTimestamp();

        // Step 4: Insert task with current counter value
        // Rationale: Use subquery to fetch task_counter value that we just incremented.
        // This ensures we get the correct plan_task_number atomically.
        const insert_sql =
            \\INSERT INTO tasks (plan_id, plan_task_number, title, description, status, created_at, updated_at, completed_at)
            \\VALUES (?, (SELECT task_counter FROM plans WHERE id = ?), ?, ?, 'open', ?, ?, NULL)
        ;

        try self.executor.exec(insert_sql, .{ plan_id, plan_id, title, description, current_timestamp, current_timestamp });

        // Step 5: Get auto-generated task ID and plan_task_number
        const task_id = c.sqlite3_last_insert_rowid(self.executor.database);
        std.debug.assert(task_id > 0);

        // Step 6: Query back the plan_task_number we just inserted
        const TaskNumberRow = struct {
            plan_task_number: u32,
        };

        const get_number_sql = "SELECT plan_task_number FROM tasks WHERE id = ?";
        const number_row = try self.executor.queryOne(TaskNumberRow, self.allocator, get_number_sql, .{@as(u32, @intCast(task_id))}) orelse return storage.SqliteError.InvalidData;

        // Assertions: Verify values
        std.debug.assert(number_row.plan_task_number > 0);
        std.debug.assert(number_row.plan_task_number <= types.MAX_TASK_ID_NUMBER);

        return types.CreateTaskResult{
            .task_id = @intCast(task_id),
            .plan_task_number = number_row.plan_task_number,
        };
    }

    /// List tasks with optional filters for status and plan.
    /// Returns an array of tasks sorted chronologically by created_at (oldest first).
    /// Caller is responsible for freeing the returned array and its contents via Task.deinit().
    ///
    /// Filters work as follows:
    /// - status_filter is NULL: include all statuses
    /// - status_filter is not NULL: include only tasks matching that status
    /// - plan_filter is NULL: include all plans
    /// - plan_filter is not NULL: include only tasks under that plan (by slug)
    ///
    /// Rationale: Refactored to JOIN with plans table to fetch slug for display.
    /// Using NULL bind parameters with COALESCE-like logic via "? IS NULL".
    /// This allows a single prepared statement to handle all filter combinations
    /// without dynamic SQL construction.
    pub fn listTasks(
        self: *CrudOperations,
        status_filter: ?types.TaskStatus,
        plan_filter: ?[]const u8, // Plan slug for filtering
    ) ![]types.Task {
        // Assertions: Validate inputs (Tiger Style: 2+ per function)
        if (plan_filter) |plan| {
            std.debug.assert(plan.len > 0);
            std.debug.assert(plan.len <= 100); // Reasonable plan ID length limit
        }

        // Rationale: SQL query with JOIN to get plan slug and optional filters.
        // When a filter parameter is NULL, the "? IS NULL" check succeeds,
        // effectively disabling that filter.
        // ORDER BY created_at provides chronological output (oldest first).
        const sql =
            \\SELECT
            \\    t.id, t.plan_id, p.slug, t.plan_task_number, t.title, t.description,
            \\    t.status, t.created_at, t.updated_at, t.started_at, t.completed_at
            \\FROM tasks t
            \\JOIN plans p ON p.id = t.plan_id
            \\WHERE
            \\    (? IS NULL OR t.status = ?)
            \\    AND (? IS NULL OR p.slug = ?)
            \\ORDER BY t.created_at ASC
        ;

        // Rationale: Prepare bind parameters for optional filters.
        // Each filter needs two parameters: one for IS NULL check, one for comparison.
        const status_string: ?[]const u8 = if (status_filter) |s| s.toString() else null;
        const params = .{ status_string, status_string, plan_filter, plan_filter };

        // Rationale: Use executor to fetch all rows (eliminates prepare/bind/step boilerplate).
        const rows = try self.executor.queryAll(TaskRow, self.allocator, sql, params);
        defer {
            for (rows) |*row| {
                row.deinit(self.allocator);
            }
            self.allocator.free(rows);
        }

        // Rationale: Convert TaskRow structs to Task structs with proper status enum.
        // Allocate tasks array and convert each row.
        var tasks = try self.allocator.alloc(types.Task, rows.len);
        var initialized_count: usize = 0;
        errdefer {
            for (tasks[0..initialized_count]) |*task| {
                task.deinit(self.allocator);
            }
            self.allocator.free(tasks);
        }

        for (rows, 0..) |row, i| {
            tasks[i] = try listTasks_rowToTask(self.allocator, row);
            initialized_count = i + 1;
        }

        return tasks;
    }

    /// Get a single task by internal ID.
    /// Returns Task if found, null if not found.
    /// Caller is responsible for freeing the returned Task via Task.deinit().
    ///
    /// Rationale: JOIN with plans table to fetch slug for formatted display.
    /// Updated to use new schema with plan_id, plan_slug, plan_task_number.
    pub fn getTask(self: *CrudOperations, task_id: u32) !?types.Task {
        // Assertions: Validate inputs (Tiger Style: 2+ per function)
        std.debug.assert(task_id > 0);

        const database = self.executor.database;

        const sql =
            \\SELECT t.id, t.plan_id, p.slug, t.plan_task_number, t.title, t.description,
            \\       t.status, t.created_at, t.updated_at, t.started_at, t.completed_at
            \\FROM tasks t
            \\JOIN plans p ON p.id = t.plan_id
            \\WHERE t.id = ?
        ;

        var statement: ?*c.sqlite3_stmt = null;
        const prepare_result = c.sqlite3_prepare_v2(database, sql, -1, &statement, null);
        if (prepare_result != c.SQLITE_OK) {
            return storage.SqliteError.PrepareStatementFailed;
        }
        defer _ = c.sqlite3_finalize(statement);

        try storage.bindInt(statement.?, 1, task_id);

        const step_result = c.sqlite3_step(statement.?);
        if (step_result == c.SQLITE_DONE) {
            // No row found
            return null;
        }

        if (step_result != c.SQLITE_ROW) {
            return storage.SqliteError.StepFailed;
        }

        // Extract task data from row
        const id = @as(u32, @intCast(c.sqlite3_column_int(statement.?, 0)));
        const plan_id = @as(u32, @intCast(c.sqlite3_column_int(statement.?, 1)));

        const slug_span = std.mem.span(c.sqlite3_column_text(statement.?, 2));
        const plan_slug = try self.allocator.dupe(u8, slug_span);
        errdefer self.allocator.free(plan_slug);

        const plan_task_number = @as(u32, @intCast(c.sqlite3_column_int(statement.?, 3)));

        const title_span = std.mem.span(c.sqlite3_column_text(statement.?, 4));
        const description_span = std.mem.span(c.sqlite3_column_text(statement.?, 5));
        const status_string = std.mem.span(c.sqlite3_column_text(statement.?, 6));

        const title = try self.allocator.dupe(u8, title_span);
        errdefer {
            self.allocator.free(title);
            self.allocator.free(plan_slug);
        }

        const description = try self.allocator.dupe(u8, description_span);
        errdefer {
            self.allocator.free(description);
            self.allocator.free(title);
            self.allocator.free(plan_slug);
        }

        return types.Task{
            .id = id,
            .plan_id = plan_id,
            .plan_slug = plan_slug,
            .plan_task_number = plan_task_number,
            .title = title,
            .description = description,
            .status = try types.TaskStatus.fromString(status_string),
            .created_at = c.sqlite3_column_int64(statement.?, 7),
            .updated_at = c.sqlite3_column_int64(statement.?, 8),
            .started_at = if (c.sqlite3_column_type(statement.?, 9) == c.SQLITE_NULL)
                null
            else
                c.sqlite3_column_int64(statement.?, 9),
            .completed_at = if (c.sqlite3_column_type(statement.?, 10) == c.SQLITE_NULL)
                null
            else
                c.sqlite3_column_int64(statement.?, 10),
        };
    }

    /// Get a task's internal ID by plan slug and task number.
    /// Lookup task by user-facing formatted ID (slug:number).
    /// Returns internal task ID or null if not found.
    ///
    /// Rationale: This enables slug:number lookup for CLI commands.
    /// Example: "auth:001" resolves to internal task ID.
    pub fn getTaskByPlanAndNumber(self: *CrudOperations, slug: []const u8, number: u32) !?u32 {
        // Assertions: Validate inputs (Tiger Style: 2+ per function)
        std.debug.assert(slug.len > 0);
        std.debug.assert(slug.len <= types.MAX_PLAN_ID_LENGTH);
        std.debug.assert(number > 0);
        std.debug.assert(number <= types.MAX_TASK_ID_NUMBER);

        const sql =
            \\SELECT t.id FROM tasks t
            \\JOIN plans p ON p.id = t.plan_id
            \\WHERE p.slug = ? AND t.plan_task_number = ?
        ;

        const IdRow = struct {
            id: u32,
        };

        const result = try self.executor.queryOne(IdRow, self.allocator, sql, .{ slug, number });
        if (result) |row| {
            std.debug.assert(row.id > 0);
            return row.id;
        } else {
            return null;
        }
    }

    /// Update task fields. All parameters except task_id are optional.
    /// Only provided fields (non-null) will be updated.
    /// Always updates updated_at timestamp regardless of which fields changed.
    ///
    /// Rationale: Refactored to use SQL executor pattern and helper for timestamp logic.
    /// Uses static SQL strings for each field combination to leverage executor pattern.
    pub fn updateTask(
        self: *CrudOperations,
        task_id: u32,
        title: ?[]const u8,
        description: ?[]const u8,
        status: ?types.TaskStatus,
    ) !void {
        // Assertions: Validate inputs (Tiger Style: 2+ per function)
        std.debug.assert(task_id > 0);
        std.debug.assert(title != null or description != null or status != null); // At least one field to update

        // Rationale: At least one field must be provided for update to be meaningful.
        if (title == null and description == null and status == null) {
            return storage.SqliteError.InvalidInput;
        }

        const utils = @import("utils.zig");
        const current_timestamp = utils.unixTimestamp();
        const status_string: ?[]const u8 = if (status) |s| s.toString() else null;

        // Rationale: 7 cases based on field combinations (title, description, status).
        // Cases with status updates use helper to compute timestamp values.
        if (title != null and description != null and status_string != null) {
            const sql =
                \\UPDATE tasks SET title = ?, description = ?, status = ?,
                \\  started_at = CASE WHEN ? != 'open' AND started_at IS NULL THEN ? ELSE started_at END,
                \\  completed_at = CASE WHEN ? = 'completed' THEN ? ELSE NULL END, updated_at = ?
                \\WHERE id = ?
            ;
            try self.executor.exec(sql, .{ title.?, description.?, status_string.?, status_string.?, current_timestamp, status_string.?, current_timestamp, current_timestamp, task_id });
        } else if (title != null and description != null) {
            const sql = "UPDATE tasks SET title = ?, description = ?, updated_at = ? WHERE id = ?";
            try self.executor.exec(sql, .{ title.?, description.?, current_timestamp, task_id });
        } else if (title != null and status_string != null) {
            const sql =
                \\UPDATE tasks SET title = ?, status = ?,
                \\  started_at = CASE WHEN ? != 'open' AND started_at IS NULL THEN ? ELSE started_at END,
                \\  completed_at = CASE WHEN ? = 'completed' THEN ? ELSE NULL END, updated_at = ?
                \\WHERE id = ?
            ;
            try self.executor.exec(sql, .{ title.?, status_string.?, status_string.?, current_timestamp, status_string.?, current_timestamp, current_timestamp, task_id });
        } else if (description != null and status_string != null) {
            const sql =
                \\UPDATE tasks SET description = ?, status = ?,
                \\  started_at = CASE WHEN ? != 'open' AND started_at IS NULL THEN ? ELSE started_at END,
                \\  completed_at = CASE WHEN ? = 'completed' THEN ? ELSE NULL END, updated_at = ?
                \\WHERE id = ?
            ;
            try self.executor.exec(sql, .{ description.?, status_string.?, status_string.?, current_timestamp, status_string.?, current_timestamp, current_timestamp, task_id });
        } else if (title) |t| {
            const sql = "UPDATE tasks SET title = ?, updated_at = ? WHERE id = ?";
            try self.executor.exec(sql, .{ t, current_timestamp, task_id });
        } else if (description) |d| {
            const sql = "UPDATE tasks SET description = ?, updated_at = ? WHERE id = ?";
            try self.executor.exec(sql, .{ d, current_timestamp, task_id });
        } else {
            const sql =
                \\UPDATE tasks SET status = ?,
                \\  started_at = CASE WHEN ? != 'open' AND started_at IS NULL THEN ? ELSE started_at END,
                \\  completed_at = CASE WHEN ? = 'completed' THEN ? ELSE NULL END, updated_at = ?
                \\WHERE id = ?
            ;
            try self.executor.exec(sql, .{ status_string.?, status_string.?, current_timestamp, status_string.?, current_timestamp, current_timestamp, task_id });
        }

        // Assertion: At least one field was updated
        std.debug.assert(title != null or description != null or status != null);
    }

    /// Delete a task by ID. Fails if task has dependent tasks that block on it.
    /// Returns error if task doesn't exist or if dependencies would be orphaned.
    ///
    /// Rationale: Refactored to use SQL executor pattern (task 056).
    /// queryOne() checks for dependents, exec() performs the delete.
    /// Multi-step operation with dependency validation before deletion.
    pub fn deleteTask(self: *CrudOperations, task_id: u32) !void {
        // Assertions: Validate inputs (Tiger Style: 2+ per function)
        std.debug.assert(task_id > 0);

        // Rationale: Check if any tasks depend on this task (this task is a blocker).
        // Deleting a task that other tasks depend on would leave those tasks with invalid blockers.
        const CountRow = struct {
            count: i64,
        };

        const check_dependents_sql = "SELECT COUNT(*) as count FROM dependencies WHERE blocks_on_id = ?";
        const count_row = try self.executor.queryOne(CountRow, self.allocator, check_dependents_sql, .{task_id}) orelse return storage.SqliteError.InvalidData;

        const dependent_count = count_row.count;
        if (dependent_count > 0) {
            return storage.SqliteError.InvalidData; // Cannot delete task with dependents
        }

        // Assertion: No dependents exist
        std.debug.assert(dependent_count == 0);

        // Rationale: Delete task. CASCADE will remove dependencies where this task depends on others.
        // This is safe because we already verified no other tasks depend on this one.
        const delete_task_sql = "DELETE FROM tasks WHERE id = ?";

        try self.executor.exec(delete_task_sql, .{task_id});

        // Rationale: Verify task existed and was deleted
        const changed_rows = c.sqlite3_changes(self.executor.database);
        if (changed_rows == 0) {
            return storage.SqliteError.InvalidData; // Task not found
        }

        // Assertion: Exactly one row was deleted
        std.debug.assert(changed_rows == 1);
    }
};
