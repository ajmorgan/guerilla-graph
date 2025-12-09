# Project Context Module

Reusable operations for loading project configuration and detecting VCS environment.

## Purpose

Provides standard algorithms for project environment detection used across commands.

**Used by**: gg-plan-gen, gg-execute

---

## Operation 1: Load Project Config

**Purpose**: Extract build/test commands and language from CLAUDE.md

**Input**:
- None (reads from current working directory)

**Output**:
- `language`: Primary language (string, e.g., "Zig", "Python", "TypeScript")
- `build_command`: Command to build project (string or null)
- `test_command`: Command to run tests (string or null)
- `architecture`: Brief architecture description (string or null)

**Algorithm**:
```
1. Try: Read("CLAUDE.md") or Read("../CLAUDE.md")
2. If file not found:
   - Return defaults: language="unknown", build_command=null, test_command=null
3. Parse content:
   a. Extract language:
      - Search for "Language: " or "language: " in frontmatter/headers
      - Search for code fence labels (```zig, ```python, etc.)
      - Use most frequent code fence language
   b. Extract build command:
      - Find "## Build" or "### Building" section
      - Extract first command after section (lines starting with $, #, or in code fence)
      - Common patterns: "zig build", "npm run build", "cargo build"
   c. Extract test command:
      - Find "## Test" or "### Testing" section
      - Extract first command after section
      - Common patterns: "zig build test", "npm test", "pytest"
   d. Extract architecture:
      - Find "## Architecture" or "## Module Structure" section
      - Extract first paragraph or bullet list
4. Return structured config
```

**Usage**:
```markdown
config = LoadProjectConfig()

If config.build_command:
  Run build_command to verify project compiles
If config.test_command:
  Run test_command to verify tests pass
```

---

## Operation 2: Detect VCS Type

**Purpose**: Identify version control system and check for uncommitted changes

**Input**:
- None (checks current working directory)

**Output**:
- `vcs_type`: "git" | "jj" | "unknown"
- `has_uncommitted`: boolean (true if working directory has modifications)
- `note`: Status message

**Algorithm**:
```
1. Check for VCS directories:
   a. If .jj/ directory exists:
      - vcs_type = "jj"
      - Try: Bash("jj status")
      - Parse output for "Working copy changes:" or similar
   b. Else if .git/ directory exists:
      - vcs_type = "git"
      - Try: Bash("git status --porcelain")
      - has_uncommitted = true if output non-empty
   c. Else:
      - vcs_type = "unknown"
      - has_uncommitted = false
      - note = "No VCS detected (.git or .jj not found)"

2. Handle errors:
   - If status command fails:
     - Log warning, assume has_uncommitted = false
     - note = "VCS detected but status command failed"

3. Return vcs_type, has_uncommitted, note
```

**Usage**:
```markdown
vcs = DetectVCSType()

If vcs.vcs_type == "unknown":
  Warn: "No version control system detected"

If vcs.has_uncommitted:
  Warn: "Uncommitted changes detected - recommend committing first"
```

---

## Operation 3: Reset Files

**Purpose**: Restore files to clean state using VCS

**Input**:
- `files`: Array of file paths to reset (string[])
- `vcs_type`: VCS type from DetectVCSType ("git" | "jj" | "unknown")

**Output**:
- `success`: boolean
- `reset_count`: Number of files reset
- `note`: Result message

**Algorithm**:
```
1. Validate input:
   - If vcs_type == "unknown":
     - Return success=false, note="No VCS available for reset"
   - If files array empty:
     - Return success=true, reset_count=0, note="No files to reset"

2. Build reset command:
   a. If vcs_type == "jj":
      - command = "jj restore " + files.join(" ")
   b. If vcs_type == "git":
      - command = "git checkout -- " + files.join(" ")

3. Execute reset:
   - Try: Bash(command)
   - If succeeds:
     - success = true
     - reset_count = files.length
     - note = "Reset {reset_count} file(s)"
   - If fails:
     - success = false
     - reset_count = 0
     - note = "Reset failed: [error message]"

4. Return result
```

