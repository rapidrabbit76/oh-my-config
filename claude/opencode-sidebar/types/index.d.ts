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

// One row of /context's breakdown; `color` is a theme key. `kind`: used content,
// free window, the autocompact reserve, or deferred tool schemas (outside the window).
export type ContextPart = { name: string; tokens: number; color: string; kind: 'used' | 'free' | 'buffer' | 'deferred' }

// What fills the window, as /context counts it locally (no request).
export type ContextDetail = {
  parts: ContextPart[]
  // The biggest memory files (CLAUDE.md and the like) and MCP servers, by tokens.
  memory: { name: string; tokens: number }[]
  mcp: { name: string; tokens: number }[]
  autoCompactAt?: number
}

export type Turn = { seconds: number; tools: number }

// One request to the model: its input split three ways, and how long it came
// after the one before (a long gap lets the cache expire).
export type CacheRequest = {
  hit: number
  read: number
  write: number
  uncached: number
  at?: number
  gapMs?: number
}

// Prompt cache, from the transcript's per-request usage (main session only).
export type Cache = {
  requests: number
  // Input tokens over the session: read from cache, written to it, sent uncached.
  read: number
  write: number
  uncached: number
  // The latest requests, oldest first.
  reqs: CacheRequest[]
  // Requests after the first that read under half their input from cache.
  rebuilds: number
  // Input billed as a share of list price (reads 0.1x, 5m writes 1.25x, 1h writes 2x).
  billed: number
  lastAt?: number
  // How long the cache lives: 1h when the newest write was a 1h write.
  ttlMs: number
}

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
      ctx: ContextDetail | null
      lastTurn: Turn | null
      cache: Cache | null
      // Alerts to Discord / ntfy through agent-notify, for this session.
      notify: boolean
      // Away: questions, approvals and prompts from Discord too (agent-notify's bridge).
      away: boolean
      // peon-ping's sounds on (not paused); null when peon-ping is not installed.
      sound: boolean | null
    }
  }
}
