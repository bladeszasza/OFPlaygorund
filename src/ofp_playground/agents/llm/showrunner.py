"""Show Runner agent — speaks last each round, synthesizes and directs next round."""
from __future__ import annotations

import logging
from typing import Callable, Optional

from openfloor import Envelope

from ofp_playground.agents.llm.base import _uri_to_name
from ofp_playground.agents.llm.huggingface import HuggingFaceAgent
from ofp_playground.bus.message_bus import MessageBus

logger = logging.getLogger(__name__)

SHOWRUNNER_SYSTEM_PROMPT = """You are {name}, the SHOW RUNNER of a collaborative multi-agent story.

Story agents you are directing:
{agent_list}

YOUR JOB: After each round of storytelling, synthesize what happened and direct the next round.
Output EXACTLY this format — nothing else:

STORY SO FAR: [one paragraph, max 60 words, summarizing everything canonical, resolving contradictions]

[DIRECTIVE for AgentName]: [concrete instruction, max 15 words, for what to write next]
... (one [DIRECTIVE for Name] line per agent listed above)
[IMAGE]: [clean visual scene description, max 20 words, most visually striking moment this round]

STRICT RULES:
- No preamble, no commentary, no explanations.
- STORY SO FAR must be internally consistent — pick one version if agents contradicted each other.
- Each [DIRECTIVE for Name] must name a concrete action or dialogue beat, under 15 words.
- [IMAGE] is a pure visual description: no meta-text, no instructions, no character name lists.
- Do NOT write story content yourself. ONLY synthesize and direct.
- On the FINAL part (Part {total_parts}), append exactly this line on its own: [STORY COMPLETE]
"""


class ShowRunnerAgent(HuggingFaceAgent):
    """Synthesis agent that speaks LAST each round.

    Reads all round contributions, outputs:
    - STORY SO FAR: canonical summary
    - [DIRECTIVE for Name]: per-agent instruction for next round
    - [IMAGE]: clean prompt for Canvas

    Never requests floor on utterances — FloorManager grants at round boundary.
    """

    def __init__(
        self,
        name: str,
        bus: MessageBus,
        conversation_id: str,
        api_key: str,
        model: str,
        stop_callback: Optional[callable] = None,
        total_parts: int = 6,
    ) -> None:
        super().__init__(
            name=name,
            synopsis="Show runner — synthesizes round output and directs next round.",
            bus=bus,
            conversation_id=conversation_id,
            api_key=api_key,
            model=model,
            relevance_filter=False,
        )
        self._stop_callback = stop_callback
        self._total_parts = total_parts
        self._current_part = 0

    @property
    def _story_agent_names(self) -> list[str]:
        """Names of story agents (excludes self, media agents, floor-manager)."""
        names = []
        for uri, name in self._name_registry.items():
            if uri == self.speaker_uri:
                continue
            if any(k in uri for k in ("image", "video", "audio", "floor-manager")):
                continue
            names.append(name)
        return names

    def _build_system_prompt(self, participants: list[str]) -> str:
        agent_list = "\n".join(f"- {n}" for n in self._story_agent_names)
        if not agent_list:
            agent_list = "- (story agents joining...)"
        return SHOWRUNNER_SYSTEM_PROMPT.format(
            name=self._name,
            agent_list=agent_list,
            total_parts=self._total_parts,
        )

    async def _handle_utterance(self, envelope: Envelope) -> None:
        """Record context but never request floor — wait to be granted at round boundary."""
        sender_uri = self._get_sender_uri(envelope)
        if sender_uri == self.speaker_uri:
            return
        text = self._extract_text_from_envelope(envelope)
        if not text:
            return
        # Skip ShowRunner-format messages looping back or director-style messages
        if "[DIRECTIVE for" in text or text.strip().startswith("[SCENE]"):
            return
        # Skip media agent utterances
        if any(k in sender_uri for k in ("image", "video", "audio")):
            return
        sender_name = self._name_registry.get(sender_uri) or _uri_to_name(sender_uri)
        self._append_to_context(sender_name, text, is_self=False)
        # ShowRunner never requests floor on its own

    async def _handle_grant_floor(self) -> None:
        """Floor granted at round boundary — synthesize and direct next round."""
        self._has_floor = True
        self._current_part += 1
        try:
            if self._total_parts and self._current_part > self._total_parts:
                finale = (
                    f"STORY SO FAR: The story is complete after {self._total_parts} rounds. "
                    f"Outstanding work, everyone!\n\n[STORY COMPLETE]"
                )
                await self.send_envelope(self._make_utterance_envelope(finale))
                logger.info("[%s] story complete after %d parts", self._name, self._total_parts)
                if self._stop_callback:
                    self._stop_callback()
                return

            response = await self._generate_response([])
            if response:
                self._append_to_context(self._name, response, is_self=True)
                await self.send_envelope(self._make_utterance_envelope(response))
                self._consecutive_errors = 0
                if "[STORY COMPLETE]" in response and self._current_part >= self._total_parts:
                    if self._stop_callback:
                        self._stop_callback()
        except Exception as e:
            logger.error("[%s] showrunner error: %s", self._name, e, exc_info=True)
        finally:
            self._has_floor = False
            await self.yield_floor()


