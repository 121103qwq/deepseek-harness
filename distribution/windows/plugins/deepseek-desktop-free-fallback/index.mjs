/**
 * Retry a configured free-model request on a second configured route only when
 * the first route fails before it emits any output. The original request is
 * never mutated, which keeps loop-built requests immutable and makes the
 * retry an explicit new provider dispatch.
 */

export const name = 'deepseek-desktop-free-fallback'
export const inject = ['llm']

const DEFAULT_RETRYABLE_CODES = Object.freeze([
  'EMPTY_RESPONSE',
  'RATE_LIMIT',
  'SERVER',
  'TIMEOUT',
  'TRANSPORT',
])

function requiredString(value, key) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`deepseek-desktop-free-fallback: ${key} must be a non-empty string`)
  }
  return value.trim()
}

function resolveConfig(config = {}) {
  const resolved = {
    primaryProvider: requiredString(config.primaryProvider ?? 'groq', 'primaryProvider'),
    primaryModel: requiredString(config.primaryModel ?? 'openai/gpt-oss-20b', 'primaryModel'),
    fallbackProvider: requiredString(config.fallbackProvider ?? 'groq', 'fallbackProvider'),
    fallbackModel: requiredString(config.fallbackModel ?? 'openai/gpt-oss-120b', 'fallbackModel'),
    retryableCodes: config.retryableCodes ?? [...DEFAULT_RETRYABLE_CODES],
    includeAuxiliary: config.includeAuxiliary ?? false,
  }
  if (resolved.primaryProvider === resolved.fallbackProvider && resolved.primaryModel === resolved.fallbackModel) {
    throw new Error('deepseek-desktop-free-fallback: primary and fallback routes must differ')
  }
  if (!Array.isArray(resolved.retryableCodes)
    || resolved.retryableCodes.length === 0
    || resolved.retryableCodes.some(code => typeof code !== 'string' || code.length === 0)) {
    throw new Error('deepseek-desktop-free-fallback: retryableCodes must contain non-empty strings')
  }
  if (typeof resolved.includeAuxiliary !== 'boolean') {
    throw new Error('deepseek-desktop-free-fallback: includeAuxiliary must be boolean')
  }
  return Object.freeze({
    ...resolved,
    retryableCodes: Object.freeze([...resolved.retryableCodes]),
  })
}

function emitsOutput(chunk) {
  return chunk.type === 'text-delta'
    || chunk.type === 'reasoning-delta'
    || chunk.type === 'tool-call-delta'
    || chunk.type === 'block-end'
}

function errorCode(chunk) {
  return chunk.type === 'finish' && chunk.reason.kind === 'error'
    ? chunk.reason.failure.code
    : undefined
}

function canRoute(options, config) {
  return options.provider === config.primaryProvider
    && options.model === config.primaryModel
    && (config.includeAuxiliary || options.purpose === undefined)
}

/**
 * Install the pre-output fallback waterfall listener.
 * @param {object} ctx - Cordis context with the LLM runtime.
 * @param {object} config - primary/fallback routes and retry policy.
 */
export function apply(ctx, config) {
  const resolved = resolveConfig(config)
  ctx.on('llm/stream', (options, next) => {
    if (!canRoute(options, resolved)) return next()
    return (async function* () {
      let outputStarted = false
      let retryableFailure
      try {
        for await (const chunk of next()) {
          if (emitsOutput(chunk)) outputStarted = true
          const code = errorCode(chunk)
          if (!outputStarted && code !== undefined && resolved.retryableCodes.includes(code)) {
            retryableFailure = chunk
            break
          }
          yield chunk
        }
      } catch (error) {
        // The LLM runtime normally normalizes adapter failures into a finish
        // chunk. Middleware failures are not normalized, so leave those errors
        // visible instead of hiding a configuration or lifecycle bug.
        throw error
      }

      if (retryableFailure === undefined || outputStarted) return

      // A new object is required because loop requests may be frozen. The
      // fallback route does not re-enter this branch: canRoute matches only the
      // configured primary route.
      yield* ctx.llm.stream({
        ...options,
        provider: resolved.fallbackProvider,
        model: resolved.fallbackModel,
      })
    })()
  })
}

export { DEFAULT_RETRYABLE_CODES }
