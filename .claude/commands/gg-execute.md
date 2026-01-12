---
description: Execute gg plan with parallel agents and compilation gates
args:
  - name: plan
    description: Plan slug to execute (e.g., storage-5qp)
    required: true
  - name: plan_file
    description: Path to PLAN.md file for context (default PLAN.md)
    required: false
---

> **⚠️ AGENT MODEL CONSTRAINT**: Do NOT use `model: "haiku"` for subagents.
> Haiku makes mistakes with complex code, and quality is our first priority.
> Omit the `model` parameter to inherit from parent (recommended).

You are orchestrating parallel execution of plan **{{plan}}** using multiple sub-agents.

## Shared Modules (Read First)

Load these modules at start:
```
Read(".claude/commands/_shared/project-context.md")
Read(".claude/commands/_shared/dependency-analysis.md")
Read(".claude/commands/_prompts/implement-task.md")
Read(".claude/commands/_prompts/review-work.md")
```

Store operations: `LoadProjectConfig()`, `DetectVCSType()`, `ResetFiles()`, `DetectFileConflicts()`, agent prompt template, review template.

---

## Control Flow

```
Initialize:
  plan_slug = {{plan}}
  plan_file_path = "{{plan_file}}" or "PLAN.md"
  wave = 0
  max_waves = 10
  test_strategy = null  # Ask user once
  auto_continue = null  # Ask user once

Step 0: Setup (ONCE)
  project = LoadProjectConfig()  # From project-context.md
  vcs = DetectVCSType()           # From project-context.md
  plan_context = Read(plan_file_path)  # Load PLAN.md for context
  ValidatePlan(plan_slug)
  ShowPlanSummary()
  user_confirmed = Ask("Ready?")
  IF NOT user_confirmed: EXIT
  test_strategy = Ask("Test strategy? (each-wave/end/never)")
  auto_continue = Ask("Auto-continue waves? (yes/no)")

Main Loop:
  wave += 1

  Step 1: Check wave limit
    IF wave > max_waves:
      Error: "Max waves reached"
      Report remaining tasks
      EXIT

  Step 2: Find ready work
    ready_tasks = Bash("gg ready {{plan}} --json").parse()
    IF ready_tasks.count == 0:
      all_complete = CheckAllComplete()
      IF all_complete:
        GOTO FinalReport
      ELSE:
        ShowBlockedTasks()
        Ask user how to proceed
        EXIT or retry

  Step 3: Check file conflicts (CRITICAL - Before spawning)
    conflicts = DetectFileConflicts(ready_tasks)  # From dependency-analysis.md
    IF conflicts exist:
      Report: "FILE CONFLICT: Multiple tasks modify same file"
      Options: "Auto-fix (add deps) / Skip conflicting / Abort"
      IF auto-fix:
        FOR each conflict: Bash("gg dep add {task2} --blocks-on {task1}")
        GOTO Step 2  # Re-fetch ready tasks
      IF skip:
        Remove conflicting tasks from ready_tasks
        Continue with remaining
      IF abort: EXIT

  Step 4: Spawn parallel agents (CRITICAL - Single message)
    Print "🌊 Wave {wave}: Spawning {count} agents..."
    FOR task IN ready_tasks:
      Bash("gg start {task.id}")

    # PARALLEL SPAWN - Single message with multiple Task calls
    FOR EACH task IN ready_tasks:
      task_json = Bash("gg show {task.id} --json")
      prompt = Format(implement-task.md, task_json)
      Task(
        subagent_type="general-purpose",
        description="Implement {task.id}",
        prompt=prompt
      )

    # Wait for ALL agents to complete
    agent_results = collect results

  Step 5: Review sub-agent work
    FOR each task, result:
      IF agent reported blockers:
        Stop, report to user, ask how to proceed

      # Verify task intent (use review-work.md template)
      expected_files = Extract from task "Where" section
      success_criteria = Extract from task "Validation" section

      Read modified files
      Verify changes match task's "How" section
      Check success criteria met

      Categorize:
        ✅ COMPLETE: Ready for compilation
        ⚠️ PARTIAL: Changes missing
        ❌ BLOCKED: Needs intervention

    IF any PARTIAL or BLOCKED:
      Stop, report issues
      Ask: "Fix manually / Re-run agent / Skip?"
      Handle response or EXIT

  Step 6: Compile and validate (CRITICAL - Gate before closing)
    Print "🔨 Compiling..."
    build_result = Bash(project.build_command)

    IF build_result FAILED:
      Show errors with file:line references
      Keep tasks as in_progress (DON'T close)

      Options:
        A) Fix manually - You correct, retry compile
        B) Retry agents - Reset files, spawn with error context
        C) Update tasks - Exit to /gg-task-audit
        D) Abort - Stop execution

      IF B (Retry agents):
        modified_files = Extract from this wave
        ResetFiles(modified_files, vcs.vcs_type)  # From project-context.md
        error_context = Build error summary
        GOTO Step 4 with enhanced prompts

      IF A, C, or D: Handle as described

    # Build passed - run tests if strategy requires
    IF test_strategy == "each-wave":
      test_result = Bash(project.test_command)
      IF test_result FAILED:
        Report failures, ask user how to proceed

  Step 7: Close completed tasks (CRITICAL - Main agent does this)
    # Only execute if compilation passed
    FOR task IN ready_tasks:
      Bash("gg complete {task.id}")

  Step 8: Check next wave
    Report wave results
    more_ready = Bash("gg ready {{plan}} --json").count

    IF more_ready > 0:
      IF auto_continue:
        Print "Continuing to Wave {wave+1}..."
        CONTINUE LOOP
      ELSE:
        user_continue = Ask("Continue?")
        IF user_continue: CONTINUE LOOP
        ELSE: GOTO PausedSummary
    ELSE:
      CONTINUE LOOP  # Will check completion in Step 2

FinalReport:
  Print summary (waves, tasks, files)
  Print VCS commands for commit/review
  EXIT

PausedSummary:
  Print paused state (completed, ready, blocked)
  Print "To resume: /gg-execute {{plan}}"
  EXIT
```

