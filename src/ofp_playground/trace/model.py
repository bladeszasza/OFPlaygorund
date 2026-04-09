"""Trace event model used by the conversation timeline renderer."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(slots=True)
class TraceEvent:
    """Represents one OFP event plus routing metadata."""

    id: str
    index: int
    timestamp: float
    wall_time: float
    conversation_id: str
    breakout_id: str | None
    event_type: str
    sender_uri: str
    sender_name: str
    explicit_target_uris: list[str]
    explicit_target_names: list[str]
    route_uris: list[str]
    route_names: list[str]
    is_private: bool
    is_broadcast: bool
    summary: str
    directive: str | None
    media_type: str | None
    envelope_json: str
