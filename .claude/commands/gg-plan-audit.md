---
description: Iteratively audit and refine PLAN.md for maintainability and implementability
args:
  - name: plan_file
    description: Path to plan file (default PLAN.md)
    required: false
---

## Task

Audit **{{plan_file}}** (default: PLAN.md) iteratively. Max 5 iterations until converged.

**Convergence criteria** (exit when ANY met):
1. **Content unchanged**: plan_content == previous_content
2. **Quality threshold**: 0 Critical, 0 High issues (gate only)
3. **Max iterations**: 5

**Fix scope**: ALL severities each iteration. Gate controls iteration, not what gets fixed.

## Control Flow

```
Initialize:
  plan_path = {{plan_file}} or "PLAN.md"
  audit_prompt = Read(".claude/commands/_prompts/audit-plan.md")
  iteration = 0
  max_iterations = 5
  previous_content = null
  auto_continue = null
  auto_fix = null

Step 0: Setup (ONCE)
  # Validate plan file exists
  plan_content = Read(plan_path)
  IF plan_content is ERROR:
    Error: "Plan file not found: {plan_path}"
    Suggest: "Run /gg-plan-gen first"
    EXIT

  # Show plan summary
  Print "📋 Plan Audit: {plan_path}"
  Print "  - Sections: {count headers}"
  Print "  - Phases: {count ## Phase}"
  Print "  - Max iterations: 5"

  # User preferences
  user_confirmed = Ask("Ready to start audit?")
  IF NOT user_confirmed: EXIT

  auto_fix = Ask("Auto-apply fixes? (yes/no)")
  auto_continue = Ask("Auto-continue iterations? (yes/no)")

MainLoop:
  iteration += 1

  IF iteration > max_iterations:
    Print "⚠️ Max iterations reached"
    GOTO FinalReport

  plan_content = Read(plan_path)

  # CONVERGENCE CHECK (content-based)
  IF previous_content != null AND plan_content == previous_content:
    Print "✅ Converged (no changes)"
    GOTO FinalReport

  Print "🔍 Iteration {iteration}/5: Launching audit agent..."

  # Single agent audit (NOT parallel - PLAN.md is one document)
  prompt = FormatPrompt(audit_prompt, plan_path, plan_content)
  result = Task(subagent_type="general-purpose", prompt=prompt)

  IF result is ERROR:
    Print "❌ Agent failed"
    GOTO FinalReport

  findings = ParseAuditResult(result)  # See .claude/commands/_shared/json-parsing.md

  Print "Iteration {iteration}/5: {findings.critical} Critical, {findings.high} High, {findings.medium} Medium, {findings.low} Low"

  # CONVERGENCE CHECK (quality-based)
  IF findings.critical == 0 AND findings.high == 0:
    Print "✅ Converged (quality threshold)"
    GOTO FinalReport

  # Apply fixes
  previous_content = plan_content

  IF auto_fix:
    Print "🔧 Fixing all {len(findings)} issues..."
    FOR finding IN findings:  # Fix ALL severities
      plan_content = ApplyFix(finding, plan_content, plan_path)  # See .claude/commands/_shared/fix-patterns.md
    Write(plan_path, plan_content)
  ELSE:
    Print "⏸️ Fixes available but auto-fix disabled"
    Print "Issues to address:"
    FOR finding IN findings:  # Show ALL severities
      Print "  - [{finding.severity}] {finding.issue}"
    user_fix = Ask("Apply fixes now? (yes/no)")
    IF user_fix:
      FOR finding IN findings:  # Fix ALL severities
        plan_content = ApplyFix(finding, plan_content, plan_path)
      Write(plan_path, plan_content)
    ELSE:
      Print "Skipping fixes, continuing to next iteration..."

  # Check if user wants to continue
  IF NOT auto_continue:
    user_continue = Ask("Continue to next iteration?")
    IF NOT user_continue:
      Print "⏸️ Paused by user"
      GOTO FinalReport

  GOTO MainLoop

FinalReport:
  GenerateReport(iteration, findings, exit_reason)
```

