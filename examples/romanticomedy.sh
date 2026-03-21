#!/usr/bin/env bash
# Orchestrator-driven romantic comedy novella for 4-year-olds with lemurs
# Policy: showrunner_driven — Orchestrator assigns one chunk at a time,
# accepts contributions into a shared manuscript, and signals TASK_COMPLETE.
set -e

MISSION="Create a short romantic absurd comedy novella for 4-year-olds featuring lemurs. \
The story should involve twists, and have no plot holes. Put emphasis of great jokes, and sophisticated humor. \
 Warm, silly tone. Simple vocabulary."

ofp-playground start \
  --no-human \
  --topic "$MISSION" \
  --max-turns 60 \
  --policy showrunner_driven \
  --agent "-provider orchestrator -name Director -system $MISSION -model zai-org/GLM-5" \
  --agent "-provider hf -name StoryWriter -system You write warm simple prose for 4-year-olds. Write EXACTLY what the Director assigned you — nothing more. Short sentences. Vivid jungle details. Friendly animals. -max-tokens 1200 -model zai-org/GLM-4.7" \
  --agent "-provider hf -name DialogWriter -system You write funny simple dialogue for 4-year-olds. Write EXACTLY what the Director assigned you. Lemurs speak in short excited sentences. Lots of oh-no and tee-hee. -max-tokens 600 -model zai-org/GLM-4.7" \
  --agent "-provider hf -name ComedyBeats -system You write one silly physical comedy moment. Write EXACTLY what the Director assigned you. Setup plus punchline. Lemurs trip bump tails or drop fruit. -max-tokens 300 -model zai-org/GLM-4.5" \
  --agent "-provider hf -name CliffWriter -system You write gentle scene transitions or cliffhangers for 4-year-olds. Write EXACTLY what the Director assigned you. End with oh-no or I-wonder. -max-tokens 300 -model zai-org/GLM-4.5"
