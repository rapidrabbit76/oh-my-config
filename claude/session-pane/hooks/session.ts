// "이 세션" 칸: 목적(첫 요청 제목 줄)·단계(번호 단계 ●/○)·방금(마지막 요청 한 줄, 목적과 다르면 경고).
// 담당: 에이전트 A. sessionInfo atom만 쓴다. 모델 호출 없음(글자 규칙만).
import { atom, read, update } from 'claude-code'
import type { EngineInterface, On } from 'claude-code'

import type { SessionInfo, Step } from '../types'
import { EMPTY_SESSION, FULL_CHARS, cut, firstSentence, nextPromptLine, purposeLine, statusLine, stepsLine, toSlash } from './state'

const sessionInfo = atom({ plugin: 'session-pane', key: 'session' } as const, EMPTY_SESSION)

const MAX_STEPS = 6
const PURPOSE_COLS = 34
const STEP_COLS = 8
const MIN_TOKENS = 6 // 이보다 짧은 요청은 "딴 얘기" 판정 안 함

// session.start는 pane.tsx가 잡고 있어(매처 없는 훅은 사건마다 하나) cwd는 쓸 때 $.session.cwd()로 읽는다.
/** 사람이 친 요청으로 치는 출처(일거리 알림·다른 세션 글은 뺌; plugin은 시험용 $.prompt.submit) */
const USER_ORIGINS = ['composer', 'bridge', 'sdk', 'unclassified', 'plugin'] as const
let baseTokens: string[] = [] // 목적 + 단계 이름 + 첫 요청 글의 낱말(재적재 시 목적·단계만으로 다시 만듦)

