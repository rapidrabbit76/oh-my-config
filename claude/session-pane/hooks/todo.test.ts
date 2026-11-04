import { expect, test } from 'claude-code/testing'
import type { Engine, On } from 'claude-code/testing'

import type { Todo } from '../types'
import { STORE_KEY } from './state'

const TODOS = { plugin: 'session-pane', key: 'todos' } as const
const CWD = 'C:\\MyLLMForge'
const GUARD = 'session-pane-guard'
const GUARD_PROPS = {
  title: '고칠 것 남음',
  isFocused: true,
  bodyColumns: 40,
  placement: 'inline',
  scroll: { offset: 0, bodyRows: 8 },
  view: {},
} as const

// 시험의 $에는 state 명사가 없다. 플러그인이 쓰는 todos 값을 state.set 훅에서 받아 둔다(밑의 kit가 저장).
let held: Todo[] = []
let git = '' // 가짜 `git status --porcelain` 출력
let doc = '' // 가짜 docs/domain/a.md 내용('' 이면 폴더 비어 있음)
let opened: string[] = []
let closed: string[] = []
let ran: string[] = []
let stored: Record<string, unknown> = {}
let uuid = 0

const asList = (v: unknown): Todo[] => (Array.isArray(v) ? (v as Todo[]) : ((v as { value?: Todo[] })?.value ?? []))