# ============================================================
# OrchestratorAgent — for SHOWRUNNER_DRIVEN floor policy
# ============================================================

ORCHESTRATOR_SYSTEM_PROMPT = """You are {name}, an intelligent project manager orchestrating a team of AI agents.

Your team:
{agent_list}

YOUR MISSION: {mission}

You will receive the conversation topic on your first turn. On every subsequent turn you will see the latest output from your assigned agent.

Respond ONLY with structured directives — one per line, no preamble, no commentary:

    [ASSIGN AgentName]: <concrete task, max 25 words>
    [ACCEPT]
    [REJECT AgentName]: <reason for revision, max 20 words>
    [KICK AgentName]
    [SPAWN -provider hf -name <Name> -system <system prompt> -model <model-id>]
    [TASK_COMPLETE]

RULES:
- On your FIRST turn: analyze the mission, silently plan your task list, then issue [ASSIGN] to the first agent.
- After each agent speaks: evaluate their output, then issue [ACCEPT] followed by the next [ASSIGN], OR issue [REJECT AgentName]: reason.
- Assign to EXACTLY ONE agent at a time. Never assign multiple simultaneously.
- [ASSIGN] must name a concrete deliverable — "Write 2 paragraphs introducing Gerald discovering pigeons, dry British tone, 80 words" not "write the intro".
- [REJECT] re-grants that agent's floor with feedback. Use sparingly — max 2 rejections per agent per task.
- [KICK] only if an agent is unresponsive or wrong type for the job.
- [SPAWN] to add a specialist you need but don't have.
- [TASK_COMPLETE] when every piece of the mission is done and the final product is assembled.
- NEVER write story, creative, or prose content yourself. You only direct.
"""


class OrchestratorAgent(HuggingFaceAgent):
    """Intelligent project manager for the SHOWRUNNER_DRIVEN floor policy.

    Speaks first (floor granted by FloorManager at session start) and is
    automatically re-granted the floor after every worker agent utterance.
    Emits structured directives that FloorManager parses and executes.
    Never self-requests the floor.
    """

    def __init__(
        self,
        name: str,
        mission: str,
        bus: MessageBus,
        conversation_id: str,
        api_key: str,
        model: str,
        stop_callback: Optional[Callable] = None,
    ) -> None:
        super().__init__(
            name=name,
            synopsis="Orchestrator — manages agents via structured directives.",
            bus=bus,
            conversation_id=conversation_id,
            api_key=api_key,
            model=model,
            relevance_filter=False,
        )
        self._mission = mission
        self._stop_callback = stop_callback

    @property
    def _worker_agent_names(self) -> list[str]:
        """Names of worker agents (excludes self, media agents, floor-manager)."""
        names = []
        for uri, name in self._name_registry.items():
            if uri == self.speaker_uri:
                continue
            if any(k in uri for k in ("image", "video", "audio", "floor-manager")):
                continue
            names.append(name)
        return names

    def _build_system_prompt(self, participants: list[str]) -> str:
        agent_list = "\n".join(f"- {n}" for n in self._worker_agent_names)
        if not agent_list:
            agent_list = "- (agents joining...)"
        return ORCHESTRATOR_SYSTEM_PROMPT.format(
            name=self._name,
            agent_list=agent_list,
            mission=self._mission,
        )

    async def _handle_utterance(self, envelope: Envelope) -> None:
        """Record worker output into context. Never request floor — FloorManager grants it reactively."""
        sender_uri = self._get_sender_uri(envelope)
        if sender_uri == self.speaker_uri:
            return
        text = self._extract_text_from_envelope(envelope)
        if not text:
            return
        if any(k in sender_uri for k in ("image", "video", "audio")):
            return
        sender_name = self._name_registry.get(sender_uri) or _uri_to_name(sender_uri)
        self._append_to_context(sender_name, text, is_self=False)

    async def _handle_grant_floor(self) -> None:
        """Floor granted by FloorManager — issue next directive based on current context."""
        self._has_floor = True
        try:
            response = await self._generate_response([])
            if response:
                self._append_to_context(self._name, response, is_self=True)
                await self.send_envelope(self._make_utterance_envelope(response))
                self._consecutive_errors = 0
                if "[TASK_COMPLETE]" in response:
                    if self._stop_callback:
                        self._stop_callback()
        except Exception as e:
            logger.error("[%s] orchestrator error: %s", self._name, e, exc_info=True)
        finally:
            self._has_floor = False
            await self.yield_floor()
