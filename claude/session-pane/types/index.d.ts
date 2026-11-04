// session-pane 상태 계약. 네 모듈(session·files·todo·pane)이 같이 쓴다.

/** 첫 요청에서 뽑은 번호 단계 하나 */
export type Step = { name: string; isDone: boolean }

/** 옆 창 "이 세션" 칸 */
export type SessionInfo = {
  /** 첫 요청(세션 프롬프트)의 제목 줄. 비면 "프롬프트 없이 시작" */
  purpose: string
  steps: Step[]
  /** 마지막 요청 한 줄(자름) */
  latest: string
  /** 마지막 요청이 목적과 낱말이 안 겹침 → "별도 세션?" 경고 */
  isOffTopic: boolean
  /** 요청 수(내부용, 화면엔 안 그림) */
  promptCount: number
  /** 첫 요청 글 전체(앞 400자) — 마우스를 대면 보이는 자세한 내용 */
  purposeFull: string
  /** 마지막 요청 글 전체(앞 400자) */
  latestFull: string
  /** 마지막 답변의 첫 문장(결과 한 줄) */
  answer: string
  /** 마지막 답변 앞 400자 */
  answerFull: string
  /** 대화 기록 줄 id(누르면 그 자리로 스크롤): 첫 요청·마지막 요청·마지막 답변 */
  firstRowId: string
  latestRowId: string
  answerRowId: string
  /** 모델이 "[상태] …"로 적은 상태(없으면 ''): 구상 중 | 진행 중 | 끝 */
  status: '' | '구상 중' | '진행 중' | '끝'
  /** 모델이 "[상태] … n/m"으로 적은 진행도(없으면 null) */
  progress: { done: number; total: number } | null
  /** 지금 모델이 일하는 중(요청 들어옴 ~ 답 끝) */
  isWorking: boolean
  /** 모델이 "[다음 프롬프트] …"로 적은, 이어서 시킬 붙여 넣기 줄 */
  nextPrompt: string
}

/** 옆 창 "만든 파일" 한 줄 */
export type MadeFile = {
  /** 파일이면 절대 경로, 웹이면 주소 */
  path: string
  /** 화면에 그릴 이름(파일 이름 또는 웹 제목) */
  name: string
  kind: 'file' | 'web'
  /** 마지막으로 만들거나 고친 시각, ISO 문자열 */
  at: string
  /** 지난 세션에서 넘어온 줄이면 true(흐리게 그림) */
  isPrevious?: boolean
}

/** 옆 창 "고칠 것" 한 줄 */
export type Todo = {
  /** 같은 항목을 다시 넣지 않기 위한 키 */
  id: string
  /** model = 답변 속 [고칠 것] 줄, skills = skills/ 밑 커밋 안 된 변경, confirm = 이 세션에서 늘어난 [확인 필요] */
  kind: 'model' | 'skills' | 'confirm'
  text: string
  isDone: boolean
  /** 지난 세션에서 넘어온 줄이면 true */
  isPrevious?: boolean
}

declare module 'claude-code' {
  interface PluginState {
    'session-pane': {
      session: SessionInfo
      files: Shaped<MadeFile[]>
      todos: Shaped<Todo[]>
      /** 마지막 열기 결과 등 짧은 상태 글(화면 맨 아랫줄) */
      last: string
    }
  }
}
