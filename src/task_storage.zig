//! Task storage operations for Guerilla Graph.
//!
//! This module is a clean aggregator that delegates to specialized modules:
//! - task_storage_crud: Task CRUD (create, read, update, delete)
//! - task_storage_lifecycle: Task lifecycle (start, complete, bulk complete)
//! - task_storage_queries: Task queries (ready tasks, blocked tasks, system stats)
//!
//! All operations use SQL Executor to eliminate SQLite C API boilerplate.

const std = @import("std");
const c_imports = @import("c_imports.zig");
const c = c_imports.c;
const storage = @import("storage.zig");
const types = @import("types.zig");
const sql_executor = @import("sql_executor.zig");
const task_storage_crud = @import("task_storage_crud.zig");
const task_storage_lifecycle = @import("task_storage_lifecycle.zig");
const task_storage_queries = @import("task_storage_queries.zig");

/// Task storage operations.
pub const TaskStorage = struct {
    crud_ops: task_storage_crud.CrudOperations,
    lifecycle_ops: task_storage_lifecycle.LifecycleOperations,
    query_ops: task_storage_queries.QueryOperations,
    executor: sql_executor.Executor,
    allocator: std.mem.Allocator,

    /// Initialize task storage with executor.
    /// Rationale: Store executor by VALUE to avoid dangling pointers.
    /// When Storage.init() returns by value, pointers to its fields become invalid.
    pub fn init(executor: sql_executor.Executor, allocator: std.mem.Allocator) TaskStorage {
        const task_storage = TaskStorage{
            .crud_ops = task_storage_crud.CrudOperations.init(executor, allocator),
            .lifecycle_ops = task_storage_lifecycle.LifecycleOperations.init(executor, allocator),
            .query_ops = task_storage_queries.QueryOperations.init(executor, allocator),
            .executor = executor,
            .allocator = allocator,
        };

        // Assertion: Database pointer must be valid after initialization.
        // Rationale: Catches early if executor was initialized with null database,
        // preventing cryptic errors during subsequent operations.
        std.debug.assert(@intFromPtr(task_storage.executor.database) != 0);

        return task_storage;
    }

    // Re-export CRUD functions for backward compatibility
    pub fn createTask(
        self: *TaskStorage,
        plan_slug: []const u8,
        title: []const u8,
        description: []const u8,
    ) !types.CreateTaskResult {
        return self.crud_ops.createTask(plan_slug, title, description);
    }

    pub fn listTasks(
        self: *TaskStorage,
        status_filter: ?types.TaskStatus,
        plan_filter: ?[]const u8,
    ) ![]types.Task {
        return self.crud_ops.listTasks(status_filter, plan_filter);
    }

    pub fn getTask(self: *TaskStorage, task_id: u32) !?types.Task {
        return self.crud_ops.getTask(task_id);
    }

    pub fn getTaskByPlanAndNumber(self: *TaskStorage, slug: []const u8, number: u32) !?u32 {
        return self.crud_ops.getTaskByPlanAndNumber(slug, number);
    }

    pub fn updateTask(
        self: *TaskStorage,
        task_id: u32,
        title: ?[]const u8,
        description: ?[]const u8,
        status: ?types.TaskStatus,
    ) !void {
        return self.crud_ops.updateTask(task_id, title, description, status);
    }

    pub fn deleteTask(self: *TaskStorage, task_id: u32) !void {
        return self.crud_ops.deleteTask(task_id);
    }


    // ========================================================================
    // Task Lifecycle Operations (delegated to task_storage_lifecycle)
    // ========================================================================

    /// Start a task by updating its status to in_progress and setting started_at timestamp.
    /// Also updates parent plan's execution_started_at if this is the first task in that plan to start.
    /// Only allows transition from 'open' to 'in_progress'.
    pub fn startTask(self: *TaskStorage, task_id: u32) !void {
        return self.lifecycle_ops.startTask(task_id);
    }

    /// Complete a task by setting status to completed and recording completed_at timestamp.
    /// Updates task's updated_at and completed_at fields.
    /// Returns error if task does not exist or is not in 'in_progress' status.
    pub fn completeTask(self: *TaskStorage, task_id: u32) !void {
        return self.lifecycle_ops.completeTask(task_id);
    }

    /// Complete multiple tasks in a single transaction.
    /// All tasks must be in 'in_progress' status. If any task is not in the correct status,
    /// the entire operation fails and no tasks are updated.
    pub fn completeTasksBulk(self: *TaskStorage, task_ids: []const u32) !void {
        return self.lifecycle_ops.completeTasksBulk(task_ids);
    }


    // ========================================================================
    // Task Query Operations (delegated to task_storage_queries)
    // ========================================================================

    /// Get system-wide statistics: task counts by status, blocker counts.
    /// Returns a SystemStats struct with aggregated counts.
    pub fn getSystemStats(self: *TaskStorage) !types.SystemStats {
        return self.query_ops.getSystemStats();
    }

    /// Get all tasks that are ready to work on (no unmet dependencies).
    /// Returns tasks with status 'open' that have no incomplete blockers.
    /// Results are sorted by creation time (oldest first).
    /// Limit parameter controls maximum number of results (0 = unlimited).
    pub fn getReadyTasks(self: *TaskStorage, limit: u32) ![]types.Task {
        return self.query_ops.getReadyTasks(limit);
    }

    /// Get all blocked tasks (tasks with unmet dependencies) along with their blocker counts.
    /// Returns tasks with status != 'completed' that have at least one incomplete blocker.
    /// Results are sorted by blocker count (descending), then by creation time (oldest first).
    pub fn getBlockedTasks(self: *TaskStorage) !storage.BlockedTasksResult {
        return self.query_ops.getBlockedTasks();
    }
};
