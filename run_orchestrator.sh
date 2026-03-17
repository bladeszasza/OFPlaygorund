#!/usr/bin/env bash
# Orchestrator-driven romantic comedy novella for 4-year-olds with lemurs
# Policy: showrunner_driven — Orchestrator speaks first, assigns tasks one at a time,
# accepts/rejects output, and signals TASK_COMPLETE when the story is done.
set -e

MISSION="Create a short romantic comedy novella for 4-year-olds featuring lemurs. \
The story must have: a beginning (two lemurs meet in the jungle), a middle (a funny \
misunderstanding keeps them apart), and an ending (they make up and share a mango). \
Total length: 4-5 pages (about 1000 words). Warm, silly tone. Simple vocabulary."

ofp-playground start \
  --no-human \
  --topic "$MISSION" \
  --max-turns 60 \
  --policy showrunner_driven \
  --agent "-provider orchestrator -name Director -system $MISSION -model openai/gpt-oss-120b" \
  --agent "-provider hf -name StoryWriter -system You write warm, simple prose for 4-year-olds. Write EXACTLY what the Director assigned you. Short sentences. Vivid jungle details. Friendly animals. MAX 120 words per turn. -model zai-org/GLM-5" \
  --agent "-provider hf -name DialogWriter -system You write funny, simple dialogue for 4-year-olds. Write EXACTLY what the Director assigned you. Lemurs speak in short excited sentences. Lots of oh no and tee-hee. MAX 80 words per turn. -model moonshotai/Kimi-K2-Instruct-0905" \
  --agent "-provider hf -name ComedyBeats -system You write one silly physical comedy moment. Write EXACTLY what the Director assigned you. MAX 50 words. Setup plus punchline. Lemurs trip, bump tails, or drop fruit. -model openai/gpt-oss-20b" \
  --agent "-provider hf -name CliffWriter -system You write gentle cliffhangers suitable for 4-year-olds. Write EXACTLY what the Director assigned you. MAX 40 words. End with oh no or I wonder. -model openai/gpt-oss-20b"
