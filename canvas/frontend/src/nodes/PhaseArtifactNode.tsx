// canvas/frontend/src/nodes/PhaseArtifactNode.tsx
import { useState } from 'react'
import { Handle, Position } from '@xyflow/react'
import type { ArtifactNodeData } from '../types'

export function PhaseArtifactNode({ data }: { data: ArtifactNodeData }) {
  const [expanded, setExpanded] = useState(false)

  return (
    <div style={{
      background: 'linear-gradient(135deg, #0d1520 0%, #0d1117 100%)',
      border: '2px solid #58a6ff',
      borderRadius: 10, padding: '10px 12px',
      minWidth: 160, maxWidth: 220,
      color: '#e6edf5', fontFamily: 'ui-sans-serif, system-ui, sans-serif', fontSize: 11,
    }}>
      <Handle type="target" position={Position.Left} style={{ background: '#58a6ff' }} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 6 }}>
        <span style={{
          background: '#58a6ff22', color: '#90cdf4',
          border: '1px solid #58a6ff44', borderRadius: 4,
          padding: '1px 5px', fontSize: 9, fontWeight: 700,
        }}>PHASE</span>
        <span style={{ color: '#93a4b8', fontSize: 10, flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {data.label}
        </span>
        <span
          onClick={() => setExpanded(e => !e)}
          style={{ cursor: 'pointer', color: '#4a5568', fontSize: 10, flexShrink: 0 }}
        >
          {expanded ? '▾' : '▸'}
        </span>
      </div>
      {expanded && (
        <div style={{
          background: '#0d1520', borderRadius: 5, padding: '5px 7px',
          fontSize: 10, color: '#90cdf4', lineHeight: 1.5,
          maxHeight: 120, overflowY: 'auto',
        }}>
          {data.preview}
        </div>
      )}
    </div>
  )
}
