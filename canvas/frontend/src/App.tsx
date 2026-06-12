// canvas/frontend/src/App.tsx
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  ReactFlow,
  Background,
  Controls,
  MiniMap,
  addEdge,
  useNodesState,
  useEdgesState,
  type Node,
  type Edge,
  type Connection,
  type NodeTypes,
  type EdgeTypes,
  BackgroundVariant,
} from '@xyflow/react'
import dagre from 'dagre'

import { CanvasContext } from './context/CanvasContext'
import type { CanvasCallbacks } from './context/CanvasContext'
import { FloorNode } from './nodes/FloorNode'
import { AgentNode } from './nodes/AgentNode'
import { HumanNode } from './nodes/HumanNode'
import { ConversationNode } from './nodes/ConversationNode'
import { TraceTimelineNode } from './nodes/TraceTimelineNode'
import { ConversationChatNode } from './nodes/ConversationChatNode'
import { EventInspectorNode } from './nodes/EventInspectorNode'
import { ImageArtifactNode } from './nodes/ImageArtifactNode'
import { CodeArtifactNode } from './nodes/CodeArtifactNode'
import { PhaseArtifactNode } from './nodes/PhaseArtifactNode'
import { MusicArtifactNode } from './nodes/MusicArtifactNode'
import { GlowEdge } from './edges/GlowEdge'
import { SlugCombobox } from './components/SlugCombobox'
import { useSlugs } from './hooks/useSlugs'
import { useModels } from './hooks/useModels'
import { usePresets } from './hooks/usePresets'
import { useRemoteAgents } from './hooks/useRemoteAgents'
import { useSession } from './hooks/useSession'

import type {
  FloorNodeData, AgentNodeData, HumanNodeData, ConversationNodeData,
  ConversationChatNodeData, EventInspectorNodeData,
  ArtifactNodeData, GlowEdgeData, WSEvent, FloorPolicy, AgentFloorState, Message,
  FloorEventEntry,
} from './types'

// ── Stable module-level constants — never recreated on render ─────────────────

const NODE_TYPES: NodeTypes = {
  FloorNode,
  AgentNode,
  HumanNode,
  ConversationNode,
  TraceTimelineNode,
  ConversationChatNode,
  EventInspectorNode,
  ImageArtifactNode,
  CodeArtifactNode,
  PhaseArtifactNode,
  MusicArtifactNode,
}

const EDGE_TYPES = { glow: GlowEdge } as unknown as EdgeTypes

const TASK_SUBTYPES = [
  '', 'showrunner', 'orchestrator', 'code-generation',
  'text-to-image', 'text-to-video', 'text-to-music',
  'image-to-text', 'image-text-to-text',
  'text-generation', 'text-classification', 'summarization',
  'image-classification', 'object-detection', 'image-segmentation',
  'token-classification',
]

