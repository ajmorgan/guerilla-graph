---
description: Audit gg plan iteratively until quality standards met
args:
  - name: plan
    description: Plan slug to audit (e.g., schema-migration, auth-system)
    required: true
  - name: plan_file
    description: Path to PLAN.md file containing plan goals and architecture (default PLAN.md)
    required: false
---

> **⚠️ AGENT MODEL CONSTRAINT**: Do NOT use `model: "haiku"` for subagents.
> Haiku makes mistakes with complex code, and quality is our first priority.
> Omit the `model` parameter to inherit from parent (recommended).

You are iteratively auditing a gg plan for quality using parallel agents.

**OPERATION MODE** (configured in Step 0):
- User chooses auto-fix (yes/no) and auto-continue (yes/no)
- If both "yes": Fully autonomous (original behavior)
- If "no" to either: Pause for user input at relevant steps
- ✅ Generate final report when converged or max iterations reached
- ❌ DO NOT break loop except: convergence, max iterations, agent failure, user pause

**OUTPUT**: Brief iteration summaries (1-2 lines). Detailed report at end only.

## Task

Audit plan **{{plan}}** against **{{plan_file}}** context. Max 5 iterations.

**Convergence**: Exit when 0 Critical, 0 High, ≤2 Medium issues OR no changes between iterations.

---

## Preparation: Load Shared Modules

**FIRST STEP** (before iteration 1):

Read and store in working memory:
```
.claude/commands/_shared/quality-criteria.md
.claude/commands/_shared/code-verification.md
.claude/commands/_shared/file-verification.md
.claude/commands/_shared/dependency-analysis.md
```

Purpose: Consistent quality standards across all audit agents.

---

## Control Flow

