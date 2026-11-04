# session-pane — a status pane for the current Claude Code session

A Claude Code mod (plugin hooks module) that keeps one small status box beside the chat, **without any model calls**: it reads the prompts, tool calls and turn ends the engine already hands to plugins. When the `opencode-sidebar` plugin is installed it merges into that Session pane instead of opening a second tab.

```
┌ 이 세션 ──────────────────────────────┐
│ 목적  what this session is for         │  ← the model writes "[목적] …" once
│ 상태  ▸ 진행 중  ▰▰▱▱▱ 2/5             │  ← "[상태] 구상 중|진행 중|끝 n/m"
│ 단계  ● 조사 ● 고침 ○ 시험 ○ 회고       │  ← "[단계] a, b, c" or numbered steps in the first prompt
│ ▲ 내 말  ▲ 답변  ⧉ 다음 프롬프트 복사    │  ← scroll to my last prompt / the last answer, copy "[다음 프롬프트] …"
├ 작업물 ──────────────────────────────┤
│ ▸ 개발 기준서\TB310  [폴더]  14:02     │  ← folders where files were made (click: Explorer)
│     성적서-0442.xlsx                   │  ← the files (click: default app)
├ 고칠 것 ─────────────────────────────┤
│ ! qms-standard-doc 날짜 칸 고치기       │  ← "[고칠 것] …", uncommitted skills/, new [확인 필요]
└──────────────────────────────────────┘
```

## What it shows

| Row | Source (zero tokens) |
|---|---|
| 목적 (goal) | a `[목적] …` line the model writes in its first answer (one system-prompt paragraph asks for it), else the first line of the first prompt or the `# ` title of a `docs/prompts/*.md` file it names |
| 상태 (status) | a `[상태] 구상 중\|진행 중\|끝 n/m` line; without one, inferred from steps and work products. `▸` while the model is working |
| 단계 (steps) | a `[단계] a, b, c` line or numbered steps in the first prompt; `●` once the step name appears in a reply |
| ▲ 내 말 / ▲ 답변 | scroll the transcript to the last prompt / the last answer |
| ⧉ 다음 프롬프트 복사 | copies the `[다음 프롬프트] …` line (the one-liner to paste into the next session) |
| 작업물 (work products) | folders and files written by Write/Edit, left by shell commands, or published as claude.ai artifacts, under the watched roots; a toast when a new file appears; carried into the next session dimmed |
| 고칠 것 (fix later) | `[고칠 것] …` lines, uncommitted changes under `skills/<name>/`, and `[확인 필요]` markers added to `docs/domain/*.md` this session. Click a row to tick it. `/clear` or `/exit` with open items asks once |

The marker words are Korean because the author's workflow is; the parsing is in `hooks/state.ts` if you want to localise them.

## Opening files and folders on Windows

Processes started from Claude Code inherit a *hidden window* startup flag, so Explorer and some apps open invisibly. `helpers/open-path.ps1` opens a path with the default app, un-hides the window and brings it to the front (Alt-key + `AttachThreadInput` to get past the foreground lock), reusing an Explorer window that already shows the folder. On macOS the pane runs `open`, on Linux `xdg-open` (both untested so far). The script carries a UTF-8 BOM on purpose (Korean comments).

## Settings (`/config` → plugin options)

- `hostPane` — pane id fragment to merge into (default `opencode-sidebar`); empty opens a separate pane via `/session-pane`.
- `hideHostSections` — comma-separated host section headings to drop while merged, e.g. `Recent,Cache` (default none).
- `watchRoots` — folders under the cwd to watch (default `docs`).
- `extraRoots` — absolute folders to watch too (a work folder outside the repo).

## Development

`claude plugin validate <folder>` and `claude plugin test <folder>` (27 tests). Hooks are split by concern: `session.ts` (goal/steps/status), `files.ts` + `open.ts` (work products, opening), `todo.ts` (fix-later list and the close guard), `pane.tsx` (drawing and the merge). Each file declares its own `atom(...)` for the shared state keys — the validator requires the atom to be a const in the same file.

---

## 한국어

이 세션의 상태 창이에요. 모델을 부르지 않고(토큰 0) 요청·도구 호출·턴 끝남을 그대로 받아 그립니다. opencode-sidebar가 있으면 그 Session 창 안에 합쳐지고, 없으면 `/session-pane`으로 따로 엽니다. 모델이 답변 끝에 적는 표시 줄 다섯 가지(`[목적]`·`[단계]`·`[상태]`·`[다음 프롬프트]`·`[고칠 것]`)는 시스템 프롬프트 한 단락으로 넣습니다. Windows에서 폴더·파일이 열리고도 안 보이는 문제는 `helpers/open-path.ps1`이 창을 보이게 바꾸고 앞으로 가져와 풉니다.
