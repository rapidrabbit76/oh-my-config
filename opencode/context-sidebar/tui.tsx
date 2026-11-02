import { Plugin } from '@opencode/plugin/tui'
import type { BoxRenderable } from '@opentui/core'
import { createMemo, createResource, createSignal, onCleanup } from 'solid-js'
import { cacheRatio } from './context.js'

const percent = (value: number | null) => value === null ? 'N/A' : `${value.toFixed(1)}%`

export default Plugin.define({
  id: 'oh-my-config.context-sidebar',
  setup(context) {
    return context.ui.slot({
      append: 'sidebar.content',
      render: ({ sessionID }) => {
        const [revision, setRevision] = createSignal(0)
        const [width, setWidth] = createSignal(0)
        const stop = context.data.listen(({ details }) => {
          if (details.type === 'session.step.ended' || details.type === 'session.compaction.ended') {
            if (details.data.sessionID === sessionID) setRevision((value) => value + 1)
          }
        })
        onCleanup(stop)

        const [messages] = createResource(
          () => ({ sessionID, revision: revision() }),
          async ({ sessionID }) => context.client.session.context({ sessionID }),
        )
        const session = () => context.data.session.get(sessionID)
        const latest = createMemo(() => messages()?.findLast((item) => item.type === 'assistant' && item.tokens))
        const cache = () => {
          const tokens = session()?.tokens
          return tokens ? cacheRatio(tokens) : null
        }
        const lastCache = () => {
          const message = latest()
          return message?.type === 'assistant' && message.tokens ? cacheRatio(message.tokens) : null
        }
        const filled = () => Math.round((cache() ?? 0) * width() / 100)

        return (
          <box flexDirection="column" marginTop={1} width="100%" onSizeChange={function (this: BoxRenderable) { setWidth(this.width) }}>
            <text fg={context.theme.text.base}><b>Cache hit</b>  {percent(cache())}</text>
            <text><span fg={context.theme.text.base}>{'━'.repeat(filled())}</span><span fg={context.theme.text.muted}>{'─'.repeat(width() - filled())}</span></text>
            <text fg={context.theme.text.muted}>Session · last {percent(lastCache())}</text>
          </box>
        )
      },
    })
  },
})
