// canvas/frontend/src/edges/GlowEdge.tsx
import { getBezierPath } from '@xyflow/react'
import type { EdgeProps } from '@xyflow/react'
import type { GlowEdgeData } from '../types'

// Use default Edge type — avoids the Record<string,unknown> constraint issue
export function GlowEdge({
  id,
  sourceX, sourceY, targetX, targetY,
  sourcePosition, targetPosition,
  data,
}: EdgeProps) {
  const edgeData = (data as unknown) as GlowEdgeData
  const [edgePath] = getBezierPath({ sourceX, sourceY, sourcePosition, targetX, targetY, targetPosition })
  const color = edgeData?.color ?? '#2a3a4c'
  const active = edgeData?.active ?? false
  const dashed = edgeData?.dashed ?? false

  return (
    <>
      <style>{`
        @keyframes dashTravel {
          from { stroke-dashoffset: 300; }
          to   { stroke-dashoffset: 0;   }
        }
      `}</style>

      {/* Base path */}
      <path
        id={id as string | undefined}
        className="react-flow__edge-path"
        d={edgePath}
        style={{
          stroke: color,
          strokeWidth: active ? 2.5 : 1.5,
          strokeDasharray: dashed ? '5 4' : undefined,
          fill: 'none',
        }}
      />

      {/* Animated glow overlay — only when active */}
      {active && (
        <path
          d={edgePath}
          style={{
            stroke: color,
            strokeWidth: 3,
            strokeDasharray: '10 8',
            fill: 'none',
            filter: `drop-shadow(0 0 5px ${color})`,
            animation: 'dashTravel 1.0s linear infinite',
            pointerEvents: 'none',
          }}
        />
      )}
    </>
  )
}
