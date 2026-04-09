"""Tests for OFP trace capture and timeline rendering."""
from __future__ import annotations

import asyncio

import pytest
from openfloor import Conversation, DialogEvent, Envelope, Sender, TextFeature, To, Token, UtteranceEvent

from ofp_playground.bus.message_bus import FLOOR_MANAGER_URI, MessageBus
from ofp_playground.trace import EventCollector, render_trace_html


def _utterance_envelope(
    sender_uri: str,
    text: str,
    conv_id: str = "conv:test",
    target_uri: str | None = None,
) -> Envelope:
    event = UtteranceEvent(
        dialogEvent=DialogEvent(
            id="de-1",
            speakerUri=sender_uri,
            features={"text": TextFeature(tokens=[Token(value=text)])},
        )
    )
    if target_uri:
        event.to = To(speakerUri=target_uri)

    return Envelope(
        sender=Sender(speakerUri=sender_uri, serviceUrl="local://sender"),
        conversation=Conversation(id=conv_id),
        events=[event],
    )


@pytest.mark.asyncio
async def test_message_bus_collects_broadcast_event() -> None:
    bus = MessageBus()
    collector = EventCollector("conv:test")
    collector.register_agent("tag:test:sender", "Sender")
    collector.register_agent("tag:test:receiver", "Receiver")
    collector.register_agent(FLOOR_MANAGER_URI, "Floor Manager")
    bus.set_collector(collector)

    sender_q = asyncio.Queue()
    recv_q = asyncio.Queue()
    fm_q = asyncio.Queue()

    await bus.register("tag:test:sender", sender_q)
    await bus.register("tag:test:receiver", recv_q)
    await bus.register(FLOOR_MANAGER_URI, fm_q)

    env = _utterance_envelope("tag:test:sender", "hello world")
    await bus.send(env)

    assert len(collector.events) == 1
    e = collector.events[0]
    assert e.event_type == "utterance"
    assert e.is_broadcast is True
    assert e.is_private is False
    assert e.sender_name == "Sender"
    assert "Receiver" in e.route_names
    assert "Floor Manager" in e.route_names
    assert "hello world" in e.summary


@pytest.mark.asyncio
async def test_message_bus_collects_private_event() -> None:
    bus = MessageBus()
    collector = EventCollector("conv:test")
    collector.register_agent("tag:test:sender", "Sender")
    collector.register_agent("tag:test:receiver", "Receiver")
    collector.register_agent(FLOOR_MANAGER_URI, "Floor Manager")
    bus.set_collector(collector)

    sender_q = asyncio.Queue()
    recv_q = asyncio.Queue()
    fm_q = asyncio.Queue()

    await bus.register("tag:test:sender", sender_q)
    await bus.register("tag:test:receiver", recv_q)
    await bus.register(FLOOR_MANAGER_URI, fm_q)

    env = _utterance_envelope("tag:test:sender", "[ASSIGN Agent]: do x")
    await bus.send_private(env, "tag:test:receiver")

    assert len(collector.events) == 1
    e = collector.events[0]
    assert e.is_private is True
    assert e.is_broadcast is False
    assert e.directive == "ASSIGN"
    assert e.route_uris == [FLOOR_MANAGER_URI, "tag:test:receiver"]


def test_render_trace_html(tmp_path) -> None:
    collector = EventCollector("conv:test")
    collector.register_agent(FLOOR_MANAGER_URI, "Floor Manager")
    collector.register_agent("tag:test:sender", "Sender")
    collector.record(
        envelope=_utterance_envelope("tag:test:sender", "render me"),
        recipients={FLOOR_MANAGER_URI},
        is_private=False,
    )

    out = tmp_path / "trace.html"
    render_trace_html(collector, out)

    text = out.read_text(encoding="utf-8")
    assert "OFP Conversation Trace" in text
    assert "TRACE_DATA" in text
    assert "render me" in text
