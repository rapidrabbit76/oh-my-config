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

// The engine beneath, with peon-ping standing in: its script answers the
// paused flag and flips it on `toggle`, or exits 3 when not installed.
function world(on: On, isInstalled = true) {
  const peon = { isPaused: false, toggles: 0 }
  const toasts: string[] = []
  on('process.run', (_, e) => {
    const isPeon = e.argv[0] === '/bin/sh' && (e.argv[2] ?? '').includes('peon-ping')
    let exitCode = 1
    let stdout = ''
    if (isPeon && !isInstalled) exitCode = 3
    else if (isPeon) {
      if (e.argv[4] === 'toggle') {
        peon.isPaused = !peon.isPaused
        peon.toggles += 1
      }
      exitCode = 0
      stdout = peon.isPaused ? 'paused\n' : 'active\n'
    }
    return { value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.toast', (_, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  on('session.cwd', () => ({ value: '/work/my-project' }))
  on('session.model', () => ({ value: 'claude-opus-5-5' }))
  on('session.turns', () => ({ value: 3 }))
  on('session.id', () => ({ value: 'sess-1' }))
  on('ui.panes', () => ({ value: [] }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  return { peon, toasts }
}

test('/sound and the sidebar button mute and unmute peon-ping', async ($, on) => {
  mock.clock(on)
  const { peon, toasts } = world(on)
  await $.command.run(slash('sidebar'))

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Button', key: 'sound' }))?.text).toMatch(/● sound/)

  await $.command.run(slash('sound'))
  expect(peon.isPaused).toBe(true)
  expect(toasts.at(-1)).toMatch(/muted/)
  expect((await ui.find({ type: 'Button', key: 'sound' }))?.text).toMatch(/○ sound/)

  await ui.press({ key: 'sound' })
  expect(peon.isPaused).toBe(false)
  expect(peon.toggles).toBe(2)
  expect((await ui.find({ type: 'Button', key: 'sound' }))?.text).toMatch(/● sound/)
  await ui.unmount()
})

test('without peon-ping the sound row is left out', async ($, on) => {
  mock.clock(on)
  const { toasts } = world(on, false)
  await $.command.run(slash('sidebar'))

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Button', key: 'sound' })).toBeUndefined()
  await ui.unmount()

  await $.command.run(slash('sound'))
  expect(toasts.at(-1)).toMatch(/not installed/)
})
