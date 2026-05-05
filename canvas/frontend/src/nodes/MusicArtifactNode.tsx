// canvas/frontend/src/nodes/MusicArtifactNode.tsx
import { Handle, Position } from '@xyflow/react'
import type { ArtifactNodeData } from '../types'

export function MusicArtifactNode({ data }: { data: ArtifactNodeData }) {
  return (
    <div style={{
      background: 'linear-gradient(135deg, #1a1005 0%, #0d1520 100%)',
      border: '2px solid #f97316',
      borderRadius: 10, padding: '10px 12px',
      minWidth: 160, maxWidth: 200,
      color: '#e6edf5', fontFamily: 'ui-sans-serif, system-ui, sans-serif', fontSize: 11,
    }}>
      <Handle type="target" position={Position.Left} style={{ background: '#f97316' }} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8 }}>
        <span style={{
          background: '#f9731622', color: '#fdba74',
          border: '1px solid #f9731644', borderRadius: 4,
          padding: '1px 5px', fontSize: 9, fontWeight: 700,
        }}>MUSIC</span>
        <span style={{ color: '#93a4b8', fontSize: 10, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {data.label}
        </span>
      </div>
      {data.url ? (
        <audio controls src={data.url} style={{ width: '100%', height: 30 }} />
      ) : (
        <div style={{
          background: '#0d1520', borderRadius: 5, padding: '8px',
          textAlign: 'center', color: '#f97316', fontSize: 20,
        }}>
          ♪
        </div>
      )}
    </div>
  )
}
