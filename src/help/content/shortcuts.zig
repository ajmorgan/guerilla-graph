//! Help content for shortcut commands in Guerilla Graph CLI.
//!
//! This module defines help text for shortcut commands that provide quick
//! access to common operations:
//! - ready: Find unblocked tasks available for work
//! - blocked: Find tasks blocked by dependencies
//! - ls: Show hierarchical plan/task structure
//! - start/complete: Aliases to task start/complete (reference task.zig)
//!
//! Tiger Style: Full names, clear rationale, comprehensive examples.

/// Help text for `gg ready` command.
/// Shows unblocked tasks (status='open', no incomplete dependencies).
pub const ready_help =
    \\gg ready - Show unblocked tasks available for work
    \\
    \\USAGE:
    \\  gg ready [<plan-slug>] [--json]
    \\
    \\DESCRIPTION:
    \\  Find tasks that are ready to be worked on. A task is "ready" when:
    \\  - Status is 'open' (not started or completed)
    \\  - All blocking dependencies are completed (or no dependencies exist)
    \\
    \\  Tasks are displayed in a hierarchical view organized by plan, with
    \\  creation timestamps to help prioritize work. This is the primary
    \\  command for agents to discover available work.
    \\
    \\ARGUMENTS:
    \\  <plan-slug>            Filter to specific plan (optional, positional)
    \\
    \\FLAGS:
    \\  --json                 Output in JSON format for automation
    \\
    \\OUTPUT:
    \\  Displays ready tasks grouped by plan with:
    \\  - Task ID (e.g., auth:001)
    \\  - Task title
    \\  - Creation time (relative format: "2 hours ago")
    \\  - Plan summary (title and status)
    \\
    \\EXAMPLES:
    \\  # Find all ready tasks across all plans
    \\  gg ready
    \\
    \\  # Find ready tasks in auth plan only
    \\  gg ready auth
    \\
    \\  # JSON output for AI agents (recommended)
    \\  gg ready <plan-slug> --json
    \\
    \\  # Get specific task ID from JSON
    \\  gg ready --json | jq '.ready_tasks[0].id'
    \\
    \\  # Typical workflow: Find work, claim task, complete task
    \\  gg ready
    \\  gg start auth:001
    \\  # ... do work ...
    \\  gg complete auth:001
    \\
    \\PERFORMANCE:
    \\  Query executes in <5ms using optimized recursive CTE for dependency
    \\  resolution. Excludes large descriptions for fast results.
    \\
    \\SEE ALSO:
    \\  gg blocked             - Show tasks that are blocked
    \\  gg start <task-id>     - Start working on a task
    \\  gg task ls          - List all tasks with filters
    \\
;

/// Help text for `gg blocked` command.
/// Shows tasks blocked by incomplete dependencies.
pub const blocked_help =
    \\gg blocked - Show tasks blocked by dependencies
    \\
    \\USAGE:
    \\  gg blocked [--plan <plan-id>]
    \\
    \\DESCRIPTION:
    \\  Find tasks that cannot be started due to incomplete dependencies.
    \\  A task is "blocked" when it has one or more dependencies with
    \\  status != 'completed'.
    \\
    \\  Blocked tasks are ordered by blocker count (descending), showing
    \\  the most blocked tasks first. This helps identify bottlenecks in
    \\  the dependency graph and understand what needs to be unblocked.
    \\
    \\FLAGS:
    \\  --plan <plan-id>       Filter blocked tasks to a specific plan
    \\  --json                 Output in JSON format for automation
    \\
    \\OUTPUT:
    \\  Displays blocked tasks with:
    \\  - Task ID (e.g., auth:003)
    \\  - Task title
    \\  - Blocker count (e.g., "2 blockers")
    \\  - Creation time
    \\  - Plan context
    \\
    \\  Tasks are sorted by blocker count descending (most blocked first).
    \\
    \\EXAMPLES:
    \\  # Find all blocked tasks
    \\  gg blocked
    \\
    \\  # Find blocked tasks in auth plan
    \\  gg blocked --plan auth
    \\
    \\  # JSON output for monitoring
    \\  gg blocked --json | jq '.blocked_tasks | length'
    \\
    \\  # Investigate what's blocking a task
    \\  gg blocked
    \\  gg dep blockers auth:003
    \\
    \\  # Monitor bottlenecks
    \\  gg blocked  # Shows auth:005 has 3 blockers
    \\  # Resolve blockers one by one
    \\  gg complete auth:001
    \\  gg blocked  # Now auth:005 has 2 blockers
    \\
    \\PERFORMANCE:
    \\  Query executes in <5ms using JOIN with dependencies table and
    \\  status filtering. Scales to 1000s of tasks efficiently.
    \\
    \\SEE ALSO:
    \\  gg ready               - Show unblocked tasks
    \\  gg dep blockers <id>   - Show what a specific task depends on
    \\  gg dep dependents <id> - Show what depends on a specific task
    \\
