// 옆 창 = 이 세션의 상태 창(2026-11-04 사용자 재정의):
//   목적(모델이 적은 한 줄) · 상태(구상 중/진행 중/끝 + 진행도) · 단계(●○)
//   버튼 줄: ▲ 내 말(마지막 요청으로 스크롤) · ▲ 답변 · 다음 프롬프트 복사
//   작업물: 파일이 있는 폴더(열기) + 그 밑 파일 몇 개 · 웹 주소
//   고칠 것
// 세 상태(session·files·todos)와 last를 읽고, 쓰는 건 버튼 핸들러에서 last·todos(isDone)뿐.
// 모델 호출 없음. 상대 창(opencode-sidebar)이 있으면 그 안에 합치고 Recent·Cache 칸을 뺀다.
import { atom, read, update } from 'claude-code'
import type { On, PluginOptions, RenderElement, RenderNode } from 'claude-code'

import type { MadeFile, SessionInfo, Todo } from '../types'
import { EMPTY_SESSION, PANE_ID, PANE_TITLE, cut, hhmm, rowRenderId, splitList } from './state'
import { openPath, parentOf } from './open'

// 엔진 검사기: read/update에 넘기는 atom은 같은 파일 안의 const(plugin·key 글자 그대로)여야 한다.
const sessionInfo = atom({ plugin: 'session-pane', key: 'session' } as const, EMPTY_SESSION)
const files = atom({ plugin: 'session-pane', key: 'files' } as const, [] as MadeFile[], { shape: 'files-1' })
const todos = atom({ plugin: 'session-pane', key: 'todos' } as const, [] as Todo[], { shape: 'todos-1' })
const last = atom({ plugin: 'session-pane', key: 'last' } as const, '')

/** 합칠 상대 창(opencode-sidebar의 Session 창) id 조각 — 설정 hostPane, 비우면 합치지 않고 우리 창만 */
let HOST_PANE = 'opencode-sidebar'
/** 상대 창에서 뺄 칸의 머리글 — 설정 hideHostSections(쉼표 목록, 기본 없음) */
let HOST_DROP_SECTIONS: string[] = []
/** 합치기가 이만큼 안 일어나면 우리 창을 따로 연다 */
const MERGE_WAIT_MS = 4000
/** 결과 줄(last)을 잠깐만 보여 주고 지운다 */
const RESULT_SHOW_MS = 5000
/** 작업물 칸: 폴더 수와 폴더마다 보이는 파일 수 */
const MAX_FOLDERS = 4
const FILES_PER_FOLDER = 3
let isMerged = false

/** 화면 칸 수(한글·전각 2칸). state.ts의 cut과 같은 기준. */
const colsOf = (s: string) => {
  let w = 0
  for (const ch of s) w += /[ᄀ-ᇿ　-〿가-힯一-鿿＀-￯]/.test(ch) ? 2 : 1
  return w
}
const pad = (cols: number) => (cols > 0 ? ' '.repeat(cols) : '')

/** 폭에 맞춰 최대 maxLines줄로 나눔(마지막 줄은 cut으로 "…"). 낱말 경계를 되도록 지킨다. */
const wrapCols = (text: string, cols: number, maxLines: number) => {
  const words = text.replace(/\s+/g, ' ').trim().split(' ')
  const lines: string[] = []
  let cur = ''
  for (const w of words) {
    const tryLine = cur ? cur + ' ' + w : w
    if (colsOf(tryLine) <= cols) {
      cur = tryLine
      continue
    }
    if (cur) lines.push(cur)
    cur = w
    if (lines.length === maxLines - 1) break
  }
  if (cur) lines.push(cur)
  const rest = words.join(' ')
  if (lines.length > maxLines) lines.length = maxLines
  const lastLine = lines[lines.length - 1] ?? ''
  const used = lines.join(' ')
  if (used.length < rest.length || colsOf(lastLine) > cols) lines[lines.length - 1] = cut(rest.slice(used.length - lastLine.length), cols)
  return lines
}

