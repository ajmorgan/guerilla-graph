# Control Flow Module

Standard control flow conventions and tool invocation patterns for all commands.

## Purpose

Provides consistent syntax for command logic, tool invocations, conditional execution, and error handling. Ensures all commands use explicit, executable patterns instead of ambiguous prose.

---

## Tool Invocation Syntax

**Purpose**: Explicit syntax for calling Claude Code tools

### Read Tool

```
content = Read("path/to/file.ext")
content = Read("path/to/file.ext", offset=100, limit=50)
```

**Returns**: File contents as string (or error if file not found)

**Usage**:
```markdown
1. content = Read("src/storage.zig")
2. If content contains "OLD SCHEMA":
   Flag as Critical
```

---

### Bash Tool

```
result = Bash("command arg1 arg2")
result = Bash("cd /path && command")
output = Bash("zig build test")
```

**Returns**: Command output as string + exit code

**Usage**:
```markdown
1. output = Bash("zig build")
2. If output contains "error":
   compilation_failed = true
```

---

### Task Tool (Subagent)

```
result = Task(
  subagent_type="codebase_exploration",
  model="opus",
  prompt="Find all files that define Task struct"
)
```

**Parameters**:
- `subagent_type`: Type of agent to spawn
- `model`: Optional. If omitted, inherits from parent (recommended). Explicit: "opus" or "sonnet"
- `prompt`: Task for subagent

**Returns**: Subagent's complete response

**Usage**:
```markdown
1. If file_count > 10:
     exploration_result = Task(
       subagent_type="general-purpose",
       prompt="Analyze dependency graph for {plan_slug}"
     )
     # Model inherits from parent - no need to specify
```

---

### Parallel Agent Spawning (CRITICAL)

**Mechanism**: Claude Code executes multiple Task tool calls in parallel when they appear in the SAME assistant message. This is how parallelism works - not through loops, but through simultaneous tool invocations.

**Correct Pattern** (parallel - all in ONE message):
```
# Claude emits a SINGLE response containing multiple tool calls:

[Tool Call 1: Task]
  subagent_type: "general-purpose"
  description: "Audit auth:001"
  prompt: "Audit task auth:001..."

[Tool Call 2: Task]
  subagent_type: "general-purpose"
  description: "Audit auth:002"
  prompt: "Audit task auth:002..."

[Tool Call 3: Task]
  subagent_type: "general-purpose"
  description: "Audit auth:003"
  prompt: "Audit task auth:003..."

# All three agents spawn simultaneously and run in parallel
# Results return when ALL agents complete
```

**Incorrect Pattern** (sequential - SLOW):
```
# Message 1: Claude calls Task for auth:001
# ... wait for result ...
# Message 2: Claude calls Task for auth:002
# ... wait for result ...
# Message 3: Claude calls Task for auth:003
# ... wait for result ...

# This takes 3x longer than parallel!
```

**Key Insight**: The FOR loop in pseudocode is conceptual. In practice, Claude must emit all Task calls at once, not iterate through them sequentially.

**Pseudocode to Execution**:
```
# Pseudocode says:
FOR task IN ready_tasks:
  Task(subagent_type="general-purpose", prompt=...)

# Execution means:
# Emit ONE message with N Task tool calls (where N = len(ready_tasks))
# NOT: Call Task, wait, call Task, wait, call Task, wait
```

---

### AskUser Tool

```
choice = AskUser(
  question="Which approach should I use?",
  options=["option_a", "option_b", "cancel"]
)
```

**Returns**: User's selected option (string)

**Usage**:
```markdown
1. If plan_exists:
     choice = AskUser(
       question="Plan 'auth' already exists. Continue?",
       options=["overwrite", "append", "cancel"]
     )
   CASE choice:
     "overwrite": DeletePlan(plan_slug)
     "append": GOTO append_workflow
     "cancel": RETURN "Operation cancelled"
```

---

### Glob Tool

```
files = Glob("**/*.zig")
files = Glob("src/**/*_test.zig")
```

**Returns**: List of matching file paths

**Usage**:
```markdown
1. zig_files = Glob("src/**/*.zig")
2. FOR each file_path in zig_files:
     content = Read(file_path)
     Process(content)
```

---

### Grep Tool

