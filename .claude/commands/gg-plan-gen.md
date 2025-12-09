---
description: Create implementation plan from feature description
args:
  - name: feature_description
    description: Feature description (text) or file path to read
    required: true
---

## Task

Create PLAN.md for **{{feature_description}}**.

## Control Flow

```
Step 1: Load Context
  project = LoadProjectConfig()  # .claude/commands/_shared/project-context.md
  feature = ReadFeatureInput({{feature_description}})

Step 2: Extract Requirements
  goals = ParseGoals(feature)
  non_goals = ParseNonGoals(feature)
  success_criteria = ParseCriteria(feature)

Step 3: Explore Codebase
  prompt = Read(".claude/commands/_prompts/explore-codebase.md")
  exploration = ExecuteExploration(prompt, feature, project)
  patterns = ParseExplorationResults(exploration)

Step 4: Resolve Questions
  questions = CollectOpenQuestions()
  FOR q IN questions:
    IF CanResearch(q): Research(q)
    ELSE: answer = AskUser(q)

Step 5: Write Plan
  plan = GeneratePlanMD(goals, non_goals, patterns)
  Write("PLAN.md", plan)
  Print summary
```

## Step Details

### Load Context (Step 1)

**Project Context** (see `.claude/commands/_shared/project-context.md`):
- Read CLAUDE.md (or README.md if missing)
- Extract: Language, Build/Test Commands, Architecture, Performance Targets
- Warn if CLAUDE.md not found

**Feature Input**: Try Read({{feature_description}}), else use as direct text

**Verify before continuing**: Language, build command, feature complete (>50 chars), can state goal

### Extract Requirements (Step 2)

Extract from feature description:
- **Goals**: "should", "will enable", "allows"
- **Non-Goals**: "out of scope", "not included"
- **Success Criteria**: "when X", "verifies that"

State: Overview (1-2 sentences), Goals, Non-Goals, Success Criteria

If vague: Note "⚠️ Question for Step 4"

### Explore Codebase (Step 3)

Use `.claude/commands/_prompts/explore-codebase.md` template.

**Focus**: Similar features, architecture, data/state, integration points, testing, performance, error handling

**Document**: file:line + snippets, rationale, verify paths

**Read critical files** to verify.

**Analysis**: Existing implementation (purpose, components, flow, limitations), related code, patterns

### Resolve Questions (Step 4)

**CRITICAL**: No open questions in final plan.

**Triage** (resolve ALL):
1. Can research answer? → Research
2. Business decision? → Ask user, verify
3. Technical trade-off? → Present options (Context, Option A/B with Pros/Cons/Example, Recommendation)

**Verify corrections** with code before accepting.

### Write Plan (Step 5)

**Pre-Write Verification**: Context loaded, requirements extracted, exploration done, questions resolved, criteria split, pattern refs (≥1/phase), build commands (actual), no placeholders

If ANY fail: STOP - fix, retry

---

**PLAN.md Structure**:

```markdown
# [Feature] Implementation Plan

## Overview
[1-2 paragraphs: what's being built, why]

## Goals
- [Primary goal]

## Non-Goals
- [Out of scope]

## Current State Analysis
[From Step 3: existing code, architecture, patterns]

## Implementation Plan

### Architecture Overview
- Data Flow: Entry → Processing → Storage → Return
- Key Decisions: [choice] - Rationale: [why]
- Phases: Phase 1: [Name] - [goal]; Phase 2: [Name] - [goal]

---

### Phase 1: [Name] (Priority, Dependencies)

Goal: [1 sentence]

Files to Modify: `path:line` - [change]
Files to Create: `path` - [purpose]

Pattern References:
- Similar: `path:line` - [why similar]
- Testing: `path:line` - [test approach]
- Error: `path:line` - [error pattern]

Changes:
1. [Component] - Current: [state] → Change: [proposed] - Rationale: [why]

Performance (if relevant): Operations, Queries, Target latency

Success Criteria:
  Automated:
  - [ ] Build: `[command]`
  - [ ] Test: `[command]`
  Manual:
  - [ ] Feature works: [test]
  - [ ] Performance: [verify]

---

[Repeat for additional phases]

---

## Risk Assessment
- Low Risk: [item] - Pattern: `file:line`
- Medium Risk: [item] - [reason] - Mitigation: [strategy]
- High Risk: [item] - [risk] - Mitigation: [strategy, fallback]
- Breaking Changes: [change] - [impact] - Migration: [how adapt]

## File Change Summary
- Files to Create: `path` - [purpose]
- Files to Modify: `path` - [changes]

## Success Criteria
### Automated: [aggregated commands]
### Manual: [aggregated scenarios]

## Estimated Complexity
[Simple/Moderate/Complex]

Effort Breakdown:
- Phase 1: [time] - [rationale]
- Total: [time]
- Critical Path: [sequential phases]
- Parallelization: [parallel phases]
```

---

**Report Completion**:

```
✅ Plan Created: PLAN.md

Summary:
- Phases: [N]
- Files to create: [N]
- Files to modify: [N]
- Complexity: [Simple/Moderate/Complex]
- Quality checks: All passed ✅

Next:
1. Review: cat PLAN.md
2. Audit: /gg-plan-audit PLAN.md
3. Generate tasks: /gg-task-gen PLAN.md
4. Execute: /gg-execute <plan-slug>
```

## Key Principles

1. Load project context first (CLAUDE.md before anything)
2. Be language-agnostic (adapt to project patterns)
3. No open questions (resolve ALL uncertainties)
4. Reference actual codebase (file:line from exploration)
5. Autonomous exploration (discover, don't ask)
6. Split success criteria (automated vs manual)
7. Follow architecture (don't invent patterns)

## Error Handling

**Project documentation not found**: Warn, infer from directory, suggest creating CLAUDE.md

**Exploration fails**: STOP - report error, suggest clarifying feature description

**File reads fail**: Report specific files, ask user to verify repository state

**Unclear corrections**: Ask for file paths/examples, verify with code, don't guess
