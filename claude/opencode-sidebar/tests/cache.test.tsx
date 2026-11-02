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
    scroll: { offset: 0, bodyRows: 60 },
    view: {},
  },
} as const

const slash = (command: string) => ({
  command,
  args: '',
  origin: { kind: 'composer' as const },
  presentation: { isFullscreen: true, columns: 120 },
})

const T0 = Date.parse('2026-11-02T03:00:00.000Z')
const at = (min: number) => new Date(T0 + min * 60_000).toISOString()

// What the transcript script prints: timestamp, uncached, cache read, cache
// write, of which 1h writes. The first request writes everything; the fourth
// comes after the cache expired and writes it again.
const TSV = [
  `${at(0)}\t10\t0\t100000\t100000`,
  `${at(1)}\t2\t100000\t2000\t2000`,
  `${at(2)}\t2\t102000\t1000\t1000`,
  `${at(90)}\t2\t20000\t90000\t90000`,
  `${at(91)}\t2\t110000\t500\t500`,
].join('\n')

function world(on: On, tsv: string) {
  on('process.run', (_, e) => {
    const isCache = e.argv[0] === '/bin/sh' && (e.argv[2] ?? '').includes('cache_read_input_tokens')
    return {
      value: {
        exitCode: isCache ? 0 : 1,
        stdout: isCache ? tsv : '',
        stderr: '',
        isStdoutTruncated: false,
        isStderrTruncated: false,
      },
    }
  })
  on('ui.toast', () => ({ value: undefined }))
  on('session.cwd', () => ({ value: '/work/my-project' }))
  on('session.model', () => ({ value: 'claude-opus-5-5' }))
  on('session.turns', () => ({ value: 3 }))
  on('session.id', () => ({ value: 'sess-1' }))
  on('ui.panes', () => ({ value: [] }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
}

type Ui = { find: (q: { key?: string; type?: string }) => Promise<{ text: string; props: Record<string, unknown> } | undefined> }
const cardOf = (ui: Ui, key: string) => ui.find({ key })
const textOf = async (ui: Ui) => (await ui.find({ type: 'Box' }))?.text ?? ''

test('the cache indicator holds the hit rate and a cell per request, with the detail in hover cards', async ($, on) => {
  const clock = mock.clock(on, { now: T0 + 95 * 60_000 })
  world(on, TSV)
  await $.command.run(slash('sidebar'))
  await clock.settle()

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  // 332k read of 525.5k input in all; the fourth request rebuilt the cache.
  expect(await textOf(ui)).toMatch(/Cache 63\.2% ● 56m left · ↺1▁██▂█/)

  const sum = await cardOf(ui, 'cache-sum')
  expect(sum?.props.display).toBe('none')
  expect(sum?.text).toMatch(/hit 63\.2% · last 99\.5%/)
  expect(sum?.text).toMatch(/5 req · ↺1 rebuilt/)
  expect(sum?.text).toMatch(/read 332k · write 194k/)
  expect(sum?.text).toMatch(/new 18 · billed \d+(\.\d)?%/)
  // Last request at 91m with 1h writes; now 95m.
  expect(sum?.text).toMatch(/● warm · 56m left \(1h\)/)

  const rebuilt = await cardOf(ui, 'cache-req-3')
  // Hidden until hovered (the surface applies `hover`; the kit leaves it out of props).
  expect(rebuilt?.props.display).toBe('none')
  expect(rebuilt?.text).toMatch(/request 4 · 5m ago/)
  expect(rebuilt?.text).toMatch(/hit 18\.2%/)
  expect(rebuilt?.text).toMatch(/1h28m after prev/)
  expect(rebuilt?.text).toMatch(/↺ cache rebuilt/)
  expect((await cardOf(ui, 'cache-req-4'))?.text).not.toMatch(/rebuilt/)
  // The first request writes everything, which is no rebuild.
  expect((await cardOf(ui, 'cache-req-0'))?.text).not.toMatch(/rebuilt/)
  await ui.unmount()

  // An hour on, past the 1h TTL (in a session the 15s tick redraws it).
  await clock.advance(60 * 60_000)
  const later = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await textOf(later)).toMatch(/Cache 63\.2% ○ cold · ↺1/)
  expect((await cardOf(later, 'cache-sum'))?.text).toMatch(/○ cold · next rebuilds/)
  await later.unmount()
})

test('with no requests yet the cache section is left out', async ($, on) => {
  const clock = mock.clock(on, { now: T0 })
  world(on, '')
  await $.command.run(slash('sidebar'))
  await clock.settle()

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await textOf(ui)).not.toMatch(/Cache/)
  await ui.unmount()
})
