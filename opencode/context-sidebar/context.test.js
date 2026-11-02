import { test, expect } from 'bun:test'
import { cacheRatio } from './context.js'

test('cache ratio uses uncached input, cache writes and reads', () => {
  expect(cacheRatio({ input: 100, cache: { read: 800, write: 100 } })).toBe(80)
  expect(cacheRatio({ input: 0, cache: { read: 0, write: 0 } })).toBeNull()
})