const lines = (s: string) => s.split(/\r?\n/)
const firstLine = (s: string) => lines(s).map(l => l.trim()).find(Boolean) ?? ''
const stripMark = (s: string) => s.replace(/^[>#*\-\s]+/, '').replace(/\*+/g, '').trim()

/** 낱말 나누기: 공백·문장 부호로 끊고 소문자, 2글자 이상만 */
const tokens = (s: string) =>
  s.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(t => t.length >= 2)

/** 두 낱말이 겹치는가: 같거나 한쪽이 다른 쪽의 머리(한국어 조사 "성적서를"↔"성적서") */
const overlaps = (a: string, b: string) => a === b || a.startsWith(b) || b.startsWith(a)

/** 글에서 번호 단계 뽑기. 머리말(## N단계. / ## N.)이면 headings=true, 아니면 본문 줄 규칙 */
const findSteps = (text: string, headings: boolean): Step[] => {
  const found = new Map<number, string>()
  const put = (n: number, name: string) => {
    const clean = stripMark(name)
    if (n >= 1 && clean && !found.has(n)) found.set(n, cut(clean, STEP_COLS))
  }
  for (const raw of lines(text)) {
    const line = raw.trim()
    if (headings) {
      const m = /^##\s*(\d+)\s*(?:단계)?\s*[.):]?\s*(.+)$/.exec(line)
      if (m) put(Number(m[1]), m[2] ?? '')
      continue
    }
    const a = /^(\d+)[).]\s*(.+)$/.exec(line)
    const b = /(\d+)\s*단계\s*[.:]?\s*(.+)$/.exec(line)
    const c = /^([①②③④⑤⑥⑦⑧⑨])\s*(.+)$/.exec(line)
    if (a) put(Number(a[1]), a[2] ?? '')
    else if (b) put(Number(b[1]), b[2] ?? '')
    else if (c) put('①②③④⑤⑥⑦⑧⑨'.indexOf(c[1] ?? '') + 1, c[2] ?? '')
  }
  return [...found.entries()]
    .sort((x, y) => x[0] - y[0])
    .slice(0, MAX_STEPS)
    .map(([, name]) => ({ name, isDone: false }))
}

/** 요청 글이 가리키는 docs/prompts/*.md 파일의 글(없거나 못 읽으면 빈 글) */
async function readPromptFile($: EngineInterface, text: string) {
  const m = /((?:[A-Za-z]:)?[\w./\\\-가-힣]*docs[\\/]prompts[\\/][\w.\-가-힣]+\.md)/.exec(text)
  if (!m) return ''
  try {
    const rel = toSlash(m[1] ?? '')
    const isAbs = /^([A-Za-z]:)?\//.test(rel)
    const cwd = await $.session.cwd().catch(() => '')
    const path = isAbs ? rel : `${toSlash(cwd).replace(/\/$/, '')}/${rel.replace(/^\.?\//, '')}`
    return await $.fs.read(path)
  } catch {
    return ''
  }
}

/** 첫 요청(세션 프롬프트)에서 목적·단계 뽑기 */
async function deriveSession($: EngineInterface, text: string) {
  const file = await readPromptFile($, text)
  const heading = file ? lines(file).map(l => l.trim()).find(l => /^#\s+\S/.test(l)) : undefined
  const purpose = heading ? cut(heading.replace(/^#\s+/, ''), PURPOSE_COLS) : cut(stripMark(firstLine(text)), PURPOSE_COLS)
  let steps = file ? findSteps(file, true) : []
  if (steps.length === 0) steps = findSteps(text, false)
  baseTokens = tokens([purpose, ...steps.map(s => s.name), text].join(' '))
  return { purpose, steps }
}

/** 글이 어느 단계까지 끝났다고 말하는지(0이면 없음): 단계 이름이 나오거나 "N단계 끝/완료/마침" */
const doneUpTo = (text: string, steps: Step[]) => {
  let upTo = 0
  steps.forEach((step, i) => {
    const name = step.name.replace(/…$/, '').trim()
    const named = name.length >= 2 && text.includes(name)
    const said = new RegExp(`(?:^|\\D)${i + 1}\\s*단계\\s*(?:는|를|은|이|가|도)?\\s*(끝|완료|마침|마쳤)`).test(text)
    if (named || said) upTo = i + 1
  })
  return upTo
}

const markDone = (steps: Step[], upTo: number) =>
  upTo > 0 ? steps.map((s, i) => (i < upTo ? { ...s, isDone: true } : s)) : steps

export const registerSession = (on: On) => {
  on('prompt.submit', { origin: { kind: [...USER_ORIGINS] } }, async ($, e, next) => {
    try {
      if (!e.command && !e.isMeta && e.text.trim()) {
        const info = await read($, sessionInfo)
        const text = e.text
        const latest = cut(firstLine(text), PURPOSE_COLS)
        const latestFull = text.replace(/\s+/g, ' ').trim().slice(0, FULL_CHARS)
        let patch: Partial<SessionInfo>
        if (info.promptCount === 0) {
          patch = { ...(await deriveSession($, text)), isOffTopic: false, purposeFull: latestFull }
        } else {
          if (baseTokens.length === 0) baseTokens = tokens([info.purpose, ...info.steps.map(s => s.name)].join(' '))
          const mine = tokens(text)
          const isOffTopic = mine.length >= MIN_TOKENS && !mine.some(t => baseTokens.some(b => overlaps(t, b)))
          patch = { isOffTopic, steps: markDone(info.steps, doneUpTo(text, info.steps)) }
        }
        await update($, sessionInfo, cur => ({ ...cur, ...patch, latest, latestFull, isWorking: true, promptCount: cur.promptCount + 1 }))
      }
    } catch {
      // 상태 갱신이 실패해도 요청은 그대로 들어간다
    }
    return next(e)
  })

  // 대화 기록 줄 id: 요청·답변 줄이 저장될 때 그 id를 적어 둔다(옆 창에서 누르면 그 자리로 스크롤).
  // 같은 줄에 "[목적] …"이 있으면 목적을 그 한 줄로 바꾼다(모델이 이해한 의도, 또는 사용자가 직접 친 것).
  on('session.append', { door: ['prompt', 'response'] }, async ($, e, next) => {
    const stored = await next(e)
    try {
      if (e.agentId === undefined && !e.message.isMeta) {
        const text = e.message.content
          .map(b => (b.type === 'text' && typeof b.text === 'string' ? b.text : ''))
          .join('\n')
        const purpose = purposeLine(text)
        const status = statusLine(text)
        const nextPrompt = nextPromptLine(text)
        const named = stepsLine(text)
        await update($, sessionInfo, cur => {
          // [단계] 줄이 있으면 단계 목록을 그걸로(같은 이름의 끝남 표시는 유지)
          let steps = named.length
            ? named.map(name => ({ name: cut(name, STEP_COLS), isDone: cur.steps.some(s => s.name === cut(name, STEP_COLS) && s.isDone) }))
            : cur.steps
          // [상태] n/m 의 n = 끝난 단계 수(단계 수가 m과 같을 때만)
          if (status?.progress && status.progress.total === steps.length) {
            steps = steps.map((s, i) => ({ ...s, isDone: i < status.progress!.done }))
          }
          return {
            ...cur,
            steps,
            ...(e.door === 'prompt'
              ? { latestRowId: stored.uuid, firstRowId: cur.firstRowId || stored.uuid, answerRowId: '' }
              : { answerRowId: cur.answerRowId || stored.uuid }),
            ...(purpose ? { purpose: cut(purpose, PURPOSE_COLS), purposeFull: purpose.slice(0, FULL_CHARS) } : {}),
            ...(status ? { status: status.status, progress: status.progress ?? cur.progress } : {}),
            ...(nextPrompt ? { nextPrompt } : {}),
          }
        })
      }
    } catch {
      // 줄 id를 못 적어도 기록은 그대로
    }
    return stored
  })

  // 답으로 끝난 턴만(reason 매처: 다른 모듈의 매처 없는 turn.complete 훅과 안 부딪침)
  on('turn.complete', { reason: 'answer' }, async ($, e, next) => {
    try {
      if (e.agentId === undefined && e.answer) {
        const info = await read($, sessionInfo)
        const upTo = doneUpTo(e.answer, info.steps)
        const answer = cut(firstSentence(e.answer), 120)
        const answerFull = e.answer.replace(/\s+/g, ' ').trim().slice(0, FULL_CHARS)
        await update($, sessionInfo, cur => ({
          ...cur,
          answer,
          answerFull,
          isWorking: false,
          steps: upTo > 0 ? markDone(cur.steps, upTo) : cur.steps,
        }))
      }
    } catch {
      // 답변 표시는 그대로
    }
    return next(e)
  })
}
