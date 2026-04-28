# tests/test_session_bridge.py
import asyncio
from unittest.mock import MagicMock
import pytest
from canvas.backend.session_bridge import SessionBridge, _serialize_envelope


def _make_utterance_envelope(speaker_uri: str, text: str) -> MagicMock:
    token = MagicMock()
    token.value = text
    text_feat = MagicMock()
    text_feat.tokens = [token]
    features = {"text": text_feat}
    de = MagicMock()
    de.features = features
    event = MagicMock()
    event.eventType = "utterance"
    event.dialogEvent = de
    envelope = MagicMock()
    envelope.sender = MagicMock()
    envelope.sender.speakerUri = speaker_uri
    envelope.events = [event]
    return envelope


def _make_floor_envelope(control_type: str, to_uri: str) -> MagicMock:
    event = MagicMock()
    event.eventType = "floorControlEvent"
    event.controlType = control_type
    event.to = MagicMock()
    event.to.speakerUri = to_uri
    envelope = MagicMock()
    envelope.sender = MagicMock()
    envelope.sender.speakerUri = "tag:ofp-playground.local,2025:floor-manager"
    envelope.events = [event]
    return envelope


def test_serialize_utterance():
    env = _make_utterance_envelope("tag:ofp-playground.local,2025:llm-Alice", "Hello world")
    result = _serialize_envelope(env, {"tag:ofp-playground.local,2025:llm-Alice": "Alice"})
    assert result["type"] == "utterance"
    assert result["sender"] == "Alice"
    assert result["text"] == "Hello world"
    assert result["media"] is None


def test_serialize_floor_grant():
    env = _make_floor_envelope("grantFloor", "tag:ofp-playground.local,2025:llm-Bob")
    result = _serialize_envelope(env, {"tag:ofp-playground.local,2025:llm-Bob": "Bob"})
    assert result["type"] == "floor_grant"
    assert result["to"] == "Bob"


def test_serialize_floor_request():
    env = _make_floor_envelope("requestFloor", "tag:ofp-playground.local,2025:floor-manager")
    env.sender.speakerUri = "tag:ofp-playground.local,2025:llm-Carol"
    result = _serialize_envelope(env, {"tag:ofp-playground.local,2025:llm-Carol": "Carol"})
    assert result["type"] == "floor_request"
    assert result["from"] == "Carol"


def test_serialize_unknown_event_returns_none():
    event = MagicMock()
    event.eventType = "inviteEvent"
    envelope = MagicMock()
    envelope.sender = MagicMock()
    envelope.sender.speakerUri = "tag:ofp-playground.local,2025:floor-manager"
    envelope.events = [event]
    result = _serialize_envelope(envelope, {})
    assert result is None


async def test_bridge_queues_and_logs_events():
    bridge = SessionBridge()
    env = _make_utterance_envelope("tag:ofp-playground.local,2025:llm-Alice", "Hi")
    bridge.register_agent("tag:ofp-playground.local,2025:llm-Alice", "Alice")
    bridge.record(env, recipients=set(), is_private=False)
    assert len(bridge.event_log) == 1
    assert bridge.event_log[0]["type"] == "utterance"
    assert not bridge._queue.empty()


async def test_bridge_reset_clears_log():
    bridge = SessionBridge()
    env = _make_utterance_envelope("tag:ofp-playground.local,2025:llm-Alice", "Hi")
    bridge.record(env, recipients=set(), is_private=False)
    bridge.reset()
    assert bridge.event_log == []
    assert bridge._queue.empty()
