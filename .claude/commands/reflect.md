---
description: Analyze session and propose improvements to slash commands
args:
  - name: command
    description: Command to reflect on (e.g., gg-execute). Auto-detects if omitted.
    required: false
---

You are analyzing this conversation to improve the slash commands in `.claude/commands/`.

## Step 1: Identify Target Command

IF `{{command}}` is provided:
  target = "{{command}}"
ELSE:
  Scan conversation for command invocations (look for patterns like `<command-name>/gg-*</command-name>`)
  target = most recently invoked gg-* command
  IF no command found:
    Ask: "Which command should I reflect on? (gg-execute, gg-plan-gen, gg-task-gen, gg-plan-audit, gg-task-audit)"

Read the command file: `.claude/commands/{target}.md`

---

## Step 2: Analyze Conversation

Scan the conversation for these signal types:

### High Confidence (explicit corrections)
- User said "no, do X instead" or "don't do Y"
- User said "always/never do X"
- User corrected a misinterpretation of the command

### Medium Confidence (divergences)
- You followed a different sequence than the command specifies
- You improvised a step not covered by the command
- You skipped a step that the command requires
- An edge case arose that the command doesn't handle

### Low Confidence (observations)
- A pattern that worked well but isn't documented
- Ambiguous wording in the command that caused hesitation
- Missing context that would have helped

---

## Step 3: Categorize Findings

For each finding, determine:

1. **Type**:
   - `missing_step` - Command lacks a necessary step
   - `wrong_order` - Steps should be reordered
   - `missing_edge_case` - Edge case not handled
   - `clarification` - Wording is ambiguous
   - `new_pattern` - Successful pattern worth documenting

2. **Location**: Where in the command file this applies

3. **Confidence**: High / Medium / Low

4. **Evidence**: Quote from conversation showing the signal

---

## Step 4: Propose Changes

Present findings in this format:

```
## Reflection: {target}

### Signals Detected

| # | Type | Confidence | Evidence |
|---|------|------------|----------|
| 1 | missing_step | High | "User said: always check X before Y" |
| 2 | missing_edge_case | Medium | "Had to handle case where no tasks ready" |

### Proposed Changes

#### Change 1: [Brief description]
**Confidence**: High
**Evidence**: [Quote]

**Current** (line ~XX):
```
[existing text]
```

**Proposed**:
```
[new text]
```

**Rationale**: [Why this improves the command]

---

[Repeat for each change]
```

---

## Step 5: Apply Changes

After presenting all changes, ask:

```
Apply these changes?
- Y: Apply all
- N: Discard all
- 1,2,3: Apply specific changes by number
- Or describe modifications in natural language
```

IF user approves (Y or specific numbers):
  FOR each approved change:
    Use Edit tool to update `.claude/commands/{target}.md`

  Show: "Updated {target}.md with {N} changes"

IF user provides natural language feedback:
  Revise proposed changes accordingly
  Present revised changes
  Ask for approval again

---

## Constraints

- Only propose changes with clear evidence from the conversation
- Preserve the overall structure of the command file
- Don't add speculative features ("might be useful to...")
- Keep changes minimal and focused
- Each change should be independently applicable

---

## Example Output

```
## Reflection: gg-execute

### Signals Detected

| # | Type | Confidence | Evidence |
|---|------|------------|----------|
| 1 | missing_step | High | "Had to manually check if tasks were serialized on same file" |
| 2 | clarification | Medium | "Unclear whether to compile after each agent or after wave" |

### Proposed Changes

#### Change 1: Add file conflict pre-check reminder
**Confidence**: High
**Evidence**: During execution, discovered two tasks modifying same file without dependency

**Current** (line ~89):
```
  Step 4: Spawn parallel agents (CRITICAL - Single message)
    Print "Wave {wave}: Spawning {count} agents..."
```

**Proposed**:
```
  Step 4: Spawn parallel agents (CRITICAL - Single message)
    # Verify no file conflicts slipped through (belt and suspenders)
    FOR task IN ready_tasks: Verify task.files don't overlap with other ready tasks
    Print "Wave {wave}: Spawning {count} agents..."
```

**Rationale**: File conflict detection in Step 3 should catch this, but an extra check here prevents subtle bugs when dependencies are manually modified.

---

Apply these changes?
- Y: Apply all
- N: Discard all
- 1: Apply only change 1
```
