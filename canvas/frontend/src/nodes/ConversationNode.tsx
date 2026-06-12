// canvas/frontend/src/nodes/ConversationNode.tsx
import { useRef, useEffect } from 'react'
import { Handle, Position } from '@xyflow/react'
import type { ConversationNodeData, FloorEventEntry } from '../types'

function fmtTs(ts: number) {
  const d = new Date(ts)
  return `${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}:${String(d.getSeconds()).padStart(2,'0')}`
}

const EVENT_CFG: Record<FloorEventEntry['type'], { color: string; label: (e: FloorEventEntry) => string }> = {
  floor_grant:        { color: '#38a169', label: () => 'got the floor' },
  floor_revoke:       { color: '#e53e3e', label: () => 'floor revoked' },
  floor_yield:        { color: '#00bcd4', label: () => 'yielded the floor' },
  floor_request:      { color: '#d4a843', label: () => 'requested the floor' },
  utterance:          { color: '#58a6ff', label: (e) => e.preview?.slice(0, 70) ?? '' },
  manifest_published: { color: '#8b5cf6', label: () => 'published manifest' },
}

export function ConversationNode({ data }: { data: ConversationNodeData }) {
  const listRef = useRef<HTMLDivElement>(null)
  const liveUrl = data.sessionId ? `/trace/live?session=${data.sessionId}` : null

  // Scroll to top when new events arrive (newest-first list)
  useEffect(() => {
    if (listRef.current) listRef.current.scrollTop = 0
  }, [data.eventLog.length])

  const reversed = [...data.eventLog].reverse()

  return (
    <div style={{
      background: 'linear-gradient(135deg, #1a1f2e 0%, #0d1117 100%)',
      border: '2px solid #30363d',
      borderRadius: 12,
      padding: '16px 18px',
      minWidth: 560,
      color: '#e6edf5',
      fontFamily: 'ui-sans-serif, system-ui, sans-serif',
      fontSize: 13,
    }}>
      <Handle type="target" position={Position.Top} />

      {/* ── Header ─────────────────────────────────────────────────────────── */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
        <span style={{ fontSize: 15 }}>📋</span>
        <span style={{ fontWeight: 700, fontSize: 13 }}>Events</span>
        <span style={{ color: '#4a5568', fontSize: 11 }}>
          {data.turnCount} turns · {data.eventLog.length} events
        </span>
        {liveUrl && (
          <button
            className="nodrag"
            onClick={() => window.open(liveUrl, '_blank')}
            title="Open full trace in browser"
            style={{
              marginLeft: 'auto', background: '#1a2a3a', color: '#58a6ff',
              border: '1px solid #58a6ff44', borderRadius: 4,
              padding: '2px 8px', fontSize: 10, cursor: 'pointer',
            }}
          >
            ⤢ Full
          </button>
        )}
      </div>

      {/* ── Session meta ───────────────────────────────────────────────────── */}
      <div style={{ marginBottom: 10, display: 'flex', flexDirection: 'column', gap: 3 }}>
        {data.policy && (
          <div style={{ color: '#93a4b8', fontSize: 11 }}>
            Policy: <span style={{ color: '#c9d1d9' }}>{data.policy}</span>
          </div>
        )}
        {data.topic && (
          <div style={{ color: '#93a4b8', fontSize: 11 }}>
            Topic:{' '}
            <span style={{ color: '#c9d1d9' }}>
              {data.topic.length > 60 ? `${data.topic.slice(0, 60)}…` : data.topic}
            </span>
          </div>
        )}
      </div>

      {/* ── Events list (newest first) ─────────────────────────────────────── */}
      <div
        ref={listRef}
        className="nodrag nowheel nopan"
        onWheel={e => e.stopPropagation()}
        style={{
          background: '#0d1117',
          border: '1px solid #21262d',
          borderRadius: 7,
          maxHeight: 420,
          overflowY: 'auto',
          padding: '4px 8px',
        }}
      >
        {reversed.length === 0 ? (
          <div style={{
            height: 80, display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: '#4a5568', fontSize: 11,
          }}>
            No events yet
          </div>
        ) : (
          reversed.map(entry => {
            const cfg = EVENT_CFG[entry.type]
            return (
              <div
                key={entry.id}
                style={{
                  display: 'flex', alignItems: 'baseline', gap: 6,
                  padding: '3px 0', borderBottom: '1px solid #161b22',
                }}
              >
                <span style={{ color: cfg.color, fontSize: 10, flexShrink: 0, lineHeight: 1.5 }}>●</span>
                <span style={{
                  color: '#c9d1d9', fontWeight: 600, flexShrink: 0,
                  maxWidth: 130, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                  fontSize: 12,
                }}>
                  {entry.agent}
                </span>
                <span style={{
                  color: entry.type === 'utterance' ? '#6a8a9e' : cfg.color,
                  fontStyle: entry.type === 'utterance' ? 'italic' : 'normal',
                  flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                  fontSize: 12,
                }}>
                  {cfg.label(entry)}
                </span>
                <span style={{
                  color: '#484f58', flexShrink: 0,
                  fontVariantNumeric: 'tabular-nums', fontSize: 10,
                  fontFamily: 'ui-monospace, monospace',
                }}>
                  {fmtTs(entry.ts)}
                </span>
              </div>
            )
          })
        )}
      </div>

      <Handle type="source" position={Position.Bottom} />
    </div>
  )
}
