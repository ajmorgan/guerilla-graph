//! Task query operations for Guerilla Graph.
//!
//! Performance-critical read-only queries for task discovery:
//! - getSystemStats: Aggregate counts by status
//! - getReadyTasks: Find unblocked tasks (status='open', no incomplete blockers)
//! - getBlockedTasks: Find blocked tasks with blocker counts
//!
//! Uses complex SQL with JOINs, CTEs, and NOT EXISTS for dependency analysis.
//! Target: <5ms for graph queries per project spec.

const std = @import("std");
const c_imports = @import("c_imports.zig");
const c = c_imports.c;
const storage = @import("storage.zig");
const types = @import("types.zig");
const sql_executor = @import("sql_executor.zig");

/// Intermediate row struct for SQL executor extraction.
/// Status is stored as string because executor doesn't support custom fromString.
/// Rationale: Shared between getReadyTasks and getBlockedTasks.
const TaskRow = struct {
    id: u32,
    plan_id: u32,
    slug: []const u8,
    plan_task_number: u32,
    title: []const u8,
    description: []const u8,
    status: []const u8,
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

/// Extended row struct for blocked tasks query (includes blocker count).
/// Rationale: getBlockedTasks needs blocker_count which getReadyTasks doesn't use.
const BlockedTaskRow = struct {
    id: u32,
    plan_id: u32,
    slug: []const u8,
    plan_task_number: u32,
    title: []const u8,
    description: []const u8,
    status: []const u8,
    created_at: i64,
    updated_at: i64,
    started_at: ?i64,
    completed_at: ?i64,
    blocker_count: u32,

    pub fn deinit(row: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(row.slug);
        allocator.free(row.title);
        allocator.free(row.description);
        allocator.free(row.status);
    }
};

/// Convert TaskRow array to Task array with proper memory allocation.
/// Rationale: Shared conversion logic for getReadyTasks and getBlockedTasks.
/// Fixes errdefer bug: tracks initialized_count to avoid cleaning up uninitialized memory.
fn convertTaskRows(allocator: std.mem.Allocator, rows: []const TaskRow) ![]types.Task {
    // Assertions: Validate inputs
    std.debug.assert(rows.len <= 1000); // Per CLAUDE.md scale guidance

    var tasks = try allocator.alloc(types.Task, rows.len);
    var initialized_count: usize = 0;

    errdefer {
        for (tasks[0..initialized_count]) |*task| {
            task.deinit(allocator);
        }
        allocator.free(tasks);
    }

    for (rows, 0..) |row, i| {
        // Assertions: Verify data integrity
        std.debug.assert(row.id > 0);
        std.debug.assert(row.plan_id > 0);
        std.debug.assert(row.slug.len > 0);
        std.debug.assert(row.plan_task_number > 0);

        tasks[i] = types.Task{
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
        initialized_count = i + 1;
    }

    return tasks;
}

/// Convert BlockedTaskRow array to Task array (ignores blocker_count).
/// Rationale: getBlockedTasks uses BlockedTaskRow but returns []Task.
fn convertBlockedTaskRows(allocator: std.mem.Allocator, rows: []const BlockedTaskRow) ![]types.Task {
    std.debug.assert(rows.len <= 1000);

    var tasks = try allocator.alloc(types.Task, rows.len);
    var initialized_count: usize = 0;

    errdefer {
        for (tasks[0..initialized_count]) |*task| {
            task.deinit(allocator);
        }
        allocator.free(tasks);
    }

    for (rows, 0..) |row, i| {
        std.debug.assert(row.id > 0);
        std.debug.assert(row.plan_id > 0);
        std.debug.assert(row.slug.len > 0);
        std.debug.assert(row.plan_task_number > 0);

        tasks[i] = types.Task{
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
        initialized_count = i + 1;
    }

    return tasks;
}

pub const QueryOperations = struct {
    executor: sql_executor.Executor,
    allocator: std.mem.Allocator,

    pub fn init(executor: sql_executor.Executor, allocator: std.mem.Allocator) QueryOperations {
        return QueryOperations{
            .executor = executor,
            .allocator = allocator,
        };
    }

    /// Get system-wide statistics: task counts by status, blocker counts.
    /// Returns a SystemStats struct with aggregated counts.
    ///
    /// Rationale: Refactored to use SQL executor pattern (task 049).
    /// Uses three separate queryOne() calls for clarity and maintainability.
    /// Each query returns a single row with aggregate counts.
    pub fn getSystemStats(self: *QueryOperations) !types.SystemStats {
        // Rationale: Use three separate queries for clarity and maintainability:
        // 1. Get plan and task counts by status (with subqueries for conditional counts)
        // 2. Get ready task count (open tasks with no incomplete dependencies)
        // 3. Get blocked task count (open tasks with incomplete dependencies)
        // This approach is more readable than a single complex query.

        // Query 1: Get plan and task counts
        // Rationale: Use subqueries for each count to keep query simple and portable.
        // A plan is "completed" if all its tasks are completed (no open/in_progress tasks).
        const CountsRow = struct {
            total_plans: u32,
            completed_plans: u32,
            total_tasks: u32,
            open_tasks: u32,
            in_progress_tasks: u32,
            completed_tasks: u32,
        };

        const counts_sql =
            \\SELECT
            \\    (SELECT COUNT(*) FROM plans) as total_plans,
            \\    (SELECT COUNT(*) FROM plans p
            \\        WHERE NOT EXISTS (
            \\            SELECT 1 FROM tasks t
            \\            WHERE t.plan_id = p.id AND t.status != 'completed'
            \\        ) AND EXISTS (
            \\            SELECT 1 FROM tasks t WHERE t.plan_id = p.id
            \\        )) as completed_plans,
            \\    (SELECT COUNT(*) FROM tasks) as total_tasks,
            \\    (SELECT COUNT(*) FROM tasks WHERE status = 'open') as open_tasks,
            \\    (SELECT COUNT(*) FROM tasks WHERE status = 'in_progress') as in_progress_tasks,
            \\    (SELECT COUNT(*) FROM tasks WHERE status = 'completed') as completed_tasks
        ;

        // Rationale: Use executor.queryOne() to eliminate SQLite C API boilerplate.
        // COUNT queries always return a row, so orelse should never happen.
        const counts = try self.executor.queryOne(CountsRow, self.allocator, counts_sql, .{}) orelse return error.InvalidData;

        // Query 2: Get ready task count
        // Rationale: Ready tasks are open and have NO incomplete dependencies.
        // This matches the getReadyTasks query but just counts instead of returning rows.
        const ReadyRow = struct {
            count: u32,
        };

        const ready_sql =
            \\SELECT COUNT(*) as count FROM tasks t
            \\WHERE t.status = 'open'
            \\  AND NOT EXISTS (
            \\      SELECT 1 FROM dependencies d
            \\      JOIN tasks blocker ON d.blocks_on_id = blocker.id
            \\      WHERE d.task_id = t.id
            \\        AND blocker.status != 'completed'
            \\  )
        ;

        const ready = try self.executor.queryOne(ReadyRow, self.allocator, ready_sql, .{}) orelse return error.InvalidData;

        // Query 3: Get blocked task count
        // Rationale: Blocked tasks are open and have at least one incomplete dependency.
        // This is the inverse of ready tasks (among open tasks).
        const BlockedRow = struct {
            count: u32,
        };

        const blocked_sql =
            \\SELECT COUNT(DISTINCT t.id) as count FROM tasks t
            \\JOIN dependencies d ON d.task_id = t.id
            \\JOIN tasks blocker ON d.blocks_on_id = blocker.id
            \\WHERE t.status = 'open'
            \\  AND blocker.status != 'completed'
        ;

        const blocked = try self.executor.queryOne(BlockedRow, self.allocator, blocked_sql, .{}) orelse return error.InvalidData;

        // Rationale: Assemble results into SystemStats struct
        const stats = types.SystemStats{
            .total_plans = counts.total_plans,
            .completed_plans = counts.completed_plans,
            .total_tasks = counts.total_tasks,
            .open_tasks = counts.open_tasks,
            .in_progress_tasks = counts.in_progress_tasks,
            .completed_tasks = counts.completed_tasks,
            .ready_tasks = ready.count,
            .blocked_tasks = blocked.count,
        };

        // Assertions: Verify stats are internally consistent (Tiger Style: 2+ per function)
        std.debug.assert(stats.completed_plans <= stats.total_plans);
        std.debug.assert(stats.completed_tasks <= stats.total_tasks);
        std.debug.assert(stats.in_progress_tasks <= stats.total_tasks);
        std.debug.assert(stats.open_tasks <= stats.total_tasks);
        std.debug.assert(stats.ready_tasks <= stats.open_tasks);
        std.debug.assert(stats.blocked_tasks <= stats.open_tasks);

        return stats;
    }


    /// Get all tasks that are ready to work on (no unmet dependencies).
    /// Returns tasks with status 'open' that have no incomplete blockers.
    /// Results are sorted by creation time (oldest first).
    /// Limit parameter controls maximum number of results (0 = unlimited).
    ///
    /// Rationale: Refactored to use SQL executor pattern (task 047).
    /// Further refactored to use convertTaskRows helper (task 005).
    /// NOT EXISTS subquery is more efficient than LEFT JOIN for this pattern.
    /// Finds tasks in 'open' status that have zero incomplete dependencies.
    /// JOIN with plans to get slug for display.
    pub fn getReadyTasks(self: *QueryOperations, limit: u32) ![]types.Task {
        // Rationale: NOT EXISTS checks for incomplete blockers.
        // Task is ready if status='open' AND no rows in dependencies point to incomplete tasks.
        // Excludes tasks that are blocked by any non-completed task.
        // JOIN with plans to fetch slug for formatted display.
        // Note: LIMIT cannot be bound as parameter, must use bufPrint for dynamic SQL.
        var sql_buffer: [1024]u8 = undefined;
        const sql = if (limit > 0)
            try std.fmt.bufPrint(&sql_buffer,
                \\SELECT
                \\    t.id, t.plan_id, p.slug, t.plan_task_number, t.title, t.description,
                \\    t.status, t.created_at, t.updated_at, t.started_at, t.completed_at
                \\FROM tasks t
                \\JOIN plans p ON p.id = t.plan_id
                \\WHERE t.status = 'open'
                \\  AND NOT EXISTS (
                \\      SELECT 1
                \\      FROM dependencies d
                \\      INNER JOIN tasks blocker ON d.blocks_on_id = blocker.id
                \\      WHERE d.task_id = t.id
                \\        AND blocker.status != 'completed'
                \\  )
                \\ORDER BY t.created_at ASC
                \\LIMIT {d}
            , .{limit})
        else
            \\SELECT
            \\    t.id, t.plan_id, p.slug, t.plan_task_number, t.title, t.description,
            \\    t.status, t.created_at, t.updated_at, t.started_at, t.completed_at
            \\FROM tasks t
            \\JOIN plans p ON p.id = t.plan_id
            \\WHERE t.status = 'open'
            \\  AND NOT EXISTS (
            \\      SELECT 1
            \\      FROM dependencies d
            \\      INNER JOIN tasks blocker ON d.blocks_on_id = blocker.id
            \\      WHERE d.task_id = t.id
            \\        AND blocker.status != 'completed'
            \\  )
            \\ORDER BY t.created_at ASC
        ;

        // Rationale: Use executor to fetch all rows (eliminates prepare/bind/step boilerplate).
        // No bind parameters needed - query is parameterless.
        const rows = try self.executor.queryAll(TaskRow, self.allocator, sql, .{});
        defer {
            for (rows) |*row| {
                row.deinit(self.allocator);
            }
            self.allocator.free(rows);
        }

        // Rationale: Use shared helper to convert rows to tasks.
        // Helper fixes errdefer bug by tracking initialized_count.
        return try convertTaskRows(self.allocator, rows);
    }

    /// Get all blocked tasks (tasks with unmet dependencies) along with their blocker counts.
    /// Returns tasks with status != 'completed' that have at least one incomplete blocker.
    /// Results are sorted by blocker count (descending), then by creation time (oldest first).
    ///
    /// Rationale: Refactored to use SQL executor pattern (task 048).
    /// Further refactored to use convertBlockedTaskRows helper (task 005).
    /// JOIN with dependencies table to find tasks that have blockers.
    /// JOIN with plans to get slug for formatted display.
    /// COUNT aggregation gives number of blockers per task for bottleneck analysis.
    pub fn getBlockedTasks(self: *QueryOperations) !storage.BlockedTasksResult {
        // Rationale: Inner join finds tasks with dependencies, filter on incomplete blockers.
        // JOIN with plans to fetch slug for formatted display.
        // GROUP BY aggregates blocker count per task.
        // HAVING ensures we only return tasks with at least one incomplete blocker.
        const sql =
            \\SELECT
            \\    t.id, t.plan_id, p.slug, t.plan_task_number, t.title, t.description, t.status,
            \\    t.created_at, t.updated_at, t.started_at, t.completed_at,
            \\    COUNT(d.blocks_on_id) as blocker_count
            \\FROM tasks t
            \\JOIN plans p ON p.id = t.plan_id
            \\INNER JOIN dependencies d ON t.id = d.task_id
            \\INNER JOIN tasks blocker ON d.blocks_on_id = blocker.id
            \\WHERE t.status != 'completed'
            \\  AND blocker.status != 'completed'
            \\GROUP BY t.id
            \\HAVING blocker_count > 0
            \\ORDER BY blocker_count DESC, t.created_at ASC
        ;

        // Rationale: Use executor to fetch all rows (eliminates prepare/bind/step boilerplate).
        // No bind parameters needed - query is parameterless.
        const rows = try self.executor.queryAll(BlockedTaskRow, self.allocator, sql, .{});
        defer {
            for (rows) |*row| {
                row.deinit(self.allocator);
            }
            self.allocator.free(rows);
        }

        // Rationale: Use shared helper to convert rows to tasks.
        // Helper fixes errdefer bug by tracking initialized_count.
        const tasks = try convertBlockedTaskRows(self.allocator, rows);
        errdefer {
            for (tasks) |*task| {
                task.deinit(self.allocator);
            }
            self.allocator.free(tasks);
        }

        // Rationale: Extract blocker counts into separate array.
        // Matches the BlockedTasksResult struct expected by callers.
        var blocker_counts = try self.allocator.alloc(u32, rows.len);
        for (rows, 0..) |row, i| {
            // Assertion: Blocked tasks must have at least one blocker
            std.debug.assert(row.blocker_count > 0);
            blocker_counts[i] = row.blocker_count;
        }

        // Assertion: Arrays are parallel (same length)
        std.debug.assert(tasks.len == blocker_counts.len);

        return storage.BlockedTasksResult{
            .tasks = tasks,
            .blocker_counts = blocker_counts,
        };
    }
};
