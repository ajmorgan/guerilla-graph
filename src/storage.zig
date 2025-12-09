//! Storage layer for Guerilla Graph task dependency system.
//!
//! This module provides a SQLite-backed storage interface with:
//! - Database initialization and schema management
//! - Safe SQLite C API wrappers with Tiger Style compliance
//! - Transaction management for atomic operations
//! - Helper functions for binding parameters
//!
//! Tiger Style Compliance:
//! - All functions have 2+ assertions
//! - Full variable names (database, statement, index)
//! - Rationale comments for C API decisions
//! - Functions under 70 lines (split into helpers)
//! - Explicit error handling for all C calls

const std = @import("std");
const c_imports = @import("c_imports.zig");
const c = c_imports.c;
const types = @import("types.zig");
const sql_executor = @import("sql_executor.zig");
const plan_storage = @import("plan_storage.zig");
const task_storage = @import("task_storage.zig");
const deps_storage = @import("deps_storage.zig");
const health_check = @import("health_check.zig");

// Re-export C types for tests to use (ensures type compatibility)
pub const c_sqlite3 = c.sqlite3;
pub const c_sqlite3_stmt = c.sqlite3_stmt;
pub const c_funcs = c;

// Rationale: Storage-specific limits as named constants (Tiger Style: no magic numbers).

/// Maximum size for task description files loaded into memory.
/// Rationale: 10MB is large enough for detailed implementation plans with code examples,
/// but small enough to prevent memory exhaustion if accidentally loading binary files.
pub const MAX_DESCRIPTION_FILE_SIZE: usize = 10 * 1024 * 1024; // 10MB

/// SQLite-specific errors.
/// These errors indicate database operation failures or constraint violations.
pub const SqliteError = error{
    /// Failed to open the database file.
    /// Possible causes: file is locked, corrupted, or permissions are insufficient.
    OpenFailed,

    /// Failed to execute a SQL statement.
    /// This is typically caused by SQL syntax errors or constraint violations.
    ExecFailed,

    /// Failed to prepare a SQL statement for execution.
    /// This indicates a SQL syntax error in the statement.
    PrepareStatementFailed,

    /// Failed to bind a parameter value to a prepared statement.
    /// This is usually an internal error and should not occur in normal operation.
    BindFailed,

    /// Failed to execute a prepared statement step.
    /// This can occur due to constraint violations or data inconsistencies.
    StepFailed,

    /// Invalid data or operation requested.
    /// Examples: task not found, plan not found, dependency doesn't exist.
    InvalidData,

    /// The database connection is closed or unavailable.
    /// This is an internal error and should not occur in normal operation.
    DatabaseClosed,

    /// The provided ID does not conform to kebab-case format.
    /// Valid kebab-case: lowercase letters and hyphens only, no leading/trailing hyphens.
    InvalidKebabCase,

    /// Adding this dependency would create a cycle in the task graph.
    /// Dependencies must form a directed acyclic graph (DAG).
    CycleDetected,

    /// Invalid input parameters provided to a storage operation.
    /// Example: trying to update a task with no fields specified.
    InvalidInput,
};

