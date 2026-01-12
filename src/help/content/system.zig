//! System command help content for Guerilla Graph CLI.
//!
//! This module contains comprehensive help text for system commands:
//! - init_help: Initialize workspace
//! - doctor_help: Database health checks
//! - workflow_help: Agent workflow context
//!
//! Tiger Style: All help content is stored as comptime strings for zero-cost abstraction.

// ============================================================================
// Init Command Help
// ============================================================================

pub const init_help =
    \\COMMAND: gg init
    \\
    \\Initialize a new Guerilla Graph workspace in the current directory.
    \\
    \\USAGE:
    \\  gg init [--force]
    \\
    \\FLAGS:
    \\  --force                Reinitialize workspace (removes existing .gg directory)
    \\  --json                 Output result in JSON format
    \\
    \\DESCRIPTION:
    \\  Creates a .gg directory in the current working directory with a tasks.db
    \\  SQLite database. This database tracks all plans, tasks, and dependencies
    \\  for the workspace.
    \\
    \\  The init command prevents nested workspaces (similar to git). If you are
    \\  already within a gg workspace, init will fail unless --force is provided.
    \\
    \\WORKSPACE STRUCTURE:
    \\  .gg/
    \\    tasks.db             SQLite database with schema
    \\
    \\EXAMPLES:
    \\  # Initialize a new workspace
    \\  gg init
    \\
    \\  # Reinitialize workspace (destroys existing data!)
    \\  gg init --force
    \\
    \\  # Initialize with JSON output for scripting
    \\  gg init --json
    \\
    \\NEXT STEPS:
    \\  After initializing, run these commands to get started:
    \\
    \\  gg workflow                              # View workflow guide
    \\  gg new <slug> --title "Plan Name"        # Create a plan
    \\  gg new <slug>: --title "Task Name"       # Create tasks
    \\  gg ready --json                          # Find available work
    \\
    \\ERRORS:
    \\  AlreadyInWorkspace     Current or parent directory has .gg workspace
    \\                         Use --force to reinitialize
    \\
    \\SEE ALSO:
    \\  gg workflow            Comprehensive workflow guide
    \\  gg plan new --help     Create plans
    \\  gg task new --help     Create tasks
    \\
;

// ============================================================================
// Doctor Command Help
// ============================================================================

pub const doctor_help =
    \\COMMAND: gg doctor
    \\
    \\Run comprehensive health checks on the workspace database.
    \\
    \\USAGE:
    \\  gg doctor
    \\
    \\FLAGS:
    \\  --json                 Output results in JSON format
    \\
    \\DESCRIPTION:
    \\  Validates database integrity by running 11 health checks:
    \\
    \\  1. Orphaned dependencies   - Dependencies referencing deleted tasks
    \\  2. Dependency cycles       - Circular dependencies that block progress
    \\  3. Orphaned tasks          - Tasks referencing deleted plans
    \\  4. Empty plans             - Plans with no tasks (warning only)
    \\  5. Completed timestamp     - Tasks marked completed without timestamp
    \\  6. Invalid status values   - Tasks/plans with invalid status
    \\  7. Title length            - Titles exceeding 500 character limit
    \\  8. Schema version          - Database schema validation
    \\  9. Missing indexes         - Performance-critical indexes not present
    \\  10. Large descriptions     - Descriptions exceeding recommended size
    \\  11. Foreign key integrity  - Referential integrity violations
    \\
    \\OUTPUT FORMAT:
    \\  Text mode:
    \\    - Status: Healthy/Unhealthy
    \\    - Error count and list
    \\    - Warning count and list
    \\
    \\  JSON mode:
    \\    {
    \\      "status": "healthy" | "unhealthy",
    \\      "error_count": <number>,
    \\      "warning_count": <number>,
    \\      "errors": [{"message": "..."}, ...],
    \\      "warnings": [{"message": "..."}, ...]
    \\    }
    \\
    \\EXAMPLES:
    \\  # Run health check with human-readable output
    \\  gg doctor
    \\
    \\  # Get health status in JSON for monitoring
    \\  gg doctor --json
    \\
    \\  # Check for errors in CI pipeline
    \\  gg doctor --json | jq -e '.error_count == 0'
    \\
    \\WHEN TO USE:
    \\  - After migrating or modifying database manually
    \\  - Before critical operations (bulk deletes, imports)
    \\  - When observing unexpected behavior
    \\  - As part of automated monitoring
    \\  - After power loss or crash recovery
    \\
    \\TROUBLESHOOTING:
    \\  Orphaned dependencies:
    \\    Run: gg dep remove <task-id> --blocks-on <deleted-task-id>
    \\
    \\  Dependency cycles:
    \\    Identify cycle, remove one dependency:
    \\    Run: gg dep remove <task-id> --blocks-on <blocker-id>
    \\
    \\  Database corruption:
    \\    Restore from backup or reinitialize:
    \\    Run: gg init --force (WARNING: destroys all data)
    \\
    \\SEE ALSO:
    \\  gg dep remove --help       Remove problematic dependencies
    \\  gg task delete --help      Clean up orphaned tasks
    \\  gg init --help             Reinitialize workspace
    \\
;

// ============================================================================
// Workflow Command Help
// ============================================================================

