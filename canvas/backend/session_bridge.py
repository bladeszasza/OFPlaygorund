# canvas/backend/session_bridge.py
"""Bridges MessageBus events to WebSocket clients.

Implements the same record() interface as EventCollector so it can be
passed to MessageBus.set_collector(). Uses asyncio.Queue for the
sync->async handoff (record() is called synchronously from MessageBus.send()).
"""
from __future__ import annotations

import asyncio
import logging
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from openfloor import Envelope
    from fastapi import WebSocket

logger = logging.getLogger(__name__)


def _extract_agent_name(uri: str, agent_names: dict[str, str]) -> str:
    if uri in agent_names:
        return agent_names[uri]
    return uri.split(":")[-1].replace("llm-", "").replace("human-", "")


def _serialize_envelope(envelope: "Envelope", agent_names: dict[str, str]) -> dict | None:
    """Convert an OFP envelope to a WS event dict. Returns None for non-displayable events."""
    sender_uri: str = envelope.sender.speakerUri if envelope.sender else "unknown"
    sender_name = _extract_agent_name(sender_uri, agent_names)

    for event in (envelope.events or []):
        event_type = getattr(event, "eventType", type(event).__name__)

        if event_type == "utterance":
            de = getattr(event, "dialogEvent", None)
            text = ""
            media_type = None
            media_url = None
            if de and de.features:
                tf = de.features.get("text")
                if tf and tf.tokens:
                    text = " ".join(t.value for t in tf.tokens if t.value)
                for key in ("image", "video", "audio", "3d"):
                    feat = de.features.get(key)
                    if feat and feat.tokens and feat.tokens[0].value:
                        media_type = key
                        media_url = feat.tokens[0].value
                        break
            return {
                "type": "utterance",
                "sender": sender_name,
                "sender_uri": sender_uri,
                "text": text,
                "media": {"type": media_type, "url": media_url} if media_type else None,
            }

        if event_type == "floorControlEvent":
            control = getattr(event, "controlType", "")
            to_uri = ""
            if hasattr(event, "to") and event.to:
                to_uri = getattr(event.to, "speakerUri", "")
            to_name = _extract_agent_name(to_uri, agent_names) if to_uri else ""

            if control == "grantFloor":
                return {"type": "floor_grant", "to": to_name, "to_uri": to_uri}
            if control == "revokeFloor":
                return {"type": "floor_revoke", "from": sender_name, "from_uri": sender_uri}
            if control == "requestFloor":
                return {"type": "floor_request", "from": sender_name, "from_uri": sender_uri}
            if control == "yieldFloor":
                return {"type": "floor_revoke", "from": sender_name, "from_uri": sender_uri}

        if event_type in ("inviteEvent", "byeEvent", "declineEvent"):
            return None

    return None


class SessionBridge:
    """Collector-compatible bridge from MessageBus to WebSocket clients."""

    def __init__(self) -> None:
        self._agent_names: dict[str, str] = {}
        self._queue: asyncio.Queue = asyncio.Queue()
        self._clients: list["WebSocket"] = []
        self._event_log: list[dict] = []
        self._inner_collector = None

    def reset(self) -> None:
        self._agent_names = {}
        self._event_log = []
        self._clients = []
        self._queue = asyncio.Queue()
        self._inner_collector = None

    def register_agent(self, uri: str, name: str) -> None:
        self._agent_names[uri] = name
        if self._inner_collector is not None:
            self._inner_collector.register_agent(uri, name)

    def set_inner_collector(self, collector) -> None:
        self._inner_collector = collector

    @property
    def event_log(self) -> list[dict]:
        return list(self._event_log)

    def push_raw(self, event: dict) -> None:
        self._event_log.append(event)
        self._queue.put_nowait(event)

    def record(
        self,
        envelope: "Envelope",
        recipients: set,
        is_private: bool,
        breakout_id=None,
        *,
        scope_id=None,
        scope_kind=None,
        parent_conversation_id=None,
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
        if event is not None:
            self._event_log.append(event)
            self._queue.put_nowait(event)

    async def connect(self, websocket: "WebSocket") -> None:
        await websocket.accept()
        self._clients.append(websocket)
        for event in self._event_log:
            try:
                await websocket.send_json(event)
            except Exception:
                break

    def disconnect(self, websocket: "WebSocket") -> None:
        self._clients = [c for c in self._clients if c is not websocket]

    async def broadcast_loop(self) -> None:
        while True:
            event = await self._queue.get()
            dead = []
            for ws in list(self._clients):
                try:
                    await ws.send_json(event)
                except Exception:
                    dead.append(ws)
            for ws in dead:
                self.disconnect(ws)