```
matches = Grep(pattern="pub fn createTask", path="src/")
matches = Grep(pattern="TODO", output_mode="files_with_matches")
```

**Returns**: Matching lines or file paths

**Usage**:
```markdown
1. files_with_todos = Grep(
     pattern="TODO",
     path="src/",
     output_mode="files_with_matches"
   )
2. If files_with_todos.count > 0:
     Flag as High: "Found {count} files with TODOs"
```

---

## Control Flow Conventions

**Purpose**: Standard patterns for conditional logic and loops

### CASE Statement

```markdown
CASE variable:
  "value1":
    Action1()
  "value2":
    Action2()
  DEFAULT:
    DefaultAction()
```

**Usage**:
```markdown
CASE task_status:
  "open":
    operations = ["start", "update", "delete"]
  "in_progress":
    operations = ["complete", "reopen", "update"]
  "completed":
    operations = ["reopen", "delete"]
  DEFAULT:
    Flag as Critical: "Unknown status: {task_status}"
```

---

### IF/ELSE Statement

```markdown
If condition:
  Action()
Else if other_condition:
  OtherAction()
Else:
  DefaultAction()
```

**Usage**:
```markdown
If task_count == 0:
  Flag as Critical: "No tasks found for plan {plan_slug}"
Else if task_count > 100:
  Flag as Medium: "Large plan ({task_count} tasks) - consider splitting"
Else:
  CONTINUE
```

---

### FOR Loop

```markdown
FOR each item in collection:
  Process(item)
```

**Usage**:
```markdown
FOR each task in ready_tasks:
  issues = VerifyTask(task)
  If issues.critical_count > 0:
    Flag as Critical
```

---

### WHILE Loop

```markdown
WHILE condition:
  Action()
  Update condition
```

**Usage**:
```markdown
iteration = 1
WHILE iteration <= max_iterations AND has_critical_issues:
  issues = AuditPlan(plan_slug)
  If issues.critical_count == 0:
    has_critical_issues = false
  iteration = iteration + 1
```

---

### GOTO (State-Based Loops)

```markdown
LABEL: state_name
  Action()
  If continue_condition:
    GOTO state_name
  Else:
    GOTO next_state
```

**Usage**:
```markdown
LABEL: audit_iteration
  issues = AuditAllTasks(plan_slug)

  If issues.critical_count == 0:
    GOTO execution_phase

  If iteration >= max_iterations:
    RETURN "Failed to converge after {iteration} iterations"

  iteration = iteration + 1
  GOTO audit_iteration

LABEL: execution_phase
  ExecuteTasks(plan_slug)
  RETURN "Execution complete"
```

---

## Error Handling

**Purpose**: Standard patterns for handling failures

### TRY/CATCH Pattern

```markdown
TRY:
  result = Operation()
CATCH error:
  LOG "Operation failed: {error}"
  RETURN fallback_value
```

**Usage**:
```markdown
TRY:
  content = Read("PLAN.md")
CATCH error:
  LOG "Failed to read PLAN.md: {error}"
  RETURN "Please create PLAN.md first"
```

---

### Guard Clause Pattern

```markdown
If invalid_condition:
  RETURN early_exit_value
```

**Usage**:
```markdown
# Guard: Verify plan exists
plan_result = Bash("gg plan show {plan_slug}")
If plan_result contains "not found":
  RETURN "Error: Plan '{plan_slug}' does not exist"

# Guard: Verify tasks exist
tasks = Bash("gg task ls --plan {plan_slug}")
If task_count == 0:
  RETURN "Error: No tasks found for plan '{plan_slug}'"

# Main logic continues here
```

---

### Soft Failure (LOG and CONTINUE)

```markdown
TRY:
  result = NonCriticalOperation()
CATCH error:
  LOG "Warning: {operation} failed: {error}"
  CONTINUE  # Don't abort entire process
```

**Usage**:
```markdown
FOR each file_path in task_files:
  TRY:
    content = Read(file_path)
    VerifyContent(content)
  CATCH error:
    LOG "Warning: Could not verify {file_path}: {error}"
    CONTINUE  # Process remaining files
```

---

## Variable Naming

**Purpose**: Consistent variable naming conventions

### Template Variables

```markdown
{{arg_name}}       # User-provided argument
{{plan_slug}}      # Replaced at runtime
{{task_id}}        # Replaced at runtime
```

