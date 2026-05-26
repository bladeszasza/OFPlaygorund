// canvas/frontend/src/nodes/ConversationChatNode.tsx
import { useRef, useEffect } from 'react'
import { Handle, Position } from '@xyflow/react'
import type { ConversationChatNodeData, Message } from '../types'

// ── Sender color palette ──────────────────────────────────────────────────────
const PALETTE = [
  '#58a6ff', '#38a169', '#d4a843', '#8b5cf6',
  '#00bcd4', '#f97316', '#ec4899', '#a3e635',
]
function senderColor(name: string): string {
  let h = 0
  for (const c of name) h = (h * 31 + c.charCodeAt(0)) >>> 0
  return PALETTE[h % PALETTE.length]
}

function fmtTs(ts: number) {
  const d = new Date(ts)
  return `${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}:${String(d.getSeconds()).padStart(2,'0')}`
}

// ── Media renderer — handles the full range of OFP media types ────────────────
function MediaBlock({ media }: { media: NonNullable<Message['media']> }) {
  const t = media.type.toLowerCase()
  const url = media.url

  if (t === 'image' || t.startsWith('image/')) {
    return (
      <img
        src={url} alt=""
        style={{
          maxWidth: '100%', maxHeight: 320, display: 'block',
          borderRadius: 6, marginTop: 6, border: '1px solid #2a3a4c',
          cursor: 'pointer',
        }}
        onClick={() => window.open(url, '_blank')}
        title="Click to open full size"
      />
    )
  }

  if (t === 'video' || t.startsWith('video/')) {
    return (
      <video
        src={url} controls
        style={{
          maxWidth: '100%', maxHeight: 280, display: 'block',
          borderRadius: 6, marginTop: 6, border: '1px solid #2a3a4c',
        }}
      />
    )
  }

  if (t === 'audio' || t === 'music' || t.startsWith('audio/')) {
    return (
      <div style={{ marginTop: 6 }}>
        <div style={{ fontSize: 10, color: '#6a8a9e', marginBottom: 3 }}>
          {t === 'music' ? '🎵 music' : '🔊 audio'}
        </div>
        <audio
          src={url} controls
          style={{ width: '100%', display: 'block', accentColor: '#58a6ff' }}
        />
      </div>
    )
  }

  if (t === 'html' || t === 'text/html') {
    return (
      <iframe
        src={url}
        style={{
          width: '100%', height: 260, border: 'none',
          borderRadius: 6, marginTop: 6, display: 'block', background: '#fff',
        }}
        sandbox="allow-scripts allow-same-origin"
        title="html-content"
      />
    )
  }

  // 3D / unknown — show a download link
  const filename = url.split('/').pop() ?? 'file'
  return (
    <a
      href={url} target="_blank" rel="noreferrer"
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 5, marginTop: 6,
        color: '#58a6ff', fontSize: 11, textDecoration: 'none',
        background: '#0d1f30', border: '1px solid #2a4060',
        borderRadius: 5, padding: '4px 8px',
      }}
    >
      ↓ {filename} <span style={{ color: '#4a6278' }}>({media.type})</span>
    </a>
  )
}

// ── Message bubble ────────────────────────────────────────────────────────────
function MessageBubble({ msg }: { msg: Message }) {
  const col = senderColor(msg.sender)
  return (
    <div style={{
      padding: '8px 10px',
      borderBottom: '1px solid #111922',
    }}>
      {/* Sender + time */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
        <span style={{
          color: col, fontWeight: 700, fontSize: 11,
          maxWidth: 120, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
        }}>
          {msg.sender}
        </span>
        <span style={{
          color: '#3a5068', fontSize: 10,
          fontFamily: 'ui-monospace, monospace',
          fontVariantNumeric: 'tabular-nums',
        }}>
          {fmtTs(msg.ts)}
        </span>
      </div>

      {/* Text */}
      {msg.text && (
        <div style={{
          color: '#c9d1d9', fontSize: 12, lineHeight: 1.55,
          whiteSpace: 'pre-wrap', wordBreak: 'break-word',
        }}>
          {msg.text}
        </div>
      )}

      {/* Media */}
      {msg.media && <MediaBlock media={msg.media} />}
    </div>
  )
}

// ── Node ──────────────────────────────────────────────────────────────────────
export function ConversationChatNode({ data }: { data: ConversationChatNodeData }) {
  const bottomRef = useRef<HTMLDivElement>(null)

  // Auto-scroll to newest message (bottom)
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [data.messages.length])

  return (
    <div style={{
      background: 'linear-gradient(135deg, #1a1f2e 0%, #0d1117 100%)',
      border: '2px solid #30363d',
      borderRadius: 10,
      padding: '12px 14px',
      width: 600,
      color: '#e6edf5',
      fontFamily: 'ui-sans-serif, system-ui, sans-serif',
      fontSize: 12,
      boxSizing: 'border-box',
    }}>
      <Handle type="target" position={Position.Top} />

      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
        <span style={{ fontSize: 15 }}>💬</span>
        <span style={{ fontWeight: 700, fontSize: 13 }}>Conversation</span>
        <span style={{ color: '#4a5568', fontSize: 11 }}>
          {data.messages.length} messages
        </span>
      </div>

      {/* Message list */}
      <div
        className="nodrag nowheel nopan"
        onWheel={e => e.stopPropagation()}
        style={{
          background: '#0d1117',
          border: '1px solid #21262d',
          borderRadius: 7,
          maxHeight: 520,
          overflowY: 'auto',
        }}
      >
        {data.messages.length === 0 ? (
          <div style={{
            height: 100, display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: '#4a5568', fontSize: 11,
          }}>
            No messages yet
          </div>
        ) : (
          <>
            {data.messages.map(msg => <MessageBubble key={msg.id} msg={msg} />)}
            <div ref={bottomRef} />
          </>
        )}
      </div>

      <Handle type="source" position={Position.Bottom} />
    </div>
  )
}