/** 고칠 것 한 줄의 앞 글자: 끝남 → ✓, 확인 필요 → ·, 나머지(model·skills) → ! */
const todoMark = (todo: Todo) => (todo.isDone ? '✓' : todo.kind === 'confirm' ? '·' : '!')
/** 지난 세션 줄 앞에 "지난: " — 글이 이미 "지난 세션"으로 시작하면 안 붙임 */
const todoText = (todo: Todo) =>
  todo.isPrevious && !todo.text.startsWith('지난 세션') ? `지난: ${todo.text}` : todo.text

/** 상태 글과 색: 모델이 적은 [상태]가 먼저, 없으면 단계·작업물로 짐작 */
const statusOf = (info: SessionInfo, fileCount: number) => {
  const done = info.steps.filter(s => s.isDone).length
  const total = info.steps.length
  const progress = info.progress ?? (total > 0 ? { done, total } : null)
  let word: string = info.status
  if (!word) {
    if (total > 0 && done === total) word = '끝'
    else if (done > 0 || fileCount > 0) word = '진행 중'
    else word = '구상 중'
  }
  const color = word === '끝' ? 'success' : word === '진행 중' ? 'claude' : undefined
  const bar = progress
    ? '▰'.repeat(Math.min(progress.total, Math.max(0, progress.done))) +
      '▱'.repeat(Math.max(0, progress.total - progress.done)) +
      ` ${progress.done}/${progress.total}`
    : ''
  return { word, color, bar }
}

/** 상대 창 트리에서 머리글이 HOST_DROP_SECTIONS인 칸(Box)을 뺀다 */
const dropSections = (node: RenderNode): RenderNode => {
  if (typeof node === 'string' || node.type !== 'Box' || !node.children) return node
  const kept = node.children.filter(child => {
    if (typeof child === 'string' || child.type !== 'Box') return true
    const head = child.children?.[0]
    if (!head || typeof head === 'string' || head.type !== 'Text') return true
    const title = (head.children ?? []).filter((c): c is string => typeof c === 'string').join('').trim()
    return !HOST_DROP_SECTIONS.some(name => title === name || title.startsWith(name + ' '))
  })
  return { ...node, children: kept }
}

/** 작업물을 폴더별로 묶는다(새것 먼저). 웹 주소는 따로. */
const groupByFolder = (list: MadeFile[]) => {
  const sorted = [...list].sort((a, b) => (a.at < b.at ? 1 : a.at > b.at ? -1 : 0))
  const folders = new Map<string, { dir: string; at: string; files: MadeFile[]; isPrevious: boolean }>()
  const webs: MadeFile[] = []
  for (const f of sorted) {
    if (f.kind === 'web') {
      webs.push(f)
      continue
    }
    const dir = parentOf(f.path)
    const key = dir.toLowerCase()
    const g = folders.get(key) ?? { dir, at: f.at, files: [], isPrevious: true }
    g.files.push(f)
    if (!f.isPrevious) g.isPrevious = false
    folders.set(key, g)
  }
  return { folders: [...folders.values()].slice(0, MAX_FOLDERS), webs: webs.slice(0, 3) }
}

/** 폴더 이름: 뒤 두 토막("개발 기준서\TB310") */
const folderLabel = (dir: string) => {
  const parts = dir.split(/[\\/]/).filter(Boolean)
  return parts.slice(-2).join('\\') || dir
}

