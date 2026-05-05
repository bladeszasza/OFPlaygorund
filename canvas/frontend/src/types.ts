// canvas/frontend/src/types.ts

export type FloorPolicy =
  | 'SEQUENTIAL'
  | 'ROUND_ROBIN'
  | 'MODERATED'
  | 'FREE_FOR_ALL'
  | 'SHOWRUNNER_DRIVEN'

export type AgentProvider = 'anthropic' | 'openai' | 'google' | 'huggingface'

export type SessionState = 'idle' | 'running' | 'stopped'

export type AgentFloorState =
  | 'speaking' | 'waiting' | 'requesting' | 'error' | 'spawning'
  | 'yielding'   // transient ~1.5s: agent voluntarily yielded
  | 'manifest'   // transient ~1.5s: agent published capabilities

export type ArtifactKind = 'image' | 'code' | 'phase' | 'music'

export interface Message {
  id: string
  sender: string
  text: string
  ts: number
  media?: { type: string; url: string } | null
}

export interface FloorEventEntry {
  id: string
  type: 'floor_grant' | 'floor_revoke' | 'floor_yield' | 'floor_request'
       | 'utterance' | 'manifest_published'
  agent: string
  to?: string
  preview?: string
  ts: number
}

export interface FloorNodeData {
  policy: FloorPolicy
  topic: string
  maxTurns: number | null
  showFloorEvents: boolean
  noHuman: boolean
  humanName: string
  sessionState: SessionState
  sessionId: string | null
  turnCount: number
  elapsedSecs: number
}

export interface AgentNodeData {
  provider: AgentProvider
  name: string
  model: string
  systemPrompt: string
  slug: string
  agentType: string          // maps to TASK_SUBTYPES, '' = text-generation
  floorState: AgentFloorState
  messages: Message[]
  errorMessage?: string
}

export interface HumanNodeData {
  humanName: string
  messages: Message[]
}

export interface ConversationNodeData {
  sessionId: string | null
  policy: string
  topic: string
  turnCount: number
  eventLog: FloorEventEntry[]
}

export interface ArtifactNodeData {
  kind: ArtifactKind
  agentName: string
  slug?: string
  label: string        // filename or slug
  preview: string      // first ~120 chars, or image URL
  url?: string         // direct URL for images / audio
}

export interface GlowEdgeData {
  active: boolean      // true while the target agent holds the floor
  color: string        // stroke color
  dashed: boolean      // true for artifact edges
  pulse?: 'amber' | 'teal' | 'purple' | null
}

export interface ArtifactCardData {
  id: string
  kind: 'markdown' | 'image' | 'memory'
  agent: string | null
  slug?: string
  preview: string
  url?: string
  category?: string
  content?: string
  x: number
  y: number
}

// ── WebSocket event union ─────────────────────────────────────────────────────

export type WSEvent =
  | { type: 'utterance'; sender: string; sender_uri: string; text: string; media: { type: string; url: string } | null }
  | { type: 'floor_grant'; to: string }
  | { type: 'floor_revoke'; from: string }
  | { type: 'floor_request'; from: string }
  | { type: 'floor_yield'; from: string }
  | { type: 'manifest_published'; agent: string }
  | { type: 'artifact_saved'; slug: string; kind: string; agent: string; preview: string }
  | { type: 'image_saved'; agent: string; url: string }
  | { type: 'memory_saved'; category: string; content: string; agent: string | null }
  | { type: 'agent_joined'; name: string; provider: string }
  | { type: 'agent_kicked'; name: string }
  | { type: 'agent_spawning'; name: string; provider: string }
  | { type: 'error'; agent: string; message: string; retryable: boolean }
  | { type: 'session_ended' }

// ── Agent library entry ───────────────────────────────────────────────────────

export interface SlugEntry {
  slug: string
  display_name: string
  category: string
}
