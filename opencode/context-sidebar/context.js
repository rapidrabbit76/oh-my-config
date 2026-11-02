export function cacheRatio(tokens) {
  const { input, cache } = tokens
  const total = input + cache.read + cache.write
  return total > 0 && cache.read + cache.write > 0 ? (cache.read / total) * 100 : null
}