---

## Critical Mechanics

### 1. Parallel Agent Spawning

**MUST use SINGLE message with multiple Task calls.**

Ready task count = agent count = parallelism level.

```
# CORRECT: All Task calls in ONE assistant message (parallel)
FOR task IN [task1, task2, task3]:
  Task(subagent_type="general-purpose", prompt=...)
# ↑ Emit all Task calls simultaneously, not sequentially

# WRONG: Sequential messages (slow)
Task(...) → wait → Task(...) → wait → Task(...)
```

See `control-flow.md` "Parallel Agent Spawning" section for detailed explanation.

### 2. Compilation Gate

**NO task closes until build passes.**

If build fails:
- Keep ALL wave tasks as `in_progress`
- Ask user how to proceed
- Do NOT call `gg complete` until build succeeds

Main agent (you) calls `gg complete` after compilation gate passes.

### 3. File Conflict Detection

**BEFORE spawning agents each wave**, check if multiple ready tasks modify same file without dependency chain.

Use `DetectFileConflicts()` from dependency-analysis.md.

Resolution:
- Auto-fix: Add dependency chain (`gg dep add`)
- Skip: Remove conflicting tasks from current wave
- Abort: Stop execution

Only proceed if no unresolved conflicts.

### 4. Wave-Based Execution

Loop until all tasks complete:
1. Find ready tasks (DAG determines parallelism)
2. Check file conflicts
3. Spawn N agents in parallel
4. Review all agent work
5. Compile ONCE for entire wave
6. Close ALL tasks (if build passes)
7. Repeat

Each wave is atomic - all tasks succeed or all stay in_progress.

---

## Agent Prompt Template

Use `implement-task.md` with variables:
- `{{task_id}}` - From gg show
- `{{title}}` - From gg show
- `{{description}}` - Full YAML + markdown from gg show

Agent returns Implementation Summary with:
- Files modified/created
- Changes made
- Success criteria verified
- Issues/blockers
- Ready for compilation (YES/NO)

---

## Review Template

Use `review-work.md` with variables:
- `{{task_id}}` - Task being reviewed
- `{{expected_files}}` - From task's "Where" section
- `{{success_criteria}}` - From task's "Validation" section

Review returns:
- Files checked (✅ / ⚠️ / ❌)
- Success criteria status
- Overall: COMPLETE / PARTIAL / BLOCKED
- Recommendation: Proceed / Fix / Re-run

---

## Inline Algorithms

Command-specific operations not defined in shared modules:

### ValidatePlan(plan_slug)
```
result = Bash("gg show {plan_slug} --json")
If result contains "not found" or error:
  Error: "Plan '{plan_slug}' does not exist"
  Suggest: "Run `gg plan ls` to see available plans"
  EXIT
Return parsed plan info
```

### ShowPlanSummary()
```
Print:
  "📋 Executing Plan: {plan_slug}"
  "  - Title: {plan.title}"
  "  - Tasks: {total_count} total, {open_count} open, {completed_count} completed"
  "  - Ready: {ready_count} (parallelism level)"
```

### CheckAllComplete()
```
tasks = Bash("gg task ls --plan {plan_slug} --json")
For each task in tasks:
  If task.status != "completed":
    Return false
Return true
```

