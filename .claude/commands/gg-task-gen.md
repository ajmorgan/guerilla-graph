---
description: Generate tasks from PLAN.md with verification
args:
  - name: spec_file
    description: Markdown file path with feature spec (default PLAN.md)
    required: false
---

You are generating a gg plan from a markdown specification with rigorous quality verification.

## Task

Create fully-verified gg tasks from **{{spec_file}}** (default: PLAN.md) that pass quality standards BEFORE creation.

**Philosophy**: Prevent defects, don't just detect them. Generate high-quality tasks that require minimal audit cycles.

---

## Preparation: Load Shared Modules

**FIRST STEP - Load verification infrastructure**:

```
Read(".claude/commands/_shared/quality-criteria.md")
Read(".claude/commands/_shared/task-template.md")
Read(".claude/commands/_shared/dependency-analysis.md")
Read(".claude/commands/_shared/file-verification.md")
Read(".claude/commands/_shared/code-verification.md")
Read(".claude/hooks/engineering_principles.md")
Read("CLAUDE.md")
```

Store algorithms in working memory for task verification.

---

## Control Flow

```
Load:
  project = LoadProjectConfig("CLAUDE.md")  # language, build_cmd, test_cmd
  spec = Read("{{spec_file}}" or "PLAN.md")
  modules = LoadSharedModules()  # quality, template, deps, file_verify

Step 1: Parse Spec
  phases = ParsePhases(spec)
  files = ExtractFilePaths(spec)
  Print: "✅ Phases: {count}"

Step 2: Verify Files
  For each file in files:
    VerifyFileExists(file) or ERROR
    DetectOldSchemaMarkers(file) and WARN
    Read(file)  # Store for snippets
  Print: "✅ Files verified: {count}"

Step 3: Understand Syntax
  Bash("gg workflow")  # Authoritative syntax reference
  Store syntax

Step 4: Create Plan
  # Get PLAN.md birth time (creation time) as epoch.
  # macOS: stat -f %B returns birth time
  # Linux: stat -c %W returns birth time (requires ext4 with kernel 4.11+)
  # Fallback: Use mtime if birth time unavailable (returns 0 on some Linux systems)
  birth_time = Bash("stat -f %B PLAN.md 2>/dev/null || { bt=$(stat -c %W PLAN.md 2>/dev/null); [ \"$bt\" != \"0\" ] && echo $bt || stat -c %Y PLAN.md; }")

  plan_desc = FormatPlanDescription(spec)
  Bash("""gg plan new {plan_slug} --title '{title}' --created-at {birth_time} --description-file - <<'EOF'
{plan_desc}
EOF""")

Step 5: Create Tasks
  For each phase:
    files = ExtractFiles(phase)
    For each file: snippet = ExtractCodeSnippet(file, line, context=10)

    task_desc = BuildTaskDescription(phase, snippets, template)  # task-template.md

    # Verify BEFORE creating
    VerifyTaskQuality(task_desc, quality) or Fix & Re-verify
    VerifyCodeQuality(task_desc, engineering_principles) or Fix & Re-verify

    result = Bash("""gg new {plan_slug}: --title '{title}' --description-file - <<'EOF'
{task_desc}
EOF""")
    task_ids.append(result.task_id)

Step 6: Build Dependencies
  # File-level serialization
  chains = BuildFileChains(ExtractFileOps(tasks))
  For each chain: Bash("gg dep add {task} --blocks-on {blocker}")

  # Phase dependencies
  phase_deps = BuildPhaseDeps(phases)
  For each dep: Bash("gg dep add {task} --blocks-on {blocker}")

  # Explicit dependencies
  prose_deps = ParseDependencyProse(spec)
  For each dep: Bash("gg dep add {task} --blocks-on {blocker}")

Step 7: Quality Gate
  tasks = Bash("gg task ls --plan {plan_slug} --json")
  For each task:
    Verify YAML frontmatter, What/Why/Where/How, files array
    If fail: ERROR "Task {id} incomplete"

Step 8: Report
  Print completion summary with quality verification results
  Print next steps: /gg-task-audit or /gg-execute
```

---

## Step Details

### Create Tasks (Step 5)

For each phase in PLAN.md:

**5a. Parse Phase Content**
Extract: task title, files (with line numbers), implementation steps, code examples

**5b. Verify Files**
Use **file-verification.md** operations:
- `VerifyFileExists(file_path)` - ERROR if missing
- `DetectOldSchemaMarkers(file_path)` - Create prerequisite migration task if needed
- `VerifyLineNumber(file_path, line_number)` - WARN if way off, adjust
- `ExtractCodeSnippet(file_path, line_number, context=10)` - Store for task description

**5c. Build Task Description**
Use **task-template.md** structure (see .claude/commands/_shared/task-template.md for complete format):
- YAML frontmatter: complexity, language, affected_components, files array, automated_tests, validation_commands
- What/Why/Where/How sections with REAL code snippets from ExtractCodeSnippet
- Patterns to Follow, Validation, Success Criteria sections

