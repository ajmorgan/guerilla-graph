---
source: https://github.com/tigerbeetle/tigerbeetle/blob/ac75926f8868093b342ce2c64eac1e3001cf2301/docs/TIGER_STYLE.md
project: TigerBeetle
license: Apache-2.0
downloaded: 2025-12-08
purpose: Reference for Zig coding standards and design principles
---

# Tiger Style

## The Essence Of Style

> "There are three things extremely hard: steel, a diamond, and to know one's self." — Benjamin Franklin

TigerBeetle's coding style represents a synthesis of engineering and artistry—balancing numbers with intuition, reason with experience, and precision with poetry. It's a collective evolution shaped by first principles and accumulated knowledge.

## Why Have Style?

Another term for style is design.

> "The design is not just what it looks like and feels like. The design is how it works." — Steve Jobs

The design goals are safety, performance, and developer experience, in that order. Good style advances these goals.

> "...in programming, style is not something to pursue directly. Style is necessary only where understanding is missing." — Let Over Lambda

This document explores how these design goals apply to coding style.

## On Simplicity And Elegance

Simplicity is not a compromise—it's how we unify design goals into something elegant.

> "Simplicity and elegance are unpopular because they require hard work and discipline to achieve" — Edsger Dijkstra

Simplicity is rarely the first attempt; it's the hardest revision. Substantial mental effort upfront—during design—pays dividends because design costs are dwarfed by implementation, testing, operation, and maintenance costs.

> "the simple and elegant systems tend to be easier and faster to design and get right, more efficient in execution, and much more reliable" — Edsger Dijkstra

## Technical Debt

Problems discovered in design are vastly cheaper to fix than those found in production. TigerBeetle enforces a zero technical debt policy—solutions are implemented correctly the first time.

> "You shall not pass!" — Gandalf

This ensures that shipped work is solid and building momentum through consistently high-quality output.

## Safety

> "The rules act like the seat-belt in your car: initially they are perhaps a little uncomfortable, but after a while their use becomes second-nature." — Gerard J. Holzmann

Safety practices include:

**Control Flow & Structure:**
- Use only simple, explicit control flow; avoid recursion to ensure bounded execution
- Minimize abstractions; they always carry costs and introduce leaky-abstraction risks
- Put limits on everything—loops, queues, and allocations must have fixed upper bounds
- Use explicitly-sized types (u32) rather than architecture-dependent types (usize)

**Assertions:**
Assertions detect programmer errors and are critical for safety:
- Assert all function arguments, return values, preconditions, postconditions, and invariants
- Target a minimum assertion density of two per function
- Pair assertions: enforce properties in at least two different code paths
- Split compound assertions for clarity (prefer `assert(a); assert(b);` over `assert(a and b);`)
- Assert compile-time constant relationships to document subtle invariants
- Assert both positive space (what you expect) and negative space (what you don't)

**Memory & Scope:**
- All memory must be statically allocated at startup; no dynamic allocation after initialization
- Declare variables at the smallest possible scope
- Restrict function bodies to a hard limit of 70 lines

**Control & Boundaries:**
- Appreciate all compiler warnings at the strictest setting
- Don't react directly to external events; let your program run at its own pace
- Compound conditions make verification difficult; use nested if/else branches instead
- State invariants positively; prefer `if (index < length)` forms
- All errors must be handled

> "Specifically, we found that almost all (92%) of the catastrophic system failures are the result of incorrect handling of non-fatal errors explicitly signaled in software."

**Documentation & Clarity:**
- Always explain the rationale for decisions
- Pass options explicitly to library functions rather than relying on defaults
- Avoid latent bugs from library default changes

## Performance

> "The lack of back-of-the-envelope performance sketches is the root of all evil." — Rivacindela Hudsoni

Performance principles:

- Think about performance from design outset—major 1000x wins happen during design, before measurement
- Perform back-of-the-envelope sketches for network, disk, memory, and CPU (bandwidth and latency)
- Optimize slowest resources first (network → disk → memory → CPU), adjusting for frequency of use
- Distinguish control plane from data plane; use batching for both safety and performance
- Amortize network, disk, memory, and CPU costs through batching
- Give the CPU large, predictable chunks of work; avoid context-switching inefficiencies
- Be explicit; minimize reliance on compiler to optimize

## Developer Experience

> "There are only two hard things in Computer Science: cache invalidation, naming things, and off-by-one errors." — Phil Karlton

### Naming Things

Excellent naming is the foundation of excellent code:

- Get nouns and verbs precisely right to capture domain understanding
- Use `snake_case` for functions, variables, and file names
- Avoid abbreviations (except for primitive integers in specific contexts)
- Use proper capitalization for acronyms (VSRState, not VsrState)
- Add units or qualifiers to variable names, sorted by descending significance (e.g., `latency_ms_max`)
- Choose related names with the same character count to achieve visual alignment
- Prefix helper function names with their caller's name to show call hierarchy
- Place callbacks last in parameter lists, mirroring control flow
- Order matters: main function first, then consider alphabetical sorting
- Avoid overloading names with multiple context-dependent meanings
- Use nouns rather than adjectives for names that will appear in documentation
- Write descriptive commit messages that inform and delight readers
- Explain why code exists, not just what it does
- Document methodology in tests to help readers skip sections
- Comments are sentences with proper capitalization, spacing, and punctuation

### Cache Invalidation

Preventing state synchronization bugs:

- Don't duplicate variables or create aliases; reduce sync risks
- Pass large arguments (>16 bytes) as `*const` to catch accidental copies
- Construct larger structs in-place using out pointers during initialization
- In-place initialization requires pointer stability; prefer it for leaf functions
- Minimize variables in scope to reduce misuse probability
- Calculate or check variables close to where they're used (avoid POCPOU bugs)
- Use simpler function signatures and return types to reduce dimensionality
- Ensure functions run to completion without suspending, preserving assertion validity
- Watch for buffer bleeds (underflows with unzeroed padding)
- Use newlines to group resource allocation and deallocation for leak visibility

### Off-By-One Errors

Index, count, and size are distinct types with clear conversion rules:

- Index (0-based) + 1 = count (1-based)
- Count × unit = size
- Show intent in division using @divExact(), @divFloor(), or div_ceil()

### Style By The Numbers

- Run `zig fmt`
- Use 4 spaces of indentation (clearer than 2)
- Hard limit line lengths to 100 columns maximum; use trailing commas for formatting
- Add braces to if statements unless they fit on one line (defense against goto-fail bugs)

### Dependencies

TigerBeetle enforces a zero-dependencies policy apart from the Zig toolchain. Dependencies introduce supply chain risk, safety concerns, performance overhead, and slow installs. For foundational infrastructure, these costs amplify throughout the entire stack.

### Tooling

Tools have costs. A small, standardized toolbox outweighs specialized instruments.

> "The right tool for the job is often the tool you are already using—adding new tools has a higher cost than many people appreciate" — John Carmack

Standardize on Zig for tooling (e.g., scripts should be `.zig`, not `.sh`). This ensures cross-platform portability, type safety, and reduces dimensionality as teams grow.

## The Last Stage

Keep experimenting, have fun, and remember: TigerBeetle is small and fast.

> "You don't really suppose, do you, that all your adventures and escapes were managed by mere luck, just for your sole benefit?... You are only quite a little fellow in a wide world after all!"