;

/// Help text for `gg ls` command.
/// Shows hierarchical plan/task structure.
pub const ls_help =
    \\gg ls - Show hierarchical plan and task structure
    \\
    \\USAGE:
    \\  gg ls [<filter>] [--short]
    \\
    \\ARGUMENTS:
    \\  <filter>               Optional plan ID or task ID to filter results
    \\                         - Plan ID: shows all tasks in that plan
    \\                         - Task ID: shows only that task in plan context
    \\
    \\DESCRIPTION:
    \\  Display the complete workspace structure organized by plans with
    \\  tasks nested underneath. This provides a birds-eye view of all
    \\  work items, their status, and organization.
    \\
    \\  Each plan shows:
    \\  - Plan ID, title, and status
    \\  - Task count and status distribution
    \\  - All tasks with status indicators
    \\
    \\  Tasks display:
    \\  - Status icon: [→] in_progress, [✓] completed, [ ] open
    \\  - Task ID and title
    \\  - Creation time
    \\
    \\FLAGS:
    \\  --short                Hide task lists for completed plans (summary view)
    \\  --json                 Output in JSON format for automation
    \\
    \\OUTPUT:
    \\  Hierarchical display with visual status indicators:
    \\
    \\  [→] auth (Authentication System) - 3 tasks
    \\    [✓] auth:001: Add login endpoint (completed)
    \\    [→] auth:002: Add JWT middleware (in_progress)
    \\    [ ] auth:003: Add tests (open)
    \\
    \\  [ ] payments (Payment Processing) - 1 task
    \\    [ ] payments:001: Stripe integration (open)
    \\
    \\EXAMPLES:
    \\  # Show all plans and tasks
    \\  gg ls
    \\
    \\  # Show only auth plan tasks
    \\  gg ls auth
    \\
    \\  # Show specific task in plan context
    \\  gg ls auth:002
    \\
    \\  # Show summary view (hide tasks for completed plans)
    \\  gg ls --short
    \\
    \\  # Filter to plan with short mode
    \\  gg ls auth --short
    \\
    \\  # JSON output for scripts
    \\  gg ls --json | jq '.plans[] | select(.status=="in_progress")'
    \\
    \\  # Quick status check workflow
    \\  gg ls                # See all work
    \\  gg ready               # Find available tasks
    \\  gg blocked             # Check bottlenecks
    \\
    \\COMPARISON TO OTHER COMMANDS:
    \\  gg ls                - Shows ALL tasks hierarchically
    \\  gg task ls           - Same as 'gg ls' (alias)
    \\  gg ready               - Shows only UNBLOCKED tasks
    \\  gg blocked             - Shows only BLOCKED tasks
    \\  gg plan ls           - Shows only PLANS (no tasks)
    \\
    \\PERFORMANCE:
    \\  Query executes in <5ms using indexed plan and task tables.
    \\  Excludes descriptions for fast rendering of large workspaces.
    \\
    \\SEE ALSO:
    \\  gg task ls           - Alias for 'gg ls'
    \\  gg plan ls           - List plans without tasks
    \\  gg ready               - Show ready tasks
    \\  gg blocked             - Show blocked tasks
    \\
;

/// Help text for `gg start` command (shortcut alias).
/// References task start help for full documentation.
pub const start_help =
    \\gg start - Start working on a task (alias for 'gg task start')
    \\
    \\USAGE:
    \\  gg start <task-id>
    \\
    \\DESCRIPTION:
    \\  Shortcut command that marks a task as in_progress. This is an alias
    \\  for 'gg task start' - both commands are identical in behavior.
    \\
    \\  Use this to claim a task and signal to other agents that work has
    \\  begun. The task's status transitions from 'open' to 'in_progress'
    \\  and the started_at timestamp is recorded.
    \\
    \\EXAMPLES:
    \\  # Start a task (shortcut form)
    \\  gg start auth:001
    \\
    \\  # Equivalent to
    \\  gg task start auth:001
    \\
    \\  # Typical workflow
    \\  gg ready               # Find available work
    \\  gg start auth:001      # Claim the task
    \\  gg show auth:001       # Read implementation details
    \\  # ... do work ...
    \\  gg complete auth:001   # Mark as done
    \\
    \\SEE ALSO:
    \\  gg task start --help   - Full documentation for task start
    \\  gg complete            - Mark task as completed
    \\  gg ready               - Find tasks to start
    \\
;

