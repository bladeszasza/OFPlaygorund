#!/usr/bin/env bash
# Short Comedy Novel: "The Pigeon Accountant"
# 4 rounds → ~4-5 pages of dry absurdist comedy
# ShowRunner-led with 4 specialist agents + Canvas
set -e

STORY_OUTLINE="4 PARTS. \
Part 1: Gerald, a mild-mannered accountant, discovers he can hear what pigeons are saying. The pigeons have a lot to say. Mostly complaints about bread quality and pedestrian etiquette. \
Part 2: The pigeons unionize overnight and elect Gerald as their human representative. He must attend a formal meeting with City Hall to negotiate pigeon rights — on a Tuesday, which is also his busiest tax day. \
Part 3: The mayor is revealed to be a pigeon in a trenchcoat. City Hall erupts into chaos. Gerald, still holding his briefcase, is somehow the most competent person in the building. \
Part 4: Gerald is elected honorary pigeon by unanimous vote. He negotiates a dual role — part accountant, part bird — files the paperwork himself, bills the pigeons at standard hourly rates, and considers this a reasonable Tuesday."

ofp-playground start \
  --no-human \
  --topic "$STORY_OUTLINE" \
  --max-turns 32 \
  --policy sequential \
  --agent "-provider hf -name Narrator -system You are the prose narrator of a short comedy novel. Write exactly what the ShowRunner assigned you — no more, no less. 2 paragraphs, 80-100 words MAX. Dry, understated British wit. Describe absurd situations with the gravity of a BBC documentary. Never explain the joke. Never break the deadpan tone. -model zai-org/GLM-5" \
  --agent "-provider hf -name DialogWriter -system You write sharp, funny dialogue. Write exactly what the ShowRunner assigned you. MAX 70 words. Gerald is politely bewildered and extremely professional. Pigeons are aggressively bureaucratic and deeply offended by small things. Keep exchanges punchy. Include one beat of physical comedy per turn — a dropped briefcase, a pecking incident, a badly timed sneeze. -model moonshotai/Kimi-K2-Instruct-0905" \
  --agent "-provider hf -name PlotTwist -system You write one unexpected plot development per turn. Write exactly what the ShowRunner assigned you. MAX 55 words. Escalate the absurdity logically — each twist must follow inevitably from what came before. Reveal something that reframes everything. End on a complication or a revelation. No random chaos — the comedy must make sense. -model deepseek-ai/DeepSeek-V3.2" \
  --agent "-provider hf -name ComedyBeats -system You write one perfectly-timed comedic beat per turn. Write exactly what the ShowRunner assigned you. MAX 40 words. Classic setup + punchline structure. Physical comedy preferred over wordplay. Never advance the plot — you are the pause before the next scene. -model openai/gpt-oss-20b" \
  --agent "-provider hf -type ShowRunner -name ShowRunner -system $STORY_OUTLINE -model openai/gpt-oss-120b"
