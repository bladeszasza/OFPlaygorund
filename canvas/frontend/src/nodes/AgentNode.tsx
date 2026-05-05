// canvas/frontend/src/nodes/AgentNode.tsx
import { useState } from 'react'
import { Handle, Position } from '@xyflow/react'
import { useCanvas } from '../context/CanvasContext'
import type { AgentNodeData, AgentFloorState } from '../types'

const PROVIDER_COLOR: Record<string, string> = {
  anthropic: '#d4a843',
  openai: '#10a37f',
  google: '#4285f4',
  huggingface: '#ff7b00',
}

const STATE_COLOR: Record<AgentFloorState, string> = {
  speaking: '#38a169',
  waiting: '#4a5568',
  requesting: '#d69e2e',
  error: '#e53e3e',
  spawning: '#805ad5',
}

const STATE_LABEL: Record<AgentFloorState, string> = {
  speaking: '🎙 speaking',
  waiting: '⏳ waiting',
  requesting: '✋ requesting',
  error: '❌ error',
  spawning: '⚙ spawning',
}

const TYPE_COLOR: Record<string, string> = {
  showrunner: '#d4a843',
  orchestrator: '#d4a843',
  'code-generation': '#00bcd4',
  'text-to-image': '#8b5cf6',
  'text-to-music': '#f97316',
  'text-to-video': '#e53e3e',
}

export function AgentNode({ data }: { data: AgentNodeData }) {
  const { onKick } = useCanvas()
  const [hovered, setHovered] = useState(false)
  const [expanded, setExpanded] = useState(false)
  const providerColor = PROVIDER_COLOR[data.provider] ?? '#58a6ff'
  const stateColor = STATE_COLOR[data.floorState] ?? '#4a5568'
  const isSpeaking = data.floorState === 'speaking'
  const isSpawning = data.floorState === 'spawning'
  const typeColor = data.agentType ? (TYPE_COLOR[data.agentType] ?? '#58a6ff') : null

  return (
    <div
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        background: 'linear-gradient(135deg, #161f2e 0%, #0d1520 100%)',
        border: `2px solid ${isSpeaking ? stateColor : '#2a3a4c'}`,
        borderRadius: 10, padding: '12px 14px',
        minWidth: 220, maxWidth: 300,
        color: '#e6edf5', fontFamily: 'ui-sans-serif, system-ui, sans-serif', fontSize: 12,
        position: 'relative', transition: 'border-color 0.2s, box-shadow 0.2s',
        boxShadow: isSpeaking ? `0 0 18px ${stateColor}55` : undefined,
        opacity: isSpawning ? 0.6 : 1,
      }}
    >
      <Handle type="target" position={Position.Left} style={{ background: providerColor }} />

      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
        <span style={{
          background: `${providerColor}22`, color: providerColor,
          borderRadius: 4, padding: '1px 6px', fontSize: 10, fontWeight: 700,
          textTransform: 'uppercase',
        }}>
          {data.provider}
        </span>
        {typeColor && data.agentType && (
          <span style={{
            background: `${typeColor}22`, color: typeColor,
            borderRadius: 4, padding: '1px 6px', fontSize: 9, fontWeight: 700,
            textTransform: 'uppercase',
          }}>
            {data.agentType.replace('-', ' ')}
          </span>
        )}
        <span style={{ fontWeight: 700, fontSize: 13, flex: 1 }}>{data.name}</span>
        <span style={{
          fontSize: 10, background: `${stateColor}22`, color: stateColor,
          borderRadius: 4, padding: '1px 6px',
        }}>
          {STATE_LABEL[data.floorState]}
        </span>
      </div>

      {data.model && (
        <div style={{ color: '#93a4b8', fontSize: 10, marginBottom: 6 }}>{data.model}</div>
      )}

      {data.floorState === 'error' && data.errorMessage && (
        <div style={{
          background: '#2d1515', border: '1px solid #e53e3e44',
          borderRadius: 5, padding: '4px 7px', fontSize: 11,
          color: '#fc8181', marginBottom: 6,
        }}>
          {data.errorMessage}
        </div>
      )}

      {data.messages.length > 0 && (
        <div style={{ marginTop: 4 }}>
          <div
            onClick={() => setExpanded(!expanded)}
            style={{ cursor: 'pointer', fontSize: 10, color: '#93a4b8', marginBottom: 4, userSelect: 'none' }}
          >
            {expanded ? '▾' : '▸'} {data.messages.length} message{data.messages.length !== 1 ? 's' : ''}
          </div>
          {expanded && (
            <div style={{ maxHeight: 180, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 4 }}>
              {data.messages.slice(-8).map((msg) => (
                <div key={msg.id} style={{
                  background: '#0d1520', borderRadius: 6, padding: '5px 8px',
                  fontSize: 11, lineHeight: 1.4, color: '#c9d1d9',
                  wordBreak: 'break-word', border: '1px solid #2a3a4c',
                }}>
                  {msg.media && (
                    <div style={{ marginBottom: 4 }}>
                      {msg.media.type === 'image' ? (
                        <img src={msg.media.url} alt="output" style={{ maxWidth: '100%', borderRadius: 4 }} />
                      ) : (
                        <a href={msg.media.url} target="_blank" rel="noreferrer" style={{ color: '#58a6ff' }}>
                          [{msg.media.type}]
                        </a>
                      )}
                    </div>
                  )}
                  {msg.text}
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {hovered && (
        <button
          onClick={() => onKick(data.name)}
          style={{
            position: 'absolute', top: 8, right: 8,
            background: '#6b2121', color: '#fc8181',
            border: '1px solid #fc818166',
            borderRadius: 4, fontSize: 10, padding: '2px 6px', cursor: 'pointer',
          }}
        >
          Kick
        </button>
      )}
    </div>
  )
}