**5d. Verify Task Quality (BEFORE creating)**
Run checks from **quality-criteria.md**:
1. **Full Context**: YAML frontmatter, files array, What/Why/Where/How
2. **Correctness**: File paths verified, line numbers accurate, code snippets real
3. **Code Quality** (code-verification.md): Follows engineering_principles.md, no function >70 lines, no usize in business logic, has defer
4. **Implementability**: Clear step-by-step instructions, no vague terms
5. **Maintainability**: Aligns with PLAN.md Goals, doesn't implement Non-Goals

**If ANY check fails**: Fix task description, re-verify.

**5e. Create Task**
Only after quality verification passes:
```bash
gg new {plan_slug}: --title "[Title]" --description-file - <<'EOF'
{task_desc}
EOF
```

Capture task ID (format: `{plan_slug}:NNN`) for dependencies.

### Build Dependencies (Step 6)

Use algorithms from **dependency-analysis.md**:

**6a. File-Level Serialization**
Tasks modifying same file must chain. Extract file operations, run File-Level Serialization algorithm, execute dependency commands.

**6b. Phase Dependencies**
Phases execute in logical order. Define phase order from PLAN.md, run Phase Dependency Ordering algorithm.

**6c. Explicit Dependencies**
Parse PLAN.md for "after Phase X completes", "requires Phase Y", "depends on task Z".

---

## Final Report

```
✅ Plan and Tasks Generated from {spec_file}

Plan: {plan_slug} - {title}
Project: {language} ({build_command})
Source: {spec_file}

Tasks Created: {count}
├─ Phase 1: {phase1_tasks}
├─ Phase 2: {phase2_tasks}
└─ Phase 3: {phase3_tasks}

Quality Verification Results:
✅ All file paths verified
✅ All line numbers accurate
✅ All code snippets from actual codebase
✅ All code follows engineering_principles.md
✅ File-level serialization applied
✅ Phase dependencies correct
✅ No cycles in dependency graph
✅ All tasks have complete YAML frontmatter
✅ No vague instructions

Dependencies Created: {count}

Next Steps:
1. Optional audit: /gg-task-audit {plan_slug} {spec_file}
2. Execute: /gg-execute {plan_slug}
```

---

## Inline Algorithms

Command-specific operations not defined in shared modules:

### LoadSharedModules()
```
modules = {}
modules.quality = Read(".claude/commands/_shared/quality-criteria.md")
modules.template = Read(".claude/commands/_shared/task-template.md")
modules.deps = Read(".claude/commands/_shared/dependency-analysis.md")
modules.files = Read(".claude/commands/_shared/file-verification.md")
modules.code = Read(".claude/commands/_shared/code-verification.md")
modules.principles = Read(".claude/hooks/engineering_principles.md")
Return modules
```

### ParsePhases(spec)
```
phases = []
For each "### Phase N:" or "## Phase N:" header in spec:
  phase = {
    number: N,
    name: text after "Phase N:",
    content: text until next phase header,
    files: ExtractFilePaths(content),
    goal: first line after header
  }
  Add phase to phases
Return phases
```

### ExtractFilePaths(text)
```
paths = []
patterns = [
  /`([a-zA-Z0-9_/.-]+\.[a-z]+):(\d+)`/,  # `file.ext:123`
  /`([a-zA-Z0-9_/.-]+\.[a-z]+)`/          # `file.ext`
]
For each pattern match in text:
  path = {
    file: match[1],
    line: match[2] or null
  }
  Add path to paths (deduplicated)
Return paths
```

### ExtractFiles(phase)
```
Return ExtractFilePaths(phase.content)
```

### FormatPlanDescription(spec)
```
Extract from spec:
  - Overview section (first 2-3 paragraphs)
  - Goals section
  - Architecture summary
Format as markdown suitable for gg plan description
Return formatted string
```

### BuildTaskDescription(phase, snippets, template)
```
Use task-template.md structure
Fill in:
  - YAML frontmatter:
    - complexity: infer from phase size
    - language: from project config
    - files: from phase.files
    - validation_commands: from project config
  - ## What: from phase.goal
  - ## Why: from phase rationale or plan context
  - ## Where: from phase.files with line numbers
  - ## How: step-by-step from phase.content + snippets
Return formatted task description
```

### ParseDependencyProse(spec)
```
deps = []
patterns = [
  "after Phase X completes",
  "requires Phase Y",
  "depends on task Z",
  "blocked by",
  "must complete first"
]
For each match in spec:
  Extract dependent and blocker from context
  Add {dependent, blocker} to deps
Return deps
```

---

## Error Handling

- **CLAUDE.md not found**: ERROR - Required for quality task generation, Exit
- **Spec file not found**: ERROR - Suggest: "Run /gg-plan-gen first", Exit
- **File verification fails**: ERROR - List missing files, Exit
- **Cycle detected**: ERROR - Report cycle, Exit

---

## Notes

This task-gen focuses on **prevention over detection**:
- Verify files exist BEFORE creating tasks
- Extract real code BEFORE writing descriptions
- Check code quality BEFORE task creation
- Build dependencies BEFORE reporting

**Result**: Tasks ready for execution with minimal audit work needed.
