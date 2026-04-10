"""Google Lyria music generation agent (text-to-music).

Supports two API modes automatically selected by model name:
  - Lyria 3 Clip / Pro (lyria-3-clip-preview, lyria-3-pro-preview):
      uses client.models.generate_content() — standard REST API
  - Lyria RealTime (models/lyria-realtime-exp):
      uses client.aio.live.music.connect() — WebSocket streaming API
"""
from __future__ import annotations

import asyncio
import logging
import re
import wave
from datetime import datetime
from pathlib import Path
from typing import Optional

from openfloor import Capability, Envelope, Identification, Manifest, SupportedLayers

from ofp_playground.agents.base import BasePlaygroundAgent
from ofp_playground.bus.message_bus import MessageBus

logger = logging.getLogger(__name__)

OUTPUT_MUSIC_DIR = Path("ofp-music")
DEFAULT_MUSIC_MODEL = "models/lyria-realtime-exp"
GEMINI_MUSIC_URI_TEMPLATE = "tag:ofp-playground.local,2025:gmusic-{name}"

# Lyria RealTime output format: raw 16-bit PCM stereo 48 kHz
RT_SAMPLE_RATE = 48000
RT_CHANNELS = 2
RT_BYTES_PER_SAMPLE = 2
DEFAULT_DURATION_SECONDS = 15