/// SQL DDL for database schema initialization.
/// All CREATE statements use IF NOT EXISTS for idempotency.
///
/// Rationale: Extracted from initSchema() to reduce function length.
/// Schema definition is more readable and maintainable as a constant.
const SCHEMA_SQL =
    \\CREATE TABLE IF NOT EXISTS schema_version (
    \\    version INTEGER PRIMARY KEY,
    \\    applied_at INTEGER NOT NULL
    \\);
    \\
    \\INSERT OR IGNORE INTO schema_version (version, applied_at) VALUES (1, unixepoch());
    \\
    \\CREATE TABLE IF NOT EXISTS plans (
    \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    slug TEXT UNIQUE NOT NULL,
    \\    title TEXT NOT NULL CHECK(length(title) <= 500),
    \\    description TEXT NOT NULL DEFAULT '',
    \\    status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open', 'in_progress', 'completed')),
    \\    task_counter INTEGER NOT NULL DEFAULT 0,
    \\    created_at INTEGER NOT NULL,
    \\    updated_at INTEGER NOT NULL,
    \\    execution_started_at INTEGER,
    \\    completed_at INTEGER,
    \\    CHECK (status = 'open' OR execution_started_at IS NOT NULL),
    \\    CHECK ((status = 'completed') = (completed_at IS NOT NULL)),
    \\    CHECK (completed_at IS NULL OR (execution_started_at IS NOT NULL AND completed_at >= execution_started_at))
    \\);
    \\
    \\CREATE INDEX IF NOT EXISTS idx_plans_slug ON plans(slug);
    \\CREATE INDEX IF NOT EXISTS idx_plans_status ON plans(status);
    \\
    \\CREATE TABLE IF NOT EXISTS tasks (
    \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    plan_id INTEGER NOT NULL,
    \\    plan_task_number INTEGER NOT NULL,
    \\    title TEXT NOT NULL CHECK(length(title) <= 500),
    \\    description TEXT NOT NULL DEFAULT '',
    \\    status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open', 'in_progress', 'completed')),
    \\    created_at INTEGER NOT NULL,
    \\    updated_at INTEGER NOT NULL,
    \\    started_at INTEGER,
    \\    completed_at INTEGER,
    \\    CHECK (status = 'open' OR started_at IS NOT NULL),
    \\    CHECK (completed_at IS NULL OR (started_at IS NOT NULL AND completed_at >= started_at)),
    \\    FOREIGN KEY (plan_id) REFERENCES plans(id) ON DELETE CASCADE,
    \\    UNIQUE (plan_id, plan_task_number)
    \\);
    \\
    \\CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
    \\CREATE INDEX IF NOT EXISTS idx_tasks_plan_id ON tasks(plan_id);
    \\CREATE INDEX IF NOT EXISTS idx_tasks_status_plan ON tasks(status, plan_id);
    \\CREATE INDEX IF NOT EXISTS idx_tasks_plan_created ON tasks(plan_id, created_at ASC);
    \\
    \\CREATE TABLE IF NOT EXISTS dependencies (
    \\    task_id INTEGER NOT NULL,
    \\    blocks_on_id INTEGER NOT NULL,
    \\    created_at INTEGER NOT NULL,
    \\    PRIMARY KEY (task_id, blocks_on_id),
    \\    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE,
    \\    FOREIGN KEY (blocks_on_id) REFERENCES tasks(id) ON DELETE CASCADE,
    \\    CHECK (task_id != blocks_on_id)
    \\);
    \\
    \\CREATE INDEX IF NOT EXISTS idx_dependencies_task ON dependencies(task_id);
    \\CREATE INDEX IF NOT EXISTS idx_dependencies_blocks ON dependencies(blocks_on_id);
;

/// Result struct for getBlockedTasks that includes both tasks and their blocker counts.
/// Rationale: Enables callers to display blocker counts alongside tasks for bottleneck analysis.
/// The blocker_counts array is parallel to tasks array (same length, same order).
pub const BlockedTasksResult = struct {
    tasks: []types.Task,
    blocker_counts: []u32,

    /// Free all allocated memory for this result.
    /// Rationale: RAII pattern ensures no memory leaks when result is no longer needed.
    /// Caller is responsible for ensuring result is not used after deinit.
    pub fn deinit(self: *BlockedTasksResult, allocator: std.mem.Allocator) void {
        // Assertions: Validate state before cleanup
        std.debug.assert(self.tasks.len == self.blocker_counts.len); // Arrays must be parallel

        for (self.tasks) |*task| {
            task.deinit(allocator);
        }
        allocator.free(self.tasks);
        allocator.free(self.blocker_counts);
    }
};

