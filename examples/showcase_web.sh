#!/usr/bin/env bash
# OFP Playground — Creative Brand Studio | Gradio Web UI | Policy: round_robin
# Usage: bash examples/showcase_web.sh
# Keys: HF_API_KEY
#
# Agent slugs resolve to agents/<category>/<name>/SOUL.md automatically.

ofp-playground web \
  --human-name Jhony \
  --policy round_robin \
  --max-turns 600 \
  --agent "hf:text:BrandDesigner:@creative/brand-designer" \
  --agent "hf:text:Copywriter:@creative/copywriter" \
  --agent "hf:text:StoryboardWriter:@creative/storyboard-writer" \
  --port 7860
