// files.ts 시험: Write 기록·중복·숨김, Artifact 웹 줄, 셸이 남긴 파일.
import { expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'
import type { On } from 'claude-code'

import type { MadeFile } from '../types'

const CWD = 'C:\\proj'
const FILES = { plugin: 'session-pane', key: 'files' } as const

// 시험의 $에는 state 명사가 없다. 플러그인이 쓰는 값을 state.set 훅에서 받아 둔다(밑의 kit가 저장).
let held: unknown

/** 플러그인 밑에서 엔진 노릇을 할 훅들. 알림(toast) 글을 모아 돌려준다. */
const boot = (on: On, store?: Record<string, unknown>) => {
  held = undefined
  on('state.set', FILES, (_, e, next) => {
    held = e.value
    return next(e)
  })
  mock.store(on, store)
  const toasts: string[] = []
  on('ui.toast', (_, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.cwd', () => ({ value: CWD }))
  // pane.tsx·session.ts가 세션 시작에 부르는 것들
  on('command.register', () => ({ value: { command: 'session-pane' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('fs.read', () => ({ deny: 'ENOENT' }))
  on('tool.call', (_, e) => {
    if (String(e.tool) === 'Artifact') {
      return {
        result: { url: 'https://claude.ai/artifact/abc123', path: 'C:\\proj\\docs\\page.html', title: '보고서' },
        text: 'Published: https://claude.ai/artifact/abc123 (version 1)',
      }
    }
    return { result: {} }
  })
  return toasts
}

/** 마지막으로 쓴 files 목록(shape 꼴 { shape, value } 안의 value). 아직 안 썼으면 빈 목록. */
const filesOf = async (_: Parameters<TestBody>[0]) => {
  if (Array.isArray(held)) return held as MadeFile[]
  return ((held as { value?: MadeFile[] } | undefined)?.value ?? []) as MadeFile[]
}

test('Write 한 번이면 한 줄 + 알림 한 번, 같은 경로 두 번째는 줄 그대로·알림 없음', async ($, on) => {
  const toasts = boot(on)
  await $.session.start({ cwd: CWD, surface: 'terminal', isInteractive: true })

  await $.tool.call({ tool: 'Write', file_path: 'C:\\proj\\docs\\x.md', content: '하나' })
  let list = await filesOf($)
  expect(list.length).toBe(1)
  expect(list[0]?.path).toBe('C:\\proj\\docs\\x.md')
  expect(list[0]?.name).toBe('x.md')
  expect(list[0]?.kind).toBe('file')
  expect(list[0]?.isPrevious).toBe(undefined)
  expect(toasts).toEqual(['만듦: x.md'])

  await $.tool.call({ tool: 'Write', file_path: 'C:/proj/docs/X.md', content: '둘' })
  list = await filesOf($)
  expect(list.length).toBe(1)
  expect(toasts.length).toBe(1)
})

test('skills/ 밑 Write는 무시한다', async ($, on) => {
  const toasts = boot(on)
  await $.session.start({ cwd: CWD, surface: 'terminal', isInteractive: true })

  await $.tool.call({ tool: 'Write', file_path: 'C:\\proj\\skills\\foo\\SKILL.md', content: '' })
  await $.tool.call({ tool: 'Write', file_path: 'C:\\proj\\docs\\skills\\x.md', content: '' })
  await $.tool.call({ tool: 'Write', file_path: 'C:\\elsewhere\\docs\\x.md', content: '' })
  expect((await filesOf($)).length).toBe(0)
  expect(toasts.length).toBe(0)
})

test('Artifact 결과의 claude.ai 주소는 web 줄로 기록한다', async ($, on) => {
  const toasts = boot(on)
  await $.session.start({ cwd: CWD, surface: 'terminal', isInteractive: true })

  await $.tool.call({ tool: 'Artifact', file_path: 'C:\\proj\\docs\\page.html', title: '보고서' })
  const list = await filesOf($)
  expect(list.length).toBe(1)
  expect(list[0]?.kind).toBe('web')
  expect(list[0]?.path).toBe('https://claude.ai/artifact/abc123')
  expect(list[0]?.name).toBe('보고서')
  expect(toasts).toEqual(['만듦: 보고서'])
})

test('셸 명령 뒤에 고쳐진 docs/ 파일은 기록하고, 오래된 파일은 넘긴다', { options: { extraRoots: 'C:/MyLLMForge_work' } }, async ($, on) => {
  const toasts = boot(on)
  on('fs.stat', (_, e) => {
    const isOld = /old\.md$/i.test(e.path)
    return { value: { kind: 'file', size: 1, mtimeMs: isOld ? 1000 : Date.now() + 5000, isLink: false } }
  })
  await $.session.start({ cwd: CWD, surface: 'terminal', isInteractive: true })

  await $.tool.call({
    tool: 'Bash',
    command: 'cat docs/old.md > "C:\\proj\\docs\\새 글.md" && cp docs/old.md C:\\MyLLMForge_work\\out.xlsx',
  })
  const list = await filesOf($)
  expect(list.map(f => f.path).sort()).toEqual(['C:\\MyLLMForge_work\\out.xlsx', 'C:\\proj\\docs\\새 글.md'])
  expect(toasts.length).toBe(2)
})

test('지난 세션 목록은 isPrevious로 이어 보여 주고, 새 기록이 그 위에 쌓인다', async ($, on) => {
  const prev: MadeFile[] = [{ path: 'C:\\proj\\docs\\old.md', name: 'old.md', kind: 'file', at: '2026-11-03T01:00:00.000Z' }]
  boot(on, { ['session-pane:files:' + CWD.toLowerCase()]: prev })
  await $.session.start({ cwd: CWD, surface: 'terminal', isInteractive: true })

  let list = await filesOf($)
  expect(list.length).toBe(1)
  expect(list[0]?.isPrevious).toBe(true)

  await $.tool.call({ tool: 'Edit', file_path: 'C:\\proj\\docs\\old.md', old_string: 'a', new_string: 'b' })
  list = await filesOf($)
  expect(list.length).toBe(1)
  expect(list[0]?.isPrevious).toBe(undefined)
})
