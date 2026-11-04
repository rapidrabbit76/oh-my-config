// 네 모듈이 같이 쓰는 설정과 도우미. 상태(atom)는 여기서 만들지 않는다:
// 엔진의 검사기가 read/update에 넘기는 atom은 "같은 파일 안의 const"여야 통과한다.
// 그래서 모듈마다 자기 파일 안에서 아래 꼴로 똑같이 만든다(plugin·key 글자 그대로):
//   const sessionInfo = atom({ plugin: 'session-pane', key: 'session' } as const, EMPTY_SESSION)
//   const files = atom({ plugin: 'session-pane', key: 'files' } as const, [] as MadeFile[], { shape: 'files-1' })
//   const todos = atom({ plugin: 'session-pane', key: 'todos' } as const, [] as Todo[], { shape: 'todos-1' })
//   const last  = atom({ plugin: 'session-pane', key: 'last' } as const, '')
import type { SessionInfo } from '../types'

export const PLUGIN = 'session-pane' as const
export const PANE_ID = 'session-pane'
export const PANE_TITLE = '이 세션'

export const EMPTY_SESSION: SessionInfo = {
  purpose: '',
  steps: [],
  latest: '',
  isOffTopic: false,
  promptCount: 0,
  purposeFull: '',
  latestFull: '',
  answer: '',
  answerFull: '',
  firstRowId: '',
  latestRowId: '',
  answerRowId: '',
  status: '',
  progress: null,
  isWorking: false,
  nextPrompt: '',
}

/** 답변 속 "[상태] 구상 중|진행 중|끝 (n/m)" 줄 */
export const statusLine = (
  text: string,
): { status: '구상 중' | '진행 중' | '끝'; progress: { done: number; total: number } | null } | null => {
  const m = /^\s*\[상태\]\s*(구상\s*중|진행\s*중|끝|완료)\s*(?:[(（]?\s*(\d+)\s*\/\s*(\d+)\s*[)）]?)?/m.exec(text)
  if (!m) return null
  const word = (m[1] ?? '').replace(/\s+/g, '')
  const status = word === '구상중' ? '구상 중' : word === '진행중' ? '진행 중' : '끝'
  const progress = m[2] && m[3] ? { done: Number(m[2]), total: Number(m[3]) } : null
  return { status, progress }
}

/** 답변 속 "[다음 프롬프트] …" 줄(같은 줄이 비면 다음 줄) */
export const nextPromptLine = (text: string) => {
  const m = /^[ \t]*\[다음 프롬프트\][ \t]*(.*)$/m.exec(text)
  if (!m) return ''
  const strip = (s: string) => s.trim().replace(/^[`>"]+|[`"]+$/g, '').trim()
  const same = strip(m[1] ?? '')
  if (same) return same
  const rest = text.slice((m.index ?? 0) + m[0].length)
  const after = rest.split(/\r?\n/).map(l => l.trim()).find(Boolean) ?? ''
  return strip(after)
}

/** 답변 속 "[단계] 조사, 고침, 시험, 회고" 줄 → 단계 이름 목록(최대 6) */
export const stepsLine = (text: string): string[] => {
  const m = /^[ 	]*\[단계\][ 	]*(.+?)[ 	]*$/m.exec(text)
  if (!m) return []
  return (m[1] ?? '')
    .split(/\s*(?:,|→|->|>|·|\/|\|)\s*/)
    .map(s => s.replace(/^\d+[.)]?\s*/, '').trim())
    .filter(Boolean)
    .slice(0, 6)
}

/** 대화 기록 줄의 화면 id: 저장 uuid의 마지막 토막을 0으로 채운 꼴(관찰 2026-11-04) */
export const rowRenderId = (uuid: string) => uuid.replace(/-[0-9a-f]{12}$/i, '-000000000000')

/** 답변·요청 속 "[목적] …" 줄(모델이 이해한 의도 한 줄, 사용자가 직접 쳐도 됨) */
export const purposeLine = (text: string) => {
  const m = /^\s*\[목적\]\s*(.+?)\s*$/m.exec(text)
  return m ? m[1] : ''
}

/** 마우스를 댔을 때 보여 줄 글의 길이 한도 */
export const FULL_CHARS = 400

/** 답변의 첫 문장(결과 한 줄): 마크다운 표시를 걷어 내고 첫 문장만 */
export const firstSentence = (text: string) => {
  const plain = text
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/[*_`#>|]/g, '')
    .replace(/\[(.*?)\]\([^)]*\)/g, '$1')
    .replace(/\s+/g, ' ')
    .trim()
  const m = /^(.+?[.!?。]|.+?(?=\s{2,}|$))/.exec(plain)
  return (m ? m[1] : plain).trim()
}

/** 설정 값(쉼표로 나눈 목록)을 조각으로 */
export const splitList = (value: unknown) =>
  String(value ?? '')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean)

/**
 * 만든 파일로 보여 줄 뿌리 폴더(이 밑만). 슬래시(/)로 통일한 경로.
 * watch = 세션 cwd 기준 상대 폴더들(기본 docs), extra = 절대 경로 폴더들(작업 폴더 등). 둘 다 설정(userConfig)에서 온다.
 */
export const WATCH_ROOTS = (cwd: string, watch: string = 'docs', extra: string = '') => {
  const base = cwd.replace(/\\/g, '/').replace(/\/$/, '')
  const rel = splitList(watch).map(d => base + '/' + d.replace(/\\/g, '/').replace(/^\.?\//, '').replace(/\/$/, ''))
  const abs = splitList(extra).map(d => d.replace(/\\/g, '/').replace(/\/$/, ''))
  return [...rel, ...abs]
}

/** 만든 파일에서 숨길 경로 조각(슬래시 경로에 적용) */
export const HIDE_PATTERNS = [/\/skills\//i, /\/\.claude\//i, /\/tmp\//i, /\/node_modules\//i, /~\$/, /\/_폐기/]

/** 옆 창에 보이는 만든 파일 줄 수 */
export const MAX_FILES = 8

/** 다음 세션으로 넘길 때 쓰는 $.store 키 */
export const STORE_KEY = (cwd: string, what: 'files' | 'todos') => `session-pane:${what}:${cwd.toLowerCase()}`

export const toSlash = (p: string) => p.replace(/\\/g, '/')
export const toBackslash = (p: string) => p.replace(/\//g, '\\')
export const baseName = (p: string) => toSlash(p).split('/').filter(Boolean).pop() ?? p

export const hhmm = (iso: string) => {
  const d = new Date(iso)
  const p = (n: number) => String(n).padStart(2, '0')
  return `${p(d.getHours())}:${p(d.getMinutes())}`
}

/** 한 줄로 자르기(화면 폭 기준, 한글은 2칸) */
export const cut = (s: string, cols: number) => {
  let w = 0
  let out = ''
  for (const ch of s.replace(/\s+/g, ' ').trim()) {
    const cw = /[\u1100-\u11FF\u3000-\u303F\uAC00-\uD7AF\u4E00-\u9FFF\uFF00-\uFFEF]/.test(ch) ? 2 : 1
    if (w + cw > cols - 1) return out + '…'
    out += ch
    w += cw
  }
  return out
}