```
Initialize:
  plan_slug = "{{plan}}"
  plan_file_path = "{{plan_file}}" or "PLAN.md"
  iteration = 0
  max_iterations = 5
  previous_task_states = ""
  auto_continue = null
  auto_fix = null

Step 0: Setup and Extract Plan Context (REQUIRED)
  # Validate plan file exists
  plan_content = Read(plan_file_path)

  If file not found:
    ERROR: "Plan file not found: {plan_file_path}"
    EXIT

  Extract sections (## Goals, ## Non-Goals, ## Architecture, ## Breaking Changes):
    - Search for markdown headers with regex: ^##\s+(Goal|Goals)\s*$
    - Capture lines until next ## header
    - Store: plan_goals, plan_non_goals, architecture_overview, breaking_changes
    - If Goals AND Non-Goals both empty: WARN but continue

  # Validate plan exists and has tasks
  plan_info = Bash("gg show {plan_slug} --json")
  IF plan_info is ERROR:
    ERROR: "Plan not found: {plan_slug}"
    Suggest: "Run `gg plan ls` to see available plans"
    EXIT

  task_count = plan_info.tasks.length
  IF task_count == 0:
    ERROR: "Plan has no tasks"
    Suggest: "Run `/gg-task-gen {plan_file_path}` first"
    EXIT

  # Show plan summary
  Print "📋 Task Audit: {plan_slug}"
  Print "  - Plan file: {plan_file_path}"
  Print "  - Tasks: {task_count}"
  Print "  - Max iterations: 5"

  # User preferences
  user_confirmed = Ask("Ready to start audit?")
  IF NOT user_confirmed: EXIT

  auto_fix = Ask("Auto-apply fixes? (yes/no)")
  auto_continue = Ask("Auto-continue iterations? (yes/no)")

LOOP while iteration < max_iterations:
  iteration += 1

  Step 1: Fetch All Tasks
    Execute: gg show {{plan}} --json
    Parse JSON: extract tasks array, task_ids

    Validation:
      - Verify plan exists
      - Verify tasks.length >= 1
      - If no tasks: ERROR "Plan has no tasks", EXIT

  Step 2: Check Convergence (skip iteration 1)
    If iteration > 1:
      current_task_states = SerializeTaskStates(tasks)
        # Format: task_id|description|dependencies for each task (sorted by id)

      If current_task_states == previous_task_states:
        Print: "✅ Converged (no changes)"
        BREAK LOOP

  Step 3: Launch Parallel Audit Agents (CRITICAL)
    Print: "🔍 Iteration {iteration}/{max_iterations}: Auditing {count} tasks..."

    # ⚠️ CRITICAL: ONE AGENT PER TASK
    # DO NOT bundle multiple tasks into a single agent - this blows context windows!
    # Each task gets its own dedicated agent with focused context.
    #
    # ✅ Correct:  23 tasks → 23 agents (one per task)
    # ❌ Wrong:    23 tasks → 4 agents (bundled 5-6 tasks each)

    # PARALLEL EXECUTION: Emit ALL Task calls in ONE assistant message
    For EACH task in tasks:
      prompt = Read(".claude/commands/_prompts/audit-task.md")
      Fill template variables:
        {{plan_file}}, {{plan_goals}}, {{plan_non_goals}},
        {{architecture_overview}}, {{breaking_changes}},
        {{task_id}}, {{title}}, {{full_description}}

      Task(subagent_type="general-purpose", prompt=prompt)

    # Launch pattern: Single message → [Task1, Task2, Task3, ...TaskN] → parallel execution
    # See control-flow.md "Parallel Agent Spawning" for details
    #
    # Correct:  Single message with N Task tool calls (one per task)
    # Incorrect: Message1 → Task1 → wait → Message2 → Task2 → wait (sequential)
    # Incorrect: Bundling multiple tasks into fewer agents (context overflow)

    Wait for ALL agent responses → audit_results array

  Step 4: Collect Agent Results
    failed_agents = []
    successful_results = []

    For each result:
      If agent failed:
        failed_agents.append({task_id, error})
        Print: "⚠️ Agent failed for {task_id}: {error}"
      Else:
        successful_results.append(result)

    If len(failed_agents) > 0:
      Print: "⚠️ {len(failed_agents)} of {total} agents failed"
      # Continue with successful results - don't abort

    If len(successful_results) == 0:
      Print: "❌ All agents failed - cannot continue"
      BREAK LOOP

  Step 5: Parse and Analyze Results (successful_results only)
    For each agent_result:
      # Use json-parsing.md module for parsing logic
      Extract JSON between ```json and ```
      Parse: task_id, status, findings, summary

      If JSON parsing fails:
        Log: "⚠️ Failed to parse JSON for task {task_id}"
        Use fallback parsing (search "Critical: N", "High: N" in prose)

    Aggregate findings:
      critical_findings = all findings with severity="Critical"
      high_findings = all findings with severity="High"
      medium_findings = all findings with severity="Medium"
      low_findings = all findings with severity="Low"

    Count totals: critical_count, high_count, medium_count, low_count

  Step 6: Report Iteration (BRIEF)
    Print: "Iteration {iteration}/{max_iterations}: {pass_count} PASS, {needs_work_count} NEEDS_WORK | Critical: {critical_count}, High: {high_count}, Medium: {medium_count}"

    DO NOT print detailed issues (save for final report)

  Step 7: Check Quality Threshold (CONVERGENCE)
    If critical_count == 0 AND high_count == 0 AND medium_count <= 2:
      Print: "✅ Converged (quality threshold)"
      BREAK LOOP

    If iteration >= max_iterations:
      Print: "⚠️ Max iterations reached"
      BREAK LOOP

  Step 8: Apply Fixes
    Save state: previous_task_states = current_task_states
    Group findings by task_id → task_fixes map

    IF auto_fix:
      Print: "🔧 Applying {critical_count + high_count} fixes..."

      For each task_id in task_fixes:
        # Use fix-patterns.md module for fix application logic
        Apply fixes based on finding.category:
          - FullContext: Add missing YAML/sections/file paths
          - Implementability: Replace vague instructions with specific steps
          - Maintainability: Flag workarounds, suggest clean solutions
          - Correctness: Fix line numbers, verify file paths
          - Dependencies: Add missing dependencies (gg dep add)

        Write updated description to temp file
        Execute: gg update {task_id} --description-file {temp_file} --json

        If update fails:
          Log: "⚠️ Failed to update task {task_id}: {error}"
          Continue (don't stop entire process)

      Print: "✅ Tasks updated"

    ELSE:
      Print: "⏸️ Fixes available but auto-fix disabled"
      Print: "Tasks with issues:"
      For each task_id in task_fixes:
        Print: "  - {task_id}: {count} issues"
      user_fix = Ask("Apply fixes now? (yes/no)")
      IF user_fix:
        For each task_id in task_fixes:
          Apply fixes as above
        Print: "✅ Tasks updated"
      ELSE:
        Print: "Skipping fixes..."

  Step 9: Check Continuation
    IF NOT auto_continue:
      user_continue = Ask("Continue to next iteration?")
      IF NOT user_continue:
        Print: "⏸️ Paused by user"
        BREAK LOOP

    Print: "→ Continuing to iteration {iteration+1}...\n"

END LOOP

Step 10: Generate Final Report
  (See Final Report Template below)
```