export const registerPane = (on: On, options: PluginOptions = {}) => {
  if (typeof options.hostPane === 'string') HOST_PANE = options.hostPane.trim()
  if (typeof options.hideHostSections === 'string') HOST_DROP_SECTIONS = splitList(options.hideHostSections)
  // 매처를 둔 까닭: 한 모듈 안에 매처 없는 session.start가 둘이면(files.ts에도 하나) 엔진이 거부한다.
  on('session.start', { isInteractive: true }, async ($, e, next) => {
    await $.command.register({ name: 'session-pane', description: '이 세션 상태 창 열기' })
    await update($, last, () => '').catch(() => undefined) // 전 판이 남긴 결과 글은 지운다
    const started = await next(e)
    // 상대 창에 합쳐지면 따로 안 연다. 몇 초 기다려도 합쳐지지 않으면(그 모드가 없는 PC) 우리 창.
    void (async () => {
      try {
        await $.clock.sleep(MERGE_WAIT_MS)
        if (!isMerged) await $.ui.open({ id: PANE_ID, title: PANE_TITLE })
      } catch {}
    })()
    return started
  })

  on('command.run', { command: 'session-pane' }, async $ => {
    if (isMerged) return { text: '이 세션 칸은 Session 옆 창(ctrl+x tab)에 합쳐져 있어요.' }
    await $.ui.open({ id: PANE_ID, title: PANE_TITLE })
    return { text: '이 세션 상태 창을 열었어요.' }
  })

  on('ui.render', { component: 'Pane' }, async ($, e, next) => {
    const isMine = e.requestId === PANE_ID
    const isHost = !isMine && HOST_PANE !== '' && e.requestId.includes(HOST_PANE)
    if (!isMine && !isHost) return next(e)

    const { Box, Text, Button, Link } = $.ui.resolve(e)
    const width = e.props.bodyColumns || e.viewport?.columns || 40
    const inner = Math.max(20, width - 3) // "│ " + 글 + "│"

    const info = await read($, sessionInfo)
    const madeFiles = await read($, files)
    const todoList = await read($, todos)
    const note = await read($, last)

    // ── 핸들러: 누를 때만 last를 쓴다 ──
    const flash = async (text: string) => {
      const shown = cut(text, inner)
      await update($, last, () => shown)
      try {
        await $.clock.sleep(RESULT_SHOW_MS)
        await update($, last, cur => (cur === shown ? '' : cur))
      } catch {}
    }
    const openWith = (name: string, path: string) => async () => {
      await update($, last, () => cut(`여는 중… ${name}`, inner))
      const result = await openPath($, path)
      await flash(result.isOpened ? `열었어요: ${name}` : `못 열었어요: ${name} (${result.detail})`)
    }
    const goTo = (what: string, rowId: string) => async () => {
      if (!rowId) return flash(`${what}: 아직 기록 줄이 없어요`)
      const target = rowRenderId(rowId)
      const moved = await $.ui.scroll({ to: { requestId: target }, block: 'center' }).catch(err => ({ deny: String(err) }))
      if ('deny' in moved && moved.deny) await flash(`${what}: 못 움직임 (${moved.deny})`)
    }
    const copyNext = async () => {
      const r = await $.ui.copy({ text: info.nextPrompt }).catch(err => ({ isCopied: false as const, reason: String(err) }))
      await flash(r.isCopied ? '다음 프롬프트를 복사했어요' : `복사 못 함 (${'reason' in r ? r.reason : ''})`)
    }
    const toggleTodo = (id: string) => () =>
      update($, todos, list => list.map(one => (one.id === id ? { ...one, isDone: !one.isDone } : one)))

    // ── 상자 줄 도우미 ──
    const top = (title: string) => `┌ ${title} ` + '─'.repeat(Math.max(1, width - colsOf(`┌ ${title} `) - 1)) + '┐'
    const sep = (title: string) => `├ ${title} ` + '─'.repeat(Math.max(1, width - colsOf(`├ ${title} `) - 1)) + '┤'
    const bottom = '└' + '─'.repeat(Math.max(1, width - 2)) + '┘'
    const rows: RenderNode[] = []
    /** 글만 있는 줄 */
    const textRow = (node: RenderNode, cols: number) =>
      rows.push(
        <Box flexDirection="row">
          <Text>│ </Text>
          {node}
          <Text>{pad(inner - cols)}│</Text>
        </Box>,
      )
    /** "라벨  글" 줄, 글은 최대 maxLines줄(둘째 줄부터 라벨 자리 비움) */
    const labelRows = (label: string, labelNode: RenderNode, text: string, maxLines: number, dim = false) => {
      wrapCols(text, inner - 6, maxLines).forEach((line, i) => {
        textRow(
          <Text>
            {i === 0 ? labelNode : pad(colsOf(label))}
            {pad(6 - colsOf(label))}
            {dim ? <Text dimColor>{line}</Text> : line}
          </Text>,
          6 + colsOf(line),
        )
      })
    }

    rows.push(<Text>{top('이 세션')}</Text>)

    // 목적: 모델이 적은 "[목적] …"(없으면 첫 요청 첫 줄), 최대 2줄
    labelRows('목적', <Text weight="bold">목적</Text>, info.purpose || '프롬프트 없이 시작', 2, !info.purpose)

    // 상태: 작업 중(모델이 도는 중) 표시 + 구상 중/진행 중/끝 + 진행도 막대
    {
      const { word, color, bar } = statusOf(info, madeFiles.filter(f => !f.isPrevious).length)
      const spin = info.isWorking ? '▸ ' : ''
      const text = `${spin}${word}${bar ? '  ' + bar : ''}`
      textRow(
        <Text>
          <Text weight="bold">상태</Text>
          {'  '}
          <Text color={color}>
            {spin}
            {word}
          </Text>
          {bar ? <Text dimColor>{'  ' + bar}</Text> : ''}
        </Text>,
        6 + colsOf(text),
      )
    }

    // 단계: ● 끝남(초록) ○ 남음(흐림). 폭을 넘으면 거기서 끊고 "…". 없으면 흐리게 "아직 없음".
    if (info.steps.length === 0) {
      textRow(
        <Text>
          <Text weight="bold">단계</Text>
          {'  '}
          <Text dimColor>아직 없음</Text>
        </Text>,
        6 + colsOf('아직 없음'),
      )
    } else {
      const parts: Array<{ text: string; isDone: boolean }> = []
      let cols = 6
      let isCut = false
      for (const step of info.steps) {
        const text = `${step.isDone ? '●' : '○'} ${step.name}`
        const need = colsOf(text) + (parts.length ? 1 : 0)
        if (cols + need > inner - 1) {
          isCut = true
          break
        }
        parts.push({ text, isDone: step.isDone })
        cols += need
      }
      textRow(
        <Text>
          <Text weight="bold">단계</Text>
          {'  '}
          {parts.map((part, i) => (
            <Text color={part.isDone ? 'success' : undefined} dimColor={!part.isDone}>
              {i ? ' ' : ''}
              {part.text}
            </Text>
          ))}
          {isCut && <Text dimColor>…</Text>}
        </Text>,
        cols + (isCut ? 1 : 0),
      )
    }

    // 버튼 줄: ▲ 내 말 · ▲ 답변 · 다음 프롬프트 복사(있을 때만)
    {
      const b1 = '▲ 내 말'
      const b2 = '▲ 답변'
      const b3 = '⧉ 다음 프롬프트 복사'
      const hasNext = info.nextPrompt !== ''
      const cols = colsOf(b1) + 2 + colsOf(b2) + (hasNext ? 2 + colsOf(b3) : 0)
      rows.push(
        <Box flexDirection="row">
          <Text>│ </Text>
          <Button key="go:latest" plain dimColor={!info.latestRowId} onPress={goTo('내 말', info.latestRowId)}>
            {b1}
          </Button>
          <Text>{'  '}</Text>
          <Button key="go:answer" plain dimColor={!info.answerRowId} onPress={goTo('답변', info.answerRowId)}>
            {b2}
          </Button>
          {hasNext ? <Text>{'  '}</Text> : ''}
          {hasNext ? (
            <Button key="copy:next" plain onPress={copyNext}>
              <Text color="claude">{b3}</Text>
            </Button>
          ) : (
            ''
          )}
          <Text>{pad(inner - cols)}│</Text>
        </Box>,
      )
    }

    // 작업물: 폴더(열기) + 그 밑 파일 몇 개, 웹 주소
    rows.push(<Text>{sep('작업물')}</Text>)
    const { folders, webs } = groupByFolder(madeFiles)
    if (folders.length === 0 && webs.length === 0) textRow(<Text dimColor>아직 없음</Text>, colsOf('아직 없음'))
    for (const g of folders) {
      const time = hhmm(g.at)
      const tail = `  [폴더]  ${time}`
      const label = cut(folderLabel(g.dir), Math.max(4, inner - 2 - colsOf(tail)))
      rows.push(
        <Box flexDirection="row">
          <Text>│ ▸ </Text>
          <Button key={'dir:' + g.dir} plain dimColor={g.isPrevious} onPress={openWith(folderLabel(g.dir), g.dir)}>
            <Text weight="bold">{label}</Text>
          </Button>
          <Text dimColor>{tail}</Text>
          <Text>{pad(inner - 2 - colsOf(label) - colsOf(tail))}│</Text>
        </Box>,
      )
      for (const f of g.files.slice(0, FILES_PER_FOLDER)) {
        const name = cut(f.name, Math.max(4, inner - 4))
        rows.push(
          <Box flexDirection="row">
            <Text>│     </Text>
            <Button key={'open:' + f.path} plain dimColor={f.isPrevious === true} onPress={openWith(name, f.path)}>
              {name}
            </Button>
            <Text>{pad(inner - 4 - colsOf(name))}│</Text>
          </Box>,
        )
      }
      if (g.files.length > FILES_PER_FOLDER) {
        const more = `    … 외 ${g.files.length - FILES_PER_FOLDER}개`
        textRow(<Text dimColor>{more}</Text>, colsOf(more))
      }
    }
    for (const w of webs) {
      const time = hhmm(w.at)
      const tail = `  [링크]  ${time}`
      const name = cut(w.name, Math.max(4, inner - colsOf(tail)))
      rows.push(
        <Box flexDirection="row">
          <Text>│ </Text>
          <Text dimColor={w.isPrevious === true}>
            <Link href={w.path}>{name}</Link>
          </Text>
          <Text dimColor>{tail}</Text>
          <Text>{pad(inner - colsOf(name) - colsOf(tail))}│</Text>
        </Box>,
      )
    }

    // 고칠 것
    if (todoList.length > 0) {
      rows.push(<Text>{sep('고칠 것')}</Text>)
      for (const todo of todoList) {
        const dim = todo.isDone || todo.isPrevious === true
        const isWarn = !dim && todo.kind !== 'confirm'
        const mark = todoMark(todo)
        const text = cut(todoText(todo), inner - 2)
        rows.push(
          <Box flexDirection="row">
            <Text>│ </Text>
            <Button key={todo.id} plain dimColor={dim} onPress={toggleTodo(todo.id)}>
              {isWarn ? <Text color="warning">{mark}</Text> : mark}
              {' '}
              {text}
            </Button>
            <Text>{pad(inner - 2 - colsOf(text))}│</Text>
          </Box>,
        )
      }
    }

    if (note) {
      const text = cut(note, inner)
      textRow(<Text dimColor>{text}</Text>, colsOf(text))
    }
    rows.push(<Text>{bottom}</Text>)

    const mine = <Box flexDirection="column">{rows}</Box>
    if (isMine) return mine

    // 합치기: 상대 창 트리의 Recent·Cache 칸을 빼고 우리 상자를 밑에 붙인다.
    let host: RenderElement
    try {
      host = await next(e)
    } catch {
      return next(e)
    }
    if (typeof host !== 'object' || host.type !== 'Box') return host
    if (!isMerged) {
      isMerged = true
      // 전 판이 따로 열어 둔 우리 창(탭)이 있으면 닫는다 — 합쳐졌으니 탭이 둘일 까닭이 없다.
      void $.ui.panes().then(list => (list.some(p => p.id === PANE_ID) ? $.ui.close({ id: PANE_ID }) : undefined)).catch(() => {})
    }
    const trimmed = dropSections(host) as RenderElement
    return (
      <Box flexDirection="column">
        {trimmed}
        {mine}
      </Box>
    )
  }).catch(($, e, next) => next(e))
}
