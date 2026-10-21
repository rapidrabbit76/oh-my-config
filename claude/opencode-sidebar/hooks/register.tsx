import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Call, ContextPart, Git, Info, Mcp, Pr, Todo, Turn } from '../types'

const PANE = 'opencode-sidebar'
const TITLE = 'Session'
const info = atom({ plugin: 'opencode-sidebar', key: 'info' } as const, null)
const title = atom({ plugin: 'opencode-sidebar', key: 'title' } as const, '')
const todos = atom({ plugin: 'opencode-sidebar', key: 'todos' } as const, [])
const git = atom({ plugin: 'opencode-sidebar', key: 'git' } as const, null)
const pr = atom({ plugin: 'opencode-sidebar', key: 'pr' } as const, null)
const calls = atom({ plugin: 'opencode-sidebar', key: 'calls' } as const, [])
const mcp = atom({ plugin: 'opencode-sidebar', key: 'mcp' } as const, [])
const parts = atom({ plugin: 'opencode-sidebar', key: 'parts' } as const, [])
const lastTurn = atom({ plugin: 'opencode-sidebar', key: 'lastTurn' } as const, null)
const notify = atom({ plugin: 'opencode-sidebar', key: 'notify' } as const, false)

const TICK_MS = 15_000
// The PR is fetched over the network, so on every fourth tick only.
const PR_EVERY_TICKS = 4
const RECENT_CALLS = 5
const CONTEXT_PARTS = 5
const CONTEXT_WARN = 80
// How long a permission prompt or a question waits before it counts as
// "waiting for you" and is sent.
const WAIT_MS = 30_000
const ANSWER_MAX = 2000

const kilo = (n: number) => (n >= 1000 ? `${Math.round(n / 1000)}k` : `${n}`)

const basename = (path: string) => path.split('/').filter(Boolean).pop() ?? path

