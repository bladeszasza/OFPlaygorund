#!/bin/bash
# example_google_image_website.sh
# Demonstration: Google Image generation + Showrunner-driven website builder
#
# Agents used (leveraging ./agents library):
#   - google:orchestrator             → Design Showrunner (orchestrates workflow)
#   - google:brand-designer           → @creative/brand-designer (hero image)
#   - google:thumbnail-designer       → @creative/thumbnail-designer (detail image)
#   - anthropic:web-dev              → Custom web developer persona
#
# Architecture:
#   1. Showrunner (orchestrator) coordinates via [ASSIGN] directives
#   2. Image generators use Google Gemini text-to-image
#   3. Web developer builds HTML landing page
#   4. Web UI (--web flag) displays live progress
#   5. All artifacts saved to result/<session>/
#
# Usage:
#   bash example_google_image_website.sh [topic]
#   bash example_google_image_website.sh "A sustainable futuristic city"
#
# Requirements:
#   - GOOGLE_API_KEY environment variable set
#   - ANTHROPIC_API_KEY environment variable set (for web dev)
#   - ofp-playground CLI installed
#   - ./agents library available (loaded auto from @categories/agent-names)

set -e

TOPIC="${1:-SSJ5 character design of the DBZ warriors}"

echo "🎬 Starting Showrunner-Driven Image + Website Demo"
echo "   Topic: $TOPIC"
echo ""

ofp-playground start \
  --policy showrunner_driven \
  --no-human \
  --topic "$TOPIC" \
  --agent google:orchestrator:"Design Showrunner":"You are the creative director. Coordinate image generation and web design. 1) Assign Brand Designer to generate a hero image capturing the essence of: $TOPIC. 2) Assign Thumbnail Designer to generate a complementary detail/lifestyle image. 3) Assign Web Developer to build an HTML landing page with both images, responsive layout, and styling. Use [ASSIGN AgentName]: task syntax. When complete, [TASK_COMPLETE]." \
  --agent google:text-to-image:brand-designer:"@creative/brand-designer" \
  --agent google:text-to-image:thumbnail-designer:"@creative/thumbnail-designer"\
  --agent google:code-generation:"Web Developer":"You are an expert web developer. When assigned, create a beautiful HTML landing page with: 1) Hero image at top, 2) Detail image in featured section, 3) Responsive Tailwind CSS layout, 4) Professional typography. Output the COMPLETE HTML as a single code block in a markdown fence. Use relative address like :  ./../images/" \
