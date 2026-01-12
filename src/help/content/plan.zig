//! Plan management help content for Guerilla Graph CLI.

pub const resource_help =
    \\Plan Management Commands
    \\
    \\Plans are top-level organizational containers for tasks. Each plan has a unique
    \\slug (kebab-case identifier) and contains a collection of numbered tasks.
    \\
    \\USAGE:
    \\  gg plan <action> [arguments] [flags]
    \\
    \\ACTIONS:
    \\  new       Create a new plan with unique slug
    \\  show      Display plan details with task summary
    \\  ls        List all plans (filterable by status)
    \\  update    Modify plan properties
    \\  delete    Remove a plan and all its tasks
    \\
    \\SHORTCUTS (recommended):
    \\  gg new <slug>      Create plan (e.g., gg new auth --title "Auth System")
    \\  gg show <slug>     Smart show (detects plan vs task based on ID format)
    \\  gg update <slug>   Smart update (detects plan vs task based on ID format)
    \\
    \\Run 'gg plan <action> --help' for action-specific help.
    \\
    \\EXAMPLES:
    \\  gg new auth --title "Authentication System"
    \\  gg show auth
    \\  gg plan ls --status open
    \\
    \\
;

pub const action_new_help =
    \\Create a new plan (top-level container for tasks)
    \\
    \\USAGE:
    \\  gg plan new <slug> --title <text> [options]
    \\
    \\ARGUMENTS:
    \\  <slug>    Plan identifier in kebab-case (e.g., 'auth', 'tech-debt')
    \\            Must be unique and use only lowercase letters and hyphens
    \\
    \\REQUIRED FLAGS:
    \\  --title <text>              Plan title (human-readable, max 500 chars)
    \\
    \\OPTIONAL FLAGS:
    \\  --description <text>        Plan description (supports Markdown)
    \\  --description-file <path>   Read description from file (use "-" for stdin)
    \\  --json                      Output result in JSON format
    \\
    \\DESCRIPTION FORMAT:
    \\  Descriptions can include YAML frontmatter for structured metadata:
    \\
    \\    ---
    \\    complexity: moderate
    \\    priority: high
    \\    affected_components: [auth, api, db]
    \\    ---
    \\
    \\    ## Overview
    \\    Detailed plan description...
    \\
    \\EXAMPLES:
    \\  Basic plan:
    \\    gg plan new auth --title "Authentication System"
    \\
    \\  With inline description:
    \\    gg plan new auth --title "Auth" --description "Implement JWT-based auth"
    \\
    \\  With description file:
    \\    gg plan new auth --title "Auth" --description-file docs/auth-plan.md
    \\
    \\  With stdin (heredoc):
    \\    gg plan new auth --title "Auth" --description-file - <<'EOF'
    \\    ## Overview
    \\    Authentication and authorization system
    \\    EOF
    \\
    \\  JSON output:
    \\    gg plan new auth --title "Auth" --json
    \\
    \\
;

pub const action_show_help =
    \\Display plan details with task summary
    \\
    \\USAGE:
    \\  gg plan show <slug> [flags]
    \\
    \\ARGUMENTS:
    \\  <slug>    Plan slug (kebab-case identifier)
    \\
    \\FLAGS:
    \\  --json    Output in JSON format
    \\
    \\OUTPUT INCLUDES:
    \\  - Plan metadata (slug, title, status, timestamps)
    \\  - Full description (with YAML frontmatter if present)
    \\  - Task summary (total, by status)
    \\  - Recent tasks
    \\
    \\EXAMPLES:
    \\  gg plan show auth
    \\  gg plan show tech-debt --json
    \\
    \\
;

pub const action_list_help =
    \\List all plans with optional filtering
    \\
    \\USAGE:
    \\  gg plan ls [options]
    \\
    \\OPTIONAL FLAGS:
    \\  --status <status>    Filter by status (open, in_progress, completed)
    \\  --json               Output in JSON format
    \\
    \\OUTPUT FORMAT:
    \\  Table with columns: Slug, Title, Status, Tasks, Created
    \\
    \\EXAMPLES:
    \\  List all plans:
    \\    gg plan ls
    \\
    \\  List only active plans:
    \\    gg plan ls --status in_progress
    \\
    \\  JSON output for scripting:
    \\    gg plan ls --json | jq '.plans[] | select(.status == "open")'
    \\
    \\
;

pub const action_update_help =
    \\Modify plan properties
    \\
    \\USAGE:
    \\  gg plan update <slug> [options]
    \\
    \\ARGUMENTS:
    \\  <slug>    Plan slug to update
    \\
    \\OPTIONAL FLAGS:
    \\  --title <text>              New plan title
    \\  --description <text>        New plan description
    \\  --description-file <path>   Read description from file (use "-" for stdin)
    \\  --status <status>           Change status (open, in_progress, completed)
    \\  --json                      Output result in JSON format
    \\
    \\NOTES:
    \\  - At least one update flag is required
    \\  - Slug cannot be changed after creation
    \\  - Updates preserve existing values unless explicitly changed
    \\
    \\EXAMPLES:
    \\  Change title:
    \\    gg plan update auth --title "Authentication and Authorization"
    \\
    \\  Mark plan as in progress:
    \\    gg plan update auth --status in_progress
    \\
    \\  Update description from file:
    \\    gg plan update auth --description-file docs/updated-plan.md
    \\
    \\  With stdin (heredoc):
    \\    gg plan update auth --description-file - <<'EOF'
    \\    ## Updated Overview
    \\    Revised plan description with new details
    \\    EOF
    \\
    \\
;

pub const action_delete_help =
    \\Remove a plan and all its tasks
    \\
    \\USAGE:
    \\  gg plan delete <slug> [flags]
    \\
    \\ARGUMENTS:
    \\  <slug>    Plan slug to delete
    \\
    \\FLAGS:
    \\  --json    Output result in JSON format
    \\
    \\WARNING:
    \\  This operation is DESTRUCTIVE and IRREVERSIBLE.
    \\  All tasks belonging to this plan will be permanently deleted.
    \\  Dependencies involving these tasks will be removed.
    \\
    \\EXAMPLES:
    \\  gg plan delete deprecated-feature
    \\  gg plan delete old-plan --json
    \\
    \\
;