/// Help text for `gg complete` command (shortcut alias).
/// References task complete help for full documentation.
pub const complete_help =
    \\gg complete - Mark task(s) as completed (alias for 'gg task complete')
    \\
    \\USAGE:
    \\  gg complete <task-id> [<task-id>...]
    \\
    \\DESCRIPTION:
    \\  Shortcut command that marks one or more tasks as completed. This is
    \\  an alias for 'gg task complete' - both commands are identical.
    \\
    \\  Completing a task:
    \\  - Sets status to 'completed'
    \\  - Records completed_at timestamp
    \\  - Unblocks any dependent tasks
    \\
    \\  Supports batch completion for multiple tasks in a single command.
    \\
    \\EXAMPLES:
    \\  # Complete a single task (shortcut form)
    \\  gg complete auth:001
    \\
    \\  # Complete multiple tasks
    \\  gg complete auth:001 auth:002 auth:003
    \\
    \\  # Equivalent to
    \\  gg task complete auth:001
    \\
    \\  # Typical workflow
    \\  gg start auth:001      # Claim task
    \\  # ... do work ...
    \\  gg complete auth:001   # Mark done
    \\  gg ready               # Find next task
    \\
    \\  # Check what gets unblocked
    \\  gg dep dependents auth:001
    \\  gg complete auth:001
    \\  gg ready               # Dependent tasks now appear
    \\
    \\SEE ALSO:
    \\  gg task complete --help - Full documentation for task complete
    \\  gg start               - Start working on a task
    \\  gg dep dependents      - See what will be unblocked
    \\
;

/// Help text for `gg show` command (smart shortcut).
/// Detects task vs plan based on ID format.
pub const show_help =
    \\gg show - Show task or plan details (smart command)
    \\
    \\USAGE:
    \\  gg show <id> [--json]
    \\
    \\ARGUMENTS:
    \\  <id>                   Task ID (auth:001) or Plan ID (auth)
    \\
    \\FLAGS:
    \\  --json                 Output in JSON format
    \\
    \\DESCRIPTION:
    \\  Smart command that automatically detects whether the ID is a task
    \\  or plan and shows the appropriate details. This is a convenience
    \\  shortcut that eliminates the need to remember 'task show' vs
    \\  'plan show'.
    \\
    \\  Detection logic:
    \\  - Contains ':' → Treated as task ID (e.g., auth:001)
    \\  - No ':' → Treated as plan ID (e.g., auth)
    \\
    \\  For tasks: Shows full task details including description, status,
    \\  timestamps, dependencies, and blocking relationships.
    \\
    \\  For plans: Shows plan details including title, description, status,
    \\  timestamps, and task summary.
    \\
    \\EXAMPLES:
    \\  # Show task details (contains ':')
    \\  gg show auth:001
    \\  # Equivalent to: gg task show auth:001
    \\
    \\  # Show plan details (no ':')
    \\  gg show auth
    \\  # Equivalent to: gg plan show auth
    \\
    \\  # Read implementation instructions workflow
    \\  gg ready               # Find work
    \\  gg start auth:001      # Claim task
    \\  gg show auth:001       # Read full description with steps
    \\  # ... implement ...
    \\  gg complete auth:001   # Mark done
    \\
    \\COMPARISON:
    \\  gg show auth:001       - Shows TASK details (smart)
    \\  gg task show auth:001  - Shows TASK details (explicit)
    \\  gg show auth           - Shows PLAN details (smart)
    \\  gg plan show auth      - Shows PLAN details (explicit)
    \\
    \\SEE ALSO:
    \\  gg task show --help    - Full task show documentation
    \\  gg plan show --help    - Full plan show documentation
    \\  gg update              - Smart update command
    \\
;

/// Help text for `gg update` command (smart shortcut).
/// Detects task vs plan based on ID format.
pub const update_help =
    \\gg update - Update task or plan properties (smart command)
    \\
    \\USAGE:
    \\  gg update <id> [--title <text>] [--description <text>] [--status <status>]
    \\
    \\ARGUMENTS:
    \\  <id>                   Task ID (auth:001) or Plan ID (auth)
    \\
    \\DESCRIPTION:
    \\  Smart command that automatically detects whether the ID is a task
    \\  or plan and updates the appropriate entity. This is a convenience
    \\  shortcut that eliminates the need to remember 'task update' vs
    \\  'plan update'.
    \\
    \\  Detection logic:
    \\  - Contains ':' → Updates task (e.g., auth:001)
    \\  - No ':' → Updates plan (e.g., auth)
    \\
    \\  For both tasks and plans, you can update:
    \\  - title: Change the display title
    \\  - description: Update implementation details or plan overview
    \\  - status: Change status (open/in_progress/completed)
    \\
    \\FLAGS:
    \\  --title <text>         Update title
    \\  --description <text>   Update description (can be multiline)
    \\  --status <status>      Update status (open/in_progress/completed)
    \\  --json                 Output in JSON format
    \\
    \\EXAMPLES:
    \\  # Update task title (contains ':')
    \\  gg update auth:001 --title "Add OAuth2 login endpoint"
    \\  # Equivalent to: gg task update auth:001 --title "..."
    \\
    \\  # Update plan description (no ':')
    \\  gg update auth --description "Complete authentication system"
    \\  # Equivalent to: gg plan update auth --description "..."
    \\
    \\  # Update task status directly
    \\  gg update auth:001 --status completed
    \\
    \\  # Update multiple properties
    \\  gg update auth:002 --title "JWT middleware" --status in_progress
    \\
    \\  # Update with multiline description
    \\  gg update auth:001 --description "$(cat <<'EOF'
    \\  ## Implementation Notes
    \\  - Use bcrypt for password hashing
    \\  - Add rate limiting
    \\  EOF
    \\  )"
    \\
    \\COMPARISON:
    \\  gg update auth:001     - Updates TASK (smart)
    \\  gg task update auth:001 - Updates TASK (explicit)
    \\  gg update auth         - Updates PLAN (smart)
    \\  gg plan update auth    - Updates PLAN (explicit)
    \\
    \\NOTE:
    \\  For status changes, consider using semantic commands:
    \\  - gg start <task-id>    instead of  --status in_progress
    \\  - gg complete <task-id> instead of  --status completed
    \\
    \\SEE ALSO:
    \\  gg task update --help  - Full task update documentation
    \\  gg plan update --help  - Full plan update documentation
    \\  gg show                - Smart show command
    \\
