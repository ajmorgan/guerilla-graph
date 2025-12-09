# Fix Patterns Module

Reusable fix application patterns for audit commands (gg-plan-audit, gg-task-audit).

## Purpose

Provides standard algorithms for applying fixes to plans and task descriptions based on audit findings.

---

## Pattern A: Fix Incorrect Line Number

**Purpose**: Update line number references to match actual codebase locations

**Trigger**: Finding with category "Correctness" indicating line number mismatch

**Input**:
- `target_file_path`: Path to plan or task description file
- `old_line_number`: Incorrect line number from finding
- `new_line_number`: Correct line number from recommendation
- `file_reference`: Source file being referenced (e.g., "src/commands.zig")

**Algorithm**:
```
1. Read target file completely:
   content = Read(target_file_path)

2. Search for all occurrences of old line number in context:
   - Pattern: "{file_reference}:{old_line_number}"
   - Pattern: "line {old_line_number}"
   - Pattern: ":{old_line_number}" (if file_reference already mentioned)

3. Replace all occurrences:
   new_content = content.replace("{file_reference}:{old_line_number}",
                                 "{file_reference}:{new_line_number}")
   new_content = new_content.replace("line {old_line_number}",
                                     "line {new_line_number}")

4. Write updated content:
   Write(target_file_path, new_content)

5. Verify replacement:
   verify_content = Read(target_file_path)
   Assert: new_line_number appears in verify_content
   Assert: old_line_number does not appear in verify_content
```

**Example**:
```
Finding: "Line number incorrect: should be 540 not 532"
Recommendation: "Update src/commands.zig:532 to src/commands.zig:540"

Action: Replace all "src/commands.zig:532" → "src/commands.zig:540"
```

---

## Pattern B: Add Missing File Path

**Purpose**: Add file path references to Where section for better context

**Trigger**: Finding with category "FullContext" indicating missing file path

**Input**:
- `target_file_path`: Path to task description file
- `file_path_to_add`: File path from recommendation (e.g., "src/storage.zig:123")
- `description`: Context about what this file reference is for

**Algorithm**:
```
1. Read task description:
   content = Read(target_file_path)

2. Search for "## Where" section:
   where_index = content.find("## Where")

3. If section doesn't exist:
   - Find "## Why" section end (look for next "##")
   - Insert new section: "\n## Where\n- `{file_path_to_add}` - {description}\n"

4. If section exists but is empty:
   - Find section line
   - Append: "- `{file_path_to_add}` - {description}\n"

5. If section exists with content:
   - Find last item in Where list
   - Append after last item: "- `{file_path_to_add}` - {description}\n"

6. Write updated content:
   Write(target_file_path, new_content)
```

**Example**:
```
Finding: "Task lacks specific file path in Where section"
Recommendation: "Add file path: src/storage.zig:123"

Action: Append "- `src/storage.zig:123` - Add description column" to Where section
```

---

## Pattern C: Add Missing Code Snippet

**Purpose**: Add current code examples to How section for clarity

**Trigger**: Finding with category "FullContext" or "Implementability" indicating missing code

**Input**:
- `target_file_path`: Path to task description file
- `source_file_path`: File to extract code from (e.g., "src/types.zig")
- `line_number`: Line to extract code around
- `context_lines`: Lines before/after to include (default: 10)
- `step_reference`: Which step in How section to add code to

**Algorithm**:
```
1. Extract code from source file:
   code_snippet = ExtractCodeSnippet(source_file_path, line_number, context_lines)
   (Uses file-verification.md Operation 3)

2. Read task description:
   content = Read(target_file_path)

3. Locate step in ## How section:
   - Search for step_reference (e.g., "### Step 1:")
   - Find end of step (next "###" or "##")

4. Add code block before end of step:
   code_block = """
   **Current code** (`{source_file_path}:{line_number}`):
   ```{language}
   {code_snippet}
   ```
   """

5. Insert code_block into step

6. Write updated content:
   Write(target_file_path, new_content)
```

**Example**:
```
Finding: "No current code shown in How section"
Recommendation: "Add code snippet from src/types.zig:95"

Action:
1. Read src/types.zig around line 95
2. Extract 10 lines of context
3. Add to How section Step 1:
   **Current code** (`src/types.zig:95`):
   ```zig
   [extracted code]
   ```
```

---

## Pattern D: Fix Vague Instruction

**Purpose**: Replace vague language with specific instructions

**Trigger**: Finding with category "Implementability" indicating unclear instruction

**Input**:
- `target_file_path`: Path to task description file
- `vague_text`: Text to replace (e.g., "update appropriately")
- `specific_text`: Replacement from recommendation (or null)

