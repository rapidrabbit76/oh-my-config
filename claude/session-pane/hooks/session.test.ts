import { expect, test } from 'claude-code/testing'
import type { Engine, On } from 'claude-code/testing'

import type { SessionInfo } from '../types'

const SESSION = { plugin: 'session-pane', key: 'session' } as const

// 시험의 $에는 state 명사가 없다. 플러그인이 쓰는 값을 state.set 훅에서 받아 두고(밑의 kit가 저장) 그걸 본다.
let held: SessionInfo | undefined

// 엔진 밑바닥 대신 서는 훅들: 호출은 { value }, 사건은 제 결과로 답한다.
const bottom = (on: On, promptFile = '') => {
  held = undefined
  on('state.set', SESSION, (_, e, next) => {
    held = e.value as SessionInfo
    return next(e)
  })
  on('command.register', () => ({ value: { command: 'session-pane' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('turn.complete', (_, e) => ({ text: e.answer }))
  on('fs.read', () => {
    if (!promptFile) throw new Error('ENOENT')
    return { value: promptFile }
  })
}

// 엔진은 사람이 친 요청에 origin을 찍어 보낸다(매처가 그걸 본다). 시험도 엔진처럼 찍는다.
const submit = ($: Engine, text: string) =>
  $.prompt.submit({ text, wait: false, origin: { kind: 'composer' } } as unknown as Parameters<Engine['prompt']['submit']>[0])

const reply = ($: Engine, answer: string) =>
  $.turn.complete({ answer, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })

const info = async (_: Engine) => {
  if (!held) throw new Error('플러그인이 session 상태를 쓰지 않았다')
  return held
}

test('첫 요청의 번호 단계가 목적·단계·방금이 된다', async ($, on) => {
  bottom(on)
  await $.session.start({ cwd: 'C:\\MyLLMForge', surface: 'terminal', isInteractive: true })
  await submit($, '> 성적서 양식 재정립\n\n1. 도면 확인\n2. 견본 대조\n3) 성적서 만들기')

  const s = await info($)
  expect(s.purpose).toBe('성적서 양식 재정립')
  expect(s.steps.map(x => x.name)).toEqual(['도면 확…', '견본 대…', '성적서 …'])
  expect(s.steps.every(x => !x.isDone)).toBe(true)
  expect(s.latest).toBe('> 성적서 양식 재정립')
  expect(s.promptCount).toBe(1)
  expect(s.isOffTopic).toBe(false)
})

test('프롬프트 파일이 있으면 # 제목과 ## N단계 머리말을 쓴다', async ($, on) => {
  bottom(on, '# 모빌리티 성적서 갑지\n\n## 1단계. 도면\n글\n## 2단계. 견본\n## 3. 성적서\n')
  await $.session.start({ cwd: 'C:\\MyLLMForge', surface: 'terminal', isInteractive: true })
  await submit($, 'docs/prompts/c26-report.md 를 읽고 진행해')

  const s = await info($)
  expect(s.purpose).toBe('모빌리티 성적서 갑지')
  expect(s.steps.map(x => x.name)).toEqual(['도면', '견본', '성적서'])
})

test('나중 요청: 안 겹치는 긴 요청은 딴 얘기, 겹치면 아님, 짧으면 아님', async ($, on) => {
  bottom(on)
  await $.session.start({ cwd: 'C:\\MyLLMForge', surface: 'terminal', isInteractive: true })
  await submit($, '성적서 양식 재정립\n1. 도면\n2. 견본\n3. 성적서')

  await submit($, 'the quick brown fox jumps over the lazy dog')
  let s = await info($)
  expect(s.isOffTopic).toBe(true)
  expect(s.latest).toBe('the quick brown fox jumps over th…') // 34칸으로 자름
  expect(s.promptCount).toBe(2)

  await submit($, '이제 견본을 다시 보고 양식에 맞게 고쳐 주세요 부탁해요')
  s = await info($)
  expect(s.isOffTopic).toBe(false)
  expect(s.promptCount).toBe(3)

  await submit($, 'zzz qqq')
  s = await info($)
  expect(s.isOffTopic).toBe(false)
})

test('답변이 2단계 이름을 말하면 1~2단계가 끝으로 표시되고 되돌리지 않는다', async ($, on) => {
  bottom(on)
  await $.session.start({ cwd: 'C:\\MyLLMForge', surface: 'terminal', isInteractive: true })
  await submit($, '성적서 양식 재정립\n1. 도면\n2. 견본\n3. 성적서')

  await reply($, '견본 대조를 마쳤습니다. 다음으로 넘어갈까요?')
  let s = await info($)
  expect(s.steps.map(x => x.isDone)).toEqual([true, true, false])

  await reply($, '잠깐 다른 얘기입니다.')
  s = await info($)
  expect(s.steps.map(x => x.isDone)).toEqual([true, true, false])

  await reply($, '3단계 완료했습니다.')
  s = await info($)
  expect(s.steps.map(x => x.isDone)).toEqual([true, true, true])
})