;

pub const new_help =
    \\gg new - Create plan or task (smart command)
    \\
    \\USAGE:
    \\  gg new <slug> [--title <text>] [--description <text>]        # Create plan
    \\  gg new <slug>: [--title <text>] [--description <text>]       # Create task
    \\
    \\ARGUMENTS:
    \\  <slug>      Plan slug in kebab-case (e.g., 'auth', 'feature-x')
    \\  <slug>:     Plan slug with colon suffix signals task creation
    \\
    \\FLAGS (both plan and task):
    \\  --title <text>          Title (optional, can be added later via update)
    \\  --description <text>    Description text
    \\  --description-file <path>   Read description from file (use "-" for stdin)
    \\  --json                  Output result in JSON format
    \\
    \\DESCRIPTION:
    \\  Smart command that automatically detects whether to create a plan or
    \\  task based on the presence of a colon suffix on the first argument.
    \\
    \\  Detection logic:
    \\  - No ':' suffix → Create plan (e.g., 'auth')
    \\  - Has ':' suffix → Create task in plan (e.g., 'auth:')
    \\
    \\  The colon acts as a separator - everything before it is the plan slug.
    \\  This matches the task ID format pattern (plan:NNN) but signals creation.
    \\
    \\  Title is OPTIONAL for both plans and tasks. You can create entities
    \\  without titles and add them later using 'gg update':
    \\    gg new <plan-slug>                  # Plan with no title
    \\    gg update <plan-slug> --title "..."  # Add title later
    \\
    \\EXAMPLES:
    \\
    \\  # Create plan (no colon)
    \\  gg new <plan-slug>
    \\  gg new <plan-slug> --title "Authentication System"
    \\  gg new <plan-slug> --title "Payments" --description "Payment processing"
    \\
    \\  # Create task (colon suffix)
    \\  gg new <plan-slug>:
    \\  gg new <plan-slug>: --title "Add login endpoint"
    \\  gg new <plan-slug>: --title "Add OAuth"
    \\
    \\  # Equivalent explicit commands
    \\  gg new <plan-slug> --title "Auth"
    \\    ↔ gg plan new <plan-slug> --title "Auth"
    \\
    \\  gg new <plan-slug>: --title "Login"
    \\    ↔ gg task new --plan <plan-slug> --title "Login"
    \\
    \\COMMON PATTERNS:
    \\
    \\  # Quick plan + task creation
    \\  gg new <plan-slug> --title "New Feature"
    \\  gg new <plan-slug>: --title "Implement core logic"
    \\  gg new <plan-slug>: --title "Add tests"
    \\
    \\  # Create without title, add later
    \\  gg new <plan-slug>:
    \\  gg update <plan-slug>:001 --title "Refactor module"
    \\
    \\ERRORS:
    \\
    \\  Invalid format:
    \\    gg new :                    # Missing plan slug
    \\    → Error: Invalid format
    \\
    \\  Invalid slug:
    \\    gg new MyPlan               # Not kebab-case
    \\    → Error: Invalid plan slug 'MyPlan'. Must be kebab-case.
    \\
    \\  Non-existent plan:
    \\    gg new <nonexistent-plan>: --title "Task"
    \\    → Error: Plan 'nonexistent' not found
    \\
    \\SEE ALSO:
    \\  gg plan new --help          Full plan creation documentation
    \\  gg task new --help          Full task creation documentation
    \\  gg show --help              Smart show command
    \\  gg update --help            Smart update command
    \\
;