**Usage**:
```markdown
1. plan_slug = {{arg_name}}  # From user input
2. content = Read("plans/{plan_slug}.md")
```

---

### Count Suffixes

```markdown
task_count         # Number of tasks
file_count         # Number of files
critical_count     # Number of critical issues
iteration_count    # Number of iterations
```

**Usage**:
```markdown
critical_count = 0
FOR each issue in issues:
  If issue.severity == "Critical":
    critical_count = critical_count + 1

If critical_count > 0:
  RETURN "Found {critical_count} critical issues"
```

---

### List Suffixes

```markdown
task_list          # List of tasks
file_list          # List of files
issue_list         # List of issues
ready_tasks        # List of ready tasks
```

**Usage**:
```markdown
ready_tasks = Bash("gg ready --plan {plan_slug}")
FOR each task_id in ready_tasks:
  Process(task_id)
```

---

### Boolean Flags

```markdown
has_critical_issues    # Boolean flag
is_valid               # Boolean flag
compilation_failed     # Boolean flag
should_continue        # Boolean flag
```

**Usage**:
```markdown
has_critical_issues = false
FOR each issue in issues:
  If issue.severity == "Critical":
    has_critical_issues = true
    BREAK

If has_critical_issues:
  RETURN "Cannot proceed with critical issues"
```

---

## Limits

- Max iterations for convergence loops: 5
- Max subagent spawns per command: 10
- Max files to process in batch: 50

**Rationale**: Prevent runaway loops, manage computational cost.

---

## Integration Pattern

```markdown
### Standard Command Structure

1. Read shared modules:
   ```
   Read(".claude/commands/_shared/control-flow.md")
   Read(".claude/commands/_shared/file-verification.md")
   ```

2. Parse arguments:
   ```
   plan_slug = {{arg_name}}
   ```

3. Guard clauses (early exits):
   ```
   If not ValidateInput(plan_slug):
     RETURN "Invalid input"
   ```

4. Main logic with explicit control flow:
   ```
   LABEL: main_loop
     result = ProcessBatch()
     If result.should_continue:
       GOTO main_loop
     Else:
       GOTO finish

   LABEL: finish
     RETURN "Complete"
   ```

5. Error handling throughout:
   ```
   TRY:
     Operation()
   CATCH error:
     LOG "Error: {error}"
     RETURN fallback
   ```
```

---

## Example: Complete Command Flow

```markdown
### Command: /gg-task-audit

**Input**: plan_slug = "tiger-refactor"

**Flow**:

1. # Parse input
   plan_slug = {{arg_name}}

2. # Guard: Verify plan exists
   plan_check = Bash("gg plan show {plan_slug}")
   If plan_check contains "not found":
     RETURN "Error: Plan '{plan_slug}' does not exist"

3. # Get tasks
   task_list = Bash("gg task ls --plan {plan_slug}")
   If task_list.count == 0:
     RETURN "Error: No tasks found"

4. # Audit loop with convergence
   iteration = 1
   max_iterations = 5

   LABEL: audit_iteration
     issues = AuditAllTasks(task_list)

     # Check convergence
     If issues.critical_count == 0 AND issues.high_count == 0:
       RETURN "All tasks approved (no Critical/High issues)"

     # Check iteration limit
     If iteration >= max_iterations:
       RETURN "Failed to converge after {iteration} iterations"

     # Refine tasks
     FOR each task_id in task_list:
       TRY:
         task_issues = FilterIssues(issues, task_id)
         If task_issues.count > 0:
           RefinedTask(task_id, task_issues)
       CATCH error:
         LOG "Warning: Could not refine {task_id}: {error}"
         CONTINUE

     iteration = iteration + 1
     GOTO audit_iteration

5. # Success (unreachable if loop doesn't converge)
   RETURN "Audit complete"
```

---

## Notes

- **Explicit over implicit**: Always use function-call syntax for tool invocations
- **Prose is ambiguous**: "Read the file" → `content = Read("file.txt")`
- **Structured control flow**: Use CASE/IF/FOR/WHILE/GOTO for clarity
- **Error handling required**: Use TRY/CATCH or guard clauses for all operations
- **Variable naming matters**: Use consistent suffixes (_count, _list, _flag)

This module ensures commands are **executable pseudocode** rather than prose descriptions.
