# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Directory Is

`agents/` is a library of 207 SOUL.md persona files — structured system prompts for AI agents — organized into 24 category subdirectories. There is no build system, tests, or executable code here. The only task is reading, writing, and maintaining `SOUL.md` files.

The library is loaded by `src/ofp_playground/agents/library.py`. Every `agents/<category>/<agent-name>/SOUL.md` is addressable as `@category/agent-name` without any registration step.

## Adding a New Persona

```
agents/<category>/<agent-name>/SOUL.md
```

The slug is `@<category>/<agent-name>` — the directory names are the slug. No registration needed; the loader rescans on next process start.

To verify it's discoverable:
```bash
ofp-playground agents | grep <agent-name>
```

## SOUL.md Format

Free-form Markdown. No required frontmatter. The loader extracts the display name from the first heading, stripping common prefixes (`# `, `# Agent: `, `# SOUL.md — `).

Three heading styles are in use across the library — pick the one that fits:

```markdown
# Agent: Name Here          ← most common (business/creative/etc.)
# Name Here                  ← terse style (development/*)
# SOUL.md — Name Here        ← older style (data/marketing/*)
```

Common section structure seen across the library:

```markdown
## Identity / Core Identity
## Responsibilities
## Skills / Capabilities
## Rules / Behavioral Guidelines
## Tone
## Example Interactions   ← optional but valuable
```

The `development/` category personas embed software methodology (TDD, debugging discipline, verification). Match that level of specificity when writing new development personas.

## Categories

| Category | Count | Notes |
|---|---:|---|
| `marketing` | 28 | Largest category |
| `development` | 23 | Coding-methodology personas; `@development/coding-agent` auto-loaded by `BaseCodingAgent` |
| `business` | 14 | |
| `creative` | 19 | |
| `finance` | 10 | |
| `devops` | 10 | |
| `productivity` | 9 | |
| `data` | 9 | |
| `hr` | 8 | |
| `education` | 8 | |
| `personal` | 7 | |
| `healthcare` | 7 | |
| `ecommerce` | 7 | |
| `security` | 6 | |
| `saas` | 6 | |
| `legal` | 6 | |
| `automation` | 6 | |
| `real-estate` | 5 | |
| `freelance` | 4 | |
| `compliance` | 4 | |
| `voice` | 3 | |
| `supply-chain` | 3 | |
| `moltbook` | 3 | Agent-to-agent social network personas |
| `customer-success` | 2 | |

For complete documentation including Python loading API, see [`docs/agents-library.md`](../docs/agents-library.md).
