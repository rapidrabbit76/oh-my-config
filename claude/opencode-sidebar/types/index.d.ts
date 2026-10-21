export type Info = {
  dir: string
  model: string
  turns: number
  startedAt?: number
  tokens?: number
  window: number
  percent?: number
  usd?: number
  limits: { kind: string; percentUsed: number; resetsAt?: string }[]
}

export type Todo = {
  id: string
  content: string
  status: 'pending' | 'in_progress' | 'completed'
}

export type Git = {
  branch: string
  // The linked worktree's folder name; undefined in the main working tree.
  worktree?: string
  ahead: number
  behind: number
  isDirty: boolean
}

export type Pr = {
  number: number
  state: 'open' | 'draft' | 'merged' | 'closed'
  ci?: 'pass' | 'fail' | 'pending'
}

export type Call = {
  id: string
  tool: string
  detail: string
  state: 'run' | 'ok' | 'fail'
}

export type Mcp = { name: string; isConnected: boolean }

// One used row of /context's breakdown; `color` is a theme key.
export type ContextPart = { name: string; tokens: number; color: string }

export type Turn = { seconds: number; tools: number }

declare module 'claude-code' {
  interface PluginState {
    'opencode-sidebar': {
      info: Info | null
      title: string
      todos: Todo[]
      git: Git | null
      pr: Pr | null
      calls: Call[]
      mcp: Mcp[]
      parts: ContextPart[]
      lastTurn: Turn | null
      // Alerts to Discord / ntfy through agent-notify, for this session.
      notify: boolean
    }
  }
}
