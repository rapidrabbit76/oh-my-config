import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

type Clock = ReturnType<typeof mock.clock>

const slash = (command: string) => ({
  command,
  args: '',
  origin: { kind: 'composer' as const },
  presentation: { isFullscreen: true, columns: 120 },
})

const QUESTION = {
  header: 'Approach',
  question: 'Which way?',
  multiSelect: false,
  options: [
    { label: 'Fast', description: 'skip the tests' },
    { label: 'Safe', description: 'run them' },
  ],
}

type Answers = { ask?: string; inbox?: string[]; askDelayMs?: number }

// The engine beneath, with agent-notify standing in for Discord: `ask` prints
// `answers.ask` (JSON), `inbox` hands out `answers.inbox` once, `status` says
// answers are on. Every call is recorded.
function world(on: On, clock: Clock, answers: Answers = {}) {
  const calls: string[][] = []
  const stdins: string[] = []
  const prompts: string[] = []
  on('process.run', async (_, e) => {
    const args = e.argv.slice(4)
    if (args[0] === 'ask' && answers.askDelayMs) await clock.sleep(answers.askDelayMs)
    calls.push([...args])
    if (e.init?.stdin) stdins.push(e.init.stdin)
    let stdout = ''
    if (args[0] === 'ask') stdout = answers.ask ?? '{}'
    if (args[0] === 'inbox') {
      stdout = JSON.stringify(answers.inbox ?? [])
      answers.inbox = []
    }
    if (args[0] === 'status') stdout = 'discord  on  (webhook …abcd · answers on)'
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.toast', () => ({ value: undefined }))
  on('session.id', () => ({ value: 'sess-1' }))
  on('command.run', () => ({}))
  on('prompt.submit', (_, e) => {
    prompts.push(e.text)
    return { text: e.text }
  })
  return { calls, stdins, prompts }
}

test('away switches the session for the bridge', async ($, on) => {
  const { calls } = world(on, mock.clock(on))
  const switches = () => calls.filter(c => c[0] === 'switch')
  await $.command.run(slash('away'))
  expect(switches().at(-1)).toEqual(['switch', 'claude', 'sess-1', 'away'])
  await $.command.run(slash('away'))
  expect(switches().at(-1)).toEqual(['switch', 'claude', 'sess-1', 'alerts'])
})

test('a question answered in Discord first fills the dialog', async ($, on) => {
  const clock = mock.clock(on)
  const { stdins } = world(on, clock, { ask: JSON.stringify({ kind: 'choice', values: ['Safe'] }) })
  // The dialog beneath: nobody at the terminal for a minute.
  on('tool.call', async () => {
    await clock.sleep(60_000)
    return { result: { questions: [QUESTION], answers: { 'Which way?': 'Fast' } } }
  })
  await $.command.run(slash('away'))
  const call = $.tool.call({ tool: 'AskUserQuestion', questions: [QUESTION] })
  await clock.settle()
  // Let the abandoned dialog beneath run out, so the call can settle.
  await clock.advance(61_000)
  const ran = await call
  expect(ran.result).toEqual({ questions: [QUESTION], answers: { 'Which way?': 'Safe' } })
  const asked = JSON.parse(stdins[0] ?? '{}')
  expect(asked.kind).toBe('choice')
  expect(asked.options).toEqual(['Fast', 'Safe'])
  expect(asked.session).toBe('sess-1')
})

test('a question answered in the terminal first cancels the Discord one', async ($, on) => {
  const clock = mock.clock(on)
  // `ask` here takes half a minute: the terminal answers first.
  const { calls } = world(on, clock, { ask: '{}', askDelayMs: 30_000 })
  on('tool.call', () => ({ result: { questions: [QUESTION], answers: { 'Which way?': 'Fast' } } }))
  await $.command.run(slash('away'))
  const call = $.tool.call({ tool: 'AskUserQuestion', questions: [QUESTION] })
  await clock.settle()
  await clock.advance(31_000)
  const ran = await call
  expect(ran.result).toEqual({ questions: [QUESTION], answers: { 'Which way?': 'Fast' } })
  expect(calls.some(c => c[0] === 'cancel')).toBe(true)
})

test('an approval from Discord decides; none leaves the terminal prompt', async ($, on) => {
  const answers: Answers = { ask: JSON.stringify({ kind: 'allow' }) }
  world(on, mock.clock(on), answers)
  on('classic.PermissionRequest', () => ({}))
  await $.command.run(slash('away'))
  const allowed = await $.classic.PermissionRequest({ tool_name: 'Bash', tool_input: { command: 'git push' } })
  expect(allowed.decision).toEqual({ behavior: 'allow' })

  answers.ask = JSON.stringify({ kind: 'deny', value: 'not yet' })
  const denied = await $.classic.PermissionRequest({ tool_name: 'Bash', tool_input: { command: 'git push' } })
  expect(denied.decision).toEqual({ behavior: 'deny', message: 'not yet' })

  answers.ask = '{}'
  const none = await $.classic.PermissionRequest({ tool_name: 'Bash', tool_input: { command: 'git push' } })
  expect(none.decision).toBeUndefined()
})

test('without away, approvals are left alone', async ($, on) => {
  const { calls } = world(on, mock.clock(on), { ask: JSON.stringify({ kind: 'allow' }) })
  on('classic.PermissionRequest', () => ({}))
  await $.command.run(slash('notify'))
  const ran = await $.classic.PermissionRequest({ tool_name: 'Bash', tool_input: { command: 'ls' } })
  expect(ran.decision).toBeUndefined()
  expect(calls.some(c => c[0] === 'ask')).toBe(false)
})

test('a message from Discord becomes a prompt', async ($, on) => {
  const clock = mock.clock(on)
  const { prompts } = world(on, clock, { inbox: ['run the tests'] })
  await $.command.run(slash('away'))
  await clock.advance(3_100)
  expect(prompts).toEqual(['run the tests'])
  await clock.advance(3_100)
  expect(prompts).toEqual(['run the tests'])
})
