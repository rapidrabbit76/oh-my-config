// 옆 창 그리기 시험. 네 상태 키를 심어 두고 그려진 글만 확인한다(모델 호출·파일 접근 없음).
// 시험의 $에는 state 명사가 없어서, 예제처럼 state.get/state.set을 밑에서 받아 심는다:
// 심은 키는 version 0으로 답하고, 플러그인이 한 번 쓰면 그 키는 키트 바닥(진짜 저장)으로 넘긴다.
import { expect, test } from 'claude-code/testing'
import type { Engine, Mounted } from 'claude-code/testing'
import type { On } from 'claude-code'

import type { MadeFile, SessionInfo, Todo } from '../types'

const PLUGIN = 'session-pane'

const paneAt = (bodyColumns: number) =>
  ({
    plugin: PLUGIN,
    component: 'Pane',
    requestId: 'session-pane',
    props: {
      title: '이 세션',
      isFocused: false,
      bodyColumns,
      placement: 'dock',
      scroll: { offset: 0, bodyRows: 20 },
      view: {},
    },
    viewport: { columns: bodyColumns + 4, rows: 30 },
  }) as const

const SESSION: SessionInfo = {
  purpose: 'C31 옆 창 만들기',
  steps: [
    { name: '조사', isDone: true },
    { name: '고침', isDone: false },
  ],
  latest: '폴더 열기 버튼 붙여 줘',
  isOffTopic: true,
  promptCount: 3,
  purposeFull: 'C31 옆 창 만들기 — 목적·단계·방금, 고칠 것, 만든 파일을 모델 호출 없이 옆 창에 그린다.',
  latestFull: '폴더 열기 버튼 붙여 줘. 그리고 파일도 같이.',
  answer: '폴더 버튼을 붙였어요.',
  answerFull: '폴더 버튼을 붙였어요. 이 답이 끝나면 옆 창이 다시 그려져요.',
  firstRowId: 'row-1',
  latestRowId: 'row-7',
  answerRowId: 'row-8',
  status: '진행 중',
  progress: { done: 2, total: 5 },
  isWorking: false,
  nextPrompt: 'docs/prompts/c31-session-pane.md 3단계 해줘',
}

const EMPTY: SessionInfo = {
  purpose: '', steps: [], latest: '', isOffTopic: false, promptCount: 0,
  purposeFull: '', latestFull: '', answer: '', answerFull: '',
  firstRowId: '', latestRowId: '', answerRowId: '', status: '', progress: null, isWorking: false, nextPrompt: '',
}

const TODOS: Todo[] = [
  { id: 't1', kind: 'model', text: 'open.ts 윈도우 가지 마무리', isDone: false },
  { id: 't2', kind: 'confirm', text: '성적서 양식 확인', isDone: false, isPrevious: true },
]

const FILES: MadeFile[] = [
  { path: 'C:\\MyLLMForge\\docs\\prompts\\c31-session-pane.md', name: 'c31-session-pane.md', kind: 'file', at: '2026-11-04T09:10:00' },
  { path: 'C:\\MyLLMForge_work\\TB310\\성적서-0442.xlsx', name: '성적서-0442.xlsx', kind: 'file', at: '2026-11-04T10:25:00', isPrevious: true },
  { path: 'https://claude.ai/artifact/abc', name: '검토 보고 페이지', kind: 'web', at: '2026-11-04T11:40:00' },
]

const SURFACES = ['terminal', 'desktop'] as const

/** 네 키를 심는다. 돌려주는 written에는 플러그인이 쓴 값이 키별로 남는다. */
const seed = (on: On, info: SessionInfo, todos: Todo[], files: MadeFile[]) => {
  const seeds = new Map<string, unknown>([
    ['session', info],
    ['todos', { shape: 'todos-1', value: todos }],
    ['files', { shape: 'files-1', value: files }],
    ['last', ''],
  ])
  const written = new Map<string, unknown>()
  // 바닥까지 내려보내야 그림이 그 키를 구독한다(다시 그리기). 값만 심은 것으로 바꿔 답한다.
  on('state.get', async ($, e, next) => {
    const read = await next(e)
    if (e.plugin !== PLUGIN || !seeds.has(e.key) || read.deny !== undefined) return read
    return { value: { value: seeds.get(e.key), version: read.value.version } }
  })
  on('state.set', ($, e, next) => {
    if (e.plugin === PLUGIN) {
      seeds.delete(e.key)
      written.set(e.key, e.value)
    }
    return next(e)
  })
  return written
}

/** 그려진 모든 글(겹침 무관)을 한 덩어리로 */
const shown = async (ui: Mounted<(typeof SURFACES)[number], 'Pane'>) =>
  (await ui.findAll({})).map(one => one.text).join('\n')

