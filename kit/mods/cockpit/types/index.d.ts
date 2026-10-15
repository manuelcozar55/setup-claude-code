export type Eat = { name: string; tokens: number }

export type Ctx = {
  tokens: number
  limit: number
  usd?: number
  rate5h?: number
  rate7d?: number
  eating: Eat[]
}

export type Cache = { lastAt: number; ttlMs: number; isTtlKnown: boolean; cold: number; turns: number }

export type AgentRow = {
  id: string
  description: string
  type: string
  status: string
  startedAt: number
  lastActiveAt: number
  endedAt?: number
  activity: string
}

export type TaskRow = { id: string; subject: string; status: 'pending' | 'in_progress' | 'completed'; activeForm?: string }

export type Handoff = { phase: 'idle' | 'confirm' | 'working' | 'done' | 'error'; msg?: string }

export type Turn = { isRunning: boolean; startedAt: number; activity: string; mission: string }

declare module 'claude-code' {
  interface PluginState {
    cockpit: {
      isSimple: boolean
      team: number
      ctx: Ctx | null
      cache: Cache
      warned: number
      agents: AgentRow[]
      tasks: TaskRow[]
      summary: string
      handoff: Handoff
      turn: Turn
      now: number
      isMissionOpen: boolean
    }
  }
}