pub const workflow_help =
    \\COMMAND: gg workflow
    \\
    \\Display comprehensive workflow context for AI agents and parallel execution.
    \\
    \\USAGE:
    \\  gg workflow
    \\
    \\DESCRIPTION:
    \\  Shows the complete feature execution protocol for working with Guerilla
    \\  Graph. This includes planning, task creation, dependency management,
    \\  parallel execution, and completion workflows.
    \\
    \\  The workflow command is designed for AI agents (like Claude Code) to
    \\  quickly recover context after:
    \\  - Session compaction
    \\  - Context window clearing
    \\  - Starting a new session
    \\  - Onboarding new team members
    \\
    \\WORKFLOW PHASES:
    \\
    \\  1. PLANNING PHASE
    \\     Break features into tasks with dependencies (DAG structure):
    \\
    \\     - Create plan: gg new <slug> --title "Feature Name"
    \\     - Add description: gg update <slug> --description-file - <<'EOF'...EOF
    \\     - Create tasks: gg new <slug>: --title "Task Title" --description-file - <<'EOF'...EOF
    \\     - Set dependencies: gg dep add <slug:NNN> --blocks-on <slug:NNN>
    \\     - Verify DAG: gg ready
    \\
    \\  2. EXECUTION PHASE (AI Agent Workflow)
    \\     Find work, claim tasks, execute, and complete:
    \\
    \\     - Find work: gg ready <plan-slug> --json  (filter to specific plan)
    \\     - Spawn agents: N agents for N ready tasks (maximize parallelism)
    \\     - Claim and read: gg start <slug:NNN> --json (gets full task in one command)
    \\     - Execute work
    \\     - Complete: gg complete <slug:NNN>
    \\     - Repeat until feature complete
    \\
    \\     Note: gg start --json returns complete task details (id, title, description).
    \\     Separate gg show is optional if you need to re-read instructions.
    \\
    \\  3. VALIDATION PHASE
    \\     Verify completion and run tests:
    \\
    \\     - Check status: gg task ls --plan <slug>
    \\     - Run tests
    \\     - Mark plan complete: gg update <slug> --status completed
    \\
    \\TASK ID FORMAT:
    \\  Format: slug:NNN (e.g., auth:001, auth:042, payments:001)
    \\
    \\  - Each plan has independent task numbering (1, 2, 3...)
    \\  - Backwards compatible: numeric IDs still work (e.g., gg show 42)
    \\  - Plan slugs are mutable (can be renamed without breaking references)
    \\
    \\TASK DESCRIPTIONS:
    \\  Tasks should include structured implementation details:
    \\
    \\  - What: Brief summary of the change
    \\  - Where: File paths and line numbers to modify
    \\  - How: Code changes to make (with snippets)
    \\  - Validation: Commands to verify success
    \\
    \\  Use --description-file for complex tasks with:
    \\  - YAML frontmatter (complexity, components, tests)
    \\  - Multi-step implementation plans
    \\  - Code examples and detailed specifications
    \\
    \\  Stdin Support:
    \\    Use "-" with --description-file to read from stdin:
    \\
    \\    gg new auth: --title "Task" --description-file - <<'EOF'
    \\    ## What
    \\    Description content here
    \\    EOF
    \\
    \\CORE RULES:
    \\  - Track ALL work in gg (no TodoWrite tool, no markdown TODOs)
    \\  - Use 'gg ready' to find work (never guess task IDs)
    \\  - Task IDs are formatted as slug:NNN (auth:001, not just 001)
    \\  - DAG structure enables safe parallel execution
    \\  - Ready task count = parallelism capacity (5 ready = 5 agents)
    \\
    \\ESSENTIAL COMMANDS:
    \\
    \\  Finding Work:
    \\    gg ready                           Unblocked tasks (YOUR WORK QUEUE)
    \\    gg task ls --status=open           All open tasks
    \\    gg task ls --status=in_progress    Active work
    \\    gg show <slug:NNN>                 Full task details
    \\
    \\  Creating & Updating:
    \\    gg new <slug> --title "..."        Create plan (no colon)
    \\    gg new <slug>: --title "..."       Create task (colon suffix)
    \\    gg update <id> --description-file - <<'EOF'...EOF  Update via stdin
    \\    gg start <slug:NNN>                Claim task
    \\    gg complete <slug:NNN>             Mark done
    \\
    \\  Dependencies & Blocking:
    \\    gg dep add <slug:NNN> --blocks-on <slug:NNN>  Add dependency
    \\    gg blocked                                     All blocked tasks
    \\    gg dep blockers <slug:NNN>                     What blocks this
    \\    gg dep dependents <slug:NNN>                   What this unblocks
    \\
    \\  Project Health:
    \\    gg doctor                          Run health checks
    \\
    \\PARALLEL EXECUTION EXAMPLE:
    \\  gg ready                 # Find unblocked work
    \\  # Output: 5 tasks ready
    \\  # Spawn 5 parallel agents, each claims one task:
    \\  gg start auth:001        # Agent 1 claims task
    \\  # ... do the work ...
    \\  gg complete auth:001     # Mark done, unblocks dependents
    \\  gg ready                 # Find newly unblocked work
    \\
    \\SCRIPTING:
    \\  gg ready --json | jq -r '.ready_tasks[0].id'   # Get first ready task
    \\  gg ready --json | jq '.ready_tasks | length'   # Count ready tasks
    \\
    \\CONTEXT RECOVERY:
    \\  Run 'gg workflow' after:
    \\  - Session compaction in Claude Code
    \\  - Clearing conversation history
    \\  - Starting a new terminal session
    \\  - Onboarding new AI agents
    \\  - Switching between projects
    \\
    \\  This command is automatically called by hooks when .gg/ is detected.
    \\
    \\SEE ALSO:
    \\  gg help                Full command reference
    \\  gg new --help          Plan and task creation
    \\  gg dep add --help      Dependency management
    \\  gg ready --help        Finding available work
    \\  gg doctor --help       Database health checks
    \\
;
