//! Dependency management help content for Guerilla Graph CLI.
//!
//! This module contains all help text for the dep resource and its actions:
//! - dep (resource overview)
//! - dep add (create dependency relationship)
//! - dep remove (delete dependency relationship)
//! - dep blockers (query what blocks a task)
//! - dep dependents (query what depends on a task)
//!
//! All help strings are comptime-known for zero I/O overhead (<1ms response time).

/// Help text for dep resource (gg dep --help)
/// Provides overview of dependency management and DAG concepts.
pub const resource_help: []const u8 =
    \\DEPENDENCY MANAGEMENT
    \\
    \\Manage task dependencies to create execution order constraints. Dependencies
    \\form a Directed Acyclic Graph (DAG) that enables safe parallel execution while
    \\ensuring prerequisites are completed before dependent work begins.
    \\
    \\COMMANDS:
    \\  dep add <task-id> --blocks-on <task-id>
    \\                         Add a dependency (task waits for blocker)
    \\  dep remove <task-id> --blocks-on <task-id>
    \\                         Remove an existing dependency
    \\  dep blockers <task-id> Show what this task is waiting on (transitive)
    \\  dep dependents <task-id>
    \\                         Show what depends on this task (transitive)
    \\
    \\KEY CONCEPTS:
    \\
    \\  Directed Acyclic Graph (DAG):
    \\    Dependencies form a directed graph where edges point from dependent tasks
    \\    to their prerequisites. "Acyclic" means no circular dependencies are allowed.
    \\    This structure guarantees that work can be ordered and executed safely.
    \\
    \\  Cycle Detection:
    \\    The system automatically detects and prevents dependency cycles. When you
    \\    try to add a dependency that would create a cycle, the command fails with
    \\    an error showing the problematic path. Use 'gg dep blockers <task-id>' to
    \\    trace the dependency chain.
    \\
    \\  Transitive Dependencies:
    \\    If task C depends on B, and B depends on A, then C transitively depends on
    \\    A (C → B → A). The 'blockers' and 'dependents' commands show the full
    \\    transitive chain up to 100 levels deep.
    \\
    \\  Ready Tasks:
    \\    A task is "ready" when all its blockers are completed. Use 'gg ready' to
    \\    find unblocked tasks available for parallel execution.
    \\
    \\WORKFLOW EXAMPLE:
    \\
    \\  # Create linear chain (A → B → C)
    \\  gg new auth: --title "Setup database"
    \\  # Output: Created task auth:001
    \\
    \\  gg new auth: --title "Add User entity"
    \\  # Output: Created task auth:002
    \\
    \\  gg new auth: --title "Add tests"
    \\  # Output: Created task auth:003
    \\
    \\  gg dep add auth:002 --blocks-on auth:001    # B depends on A
    \\  gg dep add auth:003 --blocks-on auth:002    # C depends on B
    \\
    \\  # Verify dependency chain
    \\  gg dep blockers auth:003
    \\  # Shows: auth:002 [depth 1] and auth:001 [depth 2]
    \\
    \\  # See what completing auth:001 will unblock
    \\  gg dep dependents auth:001
    \\  # Shows: auth:002 [depth 1] and auth:003 [depth 2]
    \\
    \\  # Find available work
    \\  gg ready
    \\  # Shows: auth:001 (only unblocked task)
    \\
    \\PARALLEL EXECUTION:
    \\
    \\  # Create parallel tasks (both depend on A, neither depends on each other)
    \\  gg new auth: --title "Setup"              # auth:001
    \\  gg new auth: --title "Add User entity"    # auth:002
    \\  gg new auth: --title "Add Role entity"    # auth:003
    \\  gg new auth: --title "Integration tests"  # auth:004
    \\
    \\  gg dep add auth:002 --blocks-on auth:001     # User depends on Setup
    \\  gg dep add auth:003 --blocks-on auth:001     # Role depends on Setup
    \\  gg dep add auth:004 --blocks-on auth:002     # Tests depend on User
    \\  gg dep add auth:004 --blocks-on auth:003     # Tests depend on Role
    \\
    \\  # Initially: only auth:001 is ready
    \\  # After completing auth:001: auth:002 and auth:003 are both ready (parallel!)
    \\  # After completing both: auth:004 becomes ready
    \\
    \\CYCLE PREVENTION:
    \\
    \\  # Attempting to create a cycle fails immediately
    \\  gg dep add auth:001 --blocks-on auth:002
    \\  gg dep add auth:002 --blocks-on auth:003
    \\  gg dep add auth:003 --blocks-on auth:001     # ❌ ERROR: Cycle detected
    \\
    \\  # The error message shows the problematic path:
    \\  # "Adding this dependency would create a cycle: 001 → 002 → 003 → 001"
    \\
    \\For detailed command usage, run:
    \\  gg dep add --help
    \\  gg dep remove --help
    \\  gg dep blockers --help
    \\  gg dep dependents --help
    \\
    \\For health checks and cycle detection:
    \\  gg doctor                  (runs 11 integrity checks including cycle detection)
    \\
