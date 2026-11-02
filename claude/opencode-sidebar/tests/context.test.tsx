import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

const PANE = {
  plugin: 'opencode-sidebar',
  component: 'Pane',
  requestId: 'opencode-sidebar',
  props: {
    title: 'Session',
    isFocused: false,
    bodyColumns: 32,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 80 },
    view: {},
  },
} as const

const slash = (command: string) => ({
  command,
  args: '',
  origin: { kind: 'composer' as const },
  presentation: { isFullscreen: true, columns: 120 },
})

const row = (name: string, tokens: number, color: string, kind: string) => ({
  name,
  tokens,
  color,
  kind,
  isDeferred: kind === 'deferred',
})

// A 200k window: 100k used over three rows, 67k free, a 33k autocompact reserve,
// and 12k of deferred tool schemas outside the window.
const USAGE = {
  startedAt: 0,
  rateLimits: [],
  cost: { usd: 1.23 },
  context: {
    tokens: 100_000,
    window: 200_000,
    percent: 50,
    breakdown: {
      categories: [
        row('System prompt', 10_000, 'promptBorder', 'used'),
        row('System tools', 30_000, 'inactive', 'used'),
        row('Messages', 60_000, 'permission', 'used'),
        row('Free space', 67_000, 'text', 'free'),
        row('Autocompact buffer', 33_000, 'inactive', 'buffer'),
        row('MCP tools (deferred)', 12_000, 'inactive', 'deferred'),
      ],
      memoryFiles: [
        { path: '/work/my-project/CLAUDE.md', type: 'Project', tokens: 2_000 },
        { path: '/home/me/.claude/CLAUDE.md', type: 'User', tokens: 5_000 },
      ],
      mcpTools: [
        { name: 'a', serverName: 'github', tokens: 4_000, isLoaded: true },
        { name: 'b', serverName: 'github', tokens: 3_000, isLoaded: true },
        { name: 'c', serverName: 'slack', tokens: 9_000, isLoaded: false },
      ],
      isAutoCompactEnabled: true,
      autoCompactThreshold: 167_000,
    },
  },
}

function world(on: On) {
  on('process.run', () => ({
    value: { exitCode: 1, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
  }))
  on('ui.toast', () => ({ value: undefined }))
  on('session.cwd', () => ({ value: '/work/my-project' }))
  on('session.model', () => ({ value: 'claude-opus-5-5' }))
  on('session.turns', () => ({ value: 3 }))
  on('session.id', () => ({ value: 'sess-1' }))
  on('session.usage', () => ({ value: USAGE as never }))
  on('ui.panes', () => ({ value: [] }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
}

test('context is a label and a bar cut per /context row, with the detail in hover cards', async ($, on) => {
  const clock = mock.clock(on, { now: 60_000 })
  world(on)
  await $.command.run(slash('sidebar'))
  await clock.settle()

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const all = (await ui.find({ type: 'Box' }))?.text ?? ''
  // The pane body's 32 cells over 200k: 100k used (16 █), 67k free (11 ░), the 33k reserve (5 ▒).
  expect(all).toMatch(/Context 50% 100k\/200k · \$1\.23█{16}░{11}▒{5}100k/)

  const sum = await ui.find({ key: 'ctx-sum' })
  expect(sum?.props.display).toBe('none')
  expect(sum?.text).toMatch(/\$1\.23 · compacts at 167k/)
  expect(sum?.text).toMatch(/Messages 60k/)
  expect(sum?.text).toMatch(/· MCP tools \(deferred\) 12k/)
  // Biggest first; only loaded MCP tools count.
  expect(sum?.text).toMatch(/memoryCLAUDE\.md 5kCLAUDE\.md 2k/)
  expect(sum?.text).toMatch(/mcpgithub 7k$/)

  const messages = await ui.find({ key: 'ctx-part-2' })
  expect(messages?.props.display).toBe('none')
  expect(messages?.text).toMatch(/Messages60k · 30% of window60% of what is used/)
  expect((await ui.find({ key: 'ctx-part-4' }))?.text).toMatch(/kept free for autocompact/)
  // Deferred schemas are outside the window: no segment.
  expect(await ui.find({ key: 'ctx-part-5' })).toBeUndefined()
  await ui.unmount()

  // A wider sidebar: the bar and the cards follow the body's width.
  const wide = await $.ui.mount({ ...PANE, props: { ...PANE.props, bodyColumns: 60 }, surface: 'terminal' })
  expect((await wide.find({ type: 'Box' }))?.text).toMatch(/█{30}░{20}▒{10}100k/)
  expect((await wide.find({ key: 'ctx-sum' }))?.props.width).toBe(60)
  await wide.unmount()
})