const duration = (ms: number) => {
  const m = Math.max(0, Math.round(ms / 60000))
  if (m < 60) return `${m}m`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h${m % 60 ? `${m % 60}m` : ''}`
  return `${Math.floor(h / 24)}d${h % 24 ? `${h % 24}h` : ''}`
}

const LIMIT_LABEL: Record<string, string> = { five_hour: '5h', seven_day: '7d' }

// opencode-style ctrl+x leader keys. keybindings.json can only bind engine
// actions, so each chord is bound to an action nothing handles at the prompt,
// and a band Button claiming that action runs the slash command.
const LEADER = [
  { key: 'l', label: 'sessions', command: 'resume', action: 'app:cycleDiffBase' },
  { key: 'n', label: 'new', command: 'clear', action: 'app:toggleDiffNoiseFilter' },
  { key: 't', label: 'theme', command: 'theme', action: 'app:toggleDiffPreSession' },
] as const

let tick: { cancel: () => void } | undefined
let ticks = 0
let hasWarnedContext = false
let configuredMcp: string[] = []
let turnStartedAt = 0
let turnTools = 0
let waitTimer: { cancel: () => void } | undefined

// Each figure on its own, so one the engine cannot answer (usage before the
// first response, say) leaves the rest drawn instead of "Loading…" forever.
async function refresh($: EngineInterface) {
  const [cwd, model, turns, usage] = await Promise.all([
    $.session.cwd().catch(() => ''),
    $.session.model().catch(() => ''),
    $.session.turns().catch(() => 0),
    $.session.usage().catch(() => undefined),
  ])
  const next: Info = {
    dir: basename(cwd),
    model: model.replace(/^claude-/, ''),
    turns,
    startedAt: usage?.startedAt,
    tokens: usage?.context.tokens,
    window: usage?.context.window ?? 0,
    percent: usage?.context.percent,
    usd: usage?.cost?.usd,
    limits: (usage?.rateLimits ?? []).map(l => ({
      kind: l.kind,
      percentUsed: l.percentUsed,
      resetsAt: l.resetsAt,
    })),
  }
  await update($, info, () => next)

  const percent = next.percent ?? 0
  if (percent >= CONTEXT_WARN && !hasWarnedContext) {
    hasWarnedContext = true
    $.ui.toast(`Context ${percent}% full: consider /compact`)
  } else if (percent < CONTEXT_WARN) {
    hasWarnedContext = false
  }
}

// What fills the window, as /context's rows estimate it locally (no request).
async function refreshParts($: EngineInterface) {
  const usage = await $.session.usage({ breakdown: 'summary' })
  const rows = usage.context.breakdown?.categories ?? []
  const next: ContextPart[] = rows
    .filter(r => r.kind === 'used' && r.tokens > 0)
    .sort((a, b) => b.tokens - a.tokens)
    .slice(0, CONTEXT_PARTS)
    .map(r => ({ name: r.name, tokens: r.tokens, color: r.color }))
  await update($, parts, () => next)
}

// The /rename title, else the one the engine generated, from the transcript.
const SESSION_TITLE = `
f=$(/bin/ls "\${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$1".jsonl 2>/dev/null | head -1)
[ -n "$f" ] || exit 0
t=$(grep -o '"customTitle":"[^"]*"' "$f" | tail -1 | cut -d'"' -f4)
[ -z "$t" ] && t=$(grep -o '"aiTitle":"[^"]*"' "$f" | tail -1 | cut -d'"' -f4)
printf '%s' "$t"
`

async function refreshTitle($: EngineInterface) {
  const id = await $.session.id()
  const ran = await $.process.run(['/bin/sh', '-c', SESSION_TITLE, 'sh', id], { timeoutMs: 5000 })
  const next = ran.stdout.trim()
  await update($, title, () => next)
}

const gitRun = async ($: EngineInterface, args: string[]) => {
  const ran = await $.process.run(['git', '--no-optional-locks', ...args], { timeoutMs: 5000 })
  return ran.exitCode === 0 ? ran.stdout : undefined
}

async function refreshGit($: EngineInterface) {
  const [status, dirs] = await Promise.all([
    gitRun($, ['status', '--porcelain=v2', '--branch']),
    gitRun($, ['rev-parse', '--path-format=absolute', '--show-toplevel', '--git-dir', '--git-common-dir']),
  ])
  if (status === undefined) {
    await update($, git, () => null)
    return
  }

  let branch = ''
  let ahead = 0
  let behind = 0
  let isDirty = false
  for (const line of status.split('\n')) {
    const words = line.split(' ')
    if (line.startsWith('# branch.head ')) branch = words[2] ?? ''
    else if (line.startsWith('# branch.ab ')) {
      ahead = Number(words[2]?.slice(1) ?? 0)
      behind = Number(words[3]?.slice(1) ?? 0)
    } else if (line !== '' && !line.startsWith('#')) isDirty = true
  }

  // A linked worktree keeps its own git dir under the main one's common dir.
  const [top = '', gitDir, commonDir] = (dirs ?? '').trim().split('\n')
  const isLinked = gitDir !== undefined && commonDir !== undefined && gitDir !== commonDir

  const next: Git = {
    branch: branch === '(detached)' ? 'detached HEAD' : branch,
    worktree: isLinked ? basename(top) : undefined,
    ahead,
    behind,
    isDirty,
  }
  await update($, git, () => next)
}

type Check = { conclusion?: string; state?: string; status?: string }

const FAILED = ['FAILURE', 'ERROR', 'TIMED_OUT', 'CANCELLED', 'ACTION_REQUIRED', 'STARTUP_FAILURE']
const PASSED = ['SUCCESS', 'NEUTRAL', 'SKIPPED']

// A check run reports `conclusion` once done and `status` before; a commit
// status reports `state`.
const ciOf = (checks: Check[]): Pr['ci'] => {
  if (checks.length === 0) return undefined
  let isPending = false
  for (const c of checks) {
    const v = (c.conclusion || c.state || c.status || '').toUpperCase()
    if (FAILED.includes(v)) return 'fail'
    if (!PASSED.includes(v)) isPending = true
  }
  return isPending ? 'pending' : 'pass'
}

// The current branch's PR, through gh; none when gh is missing or logged out.
async function refreshPr($: EngineInterface) {
  const ran = await $.process.run(
    ['gh', 'pr', 'view', '--json', 'number,state,isDraft,statusCheckRollup'],
    { timeoutMs: 10_000 },
  )
  if (ran.exitCode !== 0) {
    await update($, pr, () => null)
    return
  }
  const view = JSON.parse(ran.stdout) as {
    number: number
    state: 'OPEN' | 'MERGED' | 'CLOSED'
    isDraft: boolean
    statusCheckRollup?: Check[]
  }
  const next: Pr = {
    number: view.number,
    state:
      view.state === 'MERGED'
        ? 'merged'
        : view.state === 'CLOSED'
          ? 'closed'
          : view.isDraft
            ? 'draft'
            : 'open',
    ci: ciOf(view.statusCheckRollup ?? []),
  }
  await update($, pr, () => next)
}

// agent-notify (oh-my-config/notify) sends in the background and returns at
// once, so a channel that is down or slow never holds up the session; when it
// is missing or fails, nothing happens here.
const AGENT_NOTIFY = 'n="$HOME/.local/bin/agent-notify"; [ -x "$n" ] || exit 3; exec "$n" "$@"'

const agentNotify = async ($: EngineInterface, args: string[]) => {
  try {
    const ran = await $.process.run(['/bin/sh', '-c', AGENT_NOTIFY, 'sh', ...args], { timeoutMs: 5000 })
    return ran.exitCode
  } catch {
    return -1
  }
}

const isNotifying = ($: EngineInterface) => read($, notify).catch(() => false)

const whereOf = async ($: EngineInterface) => {
  const [now, repo] = await Promise.all([read($, info), read($, git)])
  return [now?.dir, repo?.branch].filter(Boolean).join(' · ')
}

async function sendAlert($: EngineInterface, kind: 'done' | 'wait' | 'error', title: string, body: string, meta: string) {
  if (!(await isNotifying($))) return
  await agentNotify($, ['send', 'claude', kind, title, body.slice(0, ANSWER_MAX), meta])
}

const cancelWait = () => {
  waitTimer?.cancel()
  waitTimer = undefined
}

// Sent only if nothing moves for WAIT_MS: an answer ends the tool call, a
// running tool draws progress, and a new prompt or the turn's end cancels it.
function armWait($: EngineInterface, body: string) {
  cancelWait()
  waitTimer = $.clock.after(WAIT_MS, () => {
    waitTimer = undefined
    void (async () => {
      const [name, where] = await Promise.all([read($, title).catch(() => ''), whereOf($).catch(() => '')])
      await sendAlert($, 'wait', `Waiting for you${name ? ` · ${name}` : ''}`, body, where)
    })().catch(() => undefined)
  })
}

async function toggleNotify($: EngineInterface) {
  const on = !(await isNotifying($))
  await update($, notify, () => on)
  if (!on) {
    cancelWait()
    $.ui.toast('Alerts off for this session')
    return
  }
  const status = await agentNotify($, ['status'])
  if (status === 3) $.ui.toast('Alerts on, but agent-notify is not installed (oh-my-config claude/install.sh)')
  else if (status !== 0) $.ui.toast('Alerts on, but no channel is set: run `agent-notify setup` in a shell')
  else $.ui.toast('Alerts on: Discord / ntfy when a turn ends or waits for you')
}

const serverKey = (name: string) => name.replace(/[^a-zA-Z0-9]/g, '_')

// The servers in ~/.claude.json (user and this project's) and ./.mcp.json.
async function loadConfiguredMcp($: EngineInterface) {
  const names = new Set<string>()
  const cwd = await $.session.cwd()
  const home = await $.process.run(['/bin/sh', '-c', 'cat "$HOME/.claude.json"'])
  try {
    const config = JSON.parse(home.stdout) as {
      mcpServers?: Record<string, unknown>
      projects?: Record<string, { mcpServers?: Record<string, unknown> }>
    }
    Object.keys(config.mcpServers ?? {}).forEach(n => names.add(n))
    Object.keys(config.projects?.[cwd]?.mcpServers ?? {}).forEach(n => names.add(n))
  } catch {}
  if (await $.fs.exists('.mcp.json')) {
    try {
      const project = JSON.parse(await $.fs.read('.mcp.json')) as {
        mcpServers?: Record<string, unknown>
      }
      Object.keys(project.mcpServers ?? {}).forEach(n => names.add(n))
    } catch {}
  }
  configuredMcp = [...names].sort()
}

// A server counts as connected while the model has any of its tools.
async function refreshMcp($: EngineInterface) {
  const tools = await $.tool.list()
  const live = new Set(
    tools.filter(t => t.mcp && t.name.startsWith('mcp__')).map(t => t.name.slice(5).split('__')[0]),
  )
  const next: Mcp[] = configuredMcp.map(name => ({
    name,
    isConnected: live.has(serverKey(name)),
  }))
  await update($, mcp, () => next)
}

async function alertTurn($: EngineInterface, reason: string, answer: string, ms: number) {
  const [name, where] = await Promise.all([read($, title), whereOf($)])
  const kind = reason === 'error' || reason === 'refusal' ? 'error' : 'done'
  const head = kind === 'error' ? 'Turn failed' : 'Done'
  const seconds = Math.round(ms / 1000)
  const took = seconds < 60 ? `${seconds}s` : duration(ms)
  await sendAlert($, kind, name ? `${head} · ${name}` : head, answer, `${where} · ${took}`)
}

async function refreshAll($: EngineInterface) {
  await Promise.all([
    refresh($).catch(() => undefined),
    refreshGit($).catch(() => undefined),
    refreshMcp($).catch(() => undefined),
  ])
}

// What a recent-calls row says after the tool's name.
const detailOf = (input: Record<string, unknown>) => {
  const pick = (k: string) => (typeof input[k] === 'string' ? (input[k] as string) : undefined)
  const command = pick('command')
  if (command) return command.split('\n')[0] ?? ''
  const path = pick('file_path') ?? pick('notebook_path') ?? pick('path')
  if (path) return basename(path)
  return pick('pattern') ?? pick('description') ?? pick('query') ?? pick('url') ?? ''
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'sidebar',
      description: 'Toggle the opencode-style session sidebar',
      immediate: true,
    })
    await $.command.register({
      name: 'notify',
      description: 'Toggle Discord / ntfy alerts for this session (agent-notify)',
      immediate: true,
    })
    const started = await next(e)
    // An earlier version opened a session picker pane; close one left behind.
    await $.ui.close({ id: 'session-picker' }).catch(() => undefined)
    await loadConfiguredMcp($).catch(() => undefined)
    await refreshAll($)
    void refreshTitle($).catch(() => undefined)
    void refreshParts($).catch(() => undefined)
    void refreshPr($).catch(() => undefined)
    tick?.cancel()
    tick = $.clock.every(TICK_MS, () => {
      ticks += 1
      void refreshAll($)
      if (ticks % PR_EVERY_TICKS === 0) void refreshPr($).catch(() => undefined)
    })
    void $.ui.open({ id: PANE, title: TITLE })

    return started
  })

  on('command.run', { command: 'sidebar' }, async $ => {
    // No `text`: the pane opening or closing says it, and an output row would
    // be one more line the model reads.
    const isOpen = (await $.ui.panes()).some(p => p.id === PANE)
    if (isOpen) {
      await $.ui.close({ id: PANE })
      return {}
    }
    await refreshAll($)
    await $.ui.open({ id: PANE, title: TITLE })

    return {}
  })

  on('command.run', { command: 'notify' }, async $ => {
    await toggleNotify($)

    return {}
  })

  on('command.run', { command: 'rename' }, async ($, e, next) => {
    const ran = await next(e)
    await refreshTitle($).catch(() => undefined)

    return ran
  }).catch(($, e, next) => next(e))

  on('prompt.submit', async ($, e, next) => {
    cancelWait()
    turnStartedAt = await $.clock.now()
    turnTools = 0

    return next(e)
  }).catch(($, e, next) => next(e))

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId === undefined) {
      if (turnStartedAt > 0) {
        const turn: Turn = {
          seconds: Math.round(((await $.clock.now()) - turnStartedAt) / 1000),
          tools: turnTools,
        }
        await update($, lastTurn, () => turn)
      }
      await refreshAll($)
      void refreshTitle($).catch(() => undefined)
      void refreshParts($).catch(() => undefined)
      cancelWait()
      if (!e.isAborted) void alertTurn($, e.reason, e.answer, e.durationMs).catch(() => undefined)
    }

    return done
  })

  // The engine's own "needs your permission" notice; sent if still unanswered after WAIT_MS.
  on('classic.Notification', async ($, e, next) => {
    const result = await next(e)
    if (e.notification_type === 'permission_prompt' || e.notification_type === 'elicitation_dialog') {
      if (await isNotifying($)) armWait($, e.message)
    }

    return result
  }).catch(($, e, next) => (next.called ? undefined : next(e)))

  on('tool.call', { tool: 'AskUserQuestion' }, async ($, e, next) => {
    if (e.agentId === undefined && (await isNotifying($))) {
      armWait($, e.questions.map(q => q.question).join('\n'))
    }

    return next(e)
  }).catch(($, e, next) => next(e))

  // A tool drawing progress is running, so its permission was given.
  on('ui.render', { component: 'ToolProgress' }, ($, e, next) => {
    cancelWait()

    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    turnTools += 1
    const id = e.tool_use_id ?? `${e.tool}:${await $.clock.now()}`
    const call: Call = {
      id,
      tool: e.tool.startsWith('mcp__') ? e.tool.slice(5).replace('__', ':') : e.tool,
      detail: detailOf(e as unknown as Record<string, unknown>),
      state: 'run',
    }
    await update($, calls, list => [...list, call].slice(-RECENT_CALLS))
    const ran = await next(e)
    cancelWait()
    const state: Call['state'] = ran.deny === undefined && !ran.isError ? 'ok' : 'fail'
    await update($, calls, list => list.map(c => (c.id === id ? { ...c, state } : c)))
    if (e.tool === 'Bash') {
      // A command may have switched branch or worktree, or pushed or opened a PR.
      await refreshGit($).catch(() => undefined)
      if (/\b(git\s+push|gh\s+pr)\b/.test(call.detail)) void refreshPr($).catch(() => undefined)
    }

    return ran
  }).catch(($, e, next) => next(e))

  on('tool.call', { tool: 'TodoWrite' }, async ($, e, next) => {
    const ran = await next(e)
    if (ran.deny === undefined && !ran.isError) {
      const list: Todo[] = e.todos.map((t, i) => ({
        id: `${i}`,
        content: t.content,
        status: t.status,
      }))
      await update($, todos, () => list)
    }

    return ran
  }).catch(($, e, next) => next(e))

  on('tool.call', { tool: 'TaskCreate' }, async ($, e, next) => {
    const ran = await next(e)
    if (ran.deny === undefined && !ran.isError && ran.result) {
      const task = ran.result.task
      await update($, todos, list => [
        ...list,
        { id: task.id, content: task.subject, status: 'pending' as const },
      ])
    }

    return ran
  }).catch(($, e, next) => next(e))

  on('tool.call', { tool: 'TaskUpdate' }, async ($, e, next) => {
    const ran = await next(e)
    if (ran.deny === undefined && !ran.isError) {
      const status = e.status
      await update($, todos, list =>
        status === 'deleted'
          ? list.filter(t => t.id !== e.taskId)
          : list.map(t =>
              t.id === e.taskId
                ? { ...t, content: e.subject ?? t.content, status: status ?? t.status }
                : t,
            ),
      )
    }

    return ran
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const [now, name, todoList, repo, pull, callList, servers, partList, turn, clock, alerts] =
      await Promise.all([
        read($, info),
        read($, title),
        read($, todos),
        read($, git),
        read($, pr),
        read($, calls),
        read($, mcp),
        read($, parts),
        read($, lastTurn),
        $.clock.now(),
        read($, notify),
      ])
    const width = Math.max(10, Math.min(28, (e.viewport?.columns ?? 32) - 4))

    if (now === null) return <Text dimColor>Loading…</Text>

    const percent = now.percent ?? 0
    const filled = Math.round((percent / 100) * width)
    const barColor = percent >= CONTEXT_WARN ? 'error' : percent >= 60 ? 'warning' : 'success'
    const failed = servers.filter(s => !s.isConnected)
    const run = (command: string) => () =>
      $.command.run({ command }).catch(() => $.ui.toast(`/${command} failed`))

    return (
      <Box flexDirection="column" gap={1}>
        <Box flexDirection="column">
          <Text bold wrap="wrap">
            {name || now.dir}
          </Text>
          {name !== '' && <Text dimColor>{now.dir}</Text>}
          {repo !== null && (
            <Text wrap="truncate-end">
              <Text color="suggestion"> {repo.branch}</Text>
              {repo.isDirty && <Text color="warning">*</Text>}
              <Text dimColor>
                {repo.ahead > 0 && ` ↑${repo.ahead}`}
                {repo.behind > 0 && ` ↓${repo.behind}`}
              </Text>
            </Text>
          )}
          {pull !== null && (
            <Text wrap="truncate-end">
              <Text
                color={
                  pull.state === 'merged' ? 'merged' : pull.state === 'closed' ? 'error' : 'success'
                }
              >
                #{pull.number} {pull.state}
              </Text>
              {pull.ci && (
                <Text
                  color={
                    pull.ci === 'pass' ? 'success' : pull.ci === 'fail' ? 'error' : 'warning'
                  }
                >
                  {' · CI '}
                  {pull.ci === 'pass' ? '✓' : pull.ci === 'fail' ? '✗' : '●'}
                </Text>
              )}
            </Text>
          )}
          {repo !== null && (
            <Text dimColor wrap="truncate-end">
              ⎇ {repo.worktree ? `worktree ${repo.worktree}` : 'main worktree'}
            </Text>
          )}
          <Text dimColor>
            {now.model} · {now.turns} turns
            {now.startedAt !== undefined && ` · ${duration(clock - now.startedAt)}`}
          </Text>
          {turn !== null && (
            <Text dimColor>
              last turn {turn.seconds}s · {turn.tools} tools
            </Text>
          )}
        </Box>

        <Box gap={1}>
          <Button key="compact" hotkey="c" onPress={run('compact')}>
            compact
          </Button>
          <Button
            key="rename"
            hotkey="r"
            onPress={() => void $.prompt.fill({ text: '/rename ' })}
          >
            rename
          </Button>
          <Button key="export" hotkey="e" onPress={run('export')}>
            export
          </Button>
        </Box>
        <Button key="notify" hotkey="n" onPress={() => void toggleNotify($)}>
          {alerts ? '[x]' : '[ ]'} alerts <Text dimColor>Discord / ntfy</Text>
        </Button>

        <Box flexDirection="column">
          <Text bold>Context</Text>
          <Text>
            <Text color={barColor}>{'█'.repeat(filled)}</Text>
            <Text dimColor>{'░'.repeat(width - filled)}</Text>
            <Text> {percent}%</Text>
          </Text>
          <Text dimColor>
            {kilo(now.tokens ?? 0)} / {kilo(now.window)} tokens
            {now.usd !== undefined && ` · $${now.usd.toFixed(2)}`}
          </Text>
          {partList.map(p => (
            <Text wrap="truncate-end">
              <Text color={p.color}>■</Text> {p.name} <Text dimColor>{kilo(p.tokens)}</Text>
            </Text>
          ))}
          {percent >= CONTEXT_WARN && <Text color="warning">⚠ consider /compact</Text>}
        </Box>

        {now.limits.length > 0 && (
          <Box flexDirection="column">
            <Text bold>Limits</Text>
            {now.limits.map(l => {
              const resetsIn = l.resetsAt ? Date.parse(l.resetsAt) - clock : NaN
              return (
                <Text
                  color={l.percentUsed >= 80 ? 'warning' : undefined}
                  dimColor={l.percentUsed < 80}
                >
                  {(LIMIT_LABEL[l.kind] ?? l.kind).padEnd(3)}
                  {`${l.percentUsed}%`.padStart(4)} used
                  {Number.isFinite(resetsIn) && `  ↻ ${duration(resetsIn)}`}
                </Text>
              )
            })}
          </Box>
        )}

        {servers.length > 0 && (
          <Box flexDirection="column">
            <Text bold>
              MCP{' '}
              <Text dimColor>
                {servers.length - failed.length}/{servers.length}
              </Text>
            </Text>
            {failed.map(s => (
              <Text color="error" wrap="truncate-end">
                ✗ {s.name}
              </Text>
            ))}
          </Box>
        )}

        {todoList.length > 0 && (
          <Box flexDirection="column">
            <Text bold>Todo</Text>
            {todoList.map(t => (
              <Text
                wrap="truncate-end"
                color={t.status === 'in_progress' ? 'claude' : undefined}
                dimColor={t.status === 'completed'}
                strikethrough={t.status === 'completed'}
              >
                {t.status === 'completed' ? '✓' : t.status === 'in_progress' ? '▸' : '○'}{' '}
                {t.content}
              </Text>
            ))}
          </Box>
        )}

        {callList.length > 0 && (
          <Box flexDirection="column">
            <Text bold>Recent</Text>
            {callList.map(c => (
              <Text wrap="truncate-end">
                <Text
                  color={c.state === 'fail' ? 'error' : c.state === 'run' ? 'claude' : 'success'}
                >
                  {c.state === 'fail' ? '✗' : c.state === 'run' ? '▸' : '✓'}
                </Text>{' '}
                {c.tool} <Text dimColor>{c.detail}</Text>
              </Text>
            ))}
          </Box>
        )}
      </Box>
    )
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)

    const { Box, Button, Text } = $.ui.resolve(e)
    const run = (command: string) => () =>
      $.command.run({ command }).catch(() => $.ui.toast(`/${command} failed`))

    return (
      <Box gap={2}>
        {LEADER.map(k => (
          <Button key={k.key} plain action={k.action} onPress={run(k.command)}>
            <Text dimColor>ctrl+x {k.key}</Text> {k.label}
          </Button>
        ))}
        <Text>
          <Text dimColor>ctrl+x m</Text> model
        </Text>
      </Box>
    )
  })
}
