// canvas/frontend/src/nodes/EventInspectorNode.tsx
import { Handle, Position } from '@xyflow/react'
import type { EventInspectorNodeData } from '../types'

// ── JSON syntax highlighter ───────────────────────────────────────────────────
function highlightJson(str: string): string {
  return str
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(
      /("(\\u[a-zA-Z0-9]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?)/g,
      (match) => {
        let cls = 'json-num'
        if (/^"/.test(match)) {
          cls = /:$/.test(match) ? 'json-key' : 'json-str'
        } else if (/true|false/.test(match)) {
          cls = 'json-bool'
        } else if (/null/.test(match)) {
          cls = 'json-null'
        }
        return `<span class="${cls}">${match}</span>`
      },
    )
}

const TYPE_COLORS: Record<string, string> = {
  floor_grant:        '#38a169',
  floor_revoke:       '#e53e3e',
  floor_yield:        '#00bcd4',
  floor_request:      '#d4a843',
  utterance:          '#58a6ff',
  manifest_published: '#8b5cf6',
}

function fmtTs(ts: number) {
  return new Date(ts).toLocaleTimeString('en-GB', { hour12: false })
}

export function EventInspectorNode({ data }: { data: EventInspectorNodeData }) {
  const { event } = data

  const typeColor = event ? (TYPE_COLORS[event.type] ?? '#8a99ac') : '#4a5568'

  // Always show the full OFP envelope JSON stored in raw
  const jsonStr = event?.raw ? JSON.stringify(event.raw, null, 2) : null

  return (
    <div style={{
      background: 'linear-gradient(135deg, #1a1f2e 0%, #0d1117 100%)',
      border: `2px solid ${event ? typeColor + '66' : '#30363d'}`,
      borderRadius: 10,
      padding: '12px 14px',
      width: 380,
      color: '#e6edf5',
      fontFamily: 'ui-sans-serif, system-ui, sans-serif',
      fontSize: 12,
      boxSizing: 'border-box',
    }}>
      <Handle type="target" position={Position.Top} />

      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
        <span style={{ fontSize: 15 }}>🔍</span>
        <span style={{ fontWeight: 700, fontSize: 13 }}>Event Inspector</span>
        {event && (
          <span style={{
            marginLeft: 'auto', fontSize: 10, fontWeight: 700,
            color: typeColor,
            background: typeColor + '22',
            border: `1px solid ${typeColor}44`,
            borderRadius: 4, padding: '2px 7px',
            textTransform: 'uppercase', letterSpacing: '0.06em',
          }}>
            {event.type.replace('_', ' ')}
          </span>
        )}
      </div>

      {!event ? (
        <div style={{
          height: 120, display: 'flex', flexDirection: 'column',
          alignItems: 'center', justifyContent: 'center', gap: 8,
          color: '#4a5568', fontSize: 11,
          border: '1px dashed #21262d', borderRadius: 7,
        }}>
          <span style={{ fontSize: 20 }}>●</span>
          Click a dot on the Timeline to inspect its OFP envelope
        </div>
      ) : (
        <>
          {/* Summary strip */}
          <div style={{
            display: 'flex', gap: 8, marginBottom: 10, flexWrap: 'wrap',
          }}>
            <span style={{
              background: '#0d1520', border: '1px solid #2a3a4c',
              borderRadius: 5, padding: '3px 8px', fontSize: 11,
              color: '#c9d1d9', fontWeight: 600,
            }}>
              {event.agent}
            </span>
            {event.to && event.to !== event.agent && (
              <>
                <span style={{ color: '#4a5568', alignSelf: 'center' }}>→</span>
                <span style={{
                  background: '#0d1520', border: '1px solid #2a3a4c',
                  borderRadius: 5, padding: '3px 8px', fontSize: 11, color: '#c9d1d9',
                }}>
                  {event.to}
                </span>
              </>
            )}
            <span style={{
              marginLeft: 'auto', color: '#4a5568', fontSize: 10,
              fontFamily: 'ui-monospace, monospace', alignSelf: 'center',
            }}>
              {fmtTs(event.ts)}
            </span>
          </div>

          {/* Preview for utterances */}
          {event.preview && (
            <div style={{
              background: '#0d1520', border: '1px solid #1a2a3a',
              borderRadius: 6, padding: '6px 9px', marginBottom: 10,
              color: '#93a4b8', fontSize: 11, fontStyle: 'italic',
              lineHeight: 1.5,
            }}>
              {event.preview}
            </div>
          )}

          {/* JSON envelope */}
          <style>{`
            .json-key  { color: #79c0ff; }
            .json-str  { color: #a5d6ff; }
            .json-num  { color: #f2cc60; }
            .json-bool { color: #ff7b72; }
            .json-null { color: #8b949e; }
          `}</style>
          <div
            className="nodrag nowheel nopan"
            onWheel={e => e.stopPropagation()}
            style={{
              background: '#080e15',
              border: '1px solid #1a2a3a',
              borderRadius: 7,
              maxHeight: 360,
              overflowY: 'auto',
            }}
          >
            <pre
              style={{
                margin: 0,
                padding: '10px 12px',
                fontSize: 11,
                lineHeight: 1.55,
                fontFamily: "ui-monospace, 'Cascadia Code', 'Fira Code', monospace",
                whiteSpace: 'pre-wrap',
                wordBreak: 'break-word',
              }}
              // eslint-disable-next-line react/no-danger
              dangerouslySetInnerHTML={{ __html: jsonStr ? highlightJson(jsonStr) : '' }}
            />
          </div>
        </>
      )}

      <Handle type="source" position={Position.Bottom} />
    </div>
  )
}
