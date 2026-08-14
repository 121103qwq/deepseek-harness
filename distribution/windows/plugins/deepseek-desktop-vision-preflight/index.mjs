/**
 * Reject image requests before provider I/O when the selected model explicitly
 * declares that it does not accept images. Unknown capability metadata is left
 * alone so a provider that cannot describe itself keeps its existing behavior.
 */

export const name = 'deepseek-desktop-vision-preflight'
export const inject = ['llm']

function containsImage(content) {
  return content.some(block => block.type === 'image'
    || (block.type === 'tool-result' && containsImage(block.content)))
}

function requestContainsImage(messages) {
  return messages.some(message => containsImage(message.content))
}

function unsupportedImageFinish(provider, model) {
  return {
    type: 'finish',
    reason: {
      kind: 'error',
      failure: {
        code: 'UNSUPPORTED_INPUT_MODALITY',
        message: `当前模型 ${provider}/${model} 不支持图片输入。请切换到带视觉能力的模型，或移除图片后重试。`,
      },
    },
  }
}

/**
 * Install the image-capability preflight listener.
 * @param {object} ctx - Cordis context with the LLM runtime.
 * @param {object} config - optional preflight settings.
 */
export function apply(ctx, config = {}) {
  const enabled = config.enabled ?? true
  if (typeof enabled !== 'boolean') {
    throw new Error('deepseek-desktop-vision-preflight: enabled must be boolean')
  }
  if (!enabled) return

  ctx.on('llm/stream', (options, next) => {
    if (!requestContainsImage(options.messages)) return next()
    return (async function* () {
      let info
      try {
        info = await ctx.llm.resolveModelInfo(options.provider, options.model, options.signal)
      } catch {
        // An unresolved route will produce its normal adapter failure. This
        // plugin only rejects an explicit negative image capability.
        yield* next()
        return
      }
      if (info.inputModalities === undefined || info.inputModalities.includes('image')) {
        yield* next()
        return
      }
      yield unsupportedImageFinish(options.provider, options.model)
    })()
  })
}
