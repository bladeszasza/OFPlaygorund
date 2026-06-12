// canvas/frontend/src/hooks/useSession.ts
import { useEffect, useRef, useCallback, useState } from 'react'
import type { WSEvent } from '../types'

export interface UseSessionOptions {
  sessionId: string | null
  onEvent: (event: WSEvent) => void
}

export function useSession({ sessionId, onEvent }: UseSessionOptions) {
  const wsRef = useRef<WebSocket | null>(null)
  const onEventRef = useRef(onEvent)
  const [connected, setConnected] = useState(false)
  const reconnectTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Keep onEvent ref fresh so the WS handler always calls the latest version
  useEffect(() => {
    onEventRef.current = onEvent
  }, [onEvent])

  const connect = useCallback((id: string) => {
    if (wsRef.current) {
      wsRef.current.onclose = null
      wsRef.current.close()
    }

    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:'
    const ws = new WebSocket(`${protocol}//${location.host}/ws/${id}`)
    wsRef.current = ws

    ws.onopen = () => setConnected(true)

    ws.onmessage = (evt) => {
      try {
        const data = JSON.parse(evt.data) as WSEvent
        onEventRef.current(data)
      } catch {
        // ignore malformed frames
      }
    }

    ws.onerror = () => setConnected(false)

    ws.onclose = () => {
      setConnected(false)
      // Reconnect after 2 s unless sessionId is gone
      reconnectTimer.current = setTimeout(() => {
        if (wsRef.current === ws && sessionId) {
          connect(id)
        }
      }, 2000)
    }
  }, [sessionId])

  useEffect(() => {
    if (sessionId) {
      connect(sessionId)
    }
    return () => {
      if (reconnectTimer.current) clearTimeout(reconnectTimer.current)
      if (wsRef.current) {
        wsRef.current.onclose = null
        wsRef.current.close()
        wsRef.current = null
      }
      setConnected(false)
    }
  }, [sessionId, connect])

  const sendMessage = useCallback(async (text: string) => {
    await fetch('/session/message', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text }),
    })
  }, [])

  const kickAgent = useCallback(async (name: string) => {
    await fetch(`/session/agent/${encodeURIComponent(name)}`, { method: 'DELETE' })
  }, [])

  return { connected, sendMessage, kickAgent }
}