---

## Agent Prompt Template

Stored in `.claude/commands/_prompts/audit-task.md` with variables:

```markdown
You are auditing task {{task_id}} for quality.

## Plan Context (from {{plan_file}})
**Goals**: {{plan_goals}}
**Non-Goals**: {{plan_non_goals}}
**Architecture**: {{architecture_overview}}
**Breaking Changes**: {{breaking_changes}}

## Task Details
**ID**: {{task_id}}
**Title**: {{title}}
**Description**: {{full_description}}

## Your Task
Audit against quality-criteria.md and REPORT issues. DO NOT fix.

**Quality Criteria**: Full Context, Implementability, Maintainability, Correctness, Dependencies
**Code Verification**: engineering_principles.md checks (≤70 lines, types, defer, naming)
**File Verification**: VerifyFileExists, VerifyLineNumber, DetectOldSchemaMarkers

**MUST return JSON**:
{
  "task_id": "{{task_id}}",
  "status": "PASS|NEEDS_WORK",
  "findings": [{"severity": "Critical|High|Medium|Low", "category": "...", "issue": "...", "recommendation": "..."}],
  "summary": {"critical": 0, "high": 0, "medium": 0, "low": 0}
}
```

---

## Fix Application Patterns

Reference `.claude/commands/_shared/fix-patterns.md` for detailed patterns:

**Dispatcher** (use category to route):
- FullContext → Add missing sections/file paths/code snippets
- Implementability → Replace vague terms with specific instructions
- Maintainability → Flag workarounds with comments
- Correctness → Fix line numbers, verify paths
- Dependencies → Execute `gg dep add` commands

**Example patterns**:
- Missing file path → Add to ## Where section
- Incorrect line number → Search/replace in description
- Missing code snippet → Read file, extract context, insert into ## How
- Vague instruction → Replace with explicit steps from recommendation
- Missing dependency → Execute `gg dep add {task} --blocks-on {blocker}`
- File conflict → Create dependency chain for serialization

**Error handling**:
- Cycle detection → Skip dependency, log warning
- Update failure → Log error, continue with next task
- Agent failure → Stop iteration, report partial results

---

## Final Report Template

