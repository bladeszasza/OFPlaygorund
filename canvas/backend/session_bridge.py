"""Bridge MessageBus collector events to WebSocket clients."""
from __future__ import annotations

import asyncio
import logging
import os
from pathlib import Path
from typing import TYPE_CHECKING, Any

# Resolve result dir once at import time so absolute media paths can be
# converted to browser-accessible /media/<relative> URLs.
_RESULT_DIR = (Path(__file__).resolve().parents[2] / "result").resolve()


def _to_media_url(path_str: str) -> str:
    """Convert an absolute filesystem path to a /media/<relative> URL.

    If the path is already relative or an http URL, return it unchanged.
    """
    if not path_str or not os.path.isabs(path_str):
        return path_str
    try:
        rel = Path(path_str).resolve().relative_to(_RESULT_DIR)
        return f"/media/{rel.as_posix()}"
    except ValueError:
        # Path outside RESULT_DIR — return as-is; browser will fail gracefully
        return path_str

if TYPE_CHECKING:
    from fastapi import WebSocket
    from openfloor import Envelope
    from ofp_playground.trace.collector import EventCollector

logger = logging.getLogger(__name__)


def _extract_agent_name(uri: str, agent_names: dict[str, str]) -> str:
    if uri in agent_names:
        return agent_names[uri]
    return uri.split(":")[-1].replace("llm-", "").replace("human-", "")


def _token_value(token: Any) -> str:
    value = getattr(token, "value", "")
    return value if isinstance(value, str) else str(value)


def _serialize_envelope(
    envelope: "Envelope", agent_names: dict[str, str]
) -> dict[str, Any] | None:
    """Convert an OFP envelope into a canvas WebSocket event."""
    sender_uri = envelope.sender.speakerUri if envelope.sender else "unknown"
    sender_name = _extract_agent_name(sender_uri, agent_names)

    for event in envelope.events or []:
        event_type = getattr(event, "eventType", type(event).__name__)

        if event_type == "utterance":
            dialog_event = getattr(event, "dialogEvent", None)
            features = getattr(dialog_event, "features", {}) or {}
            text = ""
            media: dict[str, str] | None = None

            text_feature = features.get("text") if isinstance(features, dict) else None
            text_tokens = getattr(text_feature, "tokens", None) or []
            if text_tokens:
                text = " ".join(
                    _token_value(token) for token in text_tokens if _token_value(token)
                ).strip()

            for key in ("image", "video", "audio", "3d"):
                feature = features.get(key) if isinstance(features, dict) else None
                tokens = getattr(feature, "tokens", None) or []
                if tokens:
                    url = _to_media_url(_token_value(tokens[0]).strip())
                    if url:
                        media = {"type": key, "url": url}
                        break

            return {
                "type": "utterance",
                "sender": sender_name,
                "sender_uri": sender_uri,
                "text": text,
                "media": media,
            }

        if event_type == "grantFloor":
            target = getattr(event, "to", None)
            target_uri = getattr(target, "speakerUri", "") if target else ""
            target_name = _extract_agent_name(target_uri, agent_names) if target_uri else ""
            return {"type": "floor_grant", "to": target_name, "to_uri": target_uri}

        if event_type == "revokeFloor":
            target = getattr(event, "to", None)
            target_uri = getattr(target, "speakerUri", "") if target else ""
            target_name = _extract_agent_name(target_uri, agent_names) if target_uri else ""
            return {"type": "floor_revoke", "from": target_name, "from_uri": target_uri}

        if event_type == "requestFloor":
            return {"type": "floor_request", "from": sender_name, "from_uri": sender_uri}

        if event_type == "publishManifest":
            return {"type": "manifest_published", "agent": sender_name, "agent_uri": sender_uri}

        if event_type == "yieldFloor":
            return {"type": "floor_yield", "from": sender_name, "from_uri": sender_uri}

        # Suppress noisy protocol events — return None to skip them
        if event_type not in {"utterance"}:
            return None

    return None


class SessionBridge:
    """Collector-compatible bridge from MessageBus to WebSocket clients."""

    def __init__(self) -> None:
        self._agent_names: dict[str, str] = {}
        self._queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue()
        self._clients: list["WebSocket"] = []
        self._event_log: list[dict[str, Any]] = []
        self._inner_collector: EventCollector | None = None
        self._conversation_id = ""

    @property
    def conversation_id(self) -> str:
        if self._inner_collector is not None:
            return self._inner_collector.conversation_id
        return self._conversation_id

    @property
    def event_log(self) -> list[dict[str, Any]]:
        return list(self._event_log)

    def reset(self) -> None:
        """Clear transient state between sessions."""
        self._agent_names = {}
        self._event_log = []
        self._clients = []
        self._queue = asyncio.Queue()
        self._inner_collector = None
        self._conversation_id = ""

    def set_inner_collector(self, collector: "EventCollector") -> None:
        self._inner_collector = collector
        self._conversation_id = collector.conversation_id

    def register_agent(self, uri: str, name: str) -> None:
        self._agent_names[uri] = name
        if self._inner_collector is not None:
            self._inner_collector.register_agent(uri, name)

    def push_raw(self, event: dict[str, Any]) -> None:
        self._event_log.append(event)
        self._queue.put_nowait(event)

    def record(
        self,
        envelope: "Envelope",
        recipients: set[str],
        is_private: bool,
        breakout_id: str | None = None,
        *,
        scope_id: str | None = None,
        scope_kind: str | None = None,
        parent_conversation_id: str | None = None,
    ) -> None:
        if self._inner_collector is not None:
            self._inner_collector.record(
                envelope=envelope,
                recipients=recipients,
                is_private=is_private,
                breakout_id=breakout_id,
                scope_id=scope_id,
                scope_kind=scope_kind,
                parent_conversation_id=parent_conversation_id,
            )

        event = _serialize_envelope(envelope, self._agent_names)
        if event is None:
            # Debug: log floor events that are unexpectedly dropped
            for ev in (envelope.events or []):
                et = getattr(ev, "eventType", type(ev).__name__)
                if et in ("grantFloor", "revokeFloor", "requestFloor", "yieldFloor"):
                    logger.warning(
                        "FLOOR DROPPED: et=%r to=%r agents=%r",
                        et,
                        getattr(getattr(ev, "to", None), "speakerUri", None),
                        list(self._agent_names.keys()),
                    )
            return

        # Debug: log floor events that ARE pushed to WS
        if event.get("type") in ("floor_grant", "floor_revoke", "floor_request"):
            logger.info("FLOOR PUSHED: %r", event)

        self._event_log.append(event)
        self._queue.put_nowait(event)

    async def connect(self, websocket: "WebSocket") -> None:
        await websocket.accept()
        self._clients.append(websocket)
        for event in self._event_log:
            await websocket.send_json(event)

    def disconnect(self, websocket: "WebSocket") -> None:
        self._clients = [client for client in self._clients if client is not websocket]

    async def broadcast_loop(self) -> None:
        """Drain queued events and fan them out to connected clients."""
        try:
            while True:
                event = await self._queue.get()
                stale_clients: list["WebSocket"] = []
                for websocket in list(self._clients):
                    try:
                        await websocket.send_json(event)
                    except Exception:
                        logger.debug("Dropping stale canvas websocket", exc_info=True)
                        stale_clients.append(websocket)
                for websocket in stale_clients:
                    self.disconnect(websocket)
        except asyncio.CancelledError:
            raise