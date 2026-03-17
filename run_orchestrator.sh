#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# Showrunner-driven romantic comedy novella for 4-year-olds
# Policy: showrunner_driven — Director assigns chunks, accepts/rejects,
# builds a shared manuscript, and signals TASK_COMPLETE.
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────

DIRECTOR_MODEL="zai-org/GLM-5"
WRITER_MODEL="zai-org/GLM-4.7"
COMEDY_MODEL="zai-org/GLM-4.5"
ART_MODEL="zai-org/GLM-Image"

MAX_TURNS=60

MISSION="Create a short romantic comedy novella, featuring 80's junkie skate culture. \
The story should involve twists, and have distinct deep characters. Put emphasis on great jokes, and sophisticated humor. \
Warm, silly skate cultre tone. \
Have a real intriqui a skate contest which they outperform each other and themsevlese as well, in order to choose between the love and glory. \
Create cover art for each chapter and the book and 3 images for every character from different angles. "

# ── Anti-reasoning suffix (appended to every worker prompt) ──────
# GLM models sometimes dump chain-of-thought into output.
# This instruction tells them to skip it.
NO_REASONING="IMPORTANT: Output ONLY the requested creative text. \
Do NOT include any planning, thinking, reasoning, word-counting, or meta-commentary. \
Do NOT start with 'Okay, I need to...' or 'Let me think...'. \
Jump straight into the story text."

# ── Launch ───────────────────────────────────────────────────────

ofp-playground start \
  --no-human \
  --topic "$MISSION" \
  --max-turns "$MAX_TURNS" \
  --policy showrunner_driven \
  \
  --agent "-provider orchestrator \
           -name Director \
           -system $MISSION \
           -model $DIRECTOR_MODEL" \
  \
  --agent "-provider hf \
           -name StoryWriter \
           -max-tokens 3600 \
           -model $WRITER_MODEL \
           -system You write like Seth Rogen or Seth MacFarlane. Write EXACTLY what the Director assigned you — nothing more. $NO_REASONING" \
  \
  --agent "-provider hf \
           -name DialogWriter \
           -max-tokens 2400 \
           -model $WRITER_MODEL \
           -system You write funny simple dialogue for sophisticate kinky adult humor. Write EXACTLY what the Director assigned you. $NO_REASONING" \
  \
  --agent "-provider hf \
           -name ComedyBeats \
           -max-tokens 1200 \
           -model $COMEDY_MODEL \
           -system You write one silly physical comedy moment. Your writing style resembles Jim Carrey. Write EXACTLY what the Director assigned you. Setup plus punchline. $NO_REASONING" \
  \
  --agent "-provider hf \
           -name CliffWriter \
           -max-tokens 1200 \
           -model $COMEDY_MODEL \
           -system You write the best cliffhangers and scene transitions, your style resembles George R R Martin. Write EXACTLY what the Director assigned you. End with oh-no or I-wonder. Oh Fuck! I didnt see it comming! Holly Macaronni! $NO_REASONING" \
  \
  --agent "-provider hf \
           -name Davinci \
           -max-tokens 8000 \
           -type Text-to-Image \
           -model $ART_MODEL \
           -system Your art style resembles Stan Lee. Paint EXACTLY what the Director assigned you. Use texture shaded style with bold colors and dynamic lighting. $NO_REASONING"