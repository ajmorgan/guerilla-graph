# Guerilla Graph Slash Commands

Quality-gated workflow for AI-assisted parallel execution.

## Workflow

```
/gg-plan-gen <feature>   → Generate PLAN.md
       ↓
/gg-plan-audit           → Refine plan (max 5 iterations)
       ↓
/gg-task-gen             → Create gg tasks with dependencies
       ↓
/gg-task-audit <slug>    → Audit tasks in parallel (max 5 iterations)
       ↓
/gg-execute <slug>       → Execute with parallel agents + compilation gates
```

## Architecture

```
.claude/commands/
├── gg-plan-gen.md          # Step 1: Generate plan
├── gg-plan-audit.md        # Step 2: Audit plan
├── gg-task-gen.md          # Step 3: Generate tasks
├── gg-task-audit.md        # Step 4: Audit tasks
├── gg-execute.md           # Step 5: Execute plan
├── _shared/                # Reusable modules
│   ├── control-flow.md     # Tool invocation patterns
│   ├── quality-criteria.md # 5 quality dimensions
│   ├── fix-patterns.md     # Auto-fix algorithms
│   ├── json-parsing.md     # JSON extraction
│   ├── file-verification.md
│   ├── code-verification.md
│   ├── dependency-analysis.md
│   ├── project-context.md
│   └── task-template.md
└── _prompts/               # Agent prompt templates
    ├── audit-plan.md
    ├── audit-task.md
    ├── implement-task.md
    ├── explore-codebase.md
    └── review-work.md
```

## Design Decisions

### 1. Modular Architecture

Commands reference shared modules instead of inlining content. Benefits:
- **DRY**: Fix patterns defined once, used everywhere
- **Maintainable**: Update module, all commands benefit
- **Readable**: Commands focus on control flow

### 2. Parallel Agent Spawning

Claude Code executes multiple Task tool calls in parallel when they appear in the SAME message. See `control-flow.md` "Parallel Agent Spawning" section.

```
# CORRECT: Single message, multiple Task calls (parallel)
Task(...), Task(...), Task(...)

# WRONG: Sequential messages
Task(...) → wait → Task(...) → wait
```

**Key insight**: FOR loops in pseudocode are conceptual. Claude must emit all Task calls in ONE message.

### 3. Iterative Convergence

Audit commands use dual convergence:
1. **Content-based**: Stop if nothing changed
2. **Quality-based**: Stop if 0 Critical/High issues

Max 5 iterations prevents infinite loops.

### 4. Compilation Gates

Execute command enforces build success BEFORE closing tasks:
- If build fails: Tasks stay `in_progress`
- User chooses: Fix manually / retry wave / abort
- Prevents closing broken tasks

### 5. File-Level Serialization

Tasks modifying the same file must form dependency chains:
- Prevents concurrent modification conflicts
- Critical for parallel agent execution
- Auto-detected in task-gen, enforced in execute

### 6. Model Constraint

**Do NOT use `model: "haiku"` for subagents.** Haiku makes mistakes with complex code, and quality is our first priority.

Agents inherit model from parent by default - omit the `model` parameter entirely (recommended).
