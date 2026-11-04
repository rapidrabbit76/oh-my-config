import type { Register } from 'claude-code'

import { registerSession } from './session'
import { registerFiles } from './files'
import { registerTodos } from './todo'
import { registerPane } from './pane'

// session-pane: 이 세션(목적·단계·방금) · 고칠 것 · 만든 파일(열기 버튼)을 모델 호출 없이 옆 창에 그린다.
// 모듈마다 자기 상태만 쓴다(state.ts의 atom). 그리기는 pane.tsx 한 곳.
export const register: Register = (on, options) => {
  registerSession(on)
  registerFiles(on, options)
  registerTodos(on)
  registerPane(on, options)
}
