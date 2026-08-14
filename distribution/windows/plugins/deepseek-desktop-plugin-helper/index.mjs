/**
 * Report the installed desktop plugin roster without exposing credentials or
 * changing the user's profile. The installer always bundles this helper so a
 * broken optional download can be diagnosed from the embedded WebView.
 */

import fs from 'node:fs'
import path from 'node:path'

export const name = 'deepseek-desktop-plugin-helper'
export const inject = ['webServer']

const PATH = '/__deepseek_desktop/plugin-helper'
const HELPER_VERSION = '0.1.0'

function resolveHome() {
  const configured = process.env.DSH_HOME?.trim()
  if (configured) return configured
  const localAppData = process.env.LOCALAPPDATA?.trim()
  if (localAppData) return path.join(localAppData, 'DeepSeek Harness Data')
  return path.join(process.cwd(), '.dsh')
}

function readPluginRoster() {
  const profilePatch = path.join(resolveHome(), 'profiles', 'web', 'cordis.patch.yml')
  let text
  try {
    text = fs.readFileSync(profilePatch, 'utf8')
  } catch {
    return { plugins: [], warning: 'profile_patch_unavailable' }
  }

  const plugins = []
  for (const block of text.split(/(?=^- id: )/m)) {
    const id = /^- id:\s*(\S+)/m.exec(block)?.[1]
    if (!id) continue
    const name = /^\s+name:\s*['"]?([^'"\r\n]+)['"]?\s*$/m.exec(block)?.[1]?.trim() ?? id
    const disabled = /^\s+disabled:\s*true\s*$/m.test(block)
    plugins.push({ id, name, enabled: !disabled })
  }
  return { plugins }
}

function sendJson(res, status, body) {
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  })
  res.end(JSON.stringify(body))
}

/**
 * Register a read-only endpoint for installer/plugin diagnostics.
 * @param {object} ctx - Cordis context with the Web server service.
 */
export function apply(ctx) {
  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: PATH,
    handler: (req, res) => {
      if (req.method !== 'GET' && req.method !== 'HEAD') {
        res.setHeader('allow', 'GET, HEAD')
        sendJson(res, 405, { ok: false, error: 'method_not_allowed' })
        return
      }
      const roster = readPluginRoster()
      if (req.method === 'HEAD') {
        res.writeHead(200, {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-store',
          'x-content-type-options': 'nosniff',
        })
        res.end()
        return
      }
      sendJson(res, 200, {
        ok: true,
        helper: 'deepseek-desktop-plugin-helper',
        helperVersion: HELPER_VERSION,
        profile: 'web',
        ...roster,
      })
    },
  }), 'deepseek-desktop-plugin-helper: route')
}

export { PATH as PLUGIN_HELPER_PATH }