/// Storage provides a safe Zig interface over SQLite C API
pub const Storage = struct {
    database: ?*c.sqlite3,
    allocator: std.mem.Allocator,
    executor: sql_executor.Executor,
    plans: plan_storage.PlanStorage,
    tasks: task_storage.TaskStorage,
    deps: deps_storage.DepsStorage,
    health_checker: health_check.HealthChecker,

    /// Initialize storage with SQLite database at given path.
    /// Creates database if it doesn't exist and initializes schema.
    ///
    /// Rationale: Using sqlite3_open() to create/open database file.
    /// If database exists, it will be opened; if not, it will be created.
    /// Schema initialization is idempotent (IF NOT EXISTS), safe for existing databases.
    pub fn init(allocator: std.mem.Allocator, database_path: []const u8) !Storage {
        // Assertions: Validate inputs (Tiger Style: 2+ per function)
        std.debug.assert(database_path.len > 0);
        std.debug.assert(database_path.len < 4096); // Reasonable filesystem path limit

        var database: ?*c.sqlite3 = null;
        const result = c.sqlite3_open(database_path.ptr, &database);

        if (result != c.SQLITE_OK) {
            // Rationale: Close database handle even on open failure to free resources.
            // SQLite documentation requires sqlite3_close() after failed open.
            if (database) |d| _ = c.sqlite3_close(d);
            return SqliteError.OpenFailed;
        }

        // Assertion: Success means we have valid database handle
        std.debug.assert(database != null);

        // Rationale: Enable foreign key constraints for data integrity.
        // SQLite disables FK by default. Must enable BEFORE creating Storage struct.
        // This ensures FOREIGN KEY, DEFAULT, and ON DELETE behaviors work correctly.
        const fk_result = c.sqlite3_exec(database.?, "PRAGMA foreign_keys = ON", null, null, null);
        if (fk_result != c.SQLITE_OK) {
            _ = c.sqlite3_close(database.?);
            return SqliteError.ExecFailed;
        }

        // Initialize executor first with shared database pointer
        // Rationale: All modules now use centralized c_imports, eliminating type mismatches
        const executor = sql_executor.Executor.init(database.?);

        // Create Storage with executor but undefined submodules (initialized below)
        var storage = Storage{
            .database = database,
            .allocator = allocator,
            .executor = executor,
            .plans = undefined,
            .tasks = undefined,
            .deps = undefined,
            .health_checker = undefined,
        };

        // Initialize submodules with executor and allocator
        // Rationale: Pass executor BY VALUE to avoid dangling pointer issues.
        // Each submodule gets its own copy of the executor (which contains the database pointer).
        // This ensures all modules use the SAME database pointer consistently.
        storage.plans = plan_storage.PlanStorage.init(storage.executor, allocator);
        storage.tasks = task_storage.TaskStorage.init(storage.executor, allocator);
        storage.deps = deps_storage.DepsStorage.init(storage.executor, allocator);
        storage.health_checker = health_check.HealthChecker.init(storage.executor, allocator);

        // Rationale: Schema must be initialized before any operations.
        // Creating tables is idempotent (IF NOT EXISTS), safe to run on existing DB.
        try storage.initSchema();

        // Assertion: After init, database is still valid
        std.debug.assert(storage.database != null);

        return storage;
    }

    /// Close database and free all resources.
    /// Safe to call multiple times (idempotent).
    pub fn deinit(self: *Storage) void {
        // Rationale: Close database if open, set to null to prevent use-after-close.
        // sqlite3_close() returns error code, but we ignore it in cleanup (best effort).
        if (self.database) |database| {
            _ = c.sqlite3_close(database);
            self.database = null;
        }

        // Assertion: Database is now null (closed)
        std.debug.assert(self.database == null);
    }

    /// Initialize database schema (tables, indexes, constraints).
    /// Idempotent - safe to call on existing database.
    ///
    /// Rationale: Using IF NOT EXISTS ensures this can be called on both new
    /// and existing databases without errors. Schema creation is atomic per-table.
    fn initSchema(self: *Storage) !void {
        // Assertions: Database must be open
        std.debug.assert(self.database != null);

        const database = self.database orelse return SqliteError.DatabaseClosed;

        // Rationale: sqlite3_exec() executes multiple SQL statements separated by semicolons.
        // Fourth parameter (callback) is null since we don't need result processing.
        // Fifth parameter (error message) is null since we handle errors via return code.
        var err_msg: [*c]u8 = null;
        const exec_result = c.sqlite3_exec(database, SCHEMA_SQL, null, null, &err_msg);

        if (exec_result != c.SQLITE_OK) {
            if (err_msg != null) {
                std.debug.print("SQL Error: {s}\n", .{err_msg});
                c.sqlite3_free(err_msg);
            }
            return SqliteError.ExecFailed;
        }

        // Assertion: Schema creation succeeded
        std.debug.assert(exec_result == c.SQLITE_OK);
    }

    /// Begin a transaction for atomic multi-operation changes.
    ///
    /// Rationale: Transactions ensure atomicity (all-or-nothing execution).
    /// Use with errdefer rollback() to automatically rollback on error.
    pub fn beginTransaction(self: *Storage) !void {
        try self.executor.beginTransaction();
    }

    /// Commit the current transaction, making changes permanent.
    ///
    /// Rationale: COMMIT finalizes all changes made in the transaction.
    /// If this fails, the transaction is rolled back automatically by SQLite.
    pub fn commit(self: *Storage) !void {
        try self.executor.commit();
    }

    /// Rollback the current transaction, discarding all changes.
    /// Safe to call even if no transaction is active (no-op).
    ///
    /// Rationale: ROLLBACK discards all uncommitted changes.
    /// This is typically called in errdefer blocks for automatic cleanup.
    /// Ignores errors since rollback is best-effort during error handling.
    pub fn rollback(self: *Storage) void {
        self.executor.rollback();
    }

    // ========================================================================
    // Public API - Direct delegation to storage modules
    // ========================================================================
    // Rationale: All implementations moved to specialized modules.
    // Storage provides a unified interface that routes to the correct module.

    /// Create a new plan with AUTOINCREMENT support.
    /// Plan ID must be in kebab-case format (lowercase letters and hyphens only).
    /// Title and description are provided by caller.
    ///
    /// Rationale: With AUTOINCREMENT in schema, counters table is obsolete.
    /// Single INSERT leverages SQLite's AUTOINCREMENT for sequential IDs.
    /// Plan ID uniqueness is enforced by PRIMARY KEY constraint.
    pub fn createPlan(self: *Storage, plan_id: []const u8, title: []const u8, description: []const u8, created_at: ?i64) !void {
        return self.plans.createPlan(plan_id, title, description, created_at);
    }

    /// Extract numeric fields from getPlanSummary query result.
    /// Returns struct with timestamps and task counts.
    ///
    /// Rationale: Extracted from getPlanSummary to reduce function length.
    /// Handles nullable timestamps and validates task count consistency.
    pub fn getPlanSummary(self: *Storage, plan_id: []const u8) !?types.PlanSummary {
        return self.plans.getPlanSummary(plan_id);
    }

    pub fn listPlans(
        self: *Storage,
        status_filter: ?types.TaskStatus,
    ) ![]types.PlanSummary {
        return self.plans.listPlans(status_filter);
    }

    /// Update plan status to 'in_progress' and set execution_started_at timestamp.
    /// Only updates plans that have not been started yet (execution_started_at IS NULL).
    /// Idempotent: returns success even if no rows are updated.
    ///
    /// Rationale: Transitions plan to active state when execution begins.
    /// execution_started_at is set only once (first time starting, hence the IS NULL check).
    /// updated_at tracks when the status changed.
    pub fn updatePlanExecutionStarted(self: *Storage, plan_id: []const u8) !void {
        return self.plans.updatePlanExecutionStarted(plan_id);
    }

    pub fn updatePlan(self: *Storage, plan_id: []const u8, title: ?[]const u8, description: ?[]const u8) !void {
        return self.plans.updatePlan(plan_id, title, description);
    }

    pub fn deletePlan(self: *Storage, plan_id: []const u8) !u64 {
        return self.plans.deletePlan(plan_id);
    }

    // Task operations (delegating to TaskStorage)
    pub fn createTask(
        self: *Storage,
        plan_slug: []const u8, // Required after schema migration
        title: []const u8,
        description: []const u8,
    ) !u32 {
        const result = try self.tasks.createTask(plan_slug, title, description);
        return result.task_id;
    }

    pub fn getTask(self: *Storage, task_id: u32) !?types.Task {
        return self.tasks.getTask(task_id);
    }

    pub fn listTasks(
        self: *Storage,
        status_filter: ?types.TaskStatus,
        plan_filter: ?[]const u8,
    ) ![]types.Task {
        return self.tasks.listTasks(status_filter, plan_filter);
    }

    pub fn updateTask(
        self: *Storage,
        task_id: u32,
        title: ?[]const u8,
        description: ?[]const u8,
        status: ?types.TaskStatus,
    ) !void {
        return self.tasks.updateTask(task_id, title, description, status);
    }

    pub fn deleteTask(self: *Storage, task_id: u32) !void {
        return self.tasks.deleteTask(task_id);
    }

    pub fn startTask(self: *Storage, task_id: u32) !void {
        return self.tasks.startTask(task_id);
    }

    pub fn completeTask(self: *Storage, task_id: u32) !void {
        return self.tasks.completeTask(task_id);
    }

    pub fn completeTasksBulk(self: *Storage, task_ids: []const u32) !void {
        return self.tasks.completeTasksBulk(task_ids);
    }

    pub fn getReadyTasks(self: *Storage, limit: u32) ![]types.Task {
        return self.tasks.getReadyTasks(limit);
    }

    pub fn getBlockedTasks(self: *Storage) !BlockedTasksResult {
        return self.tasks.getBlockedTasks();
    }

    pub fn getSystemStats(self: *Storage) !types.SystemStats {
        return self.tasks.getSystemStats();
    }

    // Dependency operations (delegating to DepsStorage)
    pub fn detectCycle(self: *Storage, task_id: u32, blocks_on_id: u32) !bool {
        return self.deps.detectCycle(task_id, blocks_on_id);
    }

    pub fn addDependency(self: *Storage, task_id: u32, blocks_on_id: u32) !void {
        return self.deps.addDependency(task_id, blocks_on_id);
    }

    pub fn removeDependency(self: *Storage, task_id: u32, blocks_on_id: u32) !void {
        return self.deps.removeDependency(task_id, blocks_on_id);
    }

    pub fn getBlockers(self: *Storage, task_id: u32) ![]types.BlockerInfo {
        return self.deps.getBlockers(task_id);
    }

    pub fn getDependents(self: *Storage, task_id: u32) ![]types.BlockerInfo {
        return self.deps.getDependents(task_id);
    }
    pub fn healthCheck(self: *Storage) !types.HealthReport {
        return self.health_checker.healthCheck();
    }
};

