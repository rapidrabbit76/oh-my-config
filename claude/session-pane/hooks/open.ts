// 폴더·파일 열기. 운영체제별 가지 셋. 담당: 에이전트 B.
// Windows: helpers/open-path.ps1 (창 숨김 풀기 + 앞으로 가져오기, 1단계에서 검증됨)
//   exit 0 = 열림, 2 = 창을 못 찾음, 3 = 경로 없음. 한 줄 `hwnd=… visible=True foreground=True`를 찍는다.
// 맥: open 경로 / 리눅스: xdg-open 경로. 웹 주소는 pane.tsx가 터미널 링크(Link)로 그린다.
import type { EngineInterface } from 'claude-code'

export type OpenResult = { isOpened: boolean; detail: string }

/** 플러그인 뿌리가 윈도 경로(드라이브 글자 또는 역슬래시)면 윈도로 본다 */
const isWindowsRoot = (root: string) => /^[A-Za-z]:[\\/]/.test(root) || root.includes('\\')

/** 경로의 부모 폴더. 드라이브 뿌리(C:\)나 /는 그대로 */
export const parentOf = (path: string): string => {
  const trimmed = path.replace(/[\\/]+$/, '')
  const cut = Math.max(trimmed.lastIndexOf('/'), trimmed.lastIndexOf('\\'))
  if (cut < 0) return trimmed
  const parent = trimmed.slice(0, cut)
  if (parent === '') return trimmed.slice(0, 1)
  if (/^[A-Za-z]:$/.test(parent)) return parent + trimmed.charAt(cut)
  return parent
}

const WINDOWS_EXIT: Record<number, string> = { 2: '창을 못 찾음', 3: '경로 없음' }

const detailOf = (ran: { exitCode: number; stdout: string; stderr: string }, isWindows: boolean) => {
  const text = (ran.stdout.trim() || ran.stderr.trim()).slice(0, 80)
  if (text) return text
  const known = isWindows ? WINDOWS_EXIT[ran.exitCode] : undefined
  if (known) return known
  return ran.exitCode === 0 ? '열림' : `종료 코드 ${ran.exitCode}`
}

// 엔진 검사기 규칙: 다른 파일에서 $를 넘겨받는 함수는 function 선언이어야 한다(화살표 const는 거부).
export async function openPath($: EngineInterface, path: string): Promise<OpenResult> {
  try {
    const root = $.plugin.root
    if (isWindowsRoot(root)) {
      const helper = root.replace(/[\\/]+$/, '') + '\\helpers\\open-path.ps1'
      const ran = await $.process.run(
        ['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', helper, '-Path', path],
        { cwd: root, timeoutMs: 20000 },
      )
      return { isOpened: ran.exitCode === 0, detail: detailOf(ran, true) }
    }
    const hasOpen = await $.fs.stat('/usr/bin/open').then(() => true, () => false)
    const ran = await $.process.run(hasOpen ? ['open', path] : ['xdg-open', path], { timeoutMs: 20000 })
    return { isOpened: ran.exitCode === 0, detail: detailOf(ran, false) }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    return { isOpened: false, detail: msg.slice(0, 80) || '열기 실패' }
  }
}
