// "만든 파일" 칸: Write·Edit·NotebookEdit 대상, 셸(Bash·PowerShell)이 남긴 새 파일, Artifact 웹 주소를
// 모아 files atom에 넣고 $.store에도 남긴다(다음 세션에 흐리게 보여 줌). 모델 호출 없음.
// 담당: 에이전트 B. files atom만 쓴다. 열기는 open.ts.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, On, PluginOptions } from 'claude-code'

import type { MadeFile } from '../types'
import { HIDE_PATTERNS, MAX_FILES, STORE_KEY, WATCH_ROOTS, baseName, toSlash } from './state'

// 엔진 검사기 규칙: read/update에 넘기는 atom은 같은 파일 안의 const, plugin·key는 글자 그대로.
const files = atom({ plugin: 'session-pane', key: 'files' } as const, [] as MadeFile[], { shape: 'files-1' })

/** 상태에 남기는 최대 줄 수(화면은 MAX_FILES만 그림) */
const KEEP = 50
/** 셸 명령 하나에서 살펴볼 경로 후보 수 */
const MAX_CANDIDATES = 10
/** 셸 파일 mtime 비교 여유(밀리초). 파일 시스템 시각 해상도 때문에 조금 둔다. */
const MTIME_SLACK_MS = 1000

/** 세션 cwd. 핫 리로드로 비면 $.session.cwd()로 다시 채운다. */
let cwd = ''
/** 감시 폴더 설정(userConfig watchRoots·extraRoots) */
let watchRoots = 'docs'
let extraRoots = ''

const cwdOf = async ($: EngineInterface) => {
  if (!cwd) cwd = await $.session.cwd().catch(() => '')
  return cwd
}

type Ran = { deny?: string; isError?: true; text?: string; result?: unknown }
const isOk = (ran: Ran) => ran.deny === undefined && ran.isError !== true

const isMadeFile = (v: unknown): v is MadeFile =>
  typeof v === 'object' && v !== null &&
  typeof (v as MadeFile).path === 'string' && typeof (v as MadeFile).name === 'string' &&
  ((v as MadeFile).kind === 'file' || (v as MadeFile).kind === 'web') && typeof (v as MadeFile).at === 'string'

/** 슬래시 경로가 WATCH 뿌리 밑이고 숨길 조각이 없으면 true */
const isWatched = (slash: string, root: string) => {
  const lower = slash.toLowerCase()
  const roots = WATCH_ROOTS(root, watchRoots, extraRoots).map(r => r.toLowerCase().replace(/\/$/, ''))
  if (!roots.some(r => lower === r || lower.startsWith(r + '/'))) return false
  return !HIDE_PATTERNS.some(re => re.test(slash))
}

/** 상대 경로를 cwd 기준 절대 슬래시 경로로 */
const absSlash = (raw: string, root: string) => {
  const slash = toSlash(raw.trim())
  if (/^([A-Za-z]:\/|\/)/.test(slash)) return slash
  return toSlash(root).replace(/\/$/, '') + '/' + slash.replace(/^\.\//, '')
}

/** 저장할 꼴: 윈도 드라이브 경로면 역슬래시, 그 밖(맥·리눅스)은 그대로 */
const storedPath = (slash: string) => (/^[A-Za-z]:\//.test(slash) ? slash.replace(/\//g, '\\') : slash)

/** 한 줄 넣기: 같은 경로(대소문자 무시)면 맨 위로 올리고 시각만 새로(알림 없음), 새 줄이면 맨 위 + 알림 */
const add = async ($: EngineInterface, entry: MadeFile) => {
  let isNew = false
  const list = await update($, files, cur => {
    const key = entry.path.toLowerCase()
    const rest = cur.filter(f => f.path.toLowerCase() !== key)
    isNew = rest.length === cur.length
    return [entry, ...rest].slice(0, KEEP)
  })
  if (isNew) {
    try { $.ui.toast('만듦: ' + entry.name) } catch { /* 알림 실패는 무시 */ }
  }
  const root = await cwdOf($)
  await $.store.set(STORE_KEY(root, 'files'), list.slice(0, MAX_FILES)).catch(() => undefined)
}

/** 파일 경로 하나 기록(감시 뿌리 밖·숨김 조각은 버림). 상대 경로는 cwd 기준. */
const recordFile = async ($: EngineInterface, raw: string) => {
  const root = await cwdOf($)
  const slash = absSlash(raw, root)
  if (!isWatched(slash, root)) return
  await add($, { path: storedPath(slash), name: baseName(slash), kind: 'file', at: new Date().toISOString() })
}

const recordWeb = async ($: EngineInterface, url: string, name: string) => {
  await add($, { path: url, name, kind: 'web', at: new Date().toISOString() })
}

/** 셸 명령 글에서 경로 후보 뽑기: 따옴표 안 절대 경로(띄어쓰기 허용), 맨 절대 경로, docs/ 상대 경로 */
const QUOTED_RES = [/"([A-Za-z]:[\\/][^"]+)"/g, /'([A-Za-z]:[\\/][^']+)'/g]
const BARE_RES = [/([A-Za-z]:[\\/][^\s"'<>|;&]+)/g, /(?:^|[\s"'=(])((?:\.\/)?docs\/[^\s"'<>|;&]+)/g]
export const pathCandidates = (command: string) => {
  const out: string[] = []
  const push = (raw: string) => {
    const p = raw.replace(/[),.:]+$/, '')
    if (p && !out.some(x => x.toLowerCase() === p.toLowerCase())) out.push(p)
    return out.length >= MAX_CANDIDATES
  }
  for (const re of QUOTED_RES) for (const m of command.matchAll(re)) if (push(m[1] ?? '')) return out
  // 따옴표 구간을 지운 뒤 맨 경로를 찾는다(따옴표 안 경로가 띄어쓰기에서 잘려 또 잡히는 것 막기)
  const bare = command.replace(/"[^"]*"|'[^']*'/g, ' ')
  for (const re of BARE_RES) for (const m of bare.matchAll(re)) if (push(m[1] ?? '')) return out
  return out
}