const ARTIFACT_COLOR: Record<string, string> = {
  image: '#8b5cf6', code: '#10a37f', file: '#10a37f',
  phase: '#58a6ff', markdown: '#58a6ff', music: '#f97316',
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function artifactNodeType(kind: string): string {
  if (kind === 'image') return 'ImageArtifactNode'
  if (kind === 'code' || kind === 'file') return 'CodeArtifactNode'
  if (kind === 'music') return 'MusicArtifactNode'
  return 'PhaseArtifactNode'
}

function nextArtifactPosition(
  currentNodes: Node[],
  agentNodeId: string,
): { x: number; y: number } {
  const agentNode = currentNodes.find(n => n.id === agentNodeId)
  const agentName = (agentNode?.data as AgentNodeData | undefined)?.name ?? ''
  const baseX = (agentNode?.position.x ?? 400) + 260
  const baseY = agentNode?.position.y ?? 100
  const agentArtifactCount = currentNodes.filter(n =>
    (n.type?.includes('ArtifactNode') ?? false) &&
    asArtifact(n.data)?.agentName === agentName
  ).length
  return { x: baseX, y: baseY + agentArtifactCount * 140 }
}

function glowEdge(
  id: string, source: string, target: string,
  opts: Partial<GlowEdgeData> = {},
): Edge {
  return {
    id,
    source,
    target,
    type: 'glow',
    data: { active: false, color: '#2a3a4c', dashed: false, ...opts } satisfies GlowEdgeData,
  }
}

function toFloorEntry(event: WSEvent): FloorEventEntry | null {
  const id = `${Date.now()}-${Math.random()}`
  const ts = Date.now()
  // Prefer the full OFP envelope JSON when available, fall back to the WS event itself
  const raw = (event as unknown as Record<string, unknown>).envelope_json as Record<string, unknown> | undefined
    ?? (event as unknown as Record<string, unknown>)
  switch (event.type) {
    case 'floor_grant':
      return { id, ts, type: 'floor_grant', agent: event.to, to: event.to, raw }
    case 'floor_revoke':
      return { id, ts, type: 'floor_revoke', agent: event.from, raw }
    case 'floor_yield':
      return { id, ts, type: 'floor_yield', agent: event.from, raw }
    case 'floor_request':
      return { id, ts, type: 'floor_request', agent: event.from, raw }
    case 'utterance':
      return { id, ts, type: 'utterance', agent: event.sender, preview: event.text.slice(0, 70), raw }
    case 'manifest_published':
      return { id, ts, type: 'manifest_published', agent: event.agent, raw }
    default:
      return null
  }
}

function applyDagreLayout(nodes: Node[], edges: Edge[]): Node[] {
  const g = new dagre.graphlib.Graph()
  g.setGraph({ rankdir: 'LR', ranksep: 80, nodesep: 40 })
  g.setDefaultEdgeLabel(() => ({}))
  nodes.forEach((n) => g.setNode(n.id, { width: 280, height: 200 }))
  edges.forEach((e) => g.setEdge(e.source, e.target))
  dagre.layout(g)
  return nodes.map((n) => {
    const pos = g.node(n.id)
    return { ...n, position: { x: pos.x - 140, y: pos.y - 100 } }
  })
}

// ── Constants ─────────────────────────────────────────────────────────────────

const FLOOR_ID     = 'floor-main'
const CONV_ID      = 'conv-main'
const TIMELINE_ID  = 'timeline-main'
const CHAT_ID      = 'chat-main'
const INSPECTOR_ID = 'inspector-main'
const LAYOUT_KEY   = 'ofp-canvas-layout-v6'  // bumped: inspector + wider chat
const API = ''

// ── Typed data accessors ──────────────────────────────────────────────────────

function asFloor(data: unknown): FloorNodeData { return data as unknown as FloorNodeData }
function asAgent(data: unknown): AgentNodeData { return data as unknown as AgentNodeData }
function asHuman(data: unknown): HumanNodeData { return data as unknown as HumanNodeData }
function asConv(data: unknown): ConversationNodeData { return data as unknown as ConversationNodeData }
function asChat(data: unknown): ConversationChatNodeData { return data as unknown as ConversationChatNodeData }
function asArtifact(data: unknown): ArtifactNodeData { return data as unknown as ArtifactNodeData }
function asGlowEdge(data: unknown): GlowEdgeData { return data as unknown as GlowEdgeData }
function asInspector(data: unknown): EventInspectorNodeData { return data as unknown as EventInspectorNodeData }

// ── Initial nodes ─────────────────────────────────────────────────────────────

function makeInitialNodes(): Node[] {
  return applyDagreLayout(
    [
      {
        id: FLOOR_ID, type: 'FloorNode', position: { x: 0, y: 0 },
        data: {
          policy: 'SEQUENTIAL', topic: '', maxTurns: null, mot: 0,
          showFloorEvents: false, noHuman: true, humanName: 'User',
          sessionState: 'idle', sessionId: null, turnCount: 0, elapsedSecs: 0,
        } satisfies FloorNodeData,
      },
      {
        id: CONV_ID, type: 'ConversationNode', position: { x: 0, y: 0 },
        data: {
          sessionId: null, policy: '', topic: '', turnCount: 0, eventLog: [],
        } satisfies ConversationNodeData,
      },
      {
        id: TIMELINE_ID, type: 'TraceTimelineNode', position: { x: 0, y: 0 },
        data: {
          sessionId: null, policy: '', topic: '', turnCount: 0, eventLog: [],
        } satisfies ConversationNodeData,
      },
      {
        id: CHAT_ID, type: 'ConversationChatNode', position: { x: 0, y: 0 },
        data: { messages: [] } satisfies ConversationChatNodeData,
      },
      {
        id: INSPECTOR_ID, type: 'EventInspectorNode', position: { x: 0, y: 0 },
        data: { event: null } satisfies EventInspectorNodeData,
      },
    ],
    [
      glowEdge(`e-${FLOOR_ID}-${CONV_ID}`, FLOOR_ID, CONV_ID),
      glowEdge(`e-${CONV_ID}-${TIMELINE_ID}`, CONV_ID, TIMELINE_ID),
      glowEdge(`e-${FLOOR_ID}-${CHAT_ID}`, FLOOR_ID, CHAT_ID),
      glowEdge(`e-${TIMELINE_ID}-${INSPECTOR_ID}`, TIMELINE_ID, INSPECTOR_ID),
    ]
  )
}

function hydrateFromConfig(config: { nodes: any[]; edges: any[] }): {
  nodes: Node[]; edges: Edge[]
} {
  const rfNodes: Node[] = []
  const rfEdges: Edge[] = []

  for (const n of config.nodes ?? []) {
    if (n.type === 'FloorNode') {
      rfNodes.push({
        id: FLOOR_ID, type: 'FloorNode', position: { x: 0, y: 0 },
        data: {
          policy: n.data?.policy ?? 'SEQUENTIAL',
          topic: n.data?.topic ?? '',
          maxTurns: n.data?.maxTurns ?? null,
          mot: n.data?.mot ?? 0,
          noHuman: n.data?.noHuman ?? true,
          humanName: n.data?.humanName ?? 'User',
          showFloorEvents: false,
          sessionState: 'idle' as const,
          sessionId: null,
          turnCount: 0,
          elapsedSecs: 0,
        } satisfies FloorNodeData,
      })
    } else if (n.type === 'AgentNode') {
      const agentId = `agent-${n.data?.name}`
      rfNodes.push({
        id: agentId, type: 'AgentNode', position: { x: 0, y: 0 },
        data: {
          provider: n.data?.provider ?? 'anthropic',
          name: n.data?.name ?? '',
          model: n.data?.model ?? '',
          systemPrompt: n.data?.systemPrompt ?? '',
          slug: n.data?.slug ?? '',
          agentType: n.data?.agentType ?? '',
          remoteTarget: n.data?.remoteTarget ?? '',
          floorState: 'waiting' as const,
          messages: [],
        } satisfies AgentNodeData,
      })
      rfEdges.push(glowEdge(`e-${FLOOR_ID}-${agentId}`, FLOOR_ID, agentId))
    } else if (n.type === 'HumanNode') {
      rfNodes.push({
        id: 'human-main', type: 'HumanNode', position: { x: 0, y: 0 },
        data: {
          humanName: n.data?.humanName ?? 'User',
          messages: [],
        } satisfies HumanNodeData,
      })
      rfEdges.push(glowEdge('e-floor-human-main', FLOOR_ID, 'human-main'))
    }
  }

  if (!rfNodes.find(n => n.id === CONV_ID)) {
    rfNodes.push({
      id: CONV_ID, type: 'ConversationNode', position: { x: 0, y: 0 },
      data: {
        sessionId: null, policy: '', topic: '', turnCount: 0, eventLog: [],
      } satisfies ConversationNodeData,
    })
    rfEdges.push(glowEdge(`e-${FLOOR_ID}-${CONV_ID}`, FLOOR_ID, CONV_ID))
  }

  if (!rfNodes.find(n => n.id === TIMELINE_ID)) {
    rfNodes.push({
      id: TIMELINE_ID, type: 'TraceTimelineNode', position: { x: 0, y: 0 },
      data: {
        sessionId: null, policy: '', topic: '', turnCount: 0, eventLog: [],
      } satisfies ConversationNodeData,
    })
    rfEdges.push(glowEdge(`e-${CONV_ID}-${TIMELINE_ID}`, CONV_ID, TIMELINE_ID))
  }

  if (!rfNodes.find(n => n.id === CHAT_ID)) {
    rfNodes.push({
      id: CHAT_ID, type: 'ConversationChatNode', position: { x: 0, y: 0 },
      data: { messages: [] } satisfies ConversationChatNodeData,
    })
    rfEdges.push(glowEdge(`e-${FLOOR_ID}-${CHAT_ID}`, FLOOR_ID, CHAT_ID))
  }

  if (!rfNodes.find(n => n.id === INSPECTOR_ID)) {
    rfNodes.push({
      id: INSPECTOR_ID, type: 'EventInspectorNode', position: { x: 0, y: 0 },
      data: { event: null } satisfies EventInspectorNodeData,
    })
    rfEdges.push(glowEdge(`e-${TIMELINE_ID}-${INSPECTOR_ID}`, TIMELINE_ID, INSPECTOR_ID))
  }

  return {
    nodes: applyDagreLayout(rfNodes, rfEdges),
    edges: rfEdges,
  }
}

// ── App ───────────────────────────────────────────────────────────────────────

export default function App() {
  const [nodes, setNodes, onNodesChange] = useNodesState(makeInitialNodes())
  const [edges, setEdges, onEdgesChange] = useEdgesState([
    glowEdge(`e-${FLOOR_ID}-${CONV_ID}`, FLOOR_ID, CONV_ID),
    glowEdge(`e-${CONV_ID}-${TIMELINE_ID}`, CONV_ID, TIMELINE_ID),
    glowEdge(`e-${FLOOR_ID}-${CHAT_ID}`, FLOOR_ID, CHAT_ID),
    glowEdge(`e-${TIMELINE_ID}-${INSPECTOR_ID}`, TIMELINE_ID, INSPECTOR_ID),
  ])
  const [sessionId, setSessionId] = useState<string | null>(null)
  const [connected, setConnectedState] = useState(false)
  const [errorBanner, setErrorBanner] = useState<string | null>(null)
  const [showAddAgent, setShowAddAgent] = useState(false)
  const [modelOpen, setModelOpen] = useState(false)
  const startedAt = useRef<number>(0)
  const elapsedTimer = useRef<ReturnType<typeof setInterval> | null>(null)
  const motRef = useRef<number>(0)
  const eventBufferRef = useRef<WSEvent[]>([])
  const drainingRef = useRef(false)

  const slugs = useSlugs()
  const models = useModels()
  const presets = usePresets()
  const remoteAgents = useRemoteAgents()
  const [selectedPreset, setSelectedPreset] = useState('')

  useEffect(() => {
    fetch('/session/initial')
      .then(r => r.ok ? r.json() : null)
      .then((config: { nodes: any[]; edges: any[] } | null) => {
        if (!config) return
        const hydrated = hydrateFromConfig(config)
        setNodes(hydrated.nodes)
        setEdges(hydrated.edges)
      })
      .catch(() => {})
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  // ── Restore layout ──────────────────────────────────────────────────────────
  useEffect(() => {
    try {
      const saved = localStorage.getItem(LAYOUT_KEY)
      if (saved) {
        const positions: Record<string, { x: number; y: number }> = JSON.parse(saved)
        setNodes((nds) => nds.map((n) => positions[n.id] ? { ...n, position: positions[n.id] } : n))
      }
    } catch { /* ignore */ }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    try {
      const positions: Record<string, { x: number; y: number }> = {}
      nodes.forEach((n) => { positions[n.id] = n.position })
      localStorage.setItem(LAYOUT_KEY, JSON.stringify(positions))
    } catch { /* quota exceeded */ }
  }, [nodes])

  // ── Helpers ─────────────────────────────────────────────────────────────────
  const patchNode = useCallback(<T extends object>(id: string, patch: Partial<T>) => {
    setNodes((nds) => nds.map((n) => n.id === id ? { ...n, data: { ...n.data, ...patch } } : n))
  }, [setNodes])

  const isRunning = asFloor(nodes.find((n) => n.id === FLOOR_ID)?.data)?.sessionState === 'running'

  // ── WS event handler ────────────────────────────────────────────────────────
  const handleEvent = useCallback((event: WSEvent) => {
    // Append to conversation event log for all renderable event types
    const entry = toFloorEntry(event)
    if (entry) {
      setNodes(nds => nds.map(n => {
        if (n.id !== CONV_ID && n.id !== TIMELINE_ID) return n
        const cd = asConv(n.data)
        return {
          ...n,
          data: {
            ...cd,
            eventLog: [...cd.eventLog.slice(-199), entry],
            turnCount: event.type === 'utterance' ? cd.turnCount + 1 : cd.turnCount,
          },
        }
      }))
    }
    switch (event.type) {
      case 'utterance': {
        const msg: Message = {
          id: `${Date.now()}-${Math.random()}`,
          sender: event.sender, text: event.text, ts: Date.now(), media: event.media,
        }
        setNodes((nds) => nds.map((n) => {
          if (n.type === 'AgentNode' && asAgent(n.data).name === event.sender) {
            const nd = asAgent(n.data)
            return { ...n, data: { ...nd, messages: [...nd.messages, msg] } }
          }
          if (n.type === 'HumanNode' && asHuman(n.data).humanName === event.sender) {
            const nd = asHuman(n.data)
            return { ...n, data: { ...nd, messages: [...nd.messages, msg] } }
          }
          if (n.id === CHAT_ID) {
            const nd = asChat(n.data)
            return { ...n, data: { ...nd, messages: [...nd.messages.slice(-299), msg] } }
          }
          return n
        }))
        // Image utterance → create ImageArtifactNode
        if (event.media?.type === 'image') {
          const agentNodeId = `agent-${event.sender}`
          const artifactId = `artifact-img-${Date.now()}`
          setNodes((nds) => {
            const artNode: Node = {
              id: artifactId, type: 'ImageArtifactNode',
              position: nextArtifactPosition(nds, agentNodeId),
              data: {
                kind: 'image', agentName: event.sender,
                label: 'image', preview: event.media!.url, url: event.media!.url,
              } satisfies ArtifactNodeData,
            }
            return [...nds, artNode]
          })
          setEdges((eds) => [...eds, glowEdge(
            `e-${agentNodeId}-${artifactId}`,
            agentNodeId, artifactId,
            { color: '#8b5cf6', dashed: true },
          )])
        }
        break
      }

      case 'floor_grant': {
        setNodes((nds) => nds.map((n) => {
          if (n.type !== 'AgentNode') return n
          const nd = asAgent(n.data)
          const state: AgentFloorState = nd.name === event.to ? 'speaking' : 'waiting'
          return { ...n, data: { ...nd, floorState: state } }
        }))
        const targetAgentId = `agent-${event.to}`
        setEdges((eds) => eds.map((e) => ({
          ...e,
          data: {
            ...asGlowEdge(e.data),
            active: e.source === FLOOR_ID && e.target === targetAgentId,
            pulse: null,   // clear any pending request pulse
          },
        })))
        break
      }

      case 'floor_revoke': {
        setNodes((nds) => nds.map((n) => {
          if (n.type !== 'AgentNode') return n
          const nd = asAgent(n.data)
          if (nd.name === event.from) return { ...n, data: { ...nd, floorState: 'waiting' as AgentFloorState } }
          return n
        }))
        setEdges((eds) => eds.map((e) => ({ ...e, data: { ...asGlowEdge(e.data), active: false } })))
        break
      }

      case 'floor_request': {
        const targetAgentId = `agent-${event.from}`
        setNodes((nds) => nds.map((n) => {
          if (n.type !== 'AgentNode') return n
          const nd = asAgent(n.data)
          if (nd.name !== event.from) return n
          return { ...n, data: { ...nd, floorState: 'requesting' as AgentFloorState } }
        }))
        // pulse the edge amber while requesting
        setEdges(eds => eds.map(e =>
          e.source === FLOOR_ID && e.target === targetAgentId
            ? { ...e, data: { ...asGlowEdge(e.data), pulse: 'amber' as const } }
            : e
        ))
        break
      }

      case 'floor_yield': {
        const targetAgentId = `agent-${event.from}`
        setNodes(nds => nds.map(n => {
          if (n.type !== 'AgentNode') return n
          const nd = asAgent(n.data)
          if (nd.name !== event.from) return n
          return { ...n, data: { ...nd, floorState: 'yielding' as AgentFloorState } }
        }))
        setEdges(eds => eds.map(e =>
          e.source === FLOOR_ID && e.target === targetAgentId
            ? { ...e, data: { ...asGlowEdge(e.data), active: false, pulse: 'teal' as const } }
            : e
        ))
        setTimeout(() => {
          setNodes(nds => nds.map(n => {
            if (n.type !== 'AgentNode') return n
            const nd = asAgent(n.data)
            if (nd.name !== event.from) return n
            return { ...n, data: { ...nd, floorState: 'waiting' as AgentFloorState } }
          }))
          setEdges(eds => eds.map(e =>
            e.source === FLOOR_ID && e.target === targetAgentId
              ? { ...e, data: { ...asGlowEdge(e.data), pulse: null } }
              : e
          ))
        }, 1500)
        break
      }

      case 'manifest_published': {
        const targetAgentId = `agent-${event.agent}`
        setNodes(nds => nds.map(n => {
          if (n.type !== 'AgentNode') return n
          const nd = asAgent(n.data)
          if (nd.name !== event.agent) return n
          return { ...n, data: { ...nd, floorState: 'manifest' as AgentFloorState } }
        }))
        setEdges(eds => eds.map(e =>
          e.source === FLOOR_ID && e.target === targetAgentId
            ? { ...e, data: { ...asGlowEdge(e.data), pulse: 'purple' as const } }
            : e
        ))
        setTimeout(() => {
          setNodes(nds => nds.map(n => {
            if (n.type !== 'AgentNode') return n
            const nd = asAgent(n.data)
            if (nd.name !== event.agent) return n
            return { ...n, data: { ...nd, floorState: 'waiting' as AgentFloorState } }
          }))
          setEdges(eds => eds.map(e =>
            e.source === FLOOR_ID && e.target === targetAgentId
              ? { ...e, data: { ...asGlowEdge(e.data), pulse: null } }
              : e
          ))
        }, 1500)
        break
      }

      case 'agent_spawning': {
        setNodes((nds) => {
          const exists = nds.find((n) => n.type === 'AgentNode' && asAgent(n.data).name === event.name)
          if (exists) {
            return nds.map((n) =>
              n.id === exists.id ? { ...n, data: { ...n.data, floorState: 'spawning' as AgentFloorState } } : n
            )
          }
          const newId = `agent-${event.name}`
          const newNode: Node = {
            id: newId, type: 'AgentNode',
            position: { x: 400, y: 100 + nds.filter((n) => n.type === 'AgentNode').length * 220 },
            data: {
              provider: event.provider as AgentNodeData['provider'],
              name: event.name, model: '', systemPrompt: '', slug: '',
              agentType: '', remoteTarget: '', floorState: 'spawning', messages: [],
            } satisfies AgentNodeData,
          }
          setEdges((eds) => [...eds, glowEdge(`e-${FLOOR_ID}-${newId}`, FLOOR_ID, newId)])
          return [...nds, newNode]
        })
        break
      }

      case 'agent_joined': {
        setNodes((nds) => nds.map((n) => {
          if (n.type === 'AgentNode' && asAgent(n.data).name === event.name)
            return { ...n, data: { ...n.data, floorState: 'waiting' as AgentFloorState } }
          return n
        }))
        break
      }

      case 'agent_kicked': {
        const kickedId = `agent-${event.name}`
        setNodes((nds) => nds.filter((n) => n.id !== kickedId))
        setEdges((eds) => eds.filter((e) => e.target !== kickedId))
        break
      }

      case 'artifact_saved': {
        const agentNodeId = `agent-${event.agent}`
        const artifactId = `artifact-${event.slug ?? Date.now()}`
        const color = ARTIFACT_COLOR[event.kind] ?? '#58a6ff'
        const nodeType = artifactNodeType(event.kind)
        setNodes((nds) => {
          const artNode: Node = {
            id: artifactId, type: nodeType,
            position: nextArtifactPosition(nds, agentNodeId),
            data: {
              kind: event.kind as ArtifactNodeData['kind'],
              agentName: event.agent,
              slug: event.slug,
              label: event.slug ?? 'artifact',
              preview: event.preview,
            } satisfies ArtifactNodeData,
          }
          return [...nds, artNode]
        })
        setEdges((eds) => [...eds, glowEdge(
          `e-${agentNodeId}-${artifactId}`,
          agentNodeId, artifactId,
          { color, dashed: true },
        )])
        break
      }

      case 'image_saved': {
        const agentNodeId = `agent-${event.agent}`
        const artifactId = `artifact-img-saved-${Date.now()}`
        setNodes((nds) => {
          const artNode: Node = {
            id: artifactId, type: 'ImageArtifactNode',
            position: nextArtifactPosition(nds, agentNodeId),
            data: {
              kind: 'image', agentName: event.agent,
              label: event.url.split('/').pop() ?? 'image',
              preview: event.url, url: event.url,
            } satisfies ArtifactNodeData,
          }
          return [...nds, artNode]
        })
        setEdges((eds) => [...eds, glowEdge(
          `e-${agentNodeId}-${artifactId}`,
          agentNodeId, artifactId,
          { color: '#8b5cf6', dashed: true },
        )])
        break
      }

      case 'memory_saved': {
        const agentNodeId = `agent-${event.agent ?? 'unknown'}`
        const artifactId = `artifact-mem-${Date.now()}`
        setNodes((nds) => {
          const artNode: Node = {
            id: artifactId, type: 'PhaseArtifactNode',
            position: nextArtifactPosition(nds, agentNodeId),
            data: {
              kind: 'phase', agentName: event.agent ?? 'unknown',
              label: event.category, preview: event.content.slice(0, 120),
            } satisfies ArtifactNodeData,
          }
          return [...nds, artNode]
        })
        setEdges((eds) => [...eds, glowEdge(
          `e-${agentNodeId}-${artifactId}`,
          agentNodeId, artifactId,
          { color: '#58a6ff', dashed: true },
        )])
        break
      }

      case 'error': {
        setNodes((nds) => nds.map((n) => {
          if (n.type === 'AgentNode' && asAgent(n.data).name === event.agent)
            return { ...n, data: { ...n.data, floorState: 'error' as AgentFloorState, errorMessage: event.message } }
          return n
        }))
        break
      }

      case 'session_ended': {
        patchNode<FloorNodeData>(FLOOR_ID, { sessionState: 'stopped' })
        patchNode<ConversationNodeData>(CONV_ID, { sessionId: null })
        patchNode<ConversationNodeData>(TIMELINE_ID, { sessionId: null })
        // Keep chat messages after session ends so user can read them
        setEdges((eds) => eds.map((e) => ({ ...e, data: { ...asGlowEdge(e.data), active: false } })))
        if (elapsedTimer.current) clearInterval(elapsedTimer.current)
        break
      }
    }
  }, [patchNode, setEdges, setNodes])

  // ── Session control ──────────────────────────────────────────────────────────
  const handleRun = useCallback(async () => {
    setErrorBanner(null)
    const floorNode = nodes.find((n) => n.id === FLOOR_ID)
    if (!floorNode) return
    const fd = asFloor(floorNode.data)
    const graphNodes = nodes.map((n) => ({ id: n.id, type: n.type, data: n.data }))
    const graphEdges = edges.map((e) => ({ source: e.source, target: e.target }))
    try {
      const res = await fetch(`${API}/session/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ nodes: graphNodes, edges: graphEdges }),
      })
      if (!res.ok) {
        const detail = await res.json().then((d: { detail?: string }) => d.detail).catch(() => res.statusText)
        setErrorBanner(`Start failed: ${detail}`)
        return
      }
      const { session_id } = await res.json() as { session_id: string }
      setSessionId(session_id)
      startedAt.current = Date.now()
      patchNode<FloorNodeData>(FLOOR_ID, { sessionState: 'running', sessionId: session_id, turnCount: 0, elapsedSecs: 0 })
      const convPatch = { sessionId: session_id, policy: fd.policy, topic: fd.topic, turnCount: 0, eventLog: [] }
      patchNode<ConversationNodeData>(CONV_ID, convPatch)
      patchNode<ConversationNodeData>(TIMELINE_ID, convPatch)
      patchNode<ConversationChatNodeData>(CHAT_ID, { messages: [] })
      elapsedTimer.current = setInterval(() => {
        patchNode<FloorNodeData>(FLOOR_ID, { elapsedSecs: Math.floor((Date.now() - startedAt.current) / 1000) })
      }, 1000)
    } catch (e) {
      setErrorBanner(`Network error: ${e}`)
    }
  }, [nodes, edges, patchNode])

  const handleStop = useCallback(async () => {
    await fetch(`${API}/session/stop`, { method: 'DELETE' }).catch(() => {})
    patchNode<FloorNodeData>(FLOOR_ID, { sessionState: 'stopped' })
    setEdges((eds) => eds.map((e) => ({ ...e, data: { ...asGlowEdge(e.data), active: false } })))
    if (elapsedTimer.current) clearInterval(elapsedTimer.current)
  }, [patchNode, setEdges])

  // ── MOT event buffering ───────────────────────────────────────────────────────
  // Keep motRef current so the async drain loop always reads the latest value
  useEffect(() => {
    const floorNode = nodes.find(n => n.id === FLOOR_ID)
    motRef.current = asFloor(floorNode?.data)?.mot ?? 0
  }, [nodes])

  const drainBuffer = useCallback(async () => {
    if (drainingRef.current) return
    drainingRef.current = true
    while (eventBufferRef.current.length > 0) {
      const evt = eventBufferRef.current.shift()!
      handleEvent(evt)
      const delay = motRef.current
      if (delay > 0) {
        await new Promise<void>(r => setTimeout(r, delay))
      }
    }
    drainingRef.current = false
  }, [handleEvent])

  const onEvent = useCallback((event: WSEvent) => {
    eventBufferRef.current.push(event)
    drainBuffer()
  }, [drainBuffer])

  // ── WS ───────────────────────────────────────────────────────────────────────
  const { connected: wsConnected, sendMessage, kickAgent } = useSession({ sessionId, onEvent })
  useEffect(() => setConnectedState(wsConnected), [wsConnected])

  // ── Add agent ─────────────────────────────────────────────────────────────
  const [newAgent, setNewAgent] = useState({
    provider: 'anthropic', name: '', model: '', systemPrompt: '', slug: '', agentType: '', remoteTarget: '',
  })
  const [remoteQuery, setRemoteQuery] = useState('')
  const [remoteOpen, setRemoteOpen] = useState(false)
  const [modelQuery, setModelQuery] = useState('')
  const providerModels = (models[newAgent.provider] ?? []).filter(m =>
    modelQuery === '' || m.includes(modelQuery)
  )

  const handleAddAgent = useCallback(async () => {
    if (newAgent.provider === 'remote' ? !newAgent.remoteTarget.trim() : !newAgent.name.trim()) return
    if (isRunning) {
      await fetch(`${API}/session/agent/add`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(newAgent),
      }).catch(() => {})
    } else {
      const newId = `agent-${newAgent.name}`
      const newNode: Node = {
        id: newId, type: 'AgentNode',
        position: { x: 400, y: 100 + nodes.filter((n) => n.type === 'AgentNode').length * 220 },
        data: {
          provider: newAgent.provider as AgentNodeData['provider'],
          name: newAgent.name, model: newAgent.model,
          systemPrompt: newAgent.systemPrompt, slug: newAgent.slug,
          agentType: newAgent.agentType, remoteTarget: newAgent.remoteTarget,
          floorState: 'waiting', messages: [],
        } satisfies AgentNodeData,
      }
      setNodes((nds) => [...nds, newNode])
      setEdges((eds) => [...eds, glowEdge(`e-${FLOOR_ID}-${newId}`, FLOOR_ID, newId)])
    }
    setNewAgent({ provider: 'anthropic', name: '', model: '', systemPrompt: '', slug: '', agentType: '', remoteTarget: '' })
    setModelQuery('')
    setRemoteQuery('')
    setShowAddAgent(false)
  }, [newAgent, isRunning, nodes, setNodes, setEdges])

  const loadPreset = useCallback(async (name: string) => {
    if (!name) return
    try {
      const config = await fetch(`/presets/${name}`).then(r => r.json())
      const hydrated = hydrateFromConfig(config)
      setNodes(hydrated.nodes)
      setEdges(hydrated.edges)
      setSelectedPreset('')
    } catch { /* ignore */ }
  }, [setNodes, setEdges])

  const handleSelectEvent = useCallback((event: FloorEventEntry | null) => {
    patchNode<EventInspectorNodeData>(INSPECTOR_ID, { event })
  }, [patchNode])

  // ── Context value ─────────────────────────────────────────────────────────
  const callbacks = useMemo<CanvasCallbacks>(() => ({
    onRun: handleRun,
    onStop: handleStop,
    onFloorChange: (patch) => patchNode<FloorNodeData>(FLOOR_ID, patch),
    onKick: kickAgent,
    onSend: sendMessage,
    onSelectEvent: handleSelectEvent,
    sessionRunning: isRunning,
  }), [handleRun, handleStop, patchNode, kickAgent, sendMessage, handleSelectEvent, isRunning])

  const onConnect = useCallback(
    (connection: Connection) => setEdges((eds) => addEdge(
      { ...connection, type: 'glow', data: { active: false, color: '#2a3a4c', dashed: false } },
      eds,
    )),
    [setEdges]
  )

  return (
    <div style={{ width: '100vw', height: '100vh', display: 'flex', background: '#0d1117' }}>
      {/* ── Sidebar ─────────────────────────────────────────────────────────── */}
      <div style={{
        width: 220, background: '#161b22', borderRight: '1px solid #21262d',
        display: 'flex', flexDirection: 'column', padding: '14px 10px',
        gap: 8, flexShrink: 0, overflowY: 'auto',
      }}>
        <div style={{ color: '#58a6ff', fontWeight: 700, fontSize: 14, marginBottom: 6 }}>OFP Canvas</div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 11, color: '#93a4b8' }}>
          <div style={{ width: 7, height: 7, borderRadius: '50%', background: connected ? '#38a169' : '#e53e3e' }} />
          {connected ? 'Connected' : 'Disconnected'}
        </div>

        {presets.length > 0 && (
          <>
            <div style={{ color: '#93a4b8', fontSize: 10, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 1 }}>
              Load Preset
            </div>
            <select
              value={selectedPreset}
              onChange={e => { setSelectedPreset(e.target.value); loadPreset(e.target.value) }}
              disabled={isRunning}
              style={{
                width: '100%', background: '#0d1520', color: '#e6edf5',
                border: '1px solid #2a3a4c', borderRadius: 5,
                padding: '4px 7px', fontSize: 11, fontFamily: 'inherit',
              }}
            >
              <option value="">Select a preset…</option>
              {presets.map(p => (
                <option key={p.name} value={p.name} title={p.description}>
                  {p.title}
                </option>
              ))}
            </select>
            <hr style={{ border: 'none', borderTop: '1px solid #21262d' }} />
          </>
        )}

        <hr style={{ border: 'none', borderTop: '1px solid #21262d' }} />

        <div style={{ color: '#93a4b8', fontSize: 10, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 1 }}>
          Add Agent
        </div>

        <button
          onClick={() => setShowAddAgent(!showAddAgent)}
          style={{
            background: '#1a2a3a', color: '#58a6ff', border: '1px solid #58a6ff44',
            borderRadius: 6, padding: '7px 0', fontSize: 12, cursor: 'pointer', fontWeight: 600,
          }}
        >
          + Agent
        </button>

        {showAddAgent && (
          <div style={{
            background: '#0d1520', border: '1px solid #2a3a4c', borderRadius: 7, padding: 10,
            display: 'flex', flexDirection: 'column', gap: 6, fontSize: 11,
          }}>
            {/* Provider */}
            <select
              value={newAgent.provider}
              onChange={(e) => setNewAgent((a) => ({ ...a, provider: e.target.value, remoteTarget: '', name: '' }))}
              style={inputStyle}
            >
              <option value="anthropic">Anthropic</option>
              <option value="openai">OpenAI</option>
              <option value="google">Google</option>
              <option value="huggingface">HuggingFace</option>
              <option value="remote">Remote OFP</option>
            </select>

            {newAgent.provider === 'remote' ? (
              <>
                {/* Remote target: slug or URL with known-slug suggestions */}
                <div style={{ position: 'relative' }}>
                  <input
                    type="text"
                    placeholder="Slug (e.g. polly) or URL"
                    value={newAgent.remoteTarget}
                    onChange={(e) => {
                      const v = e.target.value
                      const match = remoteAgents.find(r => r.slug === v)
                      setNewAgent((a) => ({
                        ...a,
                        remoteTarget: v,
                        name: match ? match.name : a.name,
                      }))
                      setRemoteQuery(v)
                    }}
                    onFocus={() => setRemoteOpen(true)}
                    onBlur={() => setTimeout(() => setRemoteOpen(false), 150)}
                    style={inputStyle}
                  />
                  {remoteOpen && remoteAgents.filter(r =>
                    !remoteQuery || r.slug.includes(remoteQuery) || r.name.toLowerCase().includes(remoteQuery.toLowerCase())
                  ).length > 0 && (
                    <div style={{
                      position: 'absolute', top: 'calc(100% + 3px)', left: 0, right: 0,
                      background: '#1a2332', border: '1px solid #2a4060', borderRadius: 6,
                      zIndex: 100, overflow: 'hidden', boxShadow: '0 4px 16px #00000077',
                    }}>
                      {remoteAgents
                        .filter(r => !remoteQuery || r.slug.includes(remoteQuery) || r.name.toLowerCase().includes(remoteQuery.toLowerCase()))
                        .map((r) => (
                          <div
                            key={r.slug}
                            onMouseDown={() => {
                              setNewAgent((a) => ({ ...a, remoteTarget: r.slug, name: r.name }))
                              setRemoteQuery('')
                              setRemoteOpen(false)
                            }}
                            style={{ padding: '5px 10px', fontSize: 10, cursor: 'pointer', color: '#93a4b8' }}
                          >
                            <span style={{ color: '#58a6ff', fontWeight: 600 }}>{r.slug}</span>
                            {' — '}{r.name}
                          </div>
                        ))}
                    </div>
                  )}
                </div>
                {/* Display name (auto-filled from slug) */}
                <input
                  type="text"
                  placeholder="Display name (auto-filled)"
                  value={newAgent.name}
                  onChange={(e) => setNewAgent((a) => ({ ...a, name: e.target.value }))}
                  style={inputStyle}
                />
              </>
            ) : (
              <>
                {/* Type */}
                <select
                  value={newAgent.agentType}
                  onChange={(e) => setNewAgent((a) => ({ ...a, agentType: e.target.value }))}
                  style={inputStyle}
                >
                  {TASK_SUBTYPES.map((t) => (
                    <option key={t} value={t}>{t === '' ? '(default)' : t}</option>
                  ))}
                </select>

                {/* Name */}
                <input
                  type="text"
                  placeholder="Name (required)"
                  value={newAgent.name}
                  onChange={(e) => setNewAgent((a) => ({ ...a, name: e.target.value }))}
                  style={inputStyle}
                />

                {/* Model with suggestions */}
                <div style={{ position: 'relative' }}>
                  <input
                    type="text"
                    placeholder="Model (optional)"
                    value={newAgent.model}
                    onChange={(e) => { setNewAgent((a) => ({ ...a, model: e.target.value })); setModelQuery(e.target.value) }}
                    onFocus={() => setModelOpen(true)}
                    onBlur={() => setTimeout(() => setModelOpen(false), 150)}
                    style={inputStyle}
                  />
                  {modelOpen && providerModels.length > 0 && (
                    <div style={{
                      position: 'absolute', top: 'calc(100% + 3px)', left: 0, right: 0,
                      background: '#1a2332', border: '1px solid #2a4060', borderRadius: 6,
                      zIndex: 100, overflow: 'hidden', boxShadow: '0 4px 16px #00000077',
                    }}>
                      {providerModels.map((m) => (
                        <div
                          key={m}
                          onMouseDown={() => { setNewAgent((a) => ({ ...a, model: m })); setModelOpen(false) }}
                          style={{ padding: '5px 10px', fontSize: 10, cursor: 'pointer', color: '#93a4b8' }}
                        >
                          {m}
                        </div>
                      ))}
                    </div>
                  )}
                </div>

                {/* Slug/system prompt with autocomplete */}
                <SlugCombobox
                  value={newAgent.systemPrompt || newAgent.slug}
                  onChange={(v) => setNewAgent((a) => ({
                    ...a,
                    systemPrompt: v.startsWith('@') ? '' : v,
                    slug: v.startsWith('@') ? v : '',
                  }))}
                  slugs={slugs}
                  style={inputStyle}
                />
              </>
            )}

            <button
              onClick={handleAddAgent}
              style={{
                background: '#1a4731', color: '#68d391', border: '1px solid #68d39166',
                borderRadius: 5, padding: '5px 0', cursor: 'pointer', fontSize: 11,
              }}
            >
              Add
            </button>
          </div>
        )}

        <hr style={{ border: 'none', borderTop: '1px solid #21262d' }} />

        {errorBanner && (
          <div style={{
            background: '#2d1515', border: '1px solid #e53e3e44',
            borderRadius: 5, padding: '6px 8px', color: '#fc8181', fontSize: 11,
          }}>
            {errorBanner}
            <button
              onClick={() => setErrorBanner(null)}
              style={{ float: 'right', background: 'none', border: 'none', color: '#fc8181', cursor: 'pointer' }}
            >×</button>
          </div>
        )}
      </div>

      {/* ── Canvas ──────────────────────────────────────────────────────────── */}
      <CanvasContext.Provider value={callbacks}>
        <div style={{ flex: 1, position: 'relative' }}>
          <ReactFlow
            nodes={nodes}
            edges={edges}
            onNodesChange={onNodesChange}
            onEdgesChange={onEdgesChange}
            onConnect={onConnect}
            nodeTypes={NODE_TYPES}
            edgeTypes={EDGE_TYPES}
            fitView
            minZoom={0.05}
            maxZoom={2}
            proOptions={{ hideAttribution: true }}
            style={{ background: '#0d1117' }}
          >
            <Background color="#1a2332" variant={BackgroundVariant.Dots} gap={20} size={1} />
            <Controls style={{ background: '#161b22', border: '1px solid #21262d' }} />
            <MiniMap
              style={{ background: '#161b22', border: '1px solid #21262d' }}
              nodeColor="#2a3a4c"
            />
          </ReactFlow>
        </div>
      </CanvasContext.Provider>
    </div>
  )
}

const inputStyle: React.CSSProperties = {
  width: '100%', background: '#0d1520', color: '#e6edf5',
  border: '1px solid #2a3a4c', borderRadius: 5, padding: '4px 7px',
  fontSize: 11, boxSizing: 'border-box', fontFamily: 'inherit',
}