// ============================================================================
// Helper Functions (Tiger Style: prefixed with purpose, full names)
// ============================================================================

/// Bind a text value to a prepared statement parameter.
///
/// Rationale: Using null for the destructor means SQLITE_STATIC behavior - the string must
/// remain valid for the lifetime of the prepared statement. This works for our use case
/// because we execute statements immediately after binding. For long-lived statements,
/// we should use SQLITE_TRANSIENT (-1 cast to function pointer), but Zig's C translation
/// has alignment issues with that.
///
/// NOTE: Use null instead of SQLITE_TRANSIENT due to Zig C interop limitations.
/// This is safe (SQLite immediately copies the string in our usage pattern).
/// Track: https://github.com/ziglang/zig/issues/1499 (C ABI compatibility)
/// Internal helper for SQLite parameter binding. Not intended for external use.
pub fn bindText(statement: *c.sqlite3_stmt, index: c_int, text: []const u8) !void {
    // Assertions: Validate inputs (Tiger Style: 2+ per function)
    std.debug.assert(index > 0); // SQLite uses 1-based indexing
    // Rationale: Empty strings are valid for text binding

    // Rationale: @intCast() is explicit about converting usize to c_int.
    // This documents the intentional type conversion and catches overflow in debug builds.
    // null destructor = SQLITE_STATIC (string must remain valid during statement execution).
    const result = c.sqlite3_bind_text(
        statement,
        index,
        text.ptr,
        @intCast(text.len),
        null,
    );

    if (result != c.SQLITE_OK) {
        return SqliteError.BindFailed;
    }

    // Assertion: Verify binding succeeded
    std.debug.assert(result == c.SQLITE_OK);
}