class GeminiMusicAgent(BasePlaygroundAgent):
    """Music agent that generates music via Google Lyria (Clip, Pro, or RealTime)."""

    def __init__(
        self,
        name: str,
        style: str,
        bus: MessageBus,
        conversation_id: str,
        api_key: str,
        model: str = DEFAULT_MUSIC_MODEL,
        duration_seconds: int = DEFAULT_DURATION_SECONDS,
    ):
        speaker_uri = GEMINI_MUSIC_URI_TEMPLATE.format(name=name.lower().replace(" ", "-"))
        super().__init__(
            speaker_uri=speaker_uri,
            name=name,
            service_url=f"local://gmusic-{name.lower()}",
            bus=bus,
            conversation_id=conversation_id,
        )
        self._style = style
        self._model = model or DEFAULT_MUSIC_MODEL
        self._api_key = api_key
        self._duration_seconds = duration_seconds
        self._has_floor = False
        self._last_text: Optional[str] = None
        self._raw_prompt: Optional[str] = None  # directive task from orchestrator
        self._output_dir: Path = OUTPUT_MUSIC_DIR
        self._output_dir.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # Model routing
    # ------------------------------------------------------------------

    def _is_realtime_model(self) -> bool:
        """Return True if the model requires the RealTime WebSocket API."""
        return "realtime" in self._model.lower()

    # ------------------------------------------------------------------
    # Manifest
    # ------------------------------------------------------------------

    def _build_manifest(self) -> Manifest:
        return Manifest(
            identification=Identification(
                speakerUri=self._speaker_uri,
                serviceUrl=self._service_url,
                conversationalName=self._name,
                role="Google Lyria music generation agent",
            ),
            capabilities=[
                Capability(
                    keyphrases=["text-to-music", "music-generation", "lyria"],
                    descriptions=[self._style],
                    supportedLayers=SupportedLayers(input=["text"], output=["audio"]),
                )
            ],
        )

    # ------------------------------------------------------------------
    # Prompt builders
    # ------------------------------------------------------------------

    def _extract_music_prompt(self, text: str) -> str:
        """Extract condensed genre/mood terms for the RealTime API."""
        parts = []
        for label in ("Genre", "Tone", "Style", "Mood"):
            m = re.search(rf"{label}:\s*([^.\n]+)", text, re.IGNORECASE)
            if m:
                parts.append(m.group(1).strip())
        if parts:
            return ", ".join(parts)
        # Fallback: strip prose and take first 40 meaningful words
        clean = re.sub(r"(?:Compose|Create|Generate|Write)\s+a?\s*[\d\w-]*[\s-]second[^.]*\.", "", text, flags=re.IGNORECASE)
        clean = re.sub(r"(?:Timing\s+cues?|Duration)[^.]*\.", "", clean, flags=re.IGNORECASE)
        clean = re.sub(r"\[.*?\]", "", clean).strip()
        words = clean.split()
        return " ".join(words[:40]) if words else text[:200]

    def _build_content_prompt(self, text: str) -> str:
        """Build a rich natural-language prompt for the generateContent API (Clip/Pro).

        Unlike _extract_music_prompt (which condenses to keyword terms for RealTime),
        Lyria 3 Clip/Pro understand full natural language descriptions including
        timestamp structure, instrument lists, BPM, key, and mood sentences.

        Preserves Lyria structural markers: [Verse 1], [Chorus], [0:00-0:25], etc.
        Only strips OFP protocol markers and injected narrative context.
        """
        clean = re.sub(r"^\[.*?\]:\s*", "", text).strip()
        # Strip "Generate this music — PROMPT:" instruction prefix added by the Showrunner
        clean = re.sub(r"^(?:Generate\s+this\s+music\s*[-—]\s*)?PROMPT:\s*", "", clean, flags=re.IGNORECASE).strip()
        # Truncate at injected narrative context blocks (not relevant to Lyria)
        for marker in ("--- STORY SO FAR", "--- SESSION MEMORY", "--- BREAKOUT SESSION"):
            idx = clean.find(marker)
            if idx >= 0:
                clean = clean[:idx].strip()
        clean = re.sub(r"\*\*([^*]+)\*\*", r"\1", clean)
        clean = re.sub(r"#{1,6}\s*", "", clean)
        clean = re.sub(r"---+", "", clean)
        # Strip OFP protocol markers only — NOT Lyria section tags like [Verse 1], [0:00-0:25], [Chorus]
        clean = re.sub(r"\[(?:DIRECTIVE|DIRECTOR|floor-manager|ASSIGN|ACCEPT|REJECT|KICK|BREAKOUT)[^\]]*\][^\n]*", "", clean, flags=re.IGNORECASE)
        clean = clean.strip()
        if self._style and self._style not in clean:
            return f"{self._style}. {clean}"
        return clean

    def _build_prompt(self, text: str) -> str:
        """Build a prompt from an ad-hoc utterance (not an orchestrator directive)."""
        clean = re.sub(r"^\[.*?\]:\s*", "", text).strip()
        clean = re.sub(r"\*\*([^*]+)\*\*", r"\1", clean)
        clean = re.sub(r"#{1,6}\s*", "", clean)
        clean = re.sub(r"---+", "", clean)
        clean = re.sub(r"\[(?:DIRECTOR|floor-manager)[^\]]*\][^\n]*", "", clean, flags=re.IGNORECASE)
        clean = re.sub(r"\[.*?\]", "", clean)
        clean = clean.strip()
        words = clean.split()
        if len(words) > 40:
            clean = " ".join(words[:40])
        return f"{self._style}, {clean}" if self._style else clean

    def _extract_duration(self, text: str) -> int:
        """Parse requested duration in seconds from directive text (RealTime only)."""
        m = re.search(r"(\d+)[\s-]second", text, re.IGNORECASE)
        if m:
            return min(max(int(m.group(1)), 5), 60)
        return self._duration_seconds

    # ------------------------------------------------------------------
    # SSL helper (fixes CERTIFICATE_VERIFY_FAILED on macOS)
    # ------------------------------------------------------------------

    @staticmethod
    def _apply_certifi_patch():
        """Patch ssl.create_default_context to use certifi. Returns (ssl_module, original_fn)."""
        import ssl
        _orig = ssl.create_default_context
        try:
            import certifi
            _cafile = certifi.where()

            def _patched(*args, **kwargs):
                if not kwargs.get("cafile"):
                    kwargs["cafile"] = _cafile
                return _orig(*args, **kwargs)

            ssl.create_default_context = _patched
            return ssl, _orig
        except ImportError:
            return ssl, None

    # ------------------------------------------------------------------
    # Generation: generateContent API (Lyria 3 Clip / Pro)
    # ------------------------------------------------------------------

    async def _do_generate_content(self, prompt: str) -> Optional[Path]:
        """Generate music via client.models.generate_content() for Clip/Pro models."""
        from google import genai
        from google.genai import types

        ssl_mod, _orig = self._apply_certifi_patch()
        try:
            client = genai.Client(api_key=self._api_key)

            config = types.GenerateContentConfig(response_modalities=["AUDIO", "TEXT"])

            logger.info("[%s] Calling generateContent with model=%s prompt=%s…", self._name, self._model, prompt[:80])

            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                None,
                lambda: client.models.generate_content(
                    model=self._model,
                    contents=prompt,
                    config=config,
                ),
            )

            # Diagnose blocked / empty responses before iterating
            if not response.candidates:
                block_reason = getattr(getattr(response, "prompt_feedback", None), "block_reason", None)
                raise RuntimeError(
                    f"Lyria returned no candidates — block_reason={block_reason!r}. "
                    "Check that the prompt doesn't trigger safety filters."
                )

            audio_data: Optional[bytes] = None
            audio_mime: str = "audio/mpeg"
            for part in (response.parts or []):
                if part.inline_data is not None:
                    audio_data = part.inline_data.data
                    audio_mime = getattr(part.inline_data, "mime_type", "audio/mpeg") or "audio/mpeg"
                    break

            if not audio_data:
                # Log what text came back to help debug
                text_parts = [p.text for p in (response.parts or []) if p.text]
                logger.error("[%s] No audio in response. Text parts: %s", self._name, text_parts[:3])
                raise RuntimeError("Lyria generateContent returned no audio data")

            ext = "wav" if "wav" in audio_mime else "mp3"
            chapter_m = re.search(r"chapter[_\s]+(\d+)", self._raw_prompt or "", re.IGNORECASE)
            if chapter_m:
                fname = f"chapter_{chapter_m.group(1).zfill(2)}_music.{ext}"
            else:
                ts = datetime.now().strftime("%Y%m%d_%H%M%S")
                fname = f"{ts}_{self._name.lower()}.{ext}"

            path = self._output_dir / fname
            path.write_bytes(audio_data)
            return path
        finally:
            if _orig is not None:
                ssl_mod.create_default_context = _orig

    # ------------------------------------------------------------------
    # Generation: RealTime WebSocket API (models/lyria-realtime-exp)
    # ------------------------------------------------------------------

    async def _do_generate_realtime(self, prompt: str, duration_seconds: int) -> Optional[Path]:
        """Generate music via the Lyria RealTime streaming WebSocket API."""
        from google import genai
        from google.genai import types

        ssl_mod, _orig = self._apply_certifi_patch()
        try:
            client = genai.Client(api_key=self._api_key, http_options={"api_version": "v1alpha"})
            target_bytes = duration_seconds * RT_SAMPLE_RATE * RT_CHANNELS * RT_BYTES_PER_SAMPLE
            audio_chunks: list[bytes] = []
            total_bytes = 0

            async with client.aio.live.music.connect(model=self._model) as session:
                await session.set_weighted_prompts(
                    prompts=[types.WeightedPrompt(text=prompt, weight=1.0)]
                )
                await session.set_music_generation_config(
                    config=types.LiveMusicGenerationConfig(temperature=1.1)
                )
                await session.play()

                async for message in session.receive():
                    if message.server_content and message.server_content.audio_chunks:
                        for chunk in message.server_content.audio_chunks:
                            audio_chunks.append(bytes(chunk.data))
                            total_bytes += len(chunk.data)
                    if total_bytes >= target_bytes:
                        break

                await session.stop()
        finally:
            if _orig is not None:
                ssl_mod.create_default_context = _orig

        if not audio_chunks:
            raise RuntimeError("Lyria RealTime returned no audio data")

        pcm_data = b"".join(audio_chunks)
        chapter_m = re.search(r"chapter[_\s]+(\d+)", self._raw_prompt or "", re.IGNORECASE)
        if chapter_m:
            fname = f"chapter_{chapter_m.group(1).zfill(2)}_music.wav"
        else:
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            fname = f"{ts}_{self._name.lower()}.wav"
        path = self._output_dir / fname
        with wave.open(str(path), "wb") as wf:
            wf.setnchannels(RT_CHANNELS)
            wf.setsampwidth(RT_BYTES_PER_SAMPLE)
            wf.setframerate(RT_SAMPLE_RATE)
            wf.writeframes(pcm_data)
        return path

    # ------------------------------------------------------------------
    # Unified entry point
    # ------------------------------------------------------------------

    async def _generate_music(self, prompt: str, duration_seconds: int, max_retries: int = 3) -> Optional[Path]:
        # generateContent (Clip/Pro) can take longer for full-length songs
        timeout = 180.0 if not self._is_realtime_model() else 60.0
        last_error: Optional[Exception] = None
        for attempt in range(1, max_retries + 1):
            try:
                if self._is_realtime_model():
                    coro = self._do_generate_realtime(prompt, duration_seconds)
                else:
                    coro = self._do_generate_content(prompt)
                return await asyncio.wait_for(coro, timeout=timeout)
            except asyncio.TimeoutError:
                logger.error("[%s] Lyria timed out after %ds (attempt %d/%d)", self._name, int(timeout), attempt, max_retries)
                last_error = asyncio.TimeoutError()
            except Exception as e:
                err = str(e)
                if "CERTIFICATE_VERIFY_FAILED" in err or "SSL" in err:
                    logger.error(
                        "[%s] SSL certificate error — fix with: "
                        "/Applications/Python*/Install\\ Certificates.command  "
                        "or: pip install certifi",
                        self._name,
                    )
                    return None  # SSL errors won't recover on retry
                logger.warning("[%s] Lyria attempt %d/%d failed: %s", self._name, attempt, max_retries, e)
                last_error = e
            if attempt < max_retries:
                delay = 2 ** (attempt - 1)  # 1s, 2s, 4s …
                logger.info("[%s] Retrying in %ds…", self._name, delay)
                await asyncio.sleep(delay)
        logger.error("[%s] Lyria music generation error after %d attempts: %s", self._name, max_retries, last_error)
        return None

    # ------------------------------------------------------------------
    # OFP event handlers
    # ------------------------------------------------------------------

    async def _handle_utterance(self, envelope: Envelope) -> None:
        sender_uri = self._get_sender_uri(envelope)
        if sender_uri == self.speaker_uri:
            return
        if sender_uri and "floor-manager" in sender_uri:
            text = self._extract_text_from_envelope(envelope)
            if text:
                m = re.search(rf"\[DIRECTIVE for {re.escape(self._name)}\]:\s*(.+)", text, re.IGNORECASE | re.DOTALL)
                if m:
                    directive_text = m.group(1).strip()
                    # Ignore REJECT / KICK directives — don't overwrite the real music prompt
                    if not re.match(r"\[(?:REJECT|KICK)", directive_text, re.IGNORECASE):
                        self._raw_prompt = directive_text
                    # Orchestrator will grant floor explicitly — don't request here
            return

        text = self._extract_text_from_envelope(envelope)
        if not text:
            return
        self._last_text = text
        if not self._has_floor:
            await self.request_floor("composing music")

    async def _handle_grant_floor(self) -> None:
        self._has_floor = True
        try:
            if self._raw_prompt:
                duration = self._extract_duration(self._raw_prompt)
                if self._is_realtime_model():
                    music_prompt = self._extract_music_prompt(self._raw_prompt)
                else:
                    music_prompt = self._build_content_prompt(self._raw_prompt)
            elif self._last_text:
                duration = self._duration_seconds
                music_prompt = self._build_prompt(self._last_text)
            else:
                return

            logger.info("[%s] Generating music via %s: %s", self._name, self._model, music_prompt[:80])
            path = await self._generate_music(music_prompt, duration)
            if path:
                mime = "audio/wav" if path.suffix in (".wav",) else "audio/mpeg"
                # Use a clear completion message — NOT the prompt text.
                # The Showrunner is an LLM that can't hear audio; a truncated prompt
                # looks like an incomplete response and triggers spurious REJECTs.
                text_desc = f"Music generated successfully. File: {path.name}"
                await self.send_envelope(
                    self._make_media_utterance_envelope(
                        text_desc, "audio", mime, str(path.resolve())
                    )
                )
        except Exception as e:
            logger.error("[%s] Floor grant error: %s", self._name, e)
        finally:
            self._has_floor = False
            self._last_text = None
            self._raw_prompt = None
            await self.yield_floor()

    async def _dispatch(self, envelope: Envelope) -> None:
        for event in (envelope.events or []):
            event_type = getattr(event, "eventType", type(event).__name__)
            if event_type == "utterance":
                await self._handle_utterance(envelope)
            elif event_type == "grantFloor":
                await self._handle_grant_floor()
            elif event_type == "revokeFloor":
                self._has_floor = False
            elif event_type == "invite":
                from openfloor import Event, To
                from ofp_playground.bus.message_bus import FLOOR_MANAGER_URI
                accept_envelope = Envelope(
                    sender=self._make_sender(),
                    conversation=self._make_conversation(),
                    events=[Event(
                        eventType="acceptInvite",
                        to=To(speakerUri=FLOOR_MANAGER_URI),
                        reason="Ready to participate",
                    )],
                )
                await self.send_envelope(accept_envelope)
            elif event_type == "uninvite":
                logger.info("[%s] received uninvite — stopping", self._name)
                self._running = False

    async def run(self) -> None:
        self._running = True
        await self._bus.register(self.speaker_uri, self._queue)
        await self._publish_manifest()

        try:
            while self._running:
                try:
                    envelope = await asyncio.wait_for(self._queue.get(), timeout=1.0)
                    await self._dispatch(envelope)
                except asyncio.TimeoutError:
                    continue
                except Exception as e:
                    logger.error("[%s] error: %s", self._name, e, exc_info=True)
        finally:
            self._running = False
