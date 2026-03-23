#!/usr/bin/env bash
# OFP Playground — Multi-Provider Showcase
#
# Demonstrates one agent from every supported provider/modality in a single session:
#
#   Director   — Anthropic Claude Haiku     — orchestrator: coordinates the team
#   Analyst    — OpenAI GPT-5.4-nano        — text analysis and writing
#   Painter    — HuggingFace FLUX.1-dev     — text-to-image generation
#   Composer   — Google Lyria RealTime      — text-to-music generation
#   Verity     — Remote OFP (fact-checker)  — verifies claims against known facts
#
# Policy: showrunner_driven — Director issues [ASSIGN] directives to each specialist
# with concise, focused tasks. No human input needed.
#
# Requirements:
#   ANTHROPIC_API_KEY — Claude Haiku (Director)
#   OPENAI_API_KEY    — GPT-5.4-nano (Analyst)
#   HF_API_KEY        — FLUX image generation (Painter)
#   GOOGLE_API_KEY    — Lyria music generation (Composer)
#
# Usage:
#   chmod +x examples/showcase.sh
#   ./examples/showcase.sh
#   ./examples/showcase.sh "Your custom topic here"

TOPIC="${1:-The James Webb Space Telescope has found ancient, massive galaxies in the early universe that challenge our standard cosmological model. Explore this discovery: what was found, why it matters, and what it means for our understanding of cosmic origins.}"

ofp-playground start \
  --no-human \
  --policy showrunner_driven \
  --max-turns 20 \
  --agent "anthropic:orchestrator:Director:Coordinate the team to explore the topic. First assign the Analyst to write a concise expert summary. Then assign the Painter to visualize a striking scene from the discovery. Then assign the Composer to create evocative ambient music inspired by the cosmos. Finally assign Verity to verify the key scientific claims. After all four have contributed, issue [TASK_COMPLETE]." \
  --agent "openai:Analyst:You are a science journalist. Write a clear, compelling 3-paragraph summary of the assigned topic for a general audience. Highlight what makes it surprising or important." \
  --agent "hf:text-to-image:Painter" \
  --agent "google:text-to-music:Composer" \
  --remote verity \
  --topic "$TOPIC"
