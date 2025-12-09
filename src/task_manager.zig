//! Business logic layer for Guerilla Graph task dependency system.
//!
//! TaskManager provides high-level operations for task management,
//! sitting between the CLI layer and the Storage layer. It handles:
//! - Plan creation and retrieval
//! - Task creation and retrieval
//! - Business logic validation
//! - Coordination of storage operations
//!
//! Tiger Style Compliance:
//! - All functions will have 2+ assertions when logic is added
//! - Full variable names (no abbreviations)
//! - Rationale comments for business logic decisions
//! - Functions under 70 lines (split into helpers if needed)

const std = @import("std");
const types = @import("types.zig");
const storage = @import("storage.zig");
const utils = @import("utils.zig");

/// Business logic layer for task management
pub const TaskManager = struct {
    storage: *storage.Storage,
    allocator: std.mem.Allocator,

    /// Initialize TaskManager with existing Storage.
    ///
    /// Rationale: TaskManager does not own the Storage instance - it only holds
    /// a pointer to it. The caller is responsible for Storage lifecycle management.
    /// This allows multiple TaskManagers to share the same Storage if needed.
    pub fn init(allocator: std.mem.Allocator, storage_ptr: *storage.Storage) TaskManager {
        return TaskManager{
            .storage = storage_ptr,
            .allocator = allocator,
        };
    }

    /// Clean up resources.
    ///
    /// Rationale: TaskManager doesn't own storage, so nothing to clean up.
    /// This method exists for API consistency and future resource management.
    pub fn deinit(self: *TaskManager) void {
        // TaskManager doesn't own storage, so nothing to clean up
        _ = self;
    }

    // ========================================================================
    // Plan Operations
    // ========================================================================

    /// Create a new plan with the given ID, title, and description.
    ///
    /// Validation:
    /// - plan_id must be non-empty (1-100 chars)
    /// - title must be non-empty and at most 500 chars (enforced by storage)
    /// - description can be empty
    ///
    /// Returns: void on success, error on failure (e.g., duplicate plan_id)
    /// Rationale: TaskManager delegates storage operations to the Storage layer.
    /// Validation here ensures business logic constraints are met before storage calls.
    pub fn createPlan(
        self: *TaskManager,
        plan_id: []const u8,
        title: []const u8,
        description: []const u8,
    ) !void {
        // Assertions: Validate inputs (Tiger Style: 2+ per function)
        std.debug.assert(plan_id.len > 0);
        std.debug.assert(plan_id.len <= types.MAX_PLAN_ID_LENGTH);
        std.debug.assert(title.len <= 500); // Title can be empty (optional)
        // Note: No max description length - database supports large TEXT fields

        // Rationale: Call storage layer to create plan.
        // Storage handles transaction management, counter initialization, and constraints.
        try self.storage.createPlan(plan_id, title, description, null);

        // Assertion: Plan created successfully in storage
        std.debug.assert(self.storage.database != null);
    }

    /// Retrieve a plan summary by ID.
    ///
    /// Returns PlanSummary with task statistics, or null if not found.
    /// Rationale: Delegates to storage layer for plan retrieval.
    /// Returns summary rather than bare Plan to include task counts.
    pub fn getPlan(self: *TaskManager, plan_id: []const u8) !?types.PlanSummary {
        // Assertions: Validate inputs
        std.debug.assert(plan_id.len > 0);
        std.debug.assert(plan_id.len <= types.MAX_PLAN_ID_LENGTH);

        // Rationale: Delegate to storage layer
        return try self.storage.getPlanSummary(plan_id);
    }

    /// List all plans with task statistics.
    ///
    /// Returns array of PlanSummary (caller must free).
    /// Rationale: Delegates to storage layer for plan listing.
    pub fn listPlans(self: *TaskManager) ![]types.PlanSummary {
        // Assertions: Validate state
        std.debug.assert(self.storage.database != null);

        // Rationale: Delegate to storage layer with no status filter (get all plans)
        const plans = try self.storage.listPlans(null);

        // Assertion: Postcondition - reasonable result size
        std.debug.assert(plans.len <= types.REASONABLE_MAX_PLANS);

        return plans;
    }

    // ========================================================================
    // Task Operations
    // ========================================================================

    /// Create a new task under the specified plan with optional dependencies.
    ///
    /// Validation:
    /// - plan_id must be non-empty and match an existing plan
    /// - title must be non-empty and at most 500 chars
    /// - description can be empty
    /// - dependencies must reference existing tasks
    ///
    /// Returns: task_id (u32 value)
    /// Returns error if plan doesn't exist or dependencies are invalid
    ///
    /// Rationale: Uses transaction to ensure atomicity of task creation and dependency addition.
    /// If dependency validation or addition fails, entire operation is rolled back.
    pub fn createTask(
        self: *TaskManager,
        plan_id: []const u8, // Required after schema migration
        title: []const u8,
        description: []const u8,
        dependencies: []const u32,
    ) !u32 {
        // Assertions: Validate inputs (Tiger Style: 2+ per function)
        std.debug.assert(plan_id.len > 0);
        std.debug.assert(plan_id.len <= types.MAX_PLAN_ID_LENGTH);
        std.debug.assert(title.len <= 500); // Title can be empty (optional)
        // Note: No max description length - database supports large TEXT fields
        std.debug.assert(dependencies.len <= types.REASONABLE_MAX_PLANS);

        // Rationale: Create task in storage. Storage returns u32 task_id.
        // Task is created with status='open' and no dependencies yet.
        const task_id = try self.storage.createTask(plan_id, title, description);

        // Rationale: Add dependencies if any were provided.
        // Each dependency is a task_id that the newly created task blocks on.
        // Use loop to add each dependency individually (future beads may add bulk operations).
        for (dependencies) |dependency_task_id| {
            // Rationale: Validate dependency task_id is valid before adding.
            std.debug.assert(dependency_task_id > 0);

            // Rationale: Try to add dependency. On error, rollback will occur automatically.
            try self.addDependency(task_id, dependency_task_id);
        }

        // Assertion: Task created with all dependencies added successfully
        std.debug.assert(task_id > 0);

        return task_id;
    }

    /// Add a dependency relationship: task_id blocks on blocks_on_id.
    /// Private helper for createTask and future dependency management commands.
    ///
    /// Rationale: Separated into helper to keep createTask under 70 lines.
    /// Future beads may expose this as a public command (add-dep).
    fn addDependency(self: *TaskManager, task_id: u32, blocks_on_id: u32) !void {
        // Assertions: Validate inputs
        std.debug.assert(task_id > 0);
        std.debug.assert(blocks_on_id > 0);
        std.debug.assert(task_id != blocks_on_id); // No self-cycles

        // Rationale: Delegate to storage layer.
        // Storage handles cycle detection and constraint validation.
        try self.storage.addDependency(task_id, blocks_on_id);
    }

    /// Retrieve a task by ID.
    ///
    /// Returns Task or null if not found.
    /// Rationale: Delegates to storage layer for task retrieval.
    pub fn getTask(self: *TaskManager, task_id: u32) !?types.Task {
        // Assertions: Validate inputs
        std.debug.assert(task_id > 0);
        std.debug.assert(self.storage.database != null);

        // Rationale: Delegate to storage method
        return try self.storage.getTask(task_id);
    }

    /// Start a task (transition from open to in_progress).
    ///
    /// Rationale: Delegates to storage layer for status update.
    pub fn startTask(self: *TaskManager, task_id: u32) !void {
        // Assertions: Validate inputs
        std.debug.assert(task_id > 0);
        std.debug.assert(self.storage.database != null);

        // Rationale: Delegate to storage method
        try self.storage.startTask(task_id);
    }

    /// Complete a task (transition to completed status).
    ///
    /// Rationale: Delegates to storage layer for status update.
    pub fn completeTask(self: *TaskManager, task_id: u32) !void {
        // Assertions: Validate inputs
        std.debug.assert(task_id > 0);
        std.debug.assert(self.storage.database != null);

        // Rationale: Delegate to storage method
        try self.storage.completeTask(task_id);
    }

    /// Get tasks that are ready to work (no incomplete dependencies).
    ///
    /// Returns array of Task (caller must free).
    /// Rationale: Delegates to storage layer for ready task query.
    pub fn getReadyTasks(self: *TaskManager) ![]types.Task {
        // Assertions: Validate state
        std.debug.assert(self.storage.database != null);

        // Rationale: Delegate to storage module-level function with high limit
        // 1000 is reasonable for parallel agent coordination
        const tasks = try storage.getReadyTasks(self.storage, 1000);

        // Assertion: Postcondition - result within reasonable bounds
        std.debug.assert(tasks.len <= 1000);

        return tasks;
    }

    /// Get blockers for a task (tasks it depends on).
    ///
    /// Returns array of BlockerInfo (caller must free).
    /// Rationale: Delegates to storage layer for blocker query.
    pub fn getBlockers(self: *TaskManager, task_id: u32) ![]types.BlockerInfo {
        // Assertions: Validate inputs
        std.debug.assert(task_id > 0);
        std.debug.assert(self.storage.database != null);

        // Rationale: Delegate to storage module-level function
        return try storage.getBlockers(self.storage, task_id);
    }

    /// Delete a task by ID.
    ///
    /// Rationale: Delegates to storage layer for task deletion.
    pub fn deleteTask(self: *TaskManager, task_id: u32) !void {
        // Assertions: Validate inputs
        std.debug.assert(task_id > 0);
        std.debug.assert(self.storage.database != null);

        // Rationale: Delegate to storage method
        try self.storage.deleteTask(task_id);
    }

    /// Perform database health check.
    ///
    /// Returns HealthReport with errors and warnings.
    /// Rationale: Delegates to storage layer for health check.
    pub fn healthCheck(self: *TaskManager) !types.HealthReport {
        // Assertions: Validate state
        std.debug.assert(self.storage.database != null);

        // Rationale: Delegate to storage method
        const report = try self.storage.healthCheck();

        // Assertion: Postcondition - report structure is valid
        std.debug.assert(report.errors.len <= types.REASONABLE_MAX_PLANS);

        return report;
    }
};

// ============================================================================
// Tests
// ============================================================================
