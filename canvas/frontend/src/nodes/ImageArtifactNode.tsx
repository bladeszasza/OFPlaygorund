// canvas/frontend/src/nodes/ImageArtifactNode.tsx
import { useState } from 'react'
import { Handle, Position } from '@xyflow/react'
import type { ArtifactNodeData } from '../types'

export function ImageArtifactNode({ data }: { data: ArtifactNodeData }) {
  const [lightbox, setLightbox] = useState(false)

  return (
    <div style={{
      background: 'linear-gradient(135deg, #1a1230 0%, #0d1520 100%)',
      border: '2px solid #8b5cf6',
      borderRadius: 10, padding: '10px 12px',
      minWidth: 160, maxWidth: 200,
      color: '#e6edf5', fontFamily: 'ui-sans-serif, system-ui, sans-serif', fontSize: 11,
    }}>
      <Handle type="target" position={Position.Left} style={{ background: '#8b5cf6' }} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8 }}>
        <span style={{
          background: '#8b5cf622', color: '#c4b5fd',
          border: '1px solid #8b5cf644', borderRadius: 4,
          padding: '1px 5px', fontSize: 9, fontWeight: 700,
        }}>IMAGE</span>
        <span style={{ color: '#93a4b8', fontSize: 10, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {data.label}
        </span>
      </div>
      {data.url && (
        <img
          src={data.url}
          alt={data.label}
          onClick={() => setLightbox(true)}
          style={{ width: '100%', borderRadius: 5, cursor: 'pointer', display: 'block' }}
        />
      )}
      {lightbox && (
        <dialog
          open
          onClick={() => setLightbox(false)}
          style={{
            position: 'fixed', inset: 0, margin: 0,
            width: '100vw', height: '100vh',
            background: '#000000cc', border: 'none', zIndex: 9999,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}
        >
          <img
            src={data.url}
            alt={data.label}
            style={{ maxWidth: '90vw', maxHeight: '90vh', borderRadius: 8 }}
          />
        </dialog>
      )}
    </div>
  )
}
