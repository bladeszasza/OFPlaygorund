"""Collect OFP events and routing metadata for trace visualization."""
from __future__ import annotations

import re
import time
import uuid
from dataclasses import asdict

from openfloor import Envelope

from ofp_playground.trace.model import TraceEvent

_DIRECTIVE_RE = re.compile(
    r"\[(ASSIGN(?:_PARALLEL)?|ACCEPT|REJECT|KICK|SPAWN|TASK_COMPLETE|BREAKOUT(?:_AGENT)?)",
    flags=re.IGNORECASE,
)


class EventCollector:
    """Collects a normalized trace stream from bus-routed envelopes."""

    def __init__(self, conversation_id: str):
        self._conversation_id = conversation_id
        self._events: list[TraceEvent] = []
        self._agent_names: dict[str, str] = {}

    @property
    def conversation_id(self) -> str:
        return self._conversation_id

    @property
    def events(self) -> list[TraceEvent]:
        return list(self._events)

    @property
    def agent_names(self) -> dict[str, str]:
        return dict(self._agent_names)

    def register_agent(self, uri: str, name: str) -> None:
        self._agent_names[uri] = name

    def record(
        self,
        envelope: Envelope,
        recipients: set[str],
        is_private: bool,
        breakout_id: str | None = None,
    ) -> None:
        sender_uri = envelope.sender.speakerUri if envelope.sender else "unknown"
        sender_name = self._name_for(sender_uri)
        envelope_json = envelope.to_json(indent=2)
        route_uris = sorted(recipients)
        route_names = [self._name_for(uri) for uri in route_uris]

        for event in (envelope.events or []):
            event_type = getattr(event, "eventType", type(event).__name__)
            explicit_target_uris = self._extract_explicit_targets(event)
            explicit_target_names = [self._name_for(uri) for uri in explicit_target_uris]

            summary, directive = self._extract_summary(event_type, event)
            media_type = self._detect_media(event)
            is_broadcast = not explicit_target_uris and not is_private

            self._events.append(
                TraceEvent(
                    id=str(uuid.uuid4()),
                    index=len(self._events),
                    timestamp=time.monotonic(),
                    wall_time=time.time(),
                    conversation_id=envelope.conversation.id if envelope.conversation else self._conversation_id,
                    breakout_id=breakout_id,
                    event_type=event_type,
                    sender_uri=sender_uri,
                    sender_name=sender_name,
                    explicit_target_uris=explicit_target_uris,
                    explicit_target_names=explicit_target_names,
                    route_uris=route_uris,
                    route_names=route_names,
                    is_private=is_private,
                    is_broadcast=is_broadcast,
                    summary=summary,
                    directive=directive,
                    media_type=media_type,
                    envelope_json=envelope_json,
                )
            )

    def to_dict(self) -> dict:
        return {
            "conversation_id": self._conversation_id,
            "agents": [
                {"uri": uri, "name": name}
                for uri, name in sorted(self._agent_names.items(), key=lambda item: item[1].lower())
            ],
            "events": [asdict(e) for e in self._events],
        }

    def _extract_explicit_targets(self, event) -> list[str]:
        target = getattr(event, "to", None)
        uri = getattr(target, "speakerUri", None) if target else None
        return [uri] if uri else []

    def _name_for(self, uri: str) -> str:
        if uri in self._agent_names:
            return self._agent_names[uri]
        return uri.split(":")[-1] if ":" in uri else uri

    def _extract_summary(self, event_type: str, event) -> tuple[str, str | None]:
        reason = getattr(event, "reason", None)
        if event_type == "utterance":
            text = self._extract_text(event)
            directive = self._detect_directive(text)
            if directive:
                return f"{directive}: {self._clip(text, 120)}", directive
            return self._clip(text or "utterance", 120), None
        if reason:
            return self._clip(str(reason), 120), None
        return event_type, None

    def _extract_text(self, event) -> str:
        dialog = getattr(event, "dialogEvent", None)
        features = getattr(dialog, "features", None)
        if not features:
            return ""
        text_feature = features.get("text")
        tokens = getattr(text_feature, "tokens", None)
        if not tokens:
            return ""
        return " ".join(tok.value for tok in tokens if getattr(tok, "value", ""))

    def _detect_media(self, event) -> str | None:
        dialog = getattr(event, "dialogEvent", None)
        features = getattr(dialog, "features", None)
        if not features:
            return None
        for key in ("image", "video", "audio", "3d"):
            feat = features.get(key)
            tokens = getattr(feat, "tokens", None)
            if tokens and any(getattr(tok, "value", "") for tok in tokens):
                return key
        return None

    def _detect_directive(self, text: str) -> str | None:
        if not text:
            return None
        m = _DIRECTIVE_RE.search(text)
        if not m:
            return None
        return m.group(1).upper()

    @staticmethod
    def _clip(text: str, max_len: int) -> str:
        if len(text) <= max_len:
            return text
        return text[: max_len - 3].rstrip() + "..."