// 엔진 밑바닥 대신 서는 훅들: 호출은 { value }, 사건은 제 결과로 답한다.
const bottom = (on: On, entries?: Record<string, unknown>) => {
  held = []
  git = ''
  doc = ''
  opened = []
  closed = []
  ran = []
  stored = { ...entries }
  // 매처 없는 훅은 사건마다 하나뿐이라 mock.store 대신 직접 답한다(값을 들여다보려고).
  on('store.get', (_, e) => ({ value: stored[e.key] }))
  on('store.set', (_, e) => {
    stored[e.key] = e.value
    return { value: undefined }
  })
  on('state.set', TODOS, (_, e, next) => {
    held = asList(e.value)
    return next(e)
  })
  on('command.register', () => ({ value: { command: 'session-pane' } }))
  on('ui.open', (_, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true } }
  })
  on('ui.close', (_, e) => {
    closed.push(e.id)
    return { value: undefined }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.end', (_, e) => ({ sessionId: e.sessionId }))
  on('prompt.submit', (_, e) => {
    ran.push('prompt:' + e.text)
    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))
  on('command.run', (_, e) => {
    ran.push('command:' + e.command)
    return { text: '' }
  })
  on('fs.list', () => ({ value: doc ? [{ name: 'a.md', kind: 'file', size: doc.length, mtimeMs: 1, isLink: false }] : [] }))
  on('fs.read', () => {
    if (!doc) throw new Error('ENOENT')
    return { value: doc }
  })
  on('fs.stat', () => {
    throw new Error('ENOENT')
  })
  on('process.run', () => ({
    value: { exitCode: 0, stdout: git, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
  }))
}

const start = ($: Engine) => $.session.start({ cwd: CWD, surface: 'terminal', isInteractive: true })

/** 모델 답변의 글 블록 하나가 기록되는 사건(door response) */
const reply = ($: Engine, text: string) =>
  $.session.append({
    door: 'response',
    origin: { kind: 'model', model: 'test' },
    uuid: 'u' + ++uuid,
    message: { type: 'assistant', role: 'assistant', content: [{ type: 'text', text }] },
  })

const endTurn = ($: Engine, answer = '') =>
  $.turn.complete({ answer, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })

/** 사람이 친 슬래시 명령 줄의 prompt.submit(엔진이 command를 찍어 보낸다) */
const submitCommand = ($: Engine, name: string) =>
  $.prompt.submit({ text: '/' + name, command: { name, args: '' }, wait: false, origin: { kind: 'composer' } } as unknown as Parameters<
    Engine['prompt']['submit']
  >[0])

const runCommand = ($: Engine, name: string) =>
  $.command.run({ command: name, args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 120 } } as unknown as Parameters<
    Engine['command']['run']
  >[0])

const openTodos = () => held.filter(t => !t.isDone)

test('답변의 [고칠 것] 줄 둘 → model todo 둘, 같은 답변 다시 → 안 늘어남', async ($, on) => {
  bottom(on)
  await start($)
  const text = '정리했어요.\n[고칠 것] 용접 기호 칸 넓히기\n  [고칠 것]  훅 메시지 줄 바꿈\n본문에 [고칠 것]이라는 말만 있는 줄은 아님.'
  await reply($, text)

  const models = held.filter(t => t.kind === 'model')
  expect(models).toHaveLength(2)
  expect(models.map(t => t.text)).toEqual(['용접 기호 칸 넓히기', '훅 메시지 줄 바꿈'])
  expect(models.every(t => t.id.startsWith('model:') && !t.isDone)).toBe(true)

  await reply($, text)
  await endTurn($, text) // 마지막 답변 경로도 같은 줄을 또 넣지 않는다
  expect(held.filter(t => t.kind === 'model')).toHaveLength(2)
})

test('skills/ 밑 커밋 안 된 변경 → skills:foo "2개", 깨끗해지면 사라짐', async ($, on) => {
  bottom(on)
  await start($)
  git = ' M skills/foo/scripts/a.py\n?? skills/foo/b.md\n M docs/domain/x.md\n'
  await endTurn($)

  const skills = held.filter(t => t.kind === 'skills')
  expect(skills).toHaveLength(1)
  expect(skills[0].id).toBe('skills:foo')
  expect(skills[0].text).toBe('skills/foo 고침 2개 커밋 안 됨')

  git = ' M docs/domain/x.md\n'
  await endTurn($)
  expect(held.filter(t => t.kind === 'skills')).toHaveLength(0)
})

test('[확인 필요]: 세션 시작 수보다 늘면 confirm todo, 백틱 안은 안 셈, 되돌리면 사라짐', async ($, on) => {
  bottom(on)
  doc = '# 쪽\n[확인 필요] 하나\n'
  await start($)
  doc = '# 쪽\n[확인 필요] 하나\n[확인 필요] 둘\n`[확인 필요]` 언급\n```\n[확인 필요] 코드\n```\n'
  await endTurn($)
  expect(held.find(t => t.kind === 'confirm')?.text).toBe('[확인 필요] 새 줄 1')

  doc = '# 쪽\n[확인 필요] 하나\n'
  await endTurn($)
  expect(held.find(t => t.kind === 'confirm')).toBe(undefined)
})

test('/clear: 남은 것 있으면 drop + 안내 창, 없으면 통과(next)', async ($, on) => {
  bottom(on)
  await start($)
  const passed = await submitCommand($, 'clear')
  expect(passed.drop).toBe(undefined)
  expect(ran).toContain('prompt:/clear')
  expect(opened).not.toContain(GUARD)

  await reply($, '[고칠 것] 훅 메시지 줄 바꿈')
  ran = []
  const dropped = await submitCommand($, 'exit')
  expect(dropped.drop).toMatch(/1건/)
  expect(ran).toEqual([])
  expect(opened).toContain(GUARD)
})

test('command.run 관문: 막히면 명령이 안 돌고, 안내 창의 "그래도 닫기"가 같은 명령을 다시 돌린다', async ($, on) => {
  bottom(on)
  await start($)
  await reply($, '[고칠 것] 훅 메시지 줄 바꿈')

  const blocked = await runCommand($, 'clear')
  expect(blocked.text).toMatch(/1건/)
  expect(ran).toEqual([])
  expect(opened).toContain(GUARD)

  const ui = await $.ui.mount({ plugin: 'session-pane', surface: 'terminal', component: 'Pane', requestId: GUARD, props: GUARD_PROPS })
  expect((await ui.find({ type: 'Text', text: /훅 메시지/ }))?.text).toContain('훅 메시지 줄 바꿈')
  expect(await ui.findAll({ type: 'Button' })).toHaveLength(2)

  await ui.press({ key: 'cancel' })
  expect(closed).toEqual([GUARD])
  expect(ran).toEqual([])

  await ui.press({ key: 'force' })
  expect(closed).toEqual([GUARD, GUARD])
  expect(ran).toEqual(['command:clear']) // 관문을 지나 밑바닥까지 갔다
  await ui.unmount()

  // 다시 돌린 뒤에는 관문이 되살아난다
  const again = await runCommand($, 'clear')
  expect(again.text).toMatch(/1건/)
})

test('세션 끝에 안 끝난 것을 store에 남기고, 다음 세션 시작에 "지난 세션: "으로 되살린다', async ($, on) => {
  bottom(on)
  await start($)
  await reply($, '[고칠 것] 훅 메시지 줄 바꿈')
  await $.session.end({ reason: 'prompt_input_exit', sessionId: 's1', resume: { id: 's1' } } as unknown as Parameters<Engine['session']['end']>[0])

  const saved = stored[STORE_KEY(CWD, 'todos')] as Todo[]
  expect(saved).toHaveLength(1)
  expect(saved[0]).toEqual({ id: saved[0].id, kind: 'model', text: '훅 메시지 줄 바꿈', isDone: false })
})

test('지난 세션의 store 값은 빈 todos에 isPrevious로 들어간다', async ($, on) => {
  bottom(on, { [STORE_KEY(CWD, 'todos')]: [{ id: 'model:abc', kind: 'model', text: '훅 메시지 줄 바꿈', isDone: false }] })
  await start($)

  expect(openTodos()).toHaveLength(1)
  expect(held[0].isPrevious).toBe(true)
  expect(held[0].text).toBe('지난 세션: 훅 메시지 줄 바꿈')
})
