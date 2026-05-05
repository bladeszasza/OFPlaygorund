// canvas/frontend/src/hooks/useModels.ts
import { useEffect, useState } from 'react'

export function useModels(): Record<string, string[]> {
  const [models, setModels] = useState<Record<string, string[]>>({
    anthropic: [], openai: [], google: [], huggingface: [],
  })

  useEffect(() => {
    fetch('/models/list')
      .then(r => r.json())
      .then((data: Record<string, string[]>) => setModels(data))
      .catch(() => { /* silent fail */ })
  }, [])

  return models
}