**Usage**:
```markdown
vcs = DetectVCSType()
files_to_reset = ["src/file1.zig", "src/file2.zig"]

result = ResetFiles(files_to_reset, vcs.vcs_type)

If not result.success:
  Error: "Failed to reset files: {result.note}"
```

---

## Operation 4: Get Project Root

**Purpose**: Find project root directory (where CLAUDE.md or VCS root lives)

**Input**:
- None (uses current working directory)

**Output**:
- `root_path`: Absolute path to project root (string or null)
- `note`: How root was determined

**Algorithm**:
```
1. Start from current working directory
2. Check for project markers:
   a. CLAUDE.md exists in cwd → root_path = cwd
   b. .git/ exists in cwd → root_path = cwd
   c. .jj/ exists in cwd → root_path = cwd
   d. CLAUDE.md exists in parent → root_path = parent
   e. Check up to 3 levels up

3. If no markers found:
   - root_path = null
   - note = "Could not determine project root"

4. Return root_path, note
```

**Usage**:
```markdown
root = GetProjectRoot()

If root.root_path:
  Change to root directory for consistent command execution
Else:
  Warn: "Running from current directory - {root.note}"
```

---

## Limits

- Max directory depth to search for project root: 3 levels
- Max file size for CLAUDE.md: 1MB (Read tool limit)
- Max files to reset in single operation: 100

**Rationale**: Prevent runaway searches and operations, focus on typical project structures.

---

## Integration Pattern

```markdown
### Standard Project Setup

1. Read project context module:
   ```
   Read(".claude/commands/_shared/project-context.md")
   ```

2. Store operations in working memory:
   - LoadProjectConfig
   - DetectVCSType
   - ResetFiles
   - GetProjectRoot

3. Initialize project context:
   ```
   root = GetProjectRoot()
   config = LoadProjectConfig()
   vcs = DetectVCSType()
   ```

4. Use throughout command:
   - Reference config.build_command for compilation
   - Reference config.test_command for validation
   - Use vcs.vcs_type for file operations
   - Use ResetFiles if need to undo changes
```

---

## Example: Complete Project Initialization

```markdown
Command: gg-plan-gen "Add authentication"

1. GetProjectRoot()
   → root_path="/Users/dev/myproject", note="Found .git directory"

2. LoadProjectConfig()
   → language="Zig"
   → build_command="zig build"
   → test_command="zig build test"
   → architecture="Module structure with src/commands/, src/storage.zig..."

3. DetectVCSType()
   → vcs_type="git"
   → has_uncommitted=true
   → note="2 modified files detected"

4. Warn user:
   "Uncommitted changes detected. Recommend running 'git commit' first."

5. Use config throughout:
   - Run "zig build" to verify project compiles before planning
   - Include language="Zig" in plan metadata
   - Reference test_command in task validation steps
```

---

## Error Handling

**CLAUDE.md Not Found**:
- Return defaults with language="unknown"
- Log warning but continue (some projects may not have CLAUDE.md)
- Commands should handle unknown configuration gracefully

**VCS Status Command Fails**:
- Assume no uncommitted changes (safe default)
- Log warning but continue
- Note contains error details for debugging

**Reset Files Fails**:
- Return success=false with error message
- Caller should decide whether to abort or continue
- Preserve error details for user feedback

**Project Root Not Found**:
- Return null with descriptive note
- Commands run from current directory
- May affect relative path resolution

---

## Notes

This module provides **read-only detection** with optional **write operations** (ResetFiles).

All file operations use absolute paths when possible to avoid ambiguity.

Designed for cross-platform compatibility (Darwin, Linux, Windows paths).

VCS detection prioritizes jj over git (jj projects often coexist with git).
