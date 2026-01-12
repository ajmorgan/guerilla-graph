Slash Commands Audit Report

  As an expert on Claude Code execution mechanics, I've analyzed the .claude/commands/ directory against BOOK.md's documented patterns. Here's my comprehensive assessment.

  Executive Summary

  Overall Quality: ★★★★☆ (4/5)

  The command suite is well-architected with solid modular design, proper parallel execution patterns, and thoughtful quality gates. The separation into _shared/ modules and _prompts/ templates is excellent. Several issues require attention, mostly around tool invocation accuracy and edge case handling.

  ---
  Architecture Assessment

  Strengths

  1. DRY Compliance - Single source of truth for quality criteria, fix patterns, and file verification
  2. Correct Parallel Spawning Pattern - control-flow.md correctly documents that multiple Task calls must appear in ONE message
  3. Iterative Convergence Model - Plan/task audits have dual exit criteria (content unchanged OR quality threshold)
  4. Compilation Gates - gg-execute properly blocks task completion until build passes
  5. File-Level Serialization - dependency-analysis.md correctly prevents concurrent file modifications
  6. User Control Points - auto-fix/auto-continue preferences throughout audit commands

  Module Dependencies (Clean DAG)

  gg-plan-gen ──→ project-context.md
             └──→ explore-codebase.md
             └──→ planning-checklist.md

  gg-plan-audit ─→ audit-plan.md
               └─→ fix-patterns.md
               └─→ json-parsing.md

  gg-task-gen ───→ quality-criteria.md
             └───→ task-template.md
             └───→ dependency-analysis.md
             └───→ file-verification.md
             └───→ code-verification.md

  gg-task-audit ─→ audit-task.md
               └─→ fix-patterns.md
               └─→ json-parsing.md
               └─→ quality-criteria.md

  gg-execute ────→ project-context.md
             └───→ dependency-analysis.md
             └───→ implement-task.md
             └───→ review-work.md

  ---
  Critical Issues

  Issue 1: AskUser Pseudocode vs Real Tool Syntax

  Location: Multiple commands (gg-plan-audit.md:45-50, gg-task-audit.md:97-101, gg-execute.md:49-52)

  Problem: Commands use Ask("Ready to start audit?") but Claude Code's AskUserQuestion requires structured format with questions array, options, and header.

  Current:
  user_confirmed = Ask("Ready to start audit?")
  auto_fix = Ask("Auto-apply fixes? (yes/no)")

  Should be:
  Use AskUserQuestion tool with:
    questions: [{
      question: "Ready to start audit?",
      header: "Confirm",
      options: [{label: "Yes"}, {label: "No"}]
    }]

  Severity: High - Commands may stall if Claude interprets this as prose rather than tool call.

  ---
  Issue 2: FormatPrompt is Not a Real Operation

  Location: control-flow.md:210-241

  Problem: FormatPrompt(template, variables) is defined as a conceptual operation but isn't a Claude Code tool. Claude must perform string interpolation mentally, which works, but the documentation implies it's a callable function.

  Recommendation: Clarify this is a mental operation, not a tool invocation. Example:

  **FormatPrompt** (mental operation, not tool):
  Replace {{variable}} placeholders in template with actual values before passing to Task.

  ---
  Issue 3: Cycle Detection Algorithm Has Direction Bug

  Location: dependency-analysis.md:140-191

  Problem: The algorithm adds the proposed edge then runs DFS to check "if blocks_on_id is reachable from task_id". This is backwards.

  If task A blocks_on task B, then B must complete before A. A cycle exists if B can reach A through existing edges. The algorithm checks the wrong direction.

  Current (line 183):
  is_cycle = DFS(task_id)  # Starts from task_id

  Should be:
  is_cycle = DFS(blocks_on_id)  # Start from blocker, check if task_id is reachable

  Severity: Critical - Incorrect cycle detection could allow circular dependencies.

  ---
  Issue 4: audit-task.md Assumes Loaded Modules

  Location: _prompts/audit-task.md:17-24

  Problem:
  ## Shared Modules (Already Loaded)

  The orchestrator has loaded:
  - quality-criteria.md: 5 quality dimensions

  If an agent is spawned without orchestrator context, these modules aren't loaded. The prompt should either:
  1. Inline the critical criteria, or
  2. Include explicit Read() instructions

  ---
  Medium Issues

  Issue 5: planning-checklist.md is Domain-Specific

  Location: _shared/planning-checklist.md:70-88

  Problem: Contains Java/Spring-specific patterns (DataLoaders, @PreAuthorize, TestContainers) that don't apply to this Zig project.

  Recommendation: Make generic or split into language-specific checklists.

  ---
  Issue 6: fix-patterns.md Pattern G Doesn't Persist

  Location: _shared/fix-patterns.md:295-345

  Problem: Pattern G flags maintainability issues by inserting HTML comments into task descriptions:
  <!-- AUDIT FINDING: Maintainability concern -->

  These comments survive in the file but are confusing. Better approach: track flags in gg metadata or a separate field.

  ---
  Issue 7: gg-task-gen birthtime Command is Fragile

  Location: gg-task-gen.md:66

  Problem: Complex cross-platform birthtime detection:
  stat -f %B PLAN.md 2>/dev/null || { bt=$(stat -c %W PLAN.md 2>/dev/null); [ "$bt" != "0" ] && echo $bt || stat -c %Y PLAN.md; }

  This is overcomplicated and may fail on various systems. Consider:
  1. Just use mtime (more portable)
  2. Let user specify timestamp
  3. Use date +%s as fallback

  ---
  Issue 8: json-parsing.md Fallback is Brittle

  Location: _shared/json-parsing.md:50-79

  Problem: Fallback parsing searches for exact strings "Critical:", "High:", etc. But agents might use:
  - "Critical:"
  - "CRITICAL -"
  - "Severity: Critical"

  Recommendation: Add regex patterns for variations.

  ---
  Issue 9: Missing Agent Isolation in Parallel Execution

  Location: gg-execute.md entire Step 4-5

  Problem: When parallel agents implement tasks simultaneously:
  1. They can't see each other's work
  2. File-level serialization prevents conflicts but agents may make incompatible design decisions
  3. Review in Step 5 only checks individual task completion, not cross-task coherence

  Recommendation: Add a "wave coherence check" before compilation that reviews all changes together.

  ---
  Low Issues

  Issue 10: Model Parameter Values Outdated

  Location: control-flow.md:63-65

  Problem: Shows model: "opus" but Claude Code uses specific version strings. The documentation says "omit the model parameter to inherit from parent (recommended)" which is correct - the explicit values shown are misleading.

  ---
  Issue 11: quality-criteria.md YAML Requirements Too Strict

  Location: _shared/quality-criteria.md:26-42

  Problem: Requires files array with full path/action/lines for every task. For simple tasks (e.g., "fix typo in README"), this is overkill.

  Recommendation: Make files array required only for complexity ≥ moderate.

  ---
  Issue 12: explore-codebase.md Variable Mismatch

  Location: _prompts/explore-codebase.md:5-8 vs gg-plan-gen.md:27

  Problem: explore-codebase.md expects {{feature_summary}}, {{language}}, {{architecture}} but gg-plan-gen's ExecuteExploration signature shows (prompt, feature, project). The variable binding isn't documented.

  ---
  Positive Highlights

  1. README.md - Excellent architecture summary with clear decision rationale
  2. Model Constraint Warning - "Do NOT use model: haiku" appears in critical commands (gg-task-audit, gg-execute)
  3. reflect.md - Meta-improvement command that analyzes conversations to refine commands
  4. control-flow.md Parallel Spawning Section - Clear explanation of why FOR loops are conceptual, not sequential
  5. task-template.md Examples - Good/Bad comparisons make quality standards concrete

  ---
  Recommendations Summary
  ┌──────────┬───────────────────────────┬─────────────────────────────────────────────────┐
  │ Priority │           Issue           │                     Action                      │
  ├──────────┼───────────────────────────┼─────────────────────────────────────────────────┤
  │ P0       │ Cycle detection bug       │ Fix DFS direction in dependency-analysis.md     │
  ├──────────┼───────────────────────────┼─────────────────────────────────────────────────┤
  │ P0       │ AskUser syntax            │ Update pseudocode to match AskUserQuestion tool │
  ├──────────┼───────────────────────────┼─────────────────────────────────────────────────┤
  │ P1       │ audit-task.md module deps │ Inline critical criteria or add Read()          │
  ├──────────┼───────────────────────────┼─────────────────────────────────────────────────┤
  │ P1       │ Agent isolation           │ Add wave coherence check                        │
  ├──────────┼───────────────────────────┼─────────────────────────────────────────────────┤
  │ P2       │ planning-checklist.md     │ Make language-agnostic                          │
  ├──────────┼───────────────────────────┼─────────────────────────────────────────────────┤
  │ P2       │ birthtime command         │ Simplify or use mtime                           │
  ├──────────┼───────────────────────────┼─────────────────────────────────────────────────┤
  │ P3       │ FormatPrompt clarity      │ Document as mental operation                    │
  ├──────────┼───────────────────────────┼─────────────────────────────────────────────────┤
  │ P3       │ json-parsing fallback     │ Add regex variations                            │
  └──────────┴───────────────────────────┴─────────────────────────────────────────────────┘
  ---
  Conclusion

  The command suite is production-ready with caveats. The P0 issues (cycle detection bug, AskUser syntax) should be fixed before heavy use. The architecture is sound and follows BOOK.md's principles well - hooks injection, iterative convergence, compilation gates, and parallel execution are all correctly implemented.