**Algorithm**:
```
1. Read task description:
   content = Read(target_file_path)

2. If specific_text provided in recommendation:
   new_content = content.replace(vague_text, specific_text)
   Write(target_file_path, new_content)

3. Else (no specific replacement provided):
   # Add audit comment for manual review
   comment = "<!-- AUDIT: Make this more specific: '{vague_text}' -->"
   new_content = content.replace(vague_text, vague_text + "\n" + comment)
   Write(target_file_path, new_content)
   Log warning: "⚠️ Vague instruction flagged for manual review"

4. Verify replacement:
   verify_content = Read(target_file_path)
   Assert: vague_text no longer appears OR has comment flag
```

**Example**:
```
Finding: "Step says 'update appropriately' - not specific"
Recommendation: "Replace with explicit instructions"

Action: Add comment "<!-- AUDIT: Make this more specific: 'update appropriately' -->"
```

---

## Pattern E: Add Missing Dependency

**Purpose**: Add task dependency to gg database

**Trigger**: Finding with category "Dependencies" indicating missing blocker relationship

**Input**:
- `task_id`: Task that is blocked (e.g., "tiger:002")
- `blocks_on_id`: Task that blocks (e.g., "tiger:001")

**Algorithm**:
```
1. Execute gg command:
   result = Bash("gg dep add {task_id} --blocks-on {blocks_on_id}")

2. Check result:
   If result contains "already exists":
     Log: "Dependency already exists, skipping"
     Return SUCCESS

   If result contains "would create cycle":
     Log error: "❌ Cannot add dependency: would create cycle"
     Return FAILURE

   If result contains "Error":
     Log error: "❌ Failed to add dependency: {result}"
     Return FAILURE

   Else:
     Log: "✅ Added dependency: {task_id} blocks-on {blocks_on_id}"
     Return SUCCESS

3. No description update needed (dependency stored in gg database)
```

**Example**:
```
Finding: "Task tiger:002 needs output from tiger:001 but no dependency"
Recommendation: "Add dependency: gg dep add tiger:002 --blocks-on tiger:001"

Action: Execute: gg dep add tiger:002 --blocks-on tiger:001
```

---

## Pattern F: Create File Serialization Chain

**Purpose**: Add dependencies to serialize tasks modifying the same file

**Trigger**: Finding with category "Dependencies" indicating file conflict

**Input**:
- `task_ids`: List of tasks modifying same file (e.g., ["tiger:002", "tiger:003", "tiger:004"])

**Algorithm**:
```
1. Parse task IDs from finding

2. Sort task IDs numerically:
   sorted_ids = sort(task_ids, key=lambda x: int(x.split(':')[1]))

3. Create dependency chain:
   for i in range(1, len(sorted_ids)):
     dependent = sorted_ids[i]
     blocker = sorted_ids[i-1]

     result = Bash("gg dep add {dependent} --blocks-on {blocker}")

     If result contains "Error":
       Log error: "❌ Failed to chain {dependent} → {blocker}"
       Continue to next pair (don't fail entire chain)
     Else:
       Log: "✅ Chained: {dependent} blocks-on {blocker}"

4. Result: task[0] → task[1] → task[2] → ... (serialized execution)
```

**Example**:
```
Finding: "Tasks tiger:002, tiger:003, tiger:004 all modify src/storage.zig without serialization"
Recommendation: "Create dependency chain: tiger:003 blocks-on tiger:002, tiger:004 blocks-on tiger:003"

Action:
1. Sort: [tiger:002, tiger:003, tiger:004]
2. Execute: gg dep add tiger:003 --blocks-on tiger:002
3. Execute: gg dep add tiger:004 --blocks-on tiger:003
4. Result: tiger:002 → tiger:003 → tiger:004
```

---

## Pattern G: Flag Maintainability Issue

**Purpose**: Mark maintainability concerns that need human review (not auto-fixable)

**Trigger**: Finding with category "Maintainability" indicating architectural concern

**Input**:
- `target_file_path`: Path to task description file
- `issue_description`: What maintainability concern was found
- `section`: Which section has the issue (e.g., "How - Step 3")

**Algorithm**:
```
1. Read task description:
   content = Read(target_file_path)

2. Locate issue section:
   section_index = content.find(section)
   If not found, add to top of ## How section

3. Add audit comment:
   comment = """
   <!-- AUDIT FINDING: Maintainability concern
        Issue: {issue_description}
        Recommendation: Consider redesigning for cleaner solution
        This requires human judgment - not auto-fixed -->
   """

4. Insert comment at appropriate location:
   new_content = content[:section_index] + comment + content[section_index:]

5. Write updated content:
   Write(target_file_path, new_content)

6. Log warning:
   Log: "⚠️ Task has maintainability issue requiring manual review"
   Log: "   {issue_description}"

7. Return FLAGGED (not fixed, human review needed)
```

**Example**:
```
Finding: "Task introduces workaround instead of proper solution"
Recommendation: "Replace workaround with clean implementation"

Action:
1. Add comment to task description:
   "<!-- AUDIT FINDING: This approach was flagged as a workaround.
        Consider redesigning for clean solution. -->"
2. Log warning for manual review
3. Don't automatically change implementation (requires human judgment)
```

---

## ApplyFix Dispatcher