```markdown
# Task Audit Complete - Plan: {{plan}}

## Summary
- Total iterations: {iteration}
- Exit reason: {"Converged" | "Max iterations (5)" | "Agent failure"}
- Final quality: {"Excellent" | "Good" | "Needs manual review"}

## Audit History
### Iteration {N}
**Audit Results**: PASS: {pass_count}, NEEDS_WORK: {needs_work_count}
**Findings**: Critical: {critical_count}, High: {high_count}, Medium: {medium_count}, Low: {low_count}
**Category Breakdown**: FullContext: {n}, Implementability: {n}, Maintainability: {n}, Correctness: {n}, Dependencies: {n}

{If critical/high issues fixed:}
**Issues Fixed**: [task_id]: [issue] → Fix: [recommendation]

---

## Final State
**Tasks**: Total: {total_count}, Passing: {pass_count}, Needs work: {needs_work_count}

**Remaining Issues** (Medium/Low):
{For each medium/low finding:}
- {task_id}: {issue} (Severity: {severity})
  Recommendation: {recommendation}

**Files Verified**: {unique_file_count} total, {exists_count} existing, {not_found_count} not found

---

## Quality Assessment

{If critical_count == 0 AND high_count == 0:}
✅ **Ready for Implementation!**

All tasks have:
- ✅ Verified file paths and line numbers
- ✅ Clear step-by-step instructions with code examples
- ✅ Proper rationale and design decisions
- ✅ Correct dependency relationships
- ✅ Alignment with Goals/Non-Goals

**Next Steps**:
1. Review: `gg show {{plan}} --json`
2. Check ready: `gg ready --json`
3. Execute: `/gg-execute {{plan}}`

{Else:}
⚠️ **Needs Manual Review**

**Blocking Issues**: {critical_count} Critical, {high_count} High

{For each remaining critical/high:}
- {task_id}: {issue}
  Severity: {severity}
  Recommendation: {recommendation}
  Why not fixed: {reason}

**Recommendations**:
- Address Critical issues manually
- Re-audit if needed: `/gg-task-audit {{plan}} {{plan_file}}`
- Or proceed with caution: `/gg-execute {{plan}}`

---

## Execution Readiness

**Parallel Execution Waves**:
Wave 1 (ready immediately): {list of task IDs with no blockers}
Wave 2 (after Wave 1): {list of task IDs blocked by Wave 1}
[... continue for all waves ...]

**Parallelism**: Wave 1: {count} tasks parallel, Total waves: {wave_count}

---

## Audit Statistics
- Task descriptions updated: {task_update_count}
- Dependencies added: {dependency_add_count}
- Total agent invocations: {total_agent_count}
- Agent success rate: {successful_count}/{total_count}
- JSON parsing success rate: {json_success_rate}%
- Iterations: {iteration}

{If failed_agents not empty:}
**Failed Agents** (can retry individually):
{For each failed: - {task_id}: {error}}
```

---

## Error Handling

**Plan not found**: Suggest `gg plan ls`, EXIT
**PLAN.md not found**: Error "File not found: {path}", EXIT (required)
**Plan has no tasks**: Suggest `/gg-task-gen`, EXIT
**Partial agent failures**: Continue with successful results, report failures in final summary
**All agents failed**: EXIT (cannot continue without any results)
**JSON parse failure**: Use fallback parsing (see json-parsing.md)
**Task update failure**: Log error, continue with other tasks
**Dependency cycle**: Skip dependency, log warning
**Max iterations**: Generate final report with remaining issues

---

## Important Constraints

1. **PLAN.md REQUIRED**: Command will not execute without it
2. **User setup required**: Must confirm ready, choose auto-fix and auto-continue preferences
3. **⚠️ ONE AGENT PER TASK**: Never bundle multiple tasks into a single agent (blows context window)
4. **Parallel agent launches in SINGLE message**: N tasks = N Task tool calls in one message
5. **Sequential iterations**: Complete iteration fully before next
6. **Centralized updates**: Main orchestrator makes ALL task updates (agents only report)
7. **Max 5 iterations**: Hard stop to prevent infinite loops
8. **Convergence checks**: Content-based (task states unchanged) AND quality-based (0 Critical, 0 High, ≤2 Medium)
9. **Error tolerance**: Individual fix failures don't stop entire process
10. **User pause**: Respects auto-continue=no preference (pauses between iterations)

