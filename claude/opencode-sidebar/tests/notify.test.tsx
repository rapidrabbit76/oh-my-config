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
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

const slash = (command: string) => ({
  command,
  args: '',
  origin: { kind: 'composer' as const },
  presentation: { isFullscreen: true, columns: 120 },
})

const TURN = {
  answer: 'Fixed the redirect loop.',
  durationMs: 65_000,
  isAborted: false,
  turnId: 't1',
  reason: 'answer',
} as const

// The engine beneath: agent-notify answers `status` with `status`, records
// each `send`; every other command fails, as git would outside a repo.
function world(on: On, status = 0) {
  const sent: string[][] = []
  const toasts: string[] = []
  on('process.run', (_, e) => {
    const isNotify = e.argv[0] === '/bin/sh' && (e.argv[2] ?? '').includes('agent-notify')
    const args = e.argv.slice(4)
    if (isNotify && args[0] === 'send') sent.push([...args])
    const exitCode = isNotify ? (args[0] === 'status' ? status : 0) : 1
    return { value: { exitCode, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.toast', (_, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))
  on('session.cwd', () => ({ value: '/work/my-project' }))
  on('session.model', () => ({ value: 'claude-opus-5-5' }))
  on('session.turns', () => ({ value: 3 }))
  on('tool.call', () => ({ result: {} }))
  on('command.run', () => ({}))
  return { sent, toasts }
}

test('nothing is sent until /notify turns alerts on', async ($, on) => {
  const clock = mock.clock(on)
  const { sent, toasts } = world(on)
  const turn = async (e: Parameters<typeof $.turn.complete>[0]) => {
    await $.turn.complete(e)
    await clock.settle()
  }
  await turn(TURN)
  expect(sent.length).toBe(0)

  await $.command.run(slash('notify'))
  expect(toasts.at(-1)).toMatch(/Alerts on/)
  await turn(TURN)
  expect(sent.length).toBe(1)
  expect(sent[0]?.slice(0, 2)).toEqual(['send', 'claude'])
  expect(sent[0]?.[2]).toBe('done')
  expect(sent[0]?.[4]).toBe('Fixed the redirect loop.')
  expect(sent[0]?.[5]).toMatch(/my-project · 1m/)

  // An interrupted turn: the person is right there.
  await turn({ ...TURN, isAborted: true, reason: 'aborted' })
  // A subagent's turn is not the session's.
  await turn({ ...TURN, agentId: 'a1' })
  expect(sent.length).toBe(1)

  await $.command.run(slash('notify'))
  await turn(TURN)
  expect(sent.length).toBe(1)
  expect(toasts.at(-1)).toMatch(/Alerts off/)
})

test('a missing or unset agent-notify says so and breaks nothing', async ($, on) => {
  const { toasts } = world(on, 3)
  await $.command.run(slash('notify'))
  expect(toasts.at(-1)).toMatch(/not installed/)
})

test('a failing process call never breaks the turn', async ($, on) => {
  on('process.run', () => ({ deny: 'no processes here' }))
  on('ui.toast', () => ({ value: undefined }))
  on('turn.complete', (_, e) => ({ text: e.answer }))
  on('command.run', () => ({}))
  await $.command.run(slash('notify'))
  const done = await $.turn.complete(TURN)
  expect(done.text).toBe(TURN.answer)
})

test('a permission prompt left 30s is sent; one answered sooner is not', async ($, on) => {
  const clock = mock.clock(on)
  const { sent } = world(on)
  on('classic.Notification', () => ({}))
  await $.command.run(slash('notify'))

  const ask = { message: 'Claude needs your permission to use Bash', notification_type: 'permission_prompt' }
  await $.classic.Notification(ask)
  await clock.advance(29_000)
  expect(sent.length).toBe(0)
  await clock.advance(2_000)
  expect(sent.length).toBe(1)
  expect(sent[0]?.[2]).toBe('wait')
  expect(sent[0]?.[4]).toBe(ask.message)

  // Answered: the tool call ends before the wait is up.
  await $.classic.Notification(ask)
  await clock.advance(10_000)
  await $.tool.call({ tool: 'Bash', command: 'ls' })
  await clock.advance(30_000)
  expect(sent.length).toBe(1)

  // Idle prompts are the turn's end again, already sent.
  await $.classic.Notification({ message: 'Claude is waiting for your input', notification_type: 'idle_prompt' })
  await clock.advance(31_000)
  expect(sent.length).toBe(1)
})

test('the sidebar button toggles alerts', async ($, on) => {
  mock.clock(on)
  world(on)
  on('ui.panes', () => ({ value: [] }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  await $.command.run(slash('sidebar'))

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Button', key: 'notify' }))?.text).toMatch(/\[ \] alerts/)
    await ui.press({ key: 'notify' })
    expect((await ui.find({ type: 'Button', key: 'notify' }))?.text).toMatch(/\[x\] alerts/)
    await ui.press({ key: 'notify' })
    await ui.unmount()
  }
})