const CLAUDE_URL = /https:\/\/claude\.ai\/[^\s)\]"']+/

export const registerFiles = (on: On, options: PluginOptions = {}) => {
  if (typeof options.watchRoots === 'string' && options.watchRoots.trim()) watchRoots = options.watchRoots
  if (typeof options.extraRoots === 'string') extraRoots = options.extraRoots
  // 한 모듈에 matcher 없는 session.start는 하나만 허용(pane.tsx가 씀) → 늘 맞는 matcher를 붙인다.
  on('session.start', { isInteractive: [true, false] }, async ($, e, next) => {
    cwd = e.cwd
    const started = await next(e)
    // 지난 세션 목록을 흐리게 이어 보여 준다(atom이 비어 있을 때만, MAX_FILES까지)
    try {
      const cur = await read($, files)
      if (cur.length === 0) {
        const prev = await $.store.get(STORE_KEY(e.cwd, 'files'))
        const seed = (Array.isArray(prev) ? prev : []).filter(isMadeFile).slice(0, MAX_FILES)
          .map(f => ({ ...f, isPrevious: true as const }))
        if (seed.length > 0) await update($, files, now => (now.length === 0 ? seed : now))
      }
    } catch { /* 이어 보여 주기 실패는 무시 */ }
    return started
  })

  // Write·Edit·NotebookEdit: 성공했으면 그 파일을 기록
  on('tool.call', { tool: ['Write', 'Edit', 'NotebookEdit'] }, async ($, e, next) => {
    const ran = await next(e)
    try {
      if (isOk(ran)) {
        const input = e as unknown as { file_path?: string; notebook_path?: string }
        const p = String(e.tool) === 'NotebookEdit' ? input.notebook_path : input.file_path
        if (typeof p === 'string' && p) await recordFile($, p)
      }
    } catch { /* 기록 실패는 도구 결과에 영향 없음 */ }
    return ran
  }).catch((_$, e, next) => next(e)) // 훅이 죽어도 도구 결과는 그대로 흐른다

  // Bash·PowerShell: 명령 글 속 경로 후보 중 "명령 뒤에 고쳐진 파일"만 기록
  on('tool.call', { tool: ['Bash', 'PowerShell'] }, async ($, e, next) => {
    const before = Date.now()
    const ran = await next(e)
    try {
      if (isOk(ran)) {
        const root = await cwdOf($)
        for (const cand of pathCandidates(String((e as { command?: unknown }).command ?? ''))) {
          const slash = absSlash(cand, root)
          if (!isWatched(slash, root)) continue
          const st = await $.fs.stat(slash).catch(() => undefined)
          if (st && st.kind === 'file' && st.mtimeMs >= before - MTIME_SLACK_MS) await recordFile($, slash)
        }
      }
    } catch { /* 무시 */ }
    return ran
  }).catch((_$, e, next) => next(e)) // 훅이 죽어도 도구 결과는 그대로 흐른다

  // Artifact(publish): 결과 글의 claude.ai 주소를 웹 줄로 기록
  on('tool.call', { tool: 'Artifact' }, async ($, e, next) => {
    const ran = await next(e)
    try {
      const action = (e as { action?: string }).action
      if (isOk(ran) && (action === undefined || action === 'publish')) {
        const result = (ran.result ?? {}) as { url?: unknown }
        const text = typeof ran.text === 'string' ? ran.text : JSON.stringify(ran.result ?? '')
        const url = CLAUDE_URL.exec(text)?.[0]
          ?? (typeof result.url === 'string' && CLAUDE_URL.test(result.url) ? result.url : undefined)
        if (url) {
          const input = e as { title?: string; file_path?: string }
          const name = input.title || (input.file_path ? baseName(input.file_path) : url.split('/').filter(Boolean).pop() || url)
          await recordWeb($, url, name)
        }
      }
    } catch { /* 무시 */ }
    return ran
  }).catch((_$, e, next) => next(e)) // 훅이 죽어도 도구 결과는 그대로 흐른다
}
