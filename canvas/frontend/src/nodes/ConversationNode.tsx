// canvas/frontend/src/nodes/ConversationNode.tsx
import { useState, useRef, useEffect } from 'react'
import { Handle, Position } from '@xyflow/react'
import type { ConversationNodeData, FloorEventEntry } from '../types'

interface ConversationNodeProps {
  data: ConversationNodeData
}

type Tab = 'timeline' | 'events'

function formatTs(ts: number): string {
  const d = new Date(ts)
  const hh = String(d.getHours()).padStart(2, '0')
  const mm = String(d.getMinutes()).padStart(2, '0')
  const ss = String(d.getSeconds()).padStart(2, '0')
  return `${hh}:${mm}:${ss}`
}

const EVENT_CONFIG: Record<
  FloorEventEntry['type'],
  { color: string; label: (e: FloorEventEntry) => string }
> = {
  floor_grant:       { color: '#38a169', label: () => 'got the floor' },
  floor_revoke:      { color: '#4a5568', label: () => 'lost the floor' },
  floor_yield:       { color: '#00bcd4', label: () => 'yielded the floor' },
  floor_request:     { color: '#d4a843', label: () => 'requested the floor' },
  utterance:         { color: '#58a6ff', label: (e) => e.preview?.slice(0, 70) ?? '' },
  manifest_published:{ color: '#8b5cf6', label: () => 'published manifest' },
}

export function ConversationNode({ data }: ConversationNodeProps) {
  const [tab, setTab] = useState<Tab>('timeline')
  const eventsRef = useRef<HTMLDivElement>(null)

  const liveUrl = data.sessionId
    ? `/trace/live?session=${data.sessionId}`
    : null

  const openTrace = () => {
    if (liveUrl) window.open(liveUrl, '_blank')
  }

  // Auto-scroll events list to top when new entries arrive
  useEffect(() => {
    if (eventsRef.current) {
      eventsRef.current.scrollTop = 0
    }
  }, [data.eventLog.length])

  const reversed = [...data.eventLog].reverse()

  return (
    <div style={{
      background: 'linear-gradient(135deg, #1a1f2e 0%, #0d1117 100%)',
      border: '2px solid #30363d',
      borderRadius: 10,
      padding: '12px 14px',
      minWidth: 420,
      color: '#e6edf5',
      fontFamily: 'ui-sans-serif, system-ui, sans-serif',
      fontSize: 12,
    }}>
      <Handle type="target" position={Position.Top} />

      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
        <span style={{ fontSize: 15 }}>📊</span>
        <span style={{ fontWeight: 700, fontSize: 13 }}>Conversation Trace</span>
        {liveUrl && (
          <button
            className="nodrag"
            onClick={openTrace}
            title="Open in new tab"
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

      {/* Meta */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4, marginBottom: 12 }}>
        {data.policy && (
          <div style={{ color: '#93a4b8', fontSize: 11 }}>
            Policy: <span style={{ color: '#c9d1d9' }}>{data.policy}</span>
          </div>
        )}
        {data.topic && (
          <div style={{ color: '#93a4b8', fontSize: 11 }}>
            Topic:{' '}
            <span style={{ color: '#c9d1d9' }}>
              {data.topic.slice(0, 60)}{data.topic.length > 60 ? '…' : ''}
            </span>
          </div>
        )}
        <div style={{ color: '#93a4b8', fontSize: 11 }}>
          Turns: <span style={{ color: '#58a6ff', fontWeight: 600 }}>{data.turnCount}</span>
        </div>
      </div>

      {/* Tabs */}
      <div
        className="nodrag"
        style={{
          display: 'flex',
          background: '#0d1117',
          borderRadius: '6px 6px 0 0',
          border: '1px solid #21262d',
          borderBottom: 'none',
          marginBottom: 0,
        }}
      >
        {(['timeline', 'events'] as Tab[]).map((t) => (
          <button
            key={t}
            className="nodrag"
            onClick={() => setTab(t)}
            style={{
              flex: 1,
              padding: '6px 0',
              background: 'transparent',
              border: 'none',
              borderBottom: tab === t ? '2px solid #58a6ff' : '2px solid transparent',
              color: tab === t ? '#58a6ff' : '#6e7681',
              fontWeight: tab === t ? 600 : 400,
              fontSize: 11,
              cursor: 'pointer',
              textTransform: 'capitalize',
              letterSpacing: '0.02em',
              transition: 'color 0.15s',
            }}
          >
            {t === 'timeline' ? 'Timeline' : 'Events'}
          </button>
        ))}
      </div>

      {/* Tab content */}
      <div style={{
        background: '#0d1117',
        border: '1px solid #21262d',
        borderTop: 'none',
        borderRadius: '0 0 6px 6px',
      }}>
        {/* Timeline tab */}
        {tab === 'timeline' && (
          <div style={{ height: 280 }}>
            {liveUrl ? (
              <iframe
                src={liveUrl}
                style={{
                  width: '100%', height: '100%', border: 'none',
                  borderRadius: '0 0 6px 6px', background: '#0d1117',
                  display: 'block',
                }}
                title="Live trace"
              />
            ) : (
              <div style={{
                height: '100%', display: 'flex', alignItems: 'center',
                justifyContent: 'center', color: '#4a5568', fontSize: 11,
                border: '1px dashed #2a3a4c', borderRadius: '0 0 6px 6px',
                margin: 1,
              }}>
                Run a session to see the live trace
              </div>
            )}
          </div>
        )}

        {/* Events tab */}
        {tab === 'events' && (
          <div
            ref={eventsRef}
            className="nodrag"
            style={{
              maxHeight: 280,
              overflowY: 'auto',
              padding: '6px 8px',
            }}
          >
            {reversed.length === 0 ? (
              <div style={{
                height: 260, display: 'flex', alignItems: 'center',
                justifyContent: 'center', color: '#4a5568', fontSize: 11,
              }}>
                No events yet
              </div>
            ) : (
              reversed.map((entry) => {
                const cfg = EVENT_CONFIG[entry.type]
                const isUtterance = entry.type === 'utterance'
                return (
                  <div
                    key={entry.id}
                    style={{
                      display: 'flex',
                      alignItems: 'baseline',
                      gap: 6,
                      padding: '3px 0',
                      borderBottom: '1px solid #161b22',
                      fontSize: 11,
                    }}
                  >
                    {/* Dot */}
                    <span style={{
                      color: cfg.color,
                      fontSize: 10,
                      flexShrink: 0,
                      lineHeight: 1.5,
                    }}>●</span>

                    {/* Agent name */}
                    <span style={{
                      color: '#c9d1d9',
                      fontWeight: 600,
                      flexShrink: 0,
                      maxWidth: 90,
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      whiteSpace: 'nowrap',
                    }}>
                      {entry.agent}
                    </span>

                    {/* Description */}
                    <span style={{
                      color: isUtterance ? '#93a4b8' : cfg.color,
                      fontStyle: isUtterance ? 'italic' : 'normal',
                      flex: 1,
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      whiteSpace: 'nowrap',
                    }}>
                      {cfg.label(entry)}
                    </span>

                    {/* Timestamp */}
                    <span style={{
                      color: '#484f58',
                      flexShrink: 0,
                      fontVariantNumeric: 'tabular-nums',
                      fontSize: 10,
                    }}>
                      {formatTs(entry.ts)}
                    </span>
                  </div>
                )
              })
            )}
          </div>
        )}
      </div>
    </div>
  )
}
