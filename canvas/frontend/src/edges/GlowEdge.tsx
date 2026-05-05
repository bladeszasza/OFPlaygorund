// canvas/frontend/src/edges/GlowEdge.tsx
import { getBezierPath } from '@xyflow/react'
import type { EdgeProps } from '@xyflow/react'
import type { GlowEdgeData } from '../types'

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
  const pulse = edgeData?.pulse ?? null

  const PULSE_COLOR: Record<string, string> = {
    amber: '#d4a843',
    teal: '#00bcd4',
    purple: '#8b5cf6',
  }
  const pulseColor = pulse ? PULSE_COLOR[pulse] : null

  return (
    <>
      <style>{`
        @keyframes dashTravel {
          from { stroke-dashoffset: 300; }
          to   { stroke-dashoffset: 0;   }
        }
        @keyframes edgeBlinkAmber {
          0%, 100% { opacity: 1; }
          50%      { opacity: 0.2; }
        }
        @keyframes edgeFlash {
          from { opacity: 1; }
          to   { opacity: 0; }
        }
      `}</style>

      {/* Base path */}
      <path
        id={id as string | undefined}
        className="react-flow__edge-path"
        d={edgePath}
        style={{
          stroke: pulseColor ?? color,
          strokeWidth: active ? 2.5 : 1.5,
          strokeDasharray: dashed ? '5 4' : undefined,
          fill: 'none',
        }}
      />

      {/* Active glow overlay (floor grant) */}
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

      {/* Pulse: amber (requestFloor) — dashed blink */}
      {pulse === 'amber' && (
        <path
          d={edgePath}
          style={{
            stroke: '#d4a843',
            strokeWidth: 2,
            strokeDasharray: '6 5',
            fill: 'none',
            filter: 'drop-shadow(0 0 4px #d4a843)',
            animation: 'edgeBlinkAmber 0.9s ease-in-out infinite',
            pointerEvents: 'none',
          }}
        />
      )}

      {/* Pulse: teal (yieldFloor) or purple (manifest) — solid flash fading out */}
      {(pulse === 'teal' || pulse === 'purple') && pulseColor && (
        <path
          d={edgePath}
          style={{
            stroke: pulseColor,
            strokeWidth: 3,
            fill: 'none',
            filter: `drop-shadow(0 0 6px ${pulseColor})`,
            animation: 'edgeFlash 1.5s ease-out forwards',
            pointerEvents: 'none',
          }}
        />
      )}
    </>
  )
}
