// "고칠 것" 칸: ① 답변 속 `[고칠 것] …` 줄 ② 턴 끝 git status의 skills/ 밑 커밋 안 된 변경 ③ 이 세션에서 늘어난 [확인 필요] 줄.
// 세션을 닫으려 할 때(/exit·/quit·/clear) 남아 있으면 한 번 막고 묻는다. 다음 세션으로 $.store로 넘긴다.
// 담당: 에이전트 C. todos atom만 쓴다. 모델 호출은 없다(시스템 프롬프트 한 줄만 더한다).
// 막기는 두 곳: command.run(실제로 명령을 안 돌리는 관문)과 prompt.submit(drop). 어느 쪽이 먼저 오든 한 번만 묻는다.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, On } from 'claude-code'

import type { Todo } from '../types'
import { STORE_KEY, cut, toSlash } from './state'

const todos = atom({ plugin: 'session-pane', key: 'todos' } as const, [] as Todo[], { shape: 'todos-1' })

const GUARD_ID = 'session-pane-guard'
const CLOSE_COMMANDS = ['exit', 'quit', 'clear'] as const
const MARKER = '[고칠 것]'
const MARKER_RE = /^\s*\[고칠 것\]\s*(.+)$/gm
const CONFIRM = '[확인 필요]'
const PREVIOUS = '지난 세션: '
const PROMPT_LINE =
  '옆 창(session-pane) 표시 줄 규칙 — 답변 끝에 아래 꼴의 줄을 적으면 옆 창(상태 창)이 모아 보여 준다. 각 줄은 한 줄이고 백틱 없이. ' +
  '① `[목적] …` 세션 첫 답변에서 사용자가 이 세션에서 이루려는 것을 네가 이해한 쉬운 말 한 줄(목적이 바뀌면 다시). ' +
  '②-1 `[단계] 조사, 고침, 시험, 회고` 세션 첫 답변에서 이번 일을 2~6개 단계 이름(짧게)으로 나눠 적고, 단계가 바뀌면 다시 적는다. ' +
  '② `[상태] 구상 중|진행 중|끝 n/m` 상태가 바뀔 때마다(구상 중 = 아직 만들거나 고치지 않고 의논·설계 중, 진행 중 = 파일을 만들거나 고치는 중, 끝 = 이번 일이 끝나 회고·커밋까지 됨). n/m은 알 때만(m은 [단계] 수, n은 끝난 단계 수). ' +
  '③ `[다음 프롬프트] …` 일이 끝났거나 새 세션이 필요할 때, 사용자가 다음 세션에 그대로 붙여 넣을 한 줄. ' +
  '④ `[고칠 것] …` 도구·스킬·규칙을 고쳐야 할 것을 알게 됐지만 지금 고치지 않을 때 한 줄.'

// 모듈 변수: 핫 리로드면 사라져도 되는 것만(cwd는 session.start가 다시 준다)
let cwd = ''
let baseline: number | null = null // 세션 시작 때 [확인 필요] 수
let isBypassed = false // "그래도 닫기"를 누른 뒤 같은 명령을 다시 돌리는 동안 true
let isGuardOpen = false // 안내 창이 떠 있는 동안 true
let isJustGuarded = false // command.run이 막은 직후, 같은 줄의 prompt.submit은 한 번 더 묻지 않게
let pendingCommand: string | null = null // 막힌 명령 이름(그래도 닫기가 다시 돌림)

const simpleHash = (s: string) => {
  let h = 5381
  for (const ch of s) h = ((h * 33) ^ (ch.codePointAt(0) ?? 0)) >>> 0
  return h.toString(36)
}

const isOpen = (t: Todo) => !t.isDone
const isTodo = (v: unknown): v is Todo => {
  const t = v as Partial<Todo> | null
  return typeof t?.id === 'string' && typeof t.text === 'string' && (t.kind === 'model' || t.kind === 'skills' || t.kind === 'confirm')
}

const textOf = (content: readonly { type: string; [k: string]: unknown }[]) =>
  content.map(b => (b.type === 'text' && typeof b.text === 'string' ? b.text : '')).join('\n')

/** 답변 글에서 [고칠 것] 줄을 뽑아 todos에 더한다(같은 id는 안 더함) */
const addModelTodos = async ($: EngineInterface, text: string) => {
  if (!text.includes(MARKER)) return
  const found = new Map<string, Todo>()
  for (const m of text.matchAll(MARKER_RE)) {
    const line = m[1].trim()
    if (!line) continue
    const id = 'model:' + simpleHash(line)
    found.set(id, { id, kind: 'model', text: cut(line, 36), isDone: false })
  }
  if (found.size === 0) return
  await update($, todos, list => {
    const have = new Set(list.map(t => t.id))
    return [...list, ...[...found.values()].filter(t => !have.has(t.id))]
  })
}

