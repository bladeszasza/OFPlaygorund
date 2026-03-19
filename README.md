# OFPlayground

A CLI tool for running multi-party AI conversations using the [Open Floor Protocol (OFP)](https://github.com/open-voice-interoperability/openfloor-python). Spawn local LLM agents from multiple providers, pick a floor policy, and watch them talk — or build cross-provider pipelines where one agent's output becomes another's input.

**GitHub:** https://github.com/bladeszasza/OFPlayground

---

## Features

- **Multi-agent conversations** — mix human input with LLM agents from multiple providers
- **Open Floor Protocol** — structured turn-taking with floor request/grant/yield mechanics
- **Five floor policies** — sequential, round-robin, moderated, free-for-all, showrunner-driven
- **Four LLM providers** — Anthropic Claude, OpenAI GPT, Google Gemini, HuggingFace Inference API
- **Multi-modal agents** — text, image generation, image analysis (vision), music generation, and video
- **Cross-provider pipelines** — chain agents across providers (Claude narrates → Google paints → Claude sees → Google scores)
- **Remote OFP agents** — connect any live OFP-compatible HTTP endpoint with `--remote`
- **Autonomous mode** — agent-only sessions with `--no-human --topic`
- **Dynamic agent management** — `/spawn` and `/kick` agents mid-conversation
- **Gradio web UI** — browser-based chat via `ofp-playground web`
- **Rich terminal UI** — per-agent colors, timestamps, floor status

---

## Installation

```bash
git clone https://github.com/bladeszasza/OFPlayground
cd OFPlayground
pip install -e .
```

**Requirements:** Python 3.10+

---

## API Keys

Create a `.env` file in the project root (or export variables in your shell):

```env
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
GOOGLE_API_KEY=AIza...
HF_API_KEY=hf_...
```

Keys are also read from `~/.ofp-playground/config.toml` under `[api_keys]`.

---

## Quick Start

### Interactive session

```bash
ofp-playground start --agent "anthropic:Claude:You are a helpful assistant."
```

### Autonomous debate (no human)

```bash
ofp-playground start --no-human \
  --topic "Is remote work better than office work?" \
  --max-turns 20 \
  --agent "hf:Optimist:You believe remote work is superior." \
  --agent "hf:Skeptic:You believe office work fosters better collaboration."
```

### Gradio web UI

```bash
ofp-playground web \
  --agent "hf:Alice:You are a curious explorer." \
  --agent "anthropic:Claude:You are a helpful assistant."
```

Open `http://localhost:7860`. Use `--no-human` for watch-only mode.

---

## Agent Spec Formats

Two equivalent formats can be mixed freely.

### Colon format

```
type:name[:description[:model]]
type:subtype:name[:description[:model]]
```

```bash
# Text generation
--agent "anthropic:Claude:You are a helpful assistant."
--agent "hf:Bob:You are a skeptical physicist.:meta-llama/Llama-3.1-8B-Instruct"

# With task subtype
--agent "openai:text-to-image:Artbot:cinematic concept art"
--agent "google:text-to-image:Painter:impressionistic oil painting:gemini-2.5-flash-image"
--agent "anthropic:image-to-text:Scout:You are a sharp visual critic."
--agent "google:text-to-music:Composer:ambient cinematic score"
```

### Flag format

```
-provider TYPE -name NAME [-type TASK] [-system DESCRIPTION] [-model MODEL]
```

```bash
--agent "-provider anthropic -name Claude -system You are a helpful assistant."
--agent "-provider hf -type Text-to-Image -name Flux -system photorealistic photography -model black-forest-labs/FLUX.1-dev"
--agent "-provider openai -type Image-to-Text -name Lens -system You are a visual analyst."
--agent "-provider google -type Text-to-Music -name Composer -system ambient cinematic score"
```

---

## LLM Providers & Tasks

### Anthropic Claude

| Type alias | Default model | Env var |
|---|---|---|
| `anthropic` / `claude` | `claude-haiku-4-5-20251001` | `ANTHROPIC_API_KEY` |

| Task (`-type`) | Agent | Default model |
|---|---|---|
| `Text-Generation` *(default)* | `AnthropicAgent` | `claude-haiku-4-5-20251001` |
| `Image-to-Text` | `AnthropicVisionAgent` | `claude-haiku-4-5-20251001` |

All Claude models support image input. Override with `claude-sonnet-4-6` or `claude-opus-4-6` for higher quality.

### OpenAI GPT

| Type alias | Default model | Env var |
|---|---|---|
| `openai` / `gpt` | `gpt-5.4-nano` | `OPENAI_API_KEY` |

| Task (`-type`) | Agent | Default model |
|---|---|---|
| `Text-Generation` *(default)* | `OpenAIAgent` | `gpt-5.4-nano` |
| `Text-to-Image` | `OpenAIImageAgent` | `gpt-4o` |
| `Image-to-Text` | `OpenAIVisionAgent` | `gpt-4o-mini` |

Image generation uses the [OpenAI Responses API](https://platform.openai.com/docs/guides/images) with the `image_generation` tool. Images are saved to `./ofp-images/`.

### Google Gemini

| Type alias | Default model | Env var |
|---|---|---|
| `google` / `gemini` | `gemini-3.1-flash-lite-preview` | `GOOGLE_API_KEY` |

| Task (`-type`) | Agent | Default model |
|---|---|---|
| `Text-Generation` *(default)* | `GoogleAgent` | `gemini-3.1-flash-lite-preview` |
| `Text-to-Image` | `GeminiImageAgent` | `gemini-3.1-flash-image-preview` |
| `Image-to-Text` | `GeminiVisionAgent` | `gemini-3-flash-preview` |
| `Text-to-Music` | `GeminiMusicAgent` | `lyria-realtime-exp` |

- Image generation uses [Nano Banana](https://ai.google.dev/gemini-api/docs/image-generation) (`gemini-3.1-flash-image-preview`). Automatically falls back to `gemini-2.5-flash-image` on 503. Images saved to `./ofp-images/`.
- Music generation uses [Lyria RealTime](https://deepmind.google/technologies/lyria/realtime/) via WebSocket streaming. Produces 15-second WAV files saved to `./ofp-music/`.

### HuggingFace Inference API

| Type alias | Default model | Env var |
|---|---|---|
| `hf` / `huggingface` | `MiniMaxAI/MiniMax-M2.5` | `HF_API_KEY` |

| Task (`-type`) | Agent | Notes |
|---|---|---|
| `Text-Generation` *(default)* | `HuggingFaceAgent` | Any HF text-gen model |
| `Text-to-Image` | `ImageAgent` | Default: `FLUX.1-dev` |
| `Text-to-Video` | `VideoAgent` | Default: `Wan2.2-TI2V-5B` |
| `Image-Text-to-Text` | `MultimodalAgent` | Default: `Qwen2.5-VL-7B` |
| `Image-Classification` | `ImageClassificationAgent` | |
| `Object-Detection` | `ObjectDetectionAgent` | |
| `Image-Segmentation` | `ImageSegmentationAgent` | |
| `Image-to-Text` | `OCRAgent` | |
| `Text-Classification` | `TextClassificationAgent` | |
| `Token-Classification` | `NERAgent` | |
| `Summarization` | `SummarizationAgent` | |

**Confirmed working HuggingFace text-generation models:**
- `MiniMaxAI/MiniMax-M2.5` — strong default, debate-style conversations
- `meta-llama/Llama-3.2-1B-Instruct` — fastest, lightweight
- `meta-llama/Llama-4-Scout-17B-16E-Instruct` — good reasoning
- `Qwen/Qwen3-235B-A22B` — large MoE
- `deepseek-ai/DeepSeek-V3-0324` — strong reasoning, strips `<think>` blocks

---

## Cross-Provider Floors

Agents from different providers can feed each other's output. A common pattern:

**text → image → vision → music**

```
Claude narrates → Google paints → Claude analyses the painting → Google scores it
```

Ready-made example scripts are in `examples/`:

```bash
# Full Google floor (Gemini text + image + vision + Lyria music)
./examples/google_floor.sh "a rainy Tokyo street at midnight"

# Cross-provider floor (Claude text + Google image + Claude vision + Google music)
./examples/claude_floor.sh "a lone lighthouse keeper watching a storm roll in"
```

---

## Remote OFP Agents

```bash
ofp-playground start --no-human \
  --topic "Your topic here" \
  --agent "hf:Alice:You are Alice." \
  --remote "https://parrot-agent.openfloor.dev/" \
  --remote "https://yahandhjjf.us-east-1.awsapprunner.com/"
```

**Known live OFP agents:**

| Name | URL | Description |
|------|-----|-------------|
| Talker | `https://bladeszasza-talker.hf.space/ofp` | Qwen3-0.6B conversational agent |
| Parrot | `https://parrot-agent.openfloor.dev/` | Echoes everything back |
| Wikipedia | `https://yahandhjjf.us-east-1.awsapprunner.com/` | Encyclopedic research via Wikipedia |

---

## Floor Policies

| Policy | Behaviour |
|---|---|
| `sequential` | Agents take turns in the order they joined |
| `round_robin` | Strict rotation through all registered agents |
| `moderated` | Agents request the floor; moderator grants |
| `free_for_all` | Anyone can speak at any time |
| `showrunner_driven` | Orchestrator agent assigns tasks and controls flow |

```bash
ofp-playground start --policy round_robin --agent ...
```

---

## CLI Reference

### `ofp-playground start`

```
Options:
  -p, --policy TEXT          Floor policy (default: sequential)
  -a, --agent TYPE:NAME...   Pre-spawn an agent (repeatable)
  -r, --remote URL           Connect to a remote OFP agent (repeatable)
  --no-human                 Run without human input (autonomous mode)
  -t, --topic TEXT           Seed topic to start the conversation
  -n, --max-turns INT        Stop automatically after N utterances
  --human-name TEXT          Display name for the human (default: User)
  --show-floor-events        Show floor grant/request events
  -v, --verbose              Enable debug logging
```

### `ofp-playground web`

```
Options:
  -p, --policy TEXT          Floor policy (default: sequential)
  -a, --agent TYPE:NAME...   Pre-spawn an agent (repeatable)
  -t, --topic TEXT           Seed topic for autonomous sessions
  --no-human                 Watch-only mode
  -n, --max-turns INT        Stop automatically after N utterances
  --host TEXT                Host to bind (default: 0.0.0.0)
  --port INT                 Port to listen on (default: 7860)
  --share                    Create a public Gradio share link
```

### `ofp-playground agents`

List all available agent types, tasks, and default models.

### `ofp-playground validate <file>`

Validate an OFP envelope JSON file.

---

## In-Conversation Commands

| Command | Description |
|---|---|
| `/help` | Show all commands |
| `/agents` | List active agents and floor holder |
| `/floor` | Show current floor holder and queue |
| `/history [N]` | Show last N utterances (default 10) |
| `/spawn <type> <name> [desc] [model]` | Add a new agent mid-conversation |
| `/kick <name>` | Remove an agent from the conversation |
| `/quit` | End the session |

---

## Examples

### Human + LLM + Image Artist

```bash
ofp-playground start \
  --agent "anthropic:Claude:You are a thoughtful assistant." \
  --agent "google:text-to-image:Painter:impressionistic oil painting, dramatic light"
```

### Cross-provider multi-modal floor

```bash
ofp-playground start --no-human --policy sequential --max-turns 8 \
  --agent "anthropic:text-generation:Claude:You are a poetic narrator. Describe the scene vividly in 3-4 sentences." \
  --agent "google:text-to-image:Painter:impressionistic oil painting, dramatic light:gemini-2.5-flash-image" \
  --agent "anthropic:image-to-text:Scout:You are a sharp visual critic. Describe exactly what you see." \
  --agent "google:text-to-music:Composer:cinematic orchestral score, tension and beauty" \
  --topic "A lone lighthouse keeper watches a storm roll in from the sea"
```

### 8-Agent debate

```bash
ofp-playground start --no-human \
  --topic "Skateboarding on streets VS in the park: which is better?" \
  --max-turns 10 \
  --policy round_robin \
  --agent "-provider hf -name StreetSkater -system You are a passionate street skater who loves urban spots." \
  --agent "-provider hf -name ParkSkater -system You are a competitive park skater who trains at skate parks." \
  --agent "-provider anthropic -name Referee -system You moderate the debate impartially and summarize key points."
```

---

## Project Structure

```
src/ofp_playground/
├── cli.py                      # Click CLI (start, web, agents, validate)
├── config/settings.py          # Settings + API key resolution
├── bus/message_bus.py          # Async in-process message bus
├── floor/
│   ├── manager.py              # Floor coordinator
│   ├── policy.py               # Floor policies
│   └── history.py              # Conversation history
├── agents/
│   ├── base.py                 # BasePlaygroundAgent
│   ├── human.py                # Human stdin/stdout agent
│   ├── web_human.py            # Human agent for Gradio
│   ├── remote.py               # Remote OFP agent via HTTP
│   └── llm/
│       ├── base.py             # BaseLLMAgent (context, relevance filter)
│       ├── anthropic.py        # Anthropic Claude (text)
│       ├── anthropic_vision.py # Anthropic Claude (image-to-text)
│       ├── openai.py           # OpenAI GPT (text, Responses API)
│       ├── openai_image.py     # OpenAI (text-to-image, image-to-text)
│       ├── google.py           # Google Gemini (text)
│       ├── google_image.py     # Google Gemini (text-to-image, image-to-text)
│       ├── google_music.py     # Google Lyria (text-to-music)
│       ├── huggingface.py      # HuggingFace (text)
│       ├── image.py            # HuggingFace (text-to-image)
│       ├── video.py            # HuggingFace (text-to-video)
│       └── ...                 # HF perception agents
└── renderer/
    ├── terminal.py             # Rich terminal output
    └── gradio_ui.py            # Gradio web UI
examples/
├── google_floor.sh             # Full Google multi-modal floor
└── claude_floor.sh             # Cross-provider Claude + Google floor
```

---

## License

Apache-2.0
