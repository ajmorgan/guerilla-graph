//! Task management help content for Guerilla Graph CLI.

pub const resource_help =
    \\Task Management Commands
    \\
    \\Tasks are work items within plans. Each task has a unique ID in the format
    \\<plan-slug>:NNN (e.g., auth:001, payments:003) and can have dependencies on
    \\other tasks. Tasks support rich descriptions with YAML frontmatter for
    \\structured metadata.
    \\
    \\USAGE:
    \\  gg task <action> [arguments] [flags]
    \\
    \\ACTIONS:
    \\  new         Create a new task within a plan
    \\  show        Display task details with full description
    \\  ls          List tasks (filterable by plan, status)
    \\  start       Mark a task as in_progress and claim it
    \\  complete    Mark a task as completed
    \\  update      Modify task properties
    \\  delete      Remove a task and its dependencies
    \\
    \\SHORTCUTS (recommended):
    \\  gg new <slug>:     Create task (e.g., gg new auth: --title "Login")
    \\  gg start <id>      Alias for: gg task start <id>
    \\  gg complete <id>   Alias for: gg task complete <id>
    \\  gg show <id>       Smart show (detects task vs plan based on ID format)
    \\  gg update <id>     Smart update (detects task vs plan based on ID format)
    \\
    \\Run 'gg task <action> --help' for action-specific help.
    \\
    \\EXAMPLES:
    \\  gg new auth: --title "Add login endpoint"
    \\  gg show auth:001
    \\  gg start auth:001
    \\  gg complete auth:001
    \\  gg task ls --plan auth --status open
    \\
    \\
;

pub const action_new_help =
    \\Create a new task within a plan
    \\
    \\USAGE:
    \\  gg task new <title> --plan <slug> [options]
    \\
    \\ARGUMENTS:
    \\  <title>   Task title (human-readable, max 500 chars)
    \\            Quote if it contains spaces: "Add user login"
    \\
    \\REQUIRED FLAGS:
    \\  --plan <slug>               Plan slug to create task under (e.g., 'auth')
    \\
    \\OPTIONAL FLAGS:
    \\  --description <text>        Task description (supports Markdown + YAML frontmatter)
    \\  --description-file <path>   Read description from file (use "-" for stdin)
    \\  --json                      Output result in JSON format
    \\
    \\TASK ID FORMAT:
    \\  Tasks are automatically assigned IDs in the format <plan-slug>:NNN
    \\  Example: First task in 'auth' plan becomes 'auth:001'
    \\
    \\DESCRIPTION FORMAT:
    \\  Descriptions can include YAML frontmatter for structured metadata:
    \\
    \\    ---
    \\    complexity: moderate
    \\    language: java
    \\    affected_components: [entity, repository, migration]
    \\    automated_tests:
    \\      - CrewMemberRepositoryTest.testCreate
    \\    validation_commands:
    \\      - mvn test -Dtest=CrewMemberRepositoryTest
    \\    ---
    \\
    \\    ## What
    \\    Add CrewMember entity with foreign key relationship
    \\
    \\    ## Where
    \\    - `src/main/java/entity/CrewMember.java:45` - Add projectId field
    \\
    \\    ## How
    \\    ### Step 1: Add projectId field
    \\    [detailed implementation instructions...]
    \\
    \\DEPENDENCY MANAGEMENT:
    \\  - Dependencies form a directed acyclic graph (DAG)
    \\  - Cycle detection prevents circular dependencies
    \\  - Tasks are "ready" only when all blockers are completed
    \\  - Use 'gg dep add' to specify which tasks must complete first
    \\
    \\EXAMPLES:
    \\  Basic task:
    \\    gg task new "Add login endpoint" --plan auth
    \\
    \\  With inline description:
    \\    gg task new "Add JWT middleware" --plan auth \
    \\      --description "Implement JWT validation middleware for protected routes"
    \\
    \\  With description file:
    \\    gg task new "Complex feature" --plan auth \
    \\      --description-file docs/implementation-plan.md
    \\
    \\  With stdin (heredoc):
    \\    gg task new "Add OAuth" --plan auth --description-file - <<'EOF'
    \\    ## What
    \\    Implement OAuth2 login flow
    \\    EOF
    \\
    \\  JSON output:
    \\    gg task new "Deploy changes" --plan auth --json
    \\
    \\
;

pub const action_show_help =
    \\Display task details with full description
    \\
    \\USAGE:
    \\  gg task show <task-id> [flags]
    \\  gg show <task-id> [flags]      # Smart shortcut (auto-detects task vs plan)
    \\
    \\ARGUMENTS:
    \\  <task-id>   Task ID in format <plan-slug>:NNN (e.g., 'auth:001')
    \\              Also accepts internal integer ID for backward compatibility
    \\
    \\FLAGS:
    \\  --json    Output in JSON format
    \\
    \\OUTPUT INCLUDES:
    \\  - Task metadata (ID, title, status, timestamps)
    \\  - Plan context (plan slug and title)
    \\  - Full description (including YAML frontmatter if present)
    \\  - Dependency information (blockers and dependents)
    \\  - Execution timeline (created, started, completed timestamps)
    \\
    \\TASK STATUS:
    \\  - open: Available to claim (if unblocked)
    \\  - in_progress: Currently being worked on
    \\  - completed: Finished
    \\
    \\EXAMPLES:
    \\  Show task details:
    \\    gg task show auth:001
    \\
    \\  Using shortcut:
    \\    gg show auth:001
    \\
    \\  JSON output for scripting:
    \\    gg task show auth:001 --json
    \\
    \\  Extract task title via JSON:
    \\    gg show auth:001 --json | jq -r '.title'
    \\
    \\  Check if task is blocked:
    \\    gg show auth:003 --json | jq -r '.blockers | length'
    \\
    \\
