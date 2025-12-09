//! Dependency storage operations for Guerilla Graph.
//!
//! This module handles dependency graph operations:
//! - Adding and removing task dependencies
//! - Cycle detection to maintain DAG invariant
//! - Traversal queries (blockers, dependents)
//!
//! Uses SQL Executor to eliminate SQLite C API boilerplate.

const std = @import("std");
const c_imports = @import("c_imports.zig");
const c = c_imports.c;
const storage = @import("storage.zig");
const types = @import("types.zig");
const sql_executor = @import("sql_executor.zig");

/// Dependency storage operations.
pub const DepsStorage = struct {
    executor: sql_executor.Executor,
    allocator: std.mem.Allocator,

    /// Initialize dependency storage with executor.
    /// Rationale: Store executor by VALUE to avoid dangling pointers.
    /// When Storage.init() returns by value, pointers to its fields become invalid.
    pub fn init(executor: sql_executor.Executor, allocator: std.mem.Allocator) DepsStorage {
        const deps_storage = DepsStorage{
            .executor = executor,
            .allocator = allocator,
        };
        std.debug.assert(@intFromPtr(deps_storage.executor.database) != 0);

        return deps_storage;
    }

    /// Detect if adding a dependency would create a cycle in the dependency graph.
    /// Uses recursive CTE to check if blocks_on_id is reachable from task_id through dependencies.
    /// If blocks_on_id can be reached from task_id, then task_id → blocks_on_id would create a cycle.
    ///
    /// Rationale: Checks for cycles BEFORE inserting the dependency. This uses a recursive
    /// CTE (Common Table Expression) to traverse the dependency graph up to 100 levels deep.
    /// If we find task_id in the transitive blockers of blocks_on_id, then adding this
    /// dependency would create a cycle. See PLAN.md Section 5.1 query 3.4.
    pub fn detectCycle(self: *DepsStorage, task_id: u32, blocks_on_id: u32) !bool {
        // Assertions: Validate inputs (Tiger Style: 2+ per function)
        std.debug.assert(@intFromPtr(self.executor.database) != 0);
        std.debug.assert(task_id > 0);
        std.debug.assert(blocks_on_id > 0);
        std.debug.assert(task_id != blocks_on_id); // No self-loops

        // Rationale: Recursive CTE to find all tasks transitively blocked by blocks_on_id.
        // Start from blocks_on_id and follow all dependency chains backwards (following
        // blocks_on_id links). If we encounter task_id, then adding task_id → blocks_on_id
        // would create a cycle (task_id → blocks_on_id → ... → task_id).
        const cycle_detection_sql =
            \\WITH RECURSIVE dep_chain(task_id, depth) AS (
            \\    SELECT ? as task_id, 0 as depth
            \\
            \\    UNION ALL
            \\
            \\    SELECT d.blocks_on_id, depth + 1
            \\    FROM dep_chain dc
            \\    JOIN dependencies d ON dc.task_id = d.task_id
            \\    WHERE depth < 100
            \\)
            \\SELECT COUNT(*) as cycle_count
            \\FROM dep_chain
            \\WHERE task_id = ?
        ;

        // Rationale: Define result struct for cycle count query.
        // COUNT(*) returns the number of times task_id appears in the dependency chain.
        // If count > 0, a cycle would be created.
        const CycleRow = struct {
            cycle_count: i64,
        };

        // Rationale: Use executor.queryOne() to execute recursive CTE and extract result.
        // Returns null only if query fails to return a row (which shouldn't happen for COUNT).
        // Tiger Style: Use orelse to handle unexpected null (defensive programming).
        const row = try self.executor.queryOne(CycleRow, self.allocator, cycle_detection_sql, .{ blocks_on_id, task_id }) orelse return false;

        // Assertion: COUNT result is non-negative (Tiger Style: verify invariants)
        std.debug.assert(row.cycle_count >= 0);

        return row.cycle_count > 0;
    }

    /// Add a dependency: task_id blocks on blocks_on_id.
    /// Validates both tasks exist and checks for cycles before inserting.
    ///
    /// Rationale: Uses transaction to ensure atomicity. Steps:
    /// 1. Verify both task_id and blocks_on_id exist in tasks table
    /// 2. Call detectCycle to check for cycles
    /// 3. If no cycle, INSERT INTO dependencies
    /// 4. Update task timestamp to record the modification
    /// Returns CycleDetected error if a cycle would be created.
    /// Refactored to use executor.exec() and executor.queryOne() to eliminate C API boilerplate.
    pub fn addDependency(self: *DepsStorage, task_id: u32, blocks_on_id: u32) !void {
        // Assertions: Validate inputs (Tiger Style: 2+ per function)
        std.debug.assert(@intFromPtr(self.executor.database) != 0);
        std.debug.assert(task_id > 0);
        std.debug.assert(blocks_on_id > 0);
        std.debug.assert(task_id != blocks_on_id); // No self-loops

        // Rationale: Start transaction to ensure atomicity of validation and insertion.
        // If any step fails, entire operation is rolled back.
        try self.executor.beginTransaction();
        errdefer self.executor.rollback();

        // Rationale: Verify both tasks exist before creating dependency.
        // Using a single query with COUNT ensures both exist atomically.
        // HAVING clause ensures COUNT(*) = 2, query returns no rows if tasks missing.
        const check_tasks_sql = "SELECT COUNT(*) as count FROM tasks WHERE id IN (?, ?) HAVING COUNT(*) = 2";

        // Rationale: Define result struct for task existence check.
        // COUNT(*) returns the number of matching tasks (must be 2 for both to exist).
        const TaskCountRow = struct {
            count: i64,
        };

        // Rationale: Use executor.queryOne() to check task existence.
        // Returns null if HAVING clause fails (one or both tasks don't exist).
        const row = try self.executor.queryOne(TaskCountRow, self.allocator, check_tasks_sql, .{ task_id, blocks_on_id });
        if (row == null) {
            return storage.SqliteError.InvalidData; // One or both tasks don't exist
        }

        // Assertion: Both tasks exist (count == 2)
        std.debug.assert(row.?.count == 2);

        // Rationale: Detect cycles before insertion. Must happen WITHIN transaction
        // to prevent race conditions in concurrent scenarios.
        const cycle_exists = try self.detectCycle(task_id, blocks_on_id);
        if (cycle_exists) {
            return storage.SqliteError.CycleDetected;
        }

        // Assertion: No cycle detected, safe to insert
        std.debug.assert(!cycle_exists);

        // Rationale: Get current timestamp for created_at and updated_at.
        const utils = @import("utils.zig");
        const current_timestamp = utils.unixTimestamp();

        // Rationale: Insert dependency row using executor.exec().
        // PRIMARY KEY constraint (task_id, blocks_on_id) prevents duplicates.
        const insert_dep_sql = "INSERT INTO dependencies (task_id, blocks_on_id, created_at) VALUES (?, ?, ?)";
        try self.executor.exec(insert_dep_sql, .{ task_id, blocks_on_id, current_timestamp });

        // Rationale: Update the task's updated_at timestamp to record modification.
        // Uses executor.exec() to eliminate C API boilerplate.
        const update_sql = "UPDATE tasks SET updated_at = ? WHERE id = ?";
        try self.executor.exec(update_sql, .{ current_timestamp, task_id });

        // Rationale: Commit transaction to make all changes permanent.
        try self.executor.commit();

        // Assertion: Dependency added and committed successfully
        std.debug.assert(@intFromPtr(self.executor.database) != 0);
    }

    /// Remove a dependency between two tasks.
    /// Validates dependency exists before deletion.
    ///
    /// Rationale: Uses transaction to ensure atomicity of validation and deletion.
    /// Updates task timestamp to record the modification.
    /// Refactored to use executor.exec() and executor.queryOne() to eliminate C API boilerplate.
    pub fn removeDependency(self: *DepsStorage, task_id: u32, blocks_on_id: u32) !void {
        // Assertions: Validate inputs (Tiger Style: 2+ per function)
        std.debug.assert(@intFromPtr(self.executor.database) != 0);
        std.debug.assert(task_id > 0);
        std.debug.assert(blocks_on_id > 0);
        std.debug.assert(task_id != blocks_on_id); // No self-loops

        // Rationale: Start transaction to ensure atomicity of validation and deletion.
        // If any step fails, entire operation is rolled back.
        try self.executor.beginTransaction();
        errdefer self.executor.rollback();

        // Rationale: Verify dependency exists before attempting deletion.
        // This provides a clear error signal for non-existent dependencies.
        // Using COUNT(*) to check existence is fast and atomic.
        const check_dependency_sql = "SELECT COUNT(*) as count FROM dependencies WHERE task_id = ? AND blocks_on_id = ?";

        // Rationale: Define result struct for dependency existence check.
        // COUNT(*) returns the number of matching dependencies (must be 1 to exist).
        const DependencyCountRow = struct {
            count: i64,
        };

        // Rationale: Use executor.queryOne() to check dependency existence.
        // Returns null if no rows match (dependency doesn't exist).
        const row = try self.executor.queryOne(DependencyCountRow, self.allocator, check_dependency_sql, .{ task_id, blocks_on_id });
        if (row == null or row.?.count == 0) {
            return storage.SqliteError.InvalidData; // Dependency not found
        }

        // Assertion: Dependency exists (count == 1)
        std.debug.assert(row.?.count == 1);

        // Rationale: Get current timestamp for updated_at field.
        // Using utils.unixTimestamp() for consistency with other timestamp handling.
        const utils = @import("utils.zig");
        const current_timestamp = utils.unixTimestamp();

        // Rationale: Delete dependency row with exact match on both columns using executor.exec().
        // PRIMARY KEY is (task_id, blocks_on_id) so this uniquely identifies the row.
        const delete_dependency_sql = "DELETE FROM dependencies WHERE task_id = ? AND blocks_on_id = ?";
        try self.executor.exec(delete_dependency_sql, .{ task_id, blocks_on_id });

        // Rationale: Update the task's updated_at timestamp to record modification.
        // Uses executor.exec() to eliminate C API boilerplate.
        const update_task_sql = "UPDATE tasks SET updated_at = ? WHERE id = ?";
        try self.executor.exec(update_task_sql, .{ current_timestamp, task_id });

        // Rationale: Commit transaction to make all changes permanent.
        // If commit fails, transaction is rolled back automatically by SQLite.
        try self.executor.commit();

        // Assertion: Dependency removed and committed successfully
        std.debug.assert(@intFromPtr(self.executor.database) != 0);
    }

    /// Get all blockers (transitive) for a given task.
    /// Returns array of BlockerInfo with depth indicating distance in dependency chain.
    ///
    /// Rationale: Uses recursive CTE to traverse dependency graph backwards.
    /// Finds all tasks that must be completed before the given task can start.
    /// Refactored to use executor.queryAll() to eliminate SQLite C API boilerplate.
    pub fn getBlockers(self: *DepsStorage, task_id: u32) ![]types.BlockerInfo {
        // Assertions: Validate inputs (Tiger Style: 2+ per function)
        std.debug.assert(@intFromPtr(self.executor.database) != 0);
        std.debug.assert(task_id > 0);

        // Rationale: Recursive CTE finds all transitive blockers with depth tracking.
        // Base case: Direct blockers (depth 1) from dependencies table
        // Recursive case: Follow blocks_on_id links up to 100 levels deep
        // MIN(depth) groups duplicate blockers to show shortest path
        // ORDER BY depth ASC shows nearest blockers first
        const sql =
            \\WITH RECURSIVE blockers(id, title, status, depth) AS (
            \\    SELECT t.id, t.title, t.status, 1 as depth
            \\    FROM dependencies d
            \\    JOIN tasks t ON d.blocks_on_id = t.id
            \\    WHERE d.task_id = ?
            \\
            \\    UNION ALL
            \\
            \\    SELECT t.id, t.title, t.status, b.depth + 1
            \\    FROM blockers b
            \\    JOIN dependencies d ON b.id = d.task_id
            \\    JOIN tasks t ON d.blocks_on_id = t.id
            \\    WHERE b.depth < 100
            \\)
            \\SELECT id, title, status, MIN(depth) as depth
            \\FROM blockers
            \\GROUP BY id
            \\ORDER BY depth ASC, title ASC
        ;

        // Rationale: Define row struct matching SQL SELECT columns for executor.
        // Executor uses comptime reflection to map columns to struct fields by position.
        // BlockerRow is an internal type for data extraction, we'll convert to BlockerInfo.
        // Must provide deinit() method for executor's error cleanup.
        const BlockerRow = struct {
            id: u32,
            title: []const u8,
            status: []const u8,
            depth: i64,

            pub fn deinit(row: *@This(), alloc: std.mem.Allocator) void {
                alloc.free(row.title);
                alloc.free(row.status);
            }
        };

        // Rationale: Use executor.queryAll() to execute query and collect all results.
        // This handles prepare/bind/step/finalize automatically with error cleanup.
        const rows = try self.executor.queryAll(BlockerRow, self.allocator, sql, .{task_id});
        defer {
            for (rows) |*row| {
                row.deinit(self.allocator);
            }
            self.allocator.free(rows);
        }

        // Rationale: Convert BlockerRow array to BlockerInfo array.
        // We need to parse status strings and validate depth constraints.
        var blockers = try self.allocator.alloc(types.BlockerInfo, rows.len);
        errdefer {
            for (blockers[0..rows.len]) |*blocker| {
                blocker.deinit(self.allocator);
            }
            self.allocator.free(blockers);
        }

        for (rows, 0..) |row, i| {
            // Assertions: Verify data integrity (Tiger Style: validate invariants)
            std.debug.assert(row.id > 0);
            // Note: title can be empty (optional)
            std.debug.assert(row.depth >= 1); // Depth starts at 1 (direct blockers)
            std.debug.assert(row.depth <= 100); // Max recursion depth enforced by query

            blockers[i] = types.BlockerInfo{
                .id = row.id,
                .title = try self.allocator.dupe(u8, row.title),
                .status = try types.TaskStatus.fromString(row.status),
                .depth = @intCast(row.depth),
            };
        }

        return blockers;
    }

    /// Get all dependents (transitive) for a given task.
    /// Returns array of BlockerInfo with depth indicating distance in dependency chain.
    ///
    /// Rationale: Uses recursive CTE to traverse dependency graph forward.
    /// Finds all tasks that are waiting for the given task to complete.
    /// Refactored to use executor.queryAll() to eliminate SQLite C API boilerplate.
    pub fn getDependents(self: *DepsStorage, task_id: u32) ![]types.BlockerInfo {
        // Assertions: Validate inputs (Tiger Style: 2+ per function)
        std.debug.assert(@intFromPtr(self.executor.database) != 0);
        std.debug.assert(task_id > 0);

        // Rationale: Recursive CTE finds all tasks that depend on the given task.
        // Base case: Direct dependents (depth 1) where d.blocks_on_id = task_id
        // Recursive case: Follow dependency chain forward (task depends on dependent)
        // Depth starts at 1 for direct dependents and increments for each hop
        // MAX depth of 100 prevents pathological cases in large graphs
        // MIN(depth) groups duplicate dependents to show shortest path
        // ORDER BY depth ASC shows nearest dependents first
        const sql =
            \\WITH RECURSIVE dependents(id, title, status, depth) AS (
            \\    SELECT t.id, t.title, t.status, 1 as depth
            \\    FROM dependencies d
            \\    JOIN tasks t ON d.task_id = t.id
            \\    WHERE d.blocks_on_id = ?
            \\
            \\    UNION ALL
            \\
            \\    SELECT t.id, t.title, t.status, dep.depth + 1
            \\    FROM dependents dep
            \\    JOIN dependencies d ON dep.id = d.blocks_on_id
            \\    JOIN tasks t ON d.task_id = t.id
            \\    WHERE dep.depth < 100
            \\)
            \\SELECT id, title, status, MIN(depth) as depth
            \\FROM dependents
            \\GROUP BY id
            \\ORDER BY depth ASC, title ASC
        ;

        // Rationale: Define row struct matching SQL SELECT columns for executor.
        // Executor uses comptime reflection to map columns to struct fields by position.
        // DependentRow is an internal type for data extraction, we'll convert to BlockerInfo.
        // Must provide deinit() method for executor's error cleanup.
        const DependentRow = struct {
            id: u32,
            title: []const u8,
            status: []const u8,
            depth: i64,

            pub fn deinit(row: *@This(), alloc: std.mem.Allocator) void {
                alloc.free(row.title);
                alloc.free(row.status);
            }
        };

        // Rationale: Use executor.queryAll() to execute query and collect all results.
        // This handles prepare/bind/step/finalize automatically with error cleanup.
        const rows = try self.executor.queryAll(DependentRow, self.allocator, sql, .{task_id});
        defer {
            for (rows) |*row| {
                row.deinit(self.allocator);
            }
            self.allocator.free(rows);
        }

        // Rationale: Convert DependentRow array to BlockerInfo array.
        // We need to parse status strings and validate depth constraints.
        var dependents = try self.allocator.alloc(types.BlockerInfo, rows.len);
        errdefer {
            for (dependents[0..rows.len]) |*dependent| {
                dependent.deinit(self.allocator);
            }
            self.allocator.free(dependents);
        }

        for (rows, 0..) |row, i| {
            // Assertions: Verify data integrity (Tiger Style: validate invariants)
            std.debug.assert(row.id > 0);
            // Note: title can be empty (optional)
            std.debug.assert(row.depth >= 1); // Depth starts at 1 (direct dependents)
            std.debug.assert(row.depth <= 100); // Max recursion depth enforced by query

            dependents[i] = types.BlockerInfo{
                .id = row.id,
                .title = try self.allocator.dupe(u8, row.title),
                .status = try types.TaskStatus.fromString(row.status),
                .depth = @intCast(row.depth),
            };
        }

        return dependents;
    }
};