## Key Differences from Task-Audit

| Aspect | plan-audit | task-audit |
|--------|------------|------------|
| Target | Single PLAN.md | Multiple task descriptions |
| Agents | **1 per iteration** | N per iteration (parallel) |
| Fixes | PLAN.md directly | Each task via `gg update` |

## Shared Module References

### ParseAuditResult
See `.claude/commands/_shared/json-parsing.md` for JSON extraction and fallback parsing.

### ApplyFix
See `.claude/commands/_shared/fix-patterns.md` for fix patterns:
- Pattern A: Incorrect line numbers
- Pattern B: Missing pattern references
- Pattern C: Phase too complex (split)
- Pattern D: Missing success criteria

### Audit Prompt
See `.claude/commands/_prompts/audit-plan.md` for full agent prompt with quality criteria:
- Maintainability (phase size, line numbers, pattern verification)
- Implementability (independence, function signatures, error cases)
- Missing elements (affected files, documentation, integration)
- Coding standards (assertions, types, resource management)

## Final Report Template

```markdown
# Plan Audit Complete

## Summary
- **Total iterations**: {N}
- **Exit reason**: {converged|max_iterations}
- **Final quality**: {Excellent|Needs Review}

## Audit History
{for each iteration: Findings + Fixed issues}

## Final State
**Remaining Issues** (Medium/Low): {list or "None ✅"}

## Quality Assessment
{if no critical/high}
✅ **Excellent** - Plan verified!
**Next Steps:**
1. Review: `cat PLAN.md`
2. Generate tasks: `/gg-task-gen PLAN.md`
3. Audit tasks: `/gg-task-audit <plan-slug>`
4. Execute: `/gg-execute <plan-slug>`

{else}
⚠️ **Needs Review** - {list blocking issues}
{endif}
```

## Inline Algorithms

Command-specific operations not defined in shared modules:

### GenerateReport(iteration, findings, exit_reason)
```
Use "Final Report Template" section format
Fill in:
  - Total iterations: iteration count
  - Exit reason: "converged" | "max_iterations" | "user_paused"
  - Final quality:
    - If critical_count == 0 AND high_count == 0: "Excellent"
    - Else: "Needs Review"
  - Audit History: findings from each iteration
  - Remaining Issues: Medium/Low findings still present
  - Next Steps: appropriate commands based on quality
Return formatted markdown
```

---

## Error Handling

**If agent fails:**
- Stop audit (don't continue)
- Report partial results if any iterations succeeded

**If JSON parsing fails:**
- Use prose parsing fallback (see `.claude/commands/_shared/json-parsing.md`)

**If plan file not found:**
- Error: "Plan file not found: {{plan_file}}"
- Suggest: "Run /gg-plan-gen first"

## Example Session

```
User: /gg-plan-audit

Claude: 📋 Plan Audit: PLAN.md
  - Sections: 8
  - Phases: 5
  - Max iterations: 5

Claude: [Asks] Ready to start audit? (yes/no)
User: yes

Claude: [Asks] Auto-apply fixes? (yes/no)
User: yes

Claude: [Asks] Auto-continue iterations? (yes/no)
User: yes

Claude: 🔍 Iteration 1/5: Launching audit agent...
Claude: Iteration 1/5: 2 Critical, 5 High, 3 Medium, 8 Low
🔧 Fixing all 18 issues...
✅ Plan updated

Claude: 🔍 Iteration 2/5: Launching audit agent...
Claude: Iteration 2/5: 0 Critical, 1 High, 2 Medium, 5 Low
🔧 Fixing all 8 issues...
✅ Plan updated

Claude: 🔍 Iteration 3/5: Launching audit agent...
Claude: Iteration 3/5: 0 Critical, 0 High, 0 Medium, 0 Low
✅ Converged (quality threshold)

Claude: # Plan Audit Complete
- **Total iterations**: 3
- **Final quality**: Excellent ✅
**Next Steps:** /gg-task-gen PLAN.md
```
