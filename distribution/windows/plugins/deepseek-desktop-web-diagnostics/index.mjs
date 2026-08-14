/**
 * Expose a loopback-only, dependency-free readiness document for the native
 * WebView host. It makes local connection failures distinguishable from a
 * failed model request without changing the normal Web UI route.
 */

export const name = 'deepseek-desktop-web-diagnostics'
export const inject = ['webServer']

const PATH = '/__deepseek_desktop/diagnostics'

function writeJson(res, status, body) {
  const text = JSON.stringify(body)
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  })
  res.end(text)
}

/**
 * Register the local diagnostics endpoint.
 * @param {object} ctx - Cordis context with the Web server service.
 */
export function apply(ctx) {
  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: PATH,
    handler: (req, res) => {
      if (req.method !== 'GET' && req.method !== 'HEAD') {
        res.setHeader('allow', 'GET, HEAD')
        writeJson(res, 405, { ok: false, error: 'method_not_allowed' })
        return
      }
      const port = ctx.webServer.port
      const origin = `http://127.0.0.1:${String(port)}`
      const body = {
        ok: true,
        service: 'DeepSeek Harness',
        host: ctx.webServer.host,
        port,
        origin,
        diagnosticsPath: PATH,
        timestamp: new Date().toISOString(),
      }
      if (req.method === 'HEAD') {
        res.writeHead(200, {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-store',
          'x-content-type-options': 'nosniff',
        })
        res.end()
        return
      }
      writeJson(res, 200, body)
    },
  }), 'deepseek-desktop-web-diagnostics: route')
}

export { PATH as DIAGNOSTICS_PATH }
