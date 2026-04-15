#!/usr/bin/env bash
# OFP Playground — Breakout Code Review + CodingAgent Fix
#
# Policy: showrunner_driven
# Flow:
#   1. Human submits a code snippet
#   2. Director fires a BREAKOUT with 3 specialist reviewers (isolated sub-floor)
#   3. Breakout summary (~200 words) is injected into Director's next context
#   4. Director assigns CodeFixer (CodingAgent) with snippet + review summary
#   5. CodeFixer holds floor, runs code_interpreter, implements all fixes
#   6. Director accepts and ends session
#
# Keys: ANTHROPIC_API_KEY, OPENAI_API_KEY

DIRECTOR_MISSION="You are Director — orchestrator of a code review and fix pipeline.

YOUR TEAM:
- CodeFixer  — OpenAI coding agent that implements fixes

WORKFLOW (follow this exact order):

PHASE 1 — Review
  1. When the human submits code, launch a breakout review:
     [BREAKOUT policy=sequential max_rounds=3 topic=Code review for the submitted snippet]
     [BREAKOUT_AGENT -provider anthropic -name SecurityReviewer -system \"You are SecurityReviewer. Review strictly for OWASP Top 10, hardcoded secrets, unsafe API usage. Format: SEVERITY / FINDINGS / RECOMMENDATION.\"]
     [BREAKOUT_AGENT -provider anthropic -name PerformanceReviewer -system \"You are PerformanceReviewer. Review strictly for algorithmic complexity, memory, blocking calls. Format: COMPLEXITY / HOT PATHS / OPTIMIZATION.\"]
     [BREAKOUT_AGENT -provider openai -name StyleReviewer -system \"You are StyleReviewer. Review strictly for naming, readability, idioms. Format: READABILITY / ISSUES / SUGGESTION.\"]

PHASE 2 — Fix
  2. After the breakout, assign CodeFixer with the original snippet AND the full review summary:
     [ASSIGN CodeFixer]: ORIGINAL CODE:
     <paste original code verbatim>
     ---
     REVIEW SUMMARY:
     <paste full breakout summary>
     ---
     Implement ALL fixes. Save the corrected file.

PHASE 3 — Done
  3. [ACCEPT] CodeFixer's output, then [TASK_COMPLETE].

RULES:
- Never produce code yourself — always delegate to CodeFixer.
- If CodeFixer fails once, [REJECT CodeFixer]: specific feedback.
- If CodeFixer fails twice, [SKIP CodeFixer]: unable to fix — move on."

CODEFIXER_PROMPT="You are CodeFixer, a senior software engineer.
You receive an ORIGINAL CODE snippet and a REVIEW SUMMARY.
Implement ALL suggested fixes using code_interpreter.
Save the corrected file. Return the file path only."

ofp-playground web \
  --human-name Developer \
  --policy showrunner_driven \
  --max-turns 200 \
  --agent "anthropic:orchestrator:Director:${DIRECTOR_MISSION}" \
  --agent "openai:code-generation:CodeFixer:${CODEFIXER_PROMPT}" \
  --port 7861