;

pub const action_list_help =
    \\List tasks with optional filtering
    \\
    \\USAGE:
    \\  gg task ls [options]
    \\  gg ls [options]              # Shortcut (lists tasks, not plans)
    \\
    \\OPTIONAL FLAGS:
    \\  --plan <slug>        Filter by plan slug (e.g., 'auth', 'payments')
    \\  --status <status>    Filter by status (open, in_progress, completed)
    \\  --json               Output in JSON format
    \\
    \\OUTPUT FORMAT:
    \\  Table with columns: ID, Plan, Title, Status, Created
    \\
    \\EXAMPLES:
    \\  List all tasks:
    \\    gg task ls
    \\
    \\  List tasks in a specific plan:
    \\    gg task ls --plan auth
    \\
    \\  List only open tasks:
    \\    gg task ls --status open
    \\
    \\  List in-progress tasks:
    \\    gg task ls --status in_progress
    \\
    \\  Combine filters:
    \\    gg task ls --plan auth --status open
    \\
    \\  JSON output for scripting:
    \\    gg task ls --json
    \\
    \\  Using shortcut:
    \\    gg ls --status open
    \\
    \\  Extract task IDs via JSON:
    \\    gg ls --status open --json | jq -r '.tasks[].id'
    \\
    \\  Count tasks in a plan:
    \\    gg ls --plan auth --json | jq '.tasks | length'
    \\
    \\
;

pub const action_start_help =
    \\Mark a task as in_progress and claim it
    \\
    \\USAGE:
    \\  gg task start <task-id> [flags]
    \\  gg start <task-id> [flags]      # Shortcut (recommended)
    \\
    \\ARGUMENTS:
    \\  <task-id>   Task ID in format <plan-slug>:NNN (e.g., 'auth:001')
    \\              Also accepts internal integer ID for backward compatibility
    \\
    \\FLAGS:
    \\  --json    Output result in JSON format
    \\
    \\BEHAVIOR:
    \\  - Changes task status from 'open' to 'in_progress'
    \\  - Sets started_at timestamp to current time
    \\  - Signals to other agents that this task is claimed
    \\  - Task must not already be in_progress or completed
    \\  - Task must not be blocked by incomplete dependencies
    \\
    \\AGENT WORKFLOW:
    \\  1. Find available work: gg ready
    \\  2. Claim a task: gg start <id>
    \\  3. Read implementation details: gg show <id>
    \\  4. Execute the work
    \\  5. Mark complete: gg complete <id>
    \\
    \\EXAMPLES:
    \\  Start a task (canonical form):
    \\    gg task start auth:001
    \\
    \\  Using shortcut (recommended):
    \\    gg start auth:001
    \\
    \\  JSON output:
    \\    gg start auth:001 --json
    \\
    \\  One-liner: Start next available task:
    \\    gg start $(gg ready --json | jq -r '.ready_tasks[0].id')
    \\
    \\ERROR CONDITIONS:
    \\  - Task not found: Invalid task ID
    \\  - Already started: Task is in_progress (use 'gg show' to check status)
    \\  - Already completed: Task is done (cannot restart)
    \\  - Blocked: Task has incomplete dependencies (use 'gg dep blockers' to check)
    \\
    \\
;

pub const action_complete_help =
    \\Mark a task as completed
    \\
    \\USAGE:
    \\  gg task complete <task-id> [flags]
    \\  gg complete <task-id> [flags]   # Shortcut (recommended)
    \\
    \\ARGUMENTS:
    \\  <task-id>   Task ID in format <plan-slug>:NNN (e.g., 'auth:001')
    \\              Also accepts internal integer ID for backward compatibility
    \\
    \\FLAGS:
    \\  --json    Output result in JSON format
    \\
    \\BEHAVIOR:
    \\  - Changes task status to 'completed'
    \\  - Sets completed_at timestamp to current time
    \\  - Unblocks dependent tasks (tasks that depend on this one)
    \\  - Task can be in any status (open or in_progress)
    \\  - No confirmation prompt (operation is immediate)
    \\
    \\AGENT WORKFLOW:
    \\  1. Claim task: gg start auth:001
    \\  2. Read details: gg show auth:001
    \\  3. Execute work
    \\  4. Mark complete: gg complete auth:001
    \\  5. Find next work: gg ready
    \\
    \\EXAMPLES:
    \\  Complete a task (canonical form):
    \\    gg task complete auth:001
    \\
    \\  Using shortcut (recommended):
    \\    gg complete auth:001
    \\
    \\  JSON output:
    \\    gg complete auth:001 --json
    \\
    \\  Complete and find next task:
    \\    gg complete auth:001 && gg ready auth --json
    \\
    \\  Bulk complete multiple tasks:
    \\    gg complete auth:001 auth:002 auth:003
    \\
    \\DEPENDENCY IMPACT:
    \\  When a task is completed, any tasks that depend on it may become unblocked
    \\  and appear in 'gg ready' output. Use 'gg dep dependents' to see what tasks
    \\  will be unblocked.
    \\
    \\ERROR CONDITIONS:
    \\  - Task not found: Invalid task ID
    \\  - Already completed: Task is already marked as completed (idempotent)
    \\
    \\