test('상태 창: 목적·상태·단계·버튼 줄 / 작업물(폴더+파일, 웹) / 고칠 것, 40칸과 60칸, 두 표면', async ($: Engine, on) => {
  seed(on, SESSION, TODOS, FILES)

  for (const surface of SURFACES) {
    for (const cols of [40, 60]) {
      const ui = await $.ui.mount({ ...paneAt(cols), surface })
      const text = await shown(ui)

      expect(text).toContain('목적')
      expect(text).toContain('C31 옆 창 만들기')
      expect(text).toContain('상태')
      expect(text).toContain('진행 중')
      expect(text).toContain('▰▰▱▱▱ 2/5')
      expect(text).toContain('단계')
      expect(text).toContain('● ')
      expect(text).toContain('○ ')
      expect(text).toContain('▲ 내 말')
      expect(text).toContain('▲ 답변')
      expect(text).toContain('다음 프롬프트 복사')
      // 방금·답 글 줄은 뺐다(2026-11-04 사용자 재정의)
      expect(text).not.toContain('별도 세션?')
      expect(text).not.toContain('폴더 버튼을 붙였어요')

      expect(text).toContain('고칠 것')
      expect(text).toContain('! ')
      expect(text).toContain('open.ts 윈도우 가지 마무리')
      expect(text).toContain('지난: 성적서 양식 확인')

      // 작업물: 폴더 줄(뒤 두 토막) + 밑에 파일, 웹은 링크
      expect(text).toContain('작업물')
      expect(text).toContain('docs\\prompts')
      expect(text).toContain('c31-session-pane.md')
      expect(text).toContain('[폴더]')
      expect(text).toContain('[링크]')
      expect(text).toContain('검토 보고 페이지')
      expect(text).not.toContain('아직 없음')
      expect(text).toMatch(/\d\d:\d\d/)

      // 버튼: ▲ 내 말·▲ 답변·복사 3 + 고칠 것 2 + 폴더 2 + 파일 2 = 9
      expect(await ui.findAll({ type: 'Button' })).toHaveLength(9)
      expect(await ui.find({ key: 't1' })).toBeDefined()
      expect(await ui.find({ key: 'open:' + FILES[0]!.path })).toBeDefined()
      expect(await ui.find({ key: 'dir:C:\\MyLLMForge\\docs\\prompts' })).toBeDefined()
      expect(await ui.find({ key: 'copy:next' })).toBeDefined()
      const link = await ui.find({ type: 'Link' })
      expect(link?.props.href).toBe('https://claude.ai/artifact/abc')

      await ui.unmount()
    }
  }
})

test('빈 세션은 "프롬프트 없이 시작"·"구상 중"·"아직 없음"', async ($: Engine, on) => {
  seed(on, EMPTY, [], [])

  for (const surface of SURFACES) {
    const ui = await $.ui.mount({ ...paneAt(40), surface })
    const text = await shown(ui)
    expect(text).toContain('프롬프트 없이 시작')
    expect(text).toContain('구상 중')
    expect(text).toContain('아직 없음')
    expect(text).not.toContain('고칠 것')
    // 단계 줄은 늘 있고, 비면 흐린 "아직 없음"
    expect(text).toContain('단계')
    expect(text).not.toContain('● ')
    expect(text).not.toContain('다음 프롬프트 복사')
    // 스크롤 버튼 둘은 늘 있다(기록 줄이 없으면 흐리게)
    expect(await ui.findAll({ type: 'Button' })).toHaveLength(2)
    await ui.unmount()
  }
})

test('고칠 것 줄을 누르면 isDone이 뒤집히고 ✓로 그린다', async ($: Engine, on) => {
  const written = seed(on, SESSION, TODOS, [])

  const ui = await $.ui.mount({ ...paneAt(40), surface: 'terminal' })
  expect((await ui.find({ key: 't1' }))?.text).toContain('! ')

  await ui.press({ key: 't1' })
  const stored = written.get('todos') as { value: Todo[] } | undefined
  expect(stored?.value[0]?.isDone).toBe(true)
  expect(stored?.value[1]?.isDone).toBe(false)
  expect((await ui.find({ key: 't1' }))?.text).toContain('✓ ')

  await ui.press({ key: 't1' })
  expect((written.get('todos') as { value: Todo[] }).value[0]?.isDone).toBe(false)
  expect((await ui.find({ key: 't1' }))?.text).toContain('! ')
  await ui.unmount()
})

test('긴 이름은 폭에 맞춰 자르고, 새 파일이 먼저 온다', async ($: Engine, on) => {
  const longName = '아주아주긴이름의성적서파일-모빌리티-TB310-0442-최종본.xlsx'
  seed(on, SESSION, [], [
    { path: 'C:\\a\\old.md', name: 'old.md', kind: 'file', at: '2026-11-04T08:00:00' },
    { path: 'C:\\a\\' + longName, name: longName, kind: 'file', at: '2026-11-04T12:00:00' },
  ])

  const ui = await $.ui.mount({ ...paneAt(40), surface: 'terminal' })
  // 파일 열기 버튼만 본다(라벨·폴더 버튼 제외)
  const buttons = (await ui.findAll({ type: 'Button' })).filter(b => b.key.startsWith('open:'))
  expect(buttons[0]?.key).toBe('open:C:\\a\\' + longName)
  expect(buttons[0]?.text).toEndWith('…')
  expect(buttons[0]?.text.length).toBeLessThan(longName.length)
  expect(buttons[1]?.key).toBe('open:C:\\a\\old.md')
  // 폴더 줄은 하나(둘 다 C:\a)
  expect((await ui.findAll({ type: 'Button' })).filter(b => b.key.startsWith('dir:'))).toHaveLength(1)
  await ui.unmount()
})

test('모델이 [상태]를 안 적었으면 단계로 짐작한다: 다 끝남 → 끝 2/2', async ($: Engine, on) => {
  const base = { ...SESSION, status: '' as const, progress: null }
  seed(on, { ...base, steps: [{ name: '조사', isDone: true }, { name: '고침', isDone: true }] }, [], [])
  const ui = await $.ui.mount({ ...paneAt(40), surface: 'terminal' })
  const text = await shown(ui)
  expect(text).toContain('끝')
  expect(text).toContain('▰▰ 2/2')
  await ui.unmount()
})

test('모델이 일하는 중이면 상태 앞에 ▸', async ($: Engine, on) => {
  seed(on, { ...SESSION, status: '' as const, progress: null, isWorking: true }, [], [])
  const ui = await $.ui.mount({ ...paneAt(40), surface: 'terminal' })
  const text = await shown(ui)
  expect(text).toContain('▸ 진행 중')
  await ui.unmount()
})
