# Jujutsu (jj) Workflow Context

> **Context Recovery**: Run `cat .claude/jj_prime.md` after compaction, clear, or new session
> Hooks auto-call this in Claude Code when jj repo detected

# 🚨 JJ SQUASH WORKFLOW 🚨

**Pattern**: Make many small changes, squash them down to bookmark as logical commits.

**Key Concept**: Create bookmark → `jj new` → make changes → `jj squash` down to bookmark. After squash, @ becomes new empty change ready for more work.

## Core Rules
- All changes are auto-tracked in @ (working copy)
- Always `jj new` after creating bookmark to work on top of it
- Use `jj squash` to squash @ down into bookmark (not `git commit`)
- Squash frequently after completing a logical unit/phase
- Each squashed commit should be a reviewable unit
- No interactive rebase needed - squash workflow is simpler

## Essential Commands

### Starting Work
- `jj bookmark create ACON-1234` - Create bookmark/branch
- `jj new` - Create new empty change on top of bookmark (work here!)
- `jj status` - Check what's changed in @ (working copy)
- `jj log` - View commit history

### Squashing & Committing
- `jj squash -m "Phase 1: Database migrations"` - Squash @ down into bookmark with message
- `jj log -r '@-' -T 'description'` - View last squashed commit message
- `jj op undo` - Undo last squash operation

### Syncing with Remote
- `jj git fetch` - Fetch latest changes from remote
- `jj rebase -b ACON-1234 -d main@origin` - Rebase bookmark onto latest main
- `jj git push --bookmark ACON-1234` - Push bookmark to remote
- `jj git push --bookmark ACON-1234 --allow-new` - First time push (creates remote branch)

### Feature Branches
```bash
# Create feature/ prefix branch for GitHub
jj bookmark create feature/ACON-1234 -r ACON-1234
jj git push --bookmark feature/ACON-1234 --allow-new
```

### Cleanup
- `jj bookmark delete ACON-1234` - Delete bookmark after merge

## Standard Workflow

**1. Start work:**
```bash
jj bookmark create ACON-1234
jj new                             # Create new change on top of bookmark
gg start <task-id>                 # Claim task in gg
```

**2. Make changes & squash frequently:**
```bash
# ... edit files ... (auto-saved to @)
jj squash -m "Phase 1: Database migrations

Created V1.0.32-35 for feature X"

# After squash, @ becomes new empty change automatically
# ... more changes ...
jj squash -m "Phase 2: Entity updates"
```

**3. Complete work:**
```bash
jj squash -m "Phase 3: Final implementation"
gg complete <task-id>              # Mark task done in gg
```

**4. Push for PR:**
```bash
# Option A: Direct bookmark push
jj git push --bookmark ACON-1234 --allow-new

# Option B: Feature branch
jj bookmark create feature/ACON-1234 -r ACON-1234
jj git push --bookmark feature/ACON-1234 --allow-new
```

## Updating Your Branch with Latest Main

```bash
# Fetch and rebase onto latest main
jj git fetch
jj rebase -b ACON-1234 -d main@origin

# If using feature/ branch, update it too
jj bookmark set feature/ACON-1234 -r ACON-1234
jj git push --bookmark feature/ACON-1234
```

**Note:** jj handles force pushes automatically when needed

## Git Equivalents

| Git | JJ Squash Workflow |
|-----|-------------------|
| `git checkout -b feature` | `jj bookmark create ACON-1234` + `jj new` |
| `git add . && git commit` | Auto-saved, use `jj squash` when ready |
| `git rebase -i` (squash commits) | `jj squash -m "message"` |
| `git push origin branch` | `jj git push --bookmark ACON-1234` |
| `git pull --rebase` | `jj git fetch` + `jj rebase -d main` |

## Key Differences from Git

- **No staging area** - All changes auto-tracked in @
- **No `git add`** - Changes are always visible to jj
- **No `git commit`** - Use `jj squash` to create commits
- **@ (working copy)** - Always represents current work, gets refreshed after squash
- **Bookmarks** - Equivalent to git branches
- **`jj new` required** - Always create new change after bookmark before working
- **Squash direction** - Squashes @ DOWN into bookmark below
- **Operations log** - Can undo any operation with `jj op undo`

## Workflow Visualization

```
Initial:  ACON-1234 (bookmark)

After jj new:
  @ (empty, work here)
  |
  ACON-1234 (bookmark)

After making changes:
  @ (your changes)
  |
  ACON-1234 (bookmark)

After jj squash:
  @ (new empty change, ready for next phase)
  |
  ACON-1234 (bookmark with your changes squashed in)
```

## Troubleshooting

**View working copy status:**
```bash
jj status                           # What's changed in @
jj log -r '@' -T 'description'      # Current @ message
jj log                              # See bookmark and @ relationship
```

**View recent commits:**
```bash
jj log -r 'ancestors(@, 5)' -T 'change_id.short() ++ " " ++ description.first_line()'
```

**Undo mistakes:**
```bash
jj op undo                          # Undo last operation
jj op log                           # View operation history
```

**Forgot to jj new after bookmark?**
```bash
jj new                              # Create new change now
# Your changes stay in previous @, squash when ready
```

## Integration with gg

The squash workflow integrates with gg task tracking:

1. Create bookmark: `jj bookmark create ACON-1234`
2. Create new change: `jj new`
3. Claim task: `gg start <task-id>`
4. Work & squash: Multiple `jj squash` commands for phases
5. Complete task: `gg complete <task-id>`

**Commit message format:**
```
Phase N: Description
```