/** git status --porcelain 글에서 skills/<이름>/ 밑 변경을 세어 skills todo로 */
const skillTodos = (porcelain: string): Todo[] => {
  const counts = new Map<string, number>()
  for (const line of porcelain.split(/\r?\n/)) {
    if (line.length < 4) continue
    let path = line.slice(3).trim() // "XY 경로" 또는 "XY 옛 경로 -> 새 경로"
    const arrow = path.indexOf(' -> ')
    if (arrow >= 0) path = path.slice(arrow + 4)
    path = toSlash(path.replace(/^"|"$/g, ''))
    const m = /^skills\/([^/]+)\//.exec(path)
    if (m) counts.set(m[1], (counts.get(m[1]) ?? 0) + 1)
  }
  return [...counts].map(([name, n]) => ({ id: 'skills:' + name, kind: 'skills', text: `skills/${name} 고침 ${n}개 커밋 안 됨`, isDone: false }))
}

const refreshSkills = async ($: EngineInterface) => {
  let out: string
  try {
    const r = await $.process.run(['git', 'status', '--porcelain'], { cwd, timeoutMs: 10_000 })
    if (r.exitCode !== 0) return
    out = r.stdout
  } catch {
    return
  }
  const fresh = skillTodos(out)
  await update($, todos, list => {
    const old = new Map(list.filter(t => t.kind === 'skills').map(t => [t.id, t]))
    const kept = list.filter(t => t.kind !== 'skills')
    // 글(개수)이 그대로면 사용자가 ✓한 것도 유지, 바뀌면 새로
    return [...kept, ...fresh.map(t => (old.get(t.id)?.text === t.text ? old.get(t.id)! : t))]
  })
}

