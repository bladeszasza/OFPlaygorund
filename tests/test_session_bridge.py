from __future__ import annotations

from unittest.mock import MagicMock

from canvas.backend.session_bridge import SessionBridge, _serialize_envelope


def _make_utterance_envelope(speaker_uri: str, text: str) -> MagicMock:
    token = MagicMock()
    token.value = text
    text_feature = MagicMock()
    text_feature.tokens = [token]
    dialog_event = MagicMock()
    dialog_event.features = {"text": text_feature}
    event = MagicMock()
    event.eventType = "utterance"
    event.dialogEvent = dialog_event
    envelope = MagicMock()
    envelope.sender = MagicMock()
    envelope.sender.speakerUri = speaker_uri
    envelope.events = [event]
    return envelope


def _make_floor_envelope(event_type: str, to_uri: str) -> MagicMock:
    event = MagicMock()
    event.eventType = event_type
    event.to = MagicMock()
    event.to.speakerUri = to_uri
    envelope = MagicMock()
    envelope.sender = MagicMock()
    envelope.sender.speakerUri = "tag:ofp-playground.local,2025:floor-manager"
    envelope.events = [event]
    return envelope


def test_serialize_utterance() -> None:
    env = _make_utterance_envelope("tag:ofp-playground.local,2025:llm-Alice", "Hello world")

    result = _serialize_envelope(env, {"tag:ofp-playground.local,2025:llm-Alice": "Alice"})

    assert result == {
        "type": "utterance",
        "sender": "Alice",
        "sender_uri": "tag:ofp-playground.local,2025:llm-Alice",
        "text": "Hello world",
        "media": None,
    }


def test_serialize_floor_grant() -> None:
    env = _make_floor_envelope("grantFloor", "tag:ofp-playground.local,2025:llm-Bob")

    result = _serialize_envelope(env, {"tag:ofp-playground.local,2025:llm-Bob": "Bob"})

    assert result == {
        "type": "floor_grant",
        "to": "Bob",
        "to_uri": "tag:ofp-playground.local,2025:llm-Bob",
    }


def test_serialize_floor_request() -> None:
    env = _make_floor_envelope("requestFloor", "tag:ofp-playground.local,2025:floor-manager")
    env.sender.speakerUri = "tag:ofp-playground.local,2025:llm-Carol"

    result = _serialize_envelope(env, {"tag:ofp-playground.local,2025:llm-Carol": "Carol"})

    assert result == {
        "type": "floor_request",
        "from": "Carol",
        "from_uri": "tag:ofp-playground.local,2025:llm-Carol",
    }


def test_serialize_unknown_event_returns_none() -> None:
    event = MagicMock()
    event.eventType = "inviteEvent"
    envelope = MagicMock()
    envelope.sender = MagicMock()
    envelope.sender.speakerUri = "tag:ofp-playground.local,2025:floor-manager"
    envelope.events = [event]

    result = _serialize_envelope(envelope, {})

    assert result is None


async def test_bridge_queues_and_logs_events() -> None:
    bridge = SessionBridge()
    env = _make_utterance_envelope("tag:ofp-playground.local,2025:llm-Alice", "Hi")

    bridge.register_agent("tag:ofp-playground.local,2025:llm-Alice", "Alice")
    bridge.record(env, recipients=set(), is_private=False)

    assert len(bridge.event_log) == 1
    assert bridge.event_log[0]["type"] == "utterance"
    assert not bridge._queue.empty()


async def test_bridge_reset_clears_log() -> None:
    bridge = SessionBridge()
    env = _make_utterance_envelope("tag:ofp-playground.local,2025:llm-Alice", "Hi")

    bridge.record(env, recipients=set(), is_private=False)
    bridge.reset()

    assert bridge.event_log == []
    assert bridge._queue.empty()


def _make_sender_envelope(event_type: str, sender_uri: str) -> MagicMock:
    """Envelope where the event sender is the subject (yieldFloor, publishManifest)."""
    event = MagicMock()
    event.eventType = event_type
    envelope = MagicMock()
    envelope.sender = MagicMock()
    envelope.sender.speakerUri = sender_uri
    envelope.events = [event]
    return envelope


def test_yield_floor_emits_floor_yield_not_floor_revoke() -> None:
    env = _make_sender_envelope("yieldFloor", "tag:ofp-playground.local,2025:llm-Alice")
    result = _serialize_envelope(env, {"tag:ofp-playground.local,2025:llm-Alice": "Alice"})
    assert result is not None
    assert result["type"] == "floor_yield", f"Expected floor_yield, got {result['type']}"
    assert result["from"] == "Alice"
    assert result["from_uri"] == "tag:ofp-playground.local,2025:llm-Alice"


def test_publish_manifest_emits_manifest_published() -> None:
    env = _make_sender_envelope("publishManifest", "tag:ofp-playground.local,2025:llm-Bob")
    result = _serialize_envelope(env, {"tag:ofp-playground.local,2025:llm-Bob": "Bob"})
    assert result == {
        "type": "manifest_published",
        "agent": "Bob",
        "agent_uri": "tag:ofp-playground.local,2025:llm-Bob",
    }


def test_revoke_floor_still_emits_floor_revoke() -> None:
    """revokeFloor (forced) must still produce floor_revoke, not floor_yield."""
    env = _make_floor_envelope("revokeFloor", "tag:ofp-playground.local,2025:llm-Carol")
    result = _serialize_envelope(env, {"tag:ofp-playground.local,2025:llm-Carol": "Carol"})
    assert result is not None
    assert result["type"] == "floor_revoke"
    assert result["from"] == "Carol"