**Purpose**: Route findings to appropriate fix pattern

**Input**:
- `finding`: Audit finding object with severity, category, recommendation

**Algorithm**:
```
CASE finding.category:

  WHEN "Correctness" AND recommendation contains line number change:
    Apply Pattern A: Fix Incorrect Line Number

  WHEN "FullContext" AND recommendation contains "Add file path":
    Apply Pattern B: Add Missing File Path

  WHEN "FullContext" OR "Implementability" AND recommendation contains "Add code snippet":
    Apply Pattern C: Add Missing Code Snippet

  WHEN "Implementability" AND recommendation contains "vague" OR "unclear":
    Apply Pattern D: Fix Vague Instruction

  WHEN "Dependencies" AND recommendation contains "Add dependency":
    If recommendation contains "chain" OR multiple task IDs:
      Apply Pattern F: Create File Serialization Chain
    Else:
      Apply Pattern E: Add Missing Dependency

  WHEN "Maintainability":
    Apply Pattern G: Flag Maintainability Issue

  DEFAULT:
    Log warning: "⚠️ No pattern match for: {finding.category}"
    Log: "   Recommendation: {finding.recommendation}"
    Return SKIPPED
```

**Usage**:
```markdown
For each finding in audit_results:
  If finding.severity == "Critical" OR finding.severity == "High":
    result = ApplyFix(finding)
    If result == SUCCESS:
      Log: "✅ Fixed: {finding.issue}"
    Else if result == FAILURE:
      Log: "❌ Failed: {finding.issue}"
    Else if result == FLAGGED:
      Log: "⚠️ Flagged: {finding.issue}"
```

---

## Error Handling

**Dependency Addition Failures**:
- Cycle detected: Log error, skip this dependency, continue with others
- Task not found: Log error, skip this dependency
- Already exists: Not an error, log as info, continue

**File Operations**:
- File not found: Return FAILURE, log error
- Write permission denied: Return FAILURE, log error
- Read failure: Return FAILURE, log error

**Pattern Matching**:
- No pattern matched: Return SKIPPED, log warning
- Ambiguous match: Return SKIPPED, log warning, suggest manual fix

**Partial Success**:
- For Pattern F (chains): Continue even if one link fails
- For Pattern A (replacements): All occurrences must succeed
- Log partial success state clearly

---

## Notes

- Patterns A-D modify task/plan description files
- Patterns E-F modify gg database (no file changes)
- Pattern G flags issues without auto-fixing (human review needed)
- All file modifications should be verified after write
- Dependencies use gg CLI (atomic operations)
- Error handling allows partial success (don't fail entire audit for one bad fix)

---

## End-to-End Examples

### Example: Fixing Line Number (Pattern A)

**Audit Finding**:
```json
{
  "severity": "Critical",
  "category": "Correctness",
  "issue": "Line number incorrect: src/storage.zig:532 should be :540",
  "recommendation": "Update src/storage.zig:532 to src/storage.zig:540"
}
```

**Task Description Before**:
```markdown
## Where
- `src/storage.zig:532` - createTask function
- `src/storage.zig:532` - bind parameters

## How
At `src/storage.zig:532`, add the description binding...
```

**Fix Applied**:
```
Read task description file
Replace all "src/storage.zig:532" → "src/storage.zig:540"
Write updated file
Verify: "532" no longer appears, "540" does appear
```

**Task Description After**:
```markdown
## Where
- `src/storage.zig:540` - createTask function
- `src/storage.zig:540` - bind parameters

## How
At `src/storage.zig:540`, add the description binding...
```

### Example: Adding Missing Dependency (Pattern E)

**Audit Finding**:
```json
{
  "severity": "Critical",
  "category": "Dependencies",
  "issue": "Task tiger:003 modifies src/storage.zig but no dependency on tiger:002 which also modifies it",
  "recommendation": "Add dependency: gg dep add tiger:003 --blocks-on tiger:002"
}
```

**Fix Applied**:
```bash
gg dep add tiger:003 --blocks-on tiger:002
# Output: Added dependency: task 5 blocks on task 4
```

**Result**: tiger:003 now waits for tiger:002 to complete, preventing concurrent modification of src/storage.zig.

### Example: Creating File Serialization Chain (Pattern F)

**Audit Finding**:
```json
{
  "severity": "Critical",
  "category": "Dependencies",
  "issue": "Tasks tiger:002, tiger:003, tiger:004 all modify src/storage.zig without serialization",
  "recommendation": "Create dependency chain for file serialization"
}
```

**Fix Applied**:
```bash
# Sort by task number: [tiger:002, tiger:003, tiger:004]
# Create chain:
gg dep add tiger:003 --blocks-on tiger:002
# Output: Added dependency: task 5 blocks on task 4

gg dep add tiger:004 --blocks-on tiger:003
# Output: Added dependency: task 6 blocks on task 5
```

**Result**: Execution order is now: tiger:002 → tiger:003 → tiger:004 (serialized, no conflicts)
