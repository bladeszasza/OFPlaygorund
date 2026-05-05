// canvas/frontend/src/hooks/useSlugs.ts
import { useEffect, useState } from 'react'
import type { SlugEntry } from '../types'

export function useSlugs(): SlugEntry[] {
  const [slugs, setSlugs] = useState<SlugEntry[]>([])

  useEffect(() => {
    fetch('/agents/list')
      .then(r => r.json())
      .then((data: SlugEntry[]) => setSlugs(data))
      .catch(() => { /* server not up yet — silent fail */ })
  }, [])

  return slugs
}