### ShowBlockedTasks()
```
blocked = Bash("gg blocked --plan {plan_slug} --json")
Print: "⚠️ Blocked tasks:"
For each task in blocked:
  blockers = Bash("gg dep blockers {task.id} --json")
  Print: "  - {task.id}: blocked by {blockers}"
```

### Format(template, task_json)
```
variables = {
  "task_id": task_json.id,
  "title": task_json.title,
  "description": task_json.description
}
Return FormatPrompt(template, variables)
```

### BuildErrorContext(build_result)
```
Purpose: Extract structured error information for agent retry prompts

Input: build_result (output from failed compilation)
Output: error_context object with structured errors

Algorithm:
1. Parse build output for error patterns:
   - Zig: "error: " followed by message, then "src/file.zig:line:col"
   - Java: "error: " at "File.java:line"
   - Generic: Lines containing "error" or "Error"

2. Extract file:line references:
   errors = []
   For each error_line in build_result:
     If matches pattern "{file}:{line}":
       error = {
         file: extracted_file,
         line: extracted_line,
         message: error_message,
         context: surrounding_lines
       }
       Add error to errors

3. Group by file:
   file_errors = {}
   For each error in errors:
     If error.file not in file_errors:
       file_errors[error.file] = []
     Add error to file_errors[error.file]

4. Build context string:
   context = "Build failed with {len(errors)} errors:\n"
   For each file, errs in file_errors:
     context += "\n{file}:\n"
     For each err in errs:
       context += "  - Line {err.line}: {err.message}\n"

5. Return {
     error_count: len(errors),
     file_count: len(file_errors),
     errors: errors,
     summary: context,
     raw_output: build_result (truncated to 2000 chars)
   }

Usage in retry prompt:
  "Previous attempt failed with build errors:
   {error_context.summary}

   Please fix these specific issues in your implementation."
```

---

## Error Handling

**Plan not found**: Error, suggest `gg plan list`, EXIT

**No ready tasks (open tasks remain)**: Show blockers, ask "Resolve/Exit"

**Agent fails**: Keep task in_progress, ask "Retry/Skip/Abort"

**Compilation fails**: Keep wave in_progress, offer Fix/Retry/Update/Abort

**Tests fail**: Keep in_progress, ask user

**Max waves reached**: Report remaining tasks, suggest circular dependency check, EXIT

---

## Recovery from Failed States

When execution fails or is interrupted, use these commands to recover:

### Check Current State
```bash
# See what's in progress (may need attention)
gg task ls --status in_progress --plan {plan}

# See what's still open
gg task ls --status open --plan {plan}

# See overall plan state
gg show {plan}
```

### Recovery Options

**Option A: Reset and Retry**
```bash
# Reset in_progress tasks back to open
gg update {task_id} --status open

# Reset file changes (if VCS available)
jj restore {files}  # or: git checkout {files}

# Resume execution
/gg-execute {plan}
```

**Option B: Skip Failed Tasks**
```bash
# Mark problematic task as completed (skip it)
gg complete {task_id}

# Continue with remaining work
/gg-execute {plan}
```

**Option C: Manual Fix**
```bash
# Fix the issue manually in your editor
# Then mark task complete
gg complete {task_id}

# Resume execution
/gg-execute {plan}
```

**Option D: Abandon Wave, Start Fresh**
```bash
# Reset ALL in_progress tasks
gg task ls --status in_progress --plan {plan} --json | \
  jq -r '.tasks[].id' | \
  xargs -I {} gg update {} --status open

# Discard all uncommitted changes
jj restore  # or: git checkout .

# Start over
/gg-execute {plan}
```

### Common Failure Scenarios

| Scenario | Symptoms | Recovery |
|----------|----------|----------|
| Compilation failed | Build errors after wave | Fix errors manually, retry compile, then close tasks |
| Agent timeout | Some agents didn't respond | Reset those tasks, re-run execution |
| Partial completion | Some tasks done, others stuck | Check blockers with `gg dep blockers`, resolve |
| Circular dependency | Max waves with tasks remaining | Check DAG with `gg doctor`, fix dependencies |
| File conflict | Merge conflicts in files | Resolve conflicts, reset affected tasks |

---

## Output Formats

**Initial**: Plan summary, task counts, wave preview, user preferences
**Wave**: Tasks completed, files changed, compilation/test status, progress
**Final**: Total tasks/waves, files modified, VCS commands (jj/git diff, commit)
**Paused**: Progress, ready/blocked counts, resume command

---

## Safety & Constraints

**Safety**: File conflict detection, max 10 waves, compilation gate, user checkpoints, VCS check

**Constraints**: SINGLE message parallel spawning, file conflict check before each wave, compilation gate MUST pass before closing tasks, main agent closes tasks, user collaboration when needed