;

pub const action_update_help =
    \\Modify task properties
    \\
    \\USAGE:
    \\  gg task update <task-id> [options]
    \\  gg update <task-id> [options]   # Smart shortcut (auto-detects task vs plan)
    \\
    \\ARGUMENTS:
    \\  <task-id>   Task ID in format <plan-slug>:NNN (e.g., 'auth:001')
    \\              Also accepts internal integer ID for backward compatibility
    \\
    \\OPTIONAL FLAGS:
    \\  --title <text>              New task title
    \\  --description <text>        New task description
    \\  --description-file <path>   Read description from file (use "-" for stdin)
    \\  --status <status>           Change status (open, in_progress, completed)
    \\  --json                      Output result in JSON format
    \\
    \\NOTES:
    \\  - At least one update flag is required
    \\  - Task ID cannot be changed after creation
    \\  - Plan assignment cannot be changed after creation
    \\  - Updates preserve existing values unless explicitly changed
    \\  - Dependencies are managed separately via 'gg dep' commands
    \\
    \\STATUS TRANSITIONS:
    \\  - open -> in_progress: Use 'gg task start' (preferred) or --status in_progress
    \\  - in_progress -> completed: Use 'gg task complete' (preferred) or --status completed
    \\  - completed -> open: Use --status open (reopen task)
    \\  - Any status can transition to any other status
    \\
    \\EXAMPLES:
    \\  Change title:
    \\    gg task update auth:001 --title "Add login endpoint with OAuth"
    \\
    \\  Update description:
    \\    gg task update auth:001 --description "Implement JWT-based authentication"
    \\
    \\  Update description from file:
    \\    gg task update auth:001 --description-file docs/updated-plan.md
    \\
    \\  Update description from stdin (heredoc):
    \\    gg task update auth:001 --description-file - <<'EOF'
    \\    ## What
    \\    Updated implementation details
    \\    EOF
    \\
    \\  Change status (reopen completed task):
    \\    gg task update auth:001 --status open
    \\
    \\  Update multiple properties:
    \\    gg task update auth:001 --title "New Title" --status in_progress
    \\
    \\  Using smart shortcut:
    \\    gg update auth:001 --title "Updated Title"
    \\
    \\  JSON output:
    \\    gg update auth:001 --status completed --json
    \\
    \\DEPENDENCY MANAGEMENT:
    \\  To modify task dependencies, use:
    \\    gg dep add <task-id> --blocks-on <blocker-id>
    \\    gg dep remove <task-id> --blocks-on <blocker-id>
    \\
    \\
;

pub const action_delete_help =
    \\Remove a task and its dependencies
    \\
    \\USAGE:
    \\  gg task delete <task-id> [flags]
    \\
    \\ARGUMENTS:
    \\  <task-id>   Task ID in format <plan-slug>:NNN (e.g., 'auth:001')
    \\              Also accepts internal integer ID for backward compatibility
    \\
    \\FLAGS:
    \\  --json    Output result in JSON format
    \\
    \\WARNING:
    \\  This operation is DESTRUCTIVE and IRREVERSIBLE.
    \\  The task will be permanently deleted, along with:
    \\  - All dependency relationships involving this task (as blocker or dependent)
    \\  - Task metadata and description
    \\  - Execution history (timestamps)
    \\
    \\IMPACT:
    \\  - Tasks that depended on this task (had it as a blocker) will no longer be
    \\    blocked by it and may become ready for execution
    \\  - Tasks that this task depended on (blockers) are unaffected
    \\  - Plan task counter is NOT decremented (task numbers are never reused)
    \\
    \\ALTERNATIVES:
    \\  Consider these alternatives before deleting:
    \\  - Mark as completed: gg task complete <id>
    \\  - Update status to indicate cancellation in description
    \\  - Leave task for audit trail
    \\
    \\EXAMPLES:
    \\  Delete a task:
    \\    gg task delete auth:001
    \\
    \\  JSON output:
    \\    gg task delete auth:001 --json
    \\
    \\  Check dependents before deleting:
    \\    gg dep dependents auth:001
    \\    gg task delete auth:001
    \\
    \\ERROR CONDITIONS:
    \\  - Task not found: Invalid task ID (idempotent - no error if already deleted)
    \\
    \\
;