/// Bind an integer value to a prepared statement parameter.
///
/// Rationale: sqlite3_bind_int64() handles 64-bit signed integers.
/// This matches our timestamp type (i64) and counter type.
/// Internal helper for SQLite parameter binding. Not intended for external use.
pub fn bindInt64(statement: *c.sqlite3_stmt, index: c_int, value: i64) !void {
    // Assertions: Validate inputs (Tiger Style: 2+ per function)
    std.debug.assert(index > 0); // SQLite uses 1-based indexing

    const result = c.sqlite3_bind_int64(statement, index, value);

    if (result != c.SQLITE_OK) {
        return SqliteError.BindFailed;
    }

    // Assertion: Verify binding succeeded
    std.debug.assert(result == c.SQLITE_OK);
}

/// Bind a u32 value to a prepared statement parameter.
///
/// Rationale: sqlite3_bind_int() handles 32-bit signed integers.
/// This matches our u32 values (sequence numbers, counts).
/// Internal helper for SQLite parameter binding. Not intended for external use.
pub fn bindInt(statement: *c.sqlite3_stmt, index: c_int, value: u32) !void {
    // Assertions: Validate inputs (Tiger Style: 2+ per function)
    std.debug.assert(index > 0); // SQLite uses 1-based indexing

    const result = c.sqlite3_bind_int(statement, index, @intCast(value));

    if (result != c.SQLITE_OK) {
        return SqliteError.BindFailed;
    }

    // Assertion: Verify binding succeeded
    std.debug.assert(result == c.SQLITE_OK);
}

/// Bind a NULL value to a prepared statement parameter.
///
/// Rationale: Used for optional filter parameters. When a filter is not provided,
/// binding NULL allows the SQL "? IS NULL" clause to evaluate to true, effectively
/// disabling that filter. This enables a single prepared statement to handle all
/// combinations of optional filters without dynamic SQL construction.
pub fn bindNull(statement: *c.sqlite3_stmt, index: c_int) !void {
    // Assertions: Validate inputs (Tiger Style: 2+ per function)
    std.debug.assert(index > 0); // SQLite uses 1-based indexing

    const result = c.sqlite3_bind_null(statement, index);

    if (result != c.SQLITE_OK) {
        return SqliteError.BindFailed;
    }

    // Assertion: Verify binding succeeded
    std.debug.assert(result == c.SQLITE_OK);
}

// ============================================================================
// Tests
// ============================================================================