/** 백틱 안(인라인·펜스)을 지운 뒤 [확인 필요] 수 */
const countOutsideCode = (md: string) =>
  md.replace(/```[\s\S]*?(?:```|$)/g, '').replace(/`[^`\n]*`/g, '').split(CONFIRM).length - 1

const countConfirm = async ($: EngineInterface): Promise<number | null> => {
  const dir = toSlash(cwd).replace(/\/$/, '') + '/docs/domain'
  try {
    let n = 0
    for (const en of await $.fs.list(dir)) {
      if (en.kind !== 'file' || !en.name.endsWith('.md')) continue
      const text = await $.fs.read(dir + '/' + en.name).catch(() => '')
      n += countOutsideCode(typeof text === 'string' ? text : '')
    }
    return n
  } catch {
    return null
  }
}

const refreshConfirm = async ($: EngineInterface) => {
  if (baseline === null) return
  const now = await countConfirm($)
  if (now === null) return
  const n = now - baseline
  await update($, todos, list => {
    const rest = list.filter(t => t.id !== 'confirm')
    return n > 0 ? [...rest, { id: 'confirm', kind: 'confirm', text: `${CONFIRM} 새 줄 ${n}`, isDone: false }] : rest
  })
}

/** 닫기 명령을 막아야 하면 남은 건수(>0)를 돌려주고 안내 창을 연다. 아니면 0. */
const guard = async ($: EngineInterface, name: string): Promise<number> => {
  if (isBypassed || !(CLOSE_COMMANDS as readonly string[]).includes(name)) return 0
  const n = (await read($, todos)).filter(isOpen).length
  if (n === 0) return 0
  pendingCommand = name
  if (!isGuardOpen) {
    const opened = await $.ui.open({ id: GUARD_ID, title: '고칠 것 남음', focus: true, closeOnEscape: true, rows: 8 })
    if (!opened.isPlaced) {
      // 창을 못 그리면 막지 않는다(사용자가 갇히지 않게). 알림만.
      $.ui.toast(`고칠 것 ${n}건 남음`)
      return 0
    }
    isGuardOpen = true
  }
  return n
}

export const registerTodos = (on: On) => {
  on('session.start', async ($, e, next) => {
    cwd = e.cwd
    isBypassed = false
    isGuardOpen = false
    isJustGuarded = false
    try {
      const saved = await $.store.get(STORE_KEY(cwd, 'todos'))
      if (Array.isArray(saved) && saved.length > 0) {
        const prev: Todo[] = saved.filter(isTodo).map(t => ({
          ...t,
          isDone: false,
          isPrevious: true,
          text: t.text.startsWith(PREVIOUS) ? t.text : PREVIOUS + t.text,
        }))
        if (prev.length > 0) await update($, todos, list => (list.length === 0 ? prev : list))
      }
    } catch {}
    baseline = await countConfirm($)
    return next(e)
  })

  // 모델 표식 ①: 시스템 프롬프트 한 줄
  on('prompt.compose', async ($, e, next) => {
    const r = await next(e)
    return { sections: [...r.sections, { id: 'session-pane:todo-marker', text: PROMPT_LINE, scope: 'session' as const }] }
  })

  // 모델 표식 ①: 답변의 글 블록마다(중간 답변도) 줄을 모은다. 줄은 그대로 넘긴다.
  on('session.append', { door: 'response' }, async ($, e, next) => {
    const stored = await next(e)
    if (!e.agentId) await addModelTodos($, textOf(e.message.content)).catch(() => {})
    return stored
  })

  on('turn.complete', async ($, e, next) => {
    if (!e.agentId) {
      await addModelTodos($, e.answer).catch(() => {}) // 마지막 답변도 한 번 더(중복은 id로 걸러짐)
      await refreshSkills($).catch(() => {}) // ② skills/ 커밋 안 된 변경
      await refreshConfirm($).catch(() => {}) // ③ 늘어난 [확인 필요]
    }
    return next(e)
  })

  // 다음 세션으로: 안 끝난 것만 $.store에. 예산이 짧아 store.set 하나만 한다.
  // confirm 종류는 세션마다 기준이 새로 잡히므로 넘기지 않는다.
  on('session.end', async ($, e, next) => {
    try {
      const open = (await read($, todos))
        .filter(t => isOpen(t) && t.kind !== 'confirm')
        .map(({ id, kind, text }) => ({ id, kind, text, isDone: false }))
      await $.store.set(STORE_KEY(cwd, 'todos'), open)
    } catch {}
    return next(e)
  })

  // 닫기 관문 ①: command.run — next를 안 부르면 명령이 안 돌아간다.
  on('command.run', { command: CLOSE_COMMANDS }, async ($, e, next) => {
    try {
      const n = await guard($, e.command)
      if (n > 0) {
        isJustGuarded = true
        return { text: `고칠 것 ${n}건 남음 — 옆 창에서 "그래도 닫기" 또는 "취소"를 고르세요.` }
      }
    } catch {}
    return next(e)
  }).catch(($, e, next) => next(e))

  // 닫기 관문 ②: prompt.submit — 명령 줄이면 drop. command.run이 방금 막았으면 또 묻지 않는다.
  on('prompt.submit', async ($, e, next) => {
    const name = e.command?.name
    if (name !== undefined) {
      try {
        if (isJustGuarded) {
          isJustGuarded = false
        } else {
          const n = await guard($, name)
          if (n > 0) return { drop: `고칠 것 ${n}건 남음` }
        }
      } catch {}
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  on('ui.close', { id: GUARD_ID }, ($, e, next) => {
    isGuardOpen = false
    return next(e)
  })

  // 안내 창: 남은 것 최대 5줄 + [그래도 닫기] [취소]. todo.ts라 JSX 대신 h()로 그린다.
  on('ui.render', { component: 'Pane', requestId: GUARD_ID }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const open = (await read($, todos)).filter(isOpen)
    const close = async () => {
      isGuardOpen = false
      await $.ui.close({ id: GUARD_ID }).catch(() => {})
    }
    const force = async () => {
      const name = pendingCommand
      isBypassed = true
      try {
        await close()
        if (name) await $.command.run({ command: name })
      } catch {
      } finally {
        isBypassed = false
      }
    }
    const rows = open.slice(0, 5).map(t => h(Text, { dimColor: t.isPrevious === true }, `· ${t.text}`))
    return h(
      Box,
      { flexDirection: 'column' },
      h(Text, { bold: true }, `고칠 것 ${open.length}건이 남았어요.`),
      ...rows,
      open.length > 5 ? h(Text, { dimColor: true }, `… 외 ${open.length - 5}건`) : null,
      h(
        Box,
        { gap: 1 },
        h(Button, { key: 'force', label: '그래도 닫기', variant: 'primary', onPress: force }),
        h(Button, { key: 'cancel', label: '취소', role: 'dismiss', onPress: close }),
      ),
    ) as ReturnType<typeof Box>
  })
}