;

/// Help text for dep add command (gg dep add --help)
pub const action_add_help: []const u8 =
    \\COMMAND: gg dep add
    \\
    \\Add a dependency relationship between two tasks. The first task (dependent)
    \\cannot start until the second task (blocker) is completed.
    \\
    \\USAGE:
    \\  gg dep add <task-id> --blocks-on <blocker-task-id>
    \\
    \\ARGUMENTS:
    \\  <task-id>              Task that will be blocked (cannot start until blocker completes)
    \\                         Supports both formats: "auth:001" or "42" (internal ID)
    \\
    \\FLAGS:
    \\  --blocks-on <task-id>  Task that must complete first (blocker/prerequisite)
    \\                         REQUIRED. Supports both formats: "auth:001" or "42"
    \\  --json                 Output result in JSON format
    \\
    \\BEHAVIOR:
    \\
    \\  1. Validates both tasks exist
    \\  2. Checks for cycles using recursive graph traversal (up to 100 levels)
    \\  3. If no cycle detected, inserts dependency atomically
    \\  4. Updates task timestamp to record the modification
    \\
    \\  If a cycle would be created, the command fails with a clear error message
    \\  showing the cycle path. Use 'gg dep blockers <task-id>' to trace dependencies.
    \\
    \\MULTIPLE BLOCKERS:
    \\
    \\  A task can have multiple blockers. It becomes "ready" only when ALL blockers
    \\  are completed. This enables AND-style dependencies (e.g., "integration tests
    \\  require both User entity AND Role entity to be complete").
    \\
    \\EXAMPLES:
    \\
    \\  Basic Usage:
    \\    gg dep add auth:002 --blocks-on auth:001
    \\    # auth:002 cannot start until auth:001 completes
    \\
    \\  Using Internal IDs (backwards compatible):
    \\    gg dep add 42 --blocks-on 41
    \\    # Task 42 blocks on task 41
    \\
    \\  Creating Linear Chain (A → B → C):
    \\    gg dep add auth:002 --blocks-on auth:001
    \\    gg dep add auth:003 --blocks-on auth:002
    \\    # Execution order: auth:001, then auth:002, then auth:003
    \\
    \\  Creating Multiple Blockers (AND dependency):
    \\    gg dep add auth:004 --blocks-on auth:002
    \\    gg dep add auth:004 --blocks-on auth:003
    \\    # auth:004 requires BOTH auth:002 AND auth:003 to complete
    \\
    \\  JSON Output:
    \\    gg dep add auth:002 --blocks-on auth:001 --json
    \\    # {
    \\    #   "status": "success",
    \\    #   "message": "Dependency added successfully",
    \\    #   "task_id": 42,
    \\    #   "blocks_on_id": 41
    \\    # }
    \\
    \\ERROR HANDLING:
    \\
    \\  Missing task:
    \\    gg dep add auth:999 --blocks-on auth:001
    \\    # Error: Task auth:999 not found
    \\
    \\  Cycle detection:
    \\    gg dep add auth:001 --blocks-on auth:003
    \\    # (assuming auth:001 → auth:002 → auth:003 already exists)
    \\    # Error: Cycle detected in task dependencies.
    \\    # Adding this dependency would create a circular reference.
    \\    # Use 'gg blockers <task>' to see the dependency chain.
    \\
    \\  Self-dependency:
    \\    gg dep add auth:001 --blocks-on auth:001
    \\    # Error: Invalid argument (tasks cannot depend on themselves)
    \\
    \\RELATED COMMANDS:
    \\  gg dep remove <task-id> --blocks-on <task-id>    Remove dependency
    \\  gg dep blockers <task-id>                        View what blocks this task
    \\  gg dep dependents <task-id>                      View what depends on this
    \\  gg ready                                         Find tasks ready to work on
    \\  gg doctor                                        Check for cycles in graph
    \\
;

/// Help text for dep remove command (gg dep remove --help)
pub const action_remove_help: []const u8 =
    \\COMMAND: gg dep remove
    \\
    \\Remove an existing dependency relationship between two tasks. After removal,
    \\the dependent task no longer waits for the blocker to complete.
    \\
    \\USAGE:
    \\  gg dep remove <task-id> --blocks-on <blocker-task-id>
    \\
    \\ARGUMENTS:
    \\  <task-id>              Task that is currently blocked
    \\                         Supports both formats: "auth:001" or "42" (internal ID)
    \\
    \\FLAGS:
    \\  --blocks-on <task-id>  Blocker task to remove from dependencies
    \\                         REQUIRED. Supports both formats: "auth:001" or "42"
    \\  --json                 Output result in JSON format
    \\
    \\BEHAVIOR:
    \\
    \\  1. Validates both tasks exist
    \\  2. Checks that the dependency exists
    \\  3. Deletes the dependency atomically
    \\  4. Updates task timestamp to record the modification
    \\
    \\  If the dependency doesn't exist, the command fails with an error.
    \\
    \\IMPACT:
    \\
    \\  - Removing a dependency may cause tasks to become "ready" sooner
    \\  - Use 'gg ready' after removal to see newly unblocked tasks
    \\  - Does NOT affect other dependencies (only removes specified relationship)
    \\
    \\EXAMPLES:
    \\
    \\  Basic Usage:
    \\    gg dep remove auth:002 --blocks-on auth:001
    \\    # auth:002 no longer waits for auth:001
    \\
    \\  Using Internal IDs (backwards compatible):
    \\    gg dep remove 42 --blocks-on 41
    \\    # Remove dependency: task 42 no longer blocks on task 41
    \\
    \\  Removing One of Multiple Blockers:
    \\    # Initial state: auth:004 blocks on both auth:002 and auth:003
    \\    gg dep remove auth:004 --blocks-on auth:002
    \\    # auth:004 now only blocks on auth:003
    \\
    \\  JSON Output:
    \\    gg dep remove auth:002 --blocks-on auth:001 --json
    \\    # {
    \\    #   "status": "success",
    \\    #   "message": "Dependency removed successfully",
    \\    #   "task_id": 42,
    \\    #   "blocks_on_id": 41
    \\    # }
    \\
    \\  Workflow: Refactoring Dependencies:
    \\    # Check current blockers
    \\    gg dep blockers auth:003
    \\
    \\    # Remove incorrect dependency
    \\    gg dep remove auth:003 --blocks-on auth:001
    \\
    \\    # Add correct dependency
    \\    gg dep add auth:003 --blocks-on auth:002
    \\
    \\    # Verify new structure
    \\    gg dep blockers auth:003
    \\
    \\ERROR HANDLING:
    \\
    \\  Missing task:
    \\    gg dep remove auth:999 --blocks-on auth:001
    \\    # Error: Task auth:999 not found
    \\
    \\  Dependency doesn't exist:
    \\    gg dep remove auth:002 --blocks-on auth:001
    \\    # (if auth:002 doesn't actually depend on auth:001)
    \\    # Error: Dependency not found
    \\
    \\USE CASES:
    \\
    \\  - Fix incorrect dependency graph structure
    \\  - Unblock tasks that were mistakenly made dependent
    \\  - Refactor task relationships during planning
    \\  - Enable parallel execution by removing unnecessary serialization
    \\
    \\RELATED COMMANDS:
    \\  gg dep add <task-id> --blocks-on <task-id>       Add dependency
    \\  gg dep blockers <task-id>                        View current blockers
    \\  gg dep dependents <task-id>                      View current dependents
    \\  gg ready                                         Check newly unblocked tasks
    \\
;

/// Help text for dep blockers command (gg dep blockers --help)
pub const action_blockers_help: []const u8 =
    \\COMMAND: gg dep blockers
    \\
    \\Display the transitive dependency tree showing what tasks block this task from
    \\starting. Shows the full chain of prerequisites up to 100 levels deep.
    \\
    \\USAGE:
    \\  gg dep blockers <task-id>
    \\
    \\ARGUMENTS:
    \\  <task-id>              Task to query
    \\                         Supports both formats: "auth:001" or "42" (internal ID)
    \\
    \\FLAGS:
    \\  --json                 Output result in JSON format with depth information
    \\
    \\BEHAVIOR:
    \\
    \\  Uses recursive graph traversal to find all tasks that must complete before
    \\  this task can start. Results include:
    \\  - Task ID and title
    \\  - Status (open, in_progress, completed)
    \\  - Depth (number of hops in dependency chain)
    \\
    \\  Depth Indicators:
    \\  - [depth 1] = direct blocker (immediate prerequisite)
    \\  - [depth 2] = blocker's blocker (second-order dependency)
    \\  - [depth N] = N levels of indirection
    \\
    \\OUTPUT FORMAT:
    \\
    \\  Text mode displays blockers in tree format with depth indicators:
    \\    Blockers for auth:003:
    \\    ❌ auth:002 - Add User entity [depth 1] (open)
    \\    ❌ auth:001 - Setup database [depth 2] (open)
    \\
    \\  Status Icons:
    \\    ✅ = completed (this blocker satisfied)
    \\    ⏳ = in_progress (actively being worked on)
    \\    ❌ = open (not yet started)
    \\
    \\INTERPRETING RESULTS:
    \\
    \\  Empty output:
    \\    No blockers found. Task is "ready" and can be started immediately.
    \\    Use 'gg ready' to see all unblocked tasks.
    \\
    \\  All blockers completed (all ✅):
    \\    Task is ready to start! The dependency chain is satisfied.
    \\
    \\  Some blockers incomplete (any ❌ or ⏳):
    \\    Task is blocked. Work on completing the blocking tasks first, starting
    \\    with depth 1 (direct blockers) or higher depths (earlier in chain).
    \\
    \\EXAMPLES:
    \\
    \\  Basic Usage:
    \\    gg dep blockers auth:003
    \\    # Shows all tasks that auth:003 waits for
    \\
    \\  Using Internal ID:
    \\    gg dep blockers 42
    \\    # Shows blockers for task with internal ID 42
    \\
    \\  JSON Output:
    \\    gg dep blockers auth:003 --json
    \\    # {
    \\    #   "task_id": 45,
    \\    #   "blockers": [
    \\    #     {
    \\    #       "id": 44,
    \\    #       "formatted_id": "auth:002",
    \\    #       "title": "Add User entity",
    \\    #       "status": "open",
    \\    #       "depth": 1
    \\    #     },
    \\    #     {
    \\    #       "id": 43,
    \\    #       "formatted_id": "auth:001",
    \\    #       "title": "Setup database",
    \\    #       "status": "completed",
    \\    #       "depth": 2
    \\    #     }
    \\    #   ]
    \\    # }
    \\
    \\  Workflow: Understanding Blocking Chain:
    \\    # Create dependency chain
    \\    gg dep add auth:002 --blocks-on auth:001
    \\    gg dep add auth:003 --blocks-on auth:002
    \\
    \\    # Query transitive blockers
    \\    gg dep blockers auth:003
    \\    # Output:
    \\    # Blockers for auth:003:
    \\    # ❌ auth:002 - Add User entity [depth 1]
    \\    # ❌ auth:001 - Setup database [depth 2]
    \\    #
    \\    # Interpretation: To start auth:003, first complete auth:001,
    \\    # then auth:002, then auth:003 becomes ready.
    \\
    \\  Workflow: Multiple Blockers (AND Dependency):
    \\    # auth:004 requires both auth:002 and auth:003
    \\    gg dep add auth:004 --blocks-on auth:002
    \\    gg dep add auth:004 --blocks-on auth:003
    \\
    \\    gg dep blockers auth:004
    \\    # Output:
    \\    # Blockers for auth:004:
    \\    # ❌ auth:002 - Add User entity [depth 1]
    \\    # ❌ auth:003 - Add Role entity [depth 1]
    \\    # ❌ auth:001 - Setup database [depth 2]
    \\    #
    \\    # Both depth-1 blockers must complete before auth:004 is ready
    \\
    \\  Workflow: Tracking Progress:
    \\    # Initial state: all tasks open
    \\    gg dep blockers auth:003
    \\    # Shows: auth:002 [depth 1] ❌, auth:001 [depth 2] ❌
    \\
    \\    # After completing auth:001
    \\    gg complete auth:001
    \\    gg dep blockers auth:003
    \\    # Shows: auth:002 [depth 1] ❌, auth:001 [depth 2] ✅
    \\
    \\    # After completing auth:002
    \\    gg complete auth:002
    \\    gg dep blockers auth:003
    \\    # Output: (no blockers - task is ready!)
    \\
    \\USE CASES:
    \\
    \\  - Understand why a task isn't "ready" yet
    \\  - Plan execution order for dependent work
    \\  - Identify critical path bottlenecks (deep chains)
    \\  - Debug complex dependency structures
    \\  - Verify dependency setup after planning phase
    \\
    \\RELATED COMMANDS:
    \\  gg dep dependents <task-id>                      View what depends on this
    \\  gg dep add <task-id> --blocks-on <task-id>       Add blocker
    \\  gg dep remove <task-id> --blocks-on <task-id>    Remove blocker
    \\  gg ready                                         Find all unblocked tasks
    \\  gg blocked                                       Find all blocked tasks
    \\
;

/// Help text for dep dependents command (gg dep dependents --help)
pub const action_dependents_help: []const u8 =
    \\COMMAND: gg dep dependents
    \\
    \\Display the transitive dependent tree showing what tasks depend on this task.
    \\Shows the full chain of dependent work up to 100 levels deep.
    \\
    \\USAGE:
    \\  gg dep dependents <task-id>
    \\
    \\ARGUMENTS:
    \\  <task-id>              Task to query
    \\                         Supports both formats: "auth:001" or "42" (internal ID)
    \\
    \\FLAGS:
    \\  --json                 Output result in JSON format with depth information
    \\
    \\BEHAVIOR:
    \\
    \\  Uses recursive graph traversal to find all tasks that transitively depend on
    \\  this task (cannot start until this task completes). Results include:
    \\  - Task ID and title
    \\  - Status (open, in_progress, completed)
    \\  - Depth (number of hops in dependency chain)
    \\
    \\  Depth Indicators:
    \\  - [depth 1] = direct dependent (immediately unblocked by this task)
    \\  - [depth 2] = dependent's dependent (unblocked after depth 1 completes)
    \\  - [depth N] = N levels of indirection
    \\
    \\OUTPUT FORMAT:
    \\
    \\  Text mode displays dependents in tree format with depth indicators:
    \\    Dependents of auth:001:
    \\    → auth:002 - Add User entity [depth 1]
    \\    → auth:003 - Add tests [depth 2]
    \\
    \\  Arrow indicates dependency direction (these tasks wait for auth:001)
    \\
    \\INTERPRETING RESULTS:
    \\
    \\  Empty output:
    \\    No dependents found. This task can be deleted or modified without
    \\    impacting other tasks.
    \\
    \\  Has dependents:
    \\    Shows the downstream impact of completing this task. Depth-1 tasks
    \\    become ready (or closer to ready) when this task completes.
    \\
    \\EXAMPLES:
    \\
    \\  Basic Usage:
    \\    gg dep dependents auth:001
    \\    # Shows all tasks that wait for auth:001
    \\
    \\  Using Internal ID:
    \\    gg dep dependents 42
    \\    # Shows dependents for task with internal ID 42
    \\
    \\  JSON Output:
    \\    gg dep dependents auth:001 --json
    \\    # {
    \\    #   "task_id": 43,
    \\    #   "dependents": [
    \\    #     {
    \\    #       "id": 44,
    \\    #       "formatted_id": "auth:002",
    \\    #       "title": "Add User entity",
    \\    #       "status": "open",
    \\    #       "depth": 1
    \\    #     },
    \\    #     {
    \\    #       "id": 45,
    \\    #       "formatted_id": "auth:003",
    \\    #       "title": "Add tests",
    \\    #       "status": "open",
    \\    #       "depth": 2
    \\    #     }
    \\    #   ]
    \\    # }
    \\
    \\  Workflow: Understanding Impact of Completion:
    \\    # Create dependency chain
    \\    gg dep add auth:002 --blocks-on auth:001
    \\    gg dep add auth:003 --blocks-on auth:002
    \\
    \\    # Query transitive dependents
    \\    gg dep dependents auth:001
    \\    # Output:
    \\    # Dependents of auth:001:
    \\    # → auth:002 - Add User entity [depth 1]
    \\    # → auth:003 - Add tests [depth 2]
    \\    #
    \\    # Interpretation: Completing auth:001 unblocks auth:002,
    \\    # which eventually enables auth:003
    \\
    \\  Workflow: Parallel Dependencies:
    \\    # auth:002 and auth:003 both depend on auth:001
    \\    # auth:004 depends on both auth:002 and auth:003
    \\    gg dep add auth:002 --blocks-on auth:001
    \\    gg dep add auth:003 --blocks-on auth:001
    \\    gg dep add auth:004 --blocks-on auth:002
    \\    gg dep add auth:004 --blocks-on auth:003
    \\
    \\    gg dep dependents auth:001
    \\    # Output:
    \\    # Dependents of auth:001:
    \\    # → auth:002 - Add User entity [depth 1]
    \\    # → auth:003 - Add Role entity [depth 1]
    \\    # → auth:004 - Integration tests [depth 2]
    \\    #
    \\    # Completing auth:001 enables TWO tasks in parallel (auth:002 and auth:003)
    \\
    \\  Workflow: Assessing Deletion Impact:
    \\    # Before deleting a task, check dependents
    \\    gg dep dependents auth:002
    \\
    \\    # If dependents exist, must handle them first:
    \\    # Option 1: Remove dependencies
    \\    gg dep remove auth:003 --blocks-on auth:002
    \\
    \\    # Option 2: Reassign dependencies
    \\    gg dep remove auth:003 --blocks-on auth:002
    \\    gg dep add auth:003 --blocks-on auth:001
    \\
    \\    # Option 3: Delete dependent tasks too
    \\    # (deletion fails if dependents exist)
    \\
    \\USE CASES:
    \\
    \\  - Understand downstream impact of completing a task
    \\  - Identify which tasks will become ready after completion
    \\  - Plan execution order and parallelism opportunities
    \\  - Assess impact before deleting or modifying a task
    \\  - Debug why completing a task didn't unblock expected work
    \\
    \\RELATIONSHIP TO BLOCKERS:
    \\
    \\  'dep blockers' and 'dep dependents' are inverse operations:
    \\  - If auth:002 is in blockers of auth:003, then auth:003 is in dependents of auth:002
    \\  - Blockers answer: "What do I need to complete this?"
    \\  - Dependents answer: "What will this unblock?"
    \\
    \\RELATED COMMANDS:
    \\  gg dep blockers <task-id>                        View what blocks this task
    \\  gg dep add <task-id> --blocks-on <task-id>       Add dependency
    \\  gg dep remove <task-id> --blocks-on <task-id>    Remove dependency
    \\  gg ready                                         Find all unblocked tasks
    \\  gg task delete <task-id>                         Delete task (fails if has dependents)
    \\
;
