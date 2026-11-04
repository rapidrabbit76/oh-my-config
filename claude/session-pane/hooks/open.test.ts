// open.ts 시험: 운영체제 가지마다 어떤 명령을 돌리는지, 실패 때 결과 꼴.
import { expect, test } from 'claude-code/testing'
import type { EngineInterface, ProcessRunInit, ProcessRunResult } from 'claude-code'

import { openPath, parentOf } from './open'

type Call = { argv: readonly string[]; init?: ProcessRunInit }

/** $ 흉내: plugin.root·process.run·fs.stat만 */
const fakeEngine = (root: string, calls: Call[], options: { hasOpen?: boolean; run?: Partial<ProcessRunResult> | Error } = {}) =>
  ({
    plugin: { name: 'session-pane', root },
    process: {
      run: async (argv: readonly string[], init?: ProcessRunInit) => {
        calls.push({ argv, init })
        if (options.run instanceof Error) throw options.run
        return { exitCode: 0, stdout: 'hwnd=123 visible=True foreground=True\n', stderr: '', ...options.run }
      },
    },
    fs: {
      stat: async () => {
        if (options.hasOpen) return { kind: 'file', size: 1, mtimeMs: 0, isLink: false }
        throw new Error('ENOENT')
      },
    },
  }) as unknown as EngineInterface

test('윈도 뿌리면 powershell.exe로 helpers/open-path.ps1을 돌린다', async () => {
  const calls: Call[] = []
  const root = 'C:\\mods\\session-pane'
  const got = await openPath(fakeEngine(root, calls), 'C:\\proj\\docs\\x.md')

  expect(calls.length).toBe(1)
  const argv = calls[0]?.argv ?? []
  expect(argv[0]).toBe('powershell.exe')
  expect(argv).toContain('C:\\mods\\session-pane\\helpers\\open-path.ps1')
  expect(argv[argv.length - 1]).toBe('C:\\proj\\docs\\x.md')
  expect(calls[0]?.init?.cwd).toBe(root)
  expect(calls[0]?.init?.timeoutMs).toBe(20000)
  expect(got.isOpened).toBe(true)
  expect(got.detail).toBe('hwnd=123 visible=True foreground=True')
})

test('윈도: 종료 코드 3이면 못 연 것으로, 설명은 stderr 또는 코드 뜻', async () => {
  const calls: Call[] = []
  const got = await openPath(fakeEngine('C:\\mods\\session-pane', calls, { run: { exitCode: 3, stdout: '' } }), 'C:\\없음')
  expect(got.isOpened).toBe(false)
  expect(got.detail).toBe('경로 없음')
})

test('맥(/usr/bin/open 있음)은 open, 리눅스는 xdg-open', async () => {
  const mac: Call[] = []
  await openPath(fakeEngine('/Users/me/mods/session-pane', mac, { hasOpen: true }), '/Users/me/docs/x.md')
  expect(mac[0]?.argv).toEqual(['open', '/Users/me/docs/x.md'])

  const linux: Call[] = []
  await openPath(fakeEngine('/home/me/mods/session-pane', linux), '/home/me/docs')
  expect(linux[0]?.argv).toEqual(['xdg-open', '/home/me/docs'])
})

test('process.run이 거부되면 isOpened false와 이유', async () => {
  const calls: Call[] = []
  const got = await openPath(fakeEngine('C:\\mods\\session-pane', calls, { run: new Error('spawn failed') }), 'C:\\x')
  expect(got).toEqual({ isOpened: false, detail: 'spawn failed' })
})

// 시험의 $는 사건을 일으키는 Engine이라 plugin·process·fs 명사가 없다 → 위처럼 $ 흉내로만 시험한다.

test('parentOf: 파일→폴더, 드라이브 뿌리는 그대로', () => {
  expect(parentOf('C:\\proj\\docs\\x.md')).toBe('C:\\proj\\docs')
  expect(parentOf('C:/proj/docs/')).toBe('C:/proj')
  expect(parentOf('C:\\x.md')).toBe('C:\\')
  expect(parentOf('/home/me/x')).toBe('/home/me')
  expect(parentOf('/x')).toBe('/')
  expect(parentOf('x.md')).toBe('x.md')
})
