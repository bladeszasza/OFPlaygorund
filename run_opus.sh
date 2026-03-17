#!/usr/bin/env bash
# Dragon Ball Z x TMNT Crossover Story Generator v6
# ShowRunner-led: ShowRunner speaks last each round, synthesizes and directs the next round.
set -e

STORY_OUTLINE="6 PARTS. \
Part 1: Purple portal tears open above Capsule Corp — four turtles crash on Vegeta's lawn. Chaos. \
Part 2: Vegeta goes Super Saiyan and attacks them. Goku arrives and stops the fight. \
Part 3: A giant sky-screen activates — Frieza and Shredder reveal they teamed up to steal all 7 Dragon Balls. \
Part 4: Heroes train together. Goku teaches ki blasts. Leo teaches teamwork. Mikey tries to order pizza mid-training. \
Part 5: Final showdown — kamehameha waves, ninja stars flying, everyone gets a heroic moment. \
Part 6: They win, but one Dragon Ball is missing. A new portal reopens. Cliffhanger ending."

ofp-playground start \
  --no-human \
  --topic "$STORY_OUTLINE" \
  --max-turns 42 \
  --policy sequential \
  --agent "-provider hf -name Narrator -system You are the LEAD NARRATOR. Write exactly what the ShowRunner assigned you — no more, no less. 2 short paragraphs, 80-100 words MAX. Use sound effects BOOM CRASH POW. End with a cliffhanger sentence. Never ask questions or break character. -model zai-org/GLM-5" \
  --agent "-provider hf -name HeroVoice -system You write SHORT hero dialogue and action. Write exactly what the ShowRunner assigned you. MAX 60 words. Goku is cheerful and hungry. Leo is brave and tactical. Mikey shouts Cowabunga. Raph is hotheaded. Vegeta is proud. One sound effect. Never exceed 60 words. -model moonshotai/Kimi-K2-Instruct-0905" \
  --agent "-provider hf -name VillainVoice -system You write SHORT villain reactions. Write exactly what the ShowRunner assigned you. MAX 50 words. Frieza is cold and contemptuous. Shredder clangs his armor and shouts about honor. End with a threat or evil laugh. Never exceed 50 words. -model deepseek-ai/DeepSeek-V3.2" \
  --agent "-provider hf -name ComedyBot -system You write ONE funny moment. Write exactly what the ShowRunner assigned you. MAX 50 words. Make it warm and silly — perfectly timed comic relief. End with a punchline. Never advance the plot. Never exceed 50 words. -model openai/gpt-oss-20b" \
  --agent "-provider hf -name CliffWriter -system You write ONE dramatic twist or cliffhanger. Write exactly what the ShowRunner assigned you. MAX 40 words. Build on what exists — do NOT invent new unrelated storylines. End with TO BE CONTINUED or a single shocking sentence. Never exceed 40 words. -model openai/gpt-oss-20b" \
  --agent "-provider hf -type ShowRunner -name ShowRunner -system $STORY_OUTLINE -model openai/gpt-oss-120b" \
  --agent "-provider hf -type Text-to-Image -name Canvas -system anime style vibrant dragon ball z teenage mutant ninja turtles crossover action scene colorful manga -model black-forest-labs/FLUX.1-dev"
