# OpenCode context sidebar

This TUI plugin adds session and latest-request cache hit rates to the
OpenCode V2 sidebar.

Add the absolute path to this directory to `plugins` in
`~/.config/opencode/cli.json`. The existing plugin entries can remain in place.
OpenCode reloads the CLI configuration when it changes.

Cache hit rate is `cache read / (input + cache read + cache write)`. It uses
OpenCode's normalized token counts, and shows `N/A` when no cache activity is
reported. The session value uses cumulative usage; the last value uses the
latest completed request.

Run the unit tests with `bun test opencode/context-sidebar/context.test.js`.
