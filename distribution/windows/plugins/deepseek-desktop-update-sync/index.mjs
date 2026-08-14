/**
 * Check the official Harness repository and the community desktop repository
 * without changing the installed application. Opt-in background updating only
 * stages a release installer for a later, user-confirmed launch.
 */

import fs from 'node:fs'
import path from 'node:path'
import { createHash } from 'node:crypto'
import { createWriteStream } from 'node:fs'
import { Readable } from 'node:stream'
import { pipeline } from 'node:stream/promises'

export const name = 'deepseek-desktop-update-sync'
export const inject = ['webServer']

const PATH = '/__deepseek_desktop/update-sync'
const CURRENT_VERSION = process.env.DEEPSEEK_DESKTOP_VERSION?.trim() || '0.1.0-rc.6'
const DEFAULT_INTERVAL_HOURS = 6
const MAX_ASSET_BYTES = 512 * 1024 * 1024
const SOURCES = Object.freeze([
  Object.freeze({
    id: 'official',
    label: 'DeepSeek 官方 Harness',
    repository: 'deepseek-ai/deepseek-harness',
  }),
  Object.freeze({
    id: 'community',
    label: 'DeepSeek Desktop 社区版',
    repository: '121103qwq/deepseek-harness',
  }),
])

function isBoolean(value) {
  return typeof value === 'boolean'
}

function resolveConfig(config = {}) {
  const checkInBackground = config.checkInBackground ?? true
  const allowBackgroundAutoUpdate = config.allowBackgroundAutoUpdate ?? false
  const intervalHours = config.intervalHours ?? DEFAULT_INTERVAL_HOURS
  if (!isBoolean(checkInBackground)) {
    throw new Error('deepseek-desktop-update-sync: checkInBackground must be boolean')
  }
  if (!isBoolean(allowBackgroundAutoUpdate)) {
    throw new Error('deepseek-desktop-update-sync: allowBackgroundAutoUpdate must be boolean')
  }
  if (!Number.isInteger(intervalHours) || intervalHours < 1 || intervalHours > 168) {
    throw new Error('deepseek-desktop-update-sync: intervalHours must be an integer from 1 to 168')
  }
  return Object.freeze({ checkInBackground, allowBackgroundAutoUpdate, intervalHours })
}

function versionParts(value) {
  const match = /^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?/.exec(value)
  if (!match) return undefined
  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3]),
    prerelease: match[4],
  }
}

function normalizeVersion(value) {
  const match = /v?(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)/.exec(value)
  return match?.[1] ?? value
}

function isNewerVersion(candidate, current) {
  const next = versionParts(candidate)
  const installed = versionParts(current)
  if (!next || !installed) return candidate !== current
  for (const key of ['major', 'minor', 'patch']) {
    if (next[key] !== installed[key]) return next[key] > installed[key]
  }
  if (next.prerelease === installed.prerelease) return false
  if (next.prerelease === undefined) return true
  if (installed.prerelease === undefined) return false
  return next.prerelease.localeCompare(installed.prerelease, undefined, { numeric: true }) > 0
}

function updateDirectory() {
  const root = process.env.LOCALAPPDATA?.trim()
    ? path.join(process.env.LOCALAPPDATA, 'DeepSeek Desktop', 'updates')
    : path.join(process.cwd(), '.dsh', 'updates')
  fs.mkdirSync(root, { recursive: true })
  return root
}

function safeFilename(value) {
  const filename = path.basename(value).replace(/[^0-9A-Za-z._-]/g, '_')
  return filename || 'DeepSeek-Desktop-update.exe'
}

function pickInstallerAsset(assets) {
  if (!Array.isArray(assets)) return undefined
  return assets.find((asset) => {
    const name = typeof asset?.name === 'string' ? asset.name : ''
    return /deepseek[-_ ]desktop/i.test(name) && /setup\.exe$/i.test(name)
      && typeof asset.browser_download_url === 'string'
  })
}

async function readRelease(source) {
  const url = `https://api.github.com/repos/${source.repository}/releases/latest`
  let response
  try {
    response = await fetch(url, {
      headers: {
        accept: 'application/vnd.github+json',
        'user-agent': 'DeepSeek-Desktop-Update-Sync',
      },
      signal: AbortSignal.timeout(10_000),
    })
  } catch {
    return { ...source, status: 'network_error' }
  }
  if (response.status === 404) {
    const commit = await readLatestCommit(source)
    return { ...source, status: 'not_published', latestCommit: commit }
  }
  if (!response.ok) return { ...source, status: `http_${response.status}` }
  let release
  try {
    release = await response.json()
  } catch {
    return { ...source, status: 'invalid_response' }
  }
  const tag = typeof release.tag_name === 'string' ? release.tag_name : undefined
  if (!tag) return { ...source, status: 'invalid_response' }
  const asset = pickInstallerAsset(release.assets)
  const version = normalizeVersion(tag)
  return {
    ...source,
    status: 'ok',
    version,
    publishedAt: typeof release.published_at === 'string' ? release.published_at : undefined,
    releaseUrl: typeof release.html_url === 'string' ? release.html_url : undefined,
    updateAvailable: isNewerVersion(version, CURRENT_VERSION),
    asset: asset
      ? {
          name: safeFilename(asset.name),
          url: asset.browser_download_url,
          size: Number.isSafeInteger(asset.size) ? asset.size : undefined,
          digest: typeof asset.digest === 'string' ? asset.digest : undefined,
        }
      : undefined,
  }
}

async function readLatestCommit(source) {
  const url = `https://api.github.com/repos/${source.repository}/commits/main`
  try {
    const response = await fetch(url, {
      headers: {
        accept: 'application/vnd.github+json',
        'user-agent': 'DeepSeek-Desktop-Update-Sync',
      },
      signal: AbortSignal.timeout(10_000),
    })
    if (!response.ok) return undefined
    const commit = await response.json()
    if (typeof commit?.sha !== 'string') return undefined
    return {
      sha: commit.sha,
      url: typeof commit.html_url === 'string' ? commit.html_url : undefined,
      committedAt: typeof commit.commit?.committer?.date === 'string'
        ? commit.commit.committer.date
        : undefined,
    }
  } catch {
    return undefined
  }
}

async function stageAsset(sourceResult) {
  const asset = sourceResult.asset
  if (!asset) return { status: 'asset_unavailable' }
  if (asset.size !== undefined && asset.size > MAX_ASSET_BYTES) return { status: 'asset_too_large' }
  const destination = path.join(updateDirectory(), asset.name)
  if (fs.existsSync(destination)) return { status: 'already_staged', filename: asset.name }
  const temporary = `${destination}.download`
  try {
    const response = await fetch(asset.url, {
      headers: { 'user-agent': 'DeepSeek-Desktop-Update-Sync' },
      signal: AbortSignal.timeout(120_000),
    })
    if (!response.ok || !response.body) return { status: `download_http_${response.status}` }
    const contentLength = Number(response.headers.get('content-length'))
    if (Number.isSafeInteger(contentLength) && contentLength > MAX_ASSET_BYTES) {
      return { status: 'asset_too_large' }
    }
    await pipeline(Readable.fromWeb(response.body), createWriteStream(temporary, { flags: 'wx' }))
    const hash = createHash('sha256')
    const stream = fs.createReadStream(temporary)
    for await (const chunk of stream) hash.update(chunk)
    const digest = `sha256:${hash.digest('hex')}`
    if (asset.digest && asset.digest !== digest) {
      fs.rmSync(temporary, { force: true })
      return { status: 'digest_mismatch' }
    }
    fs.renameSync(temporary, destination)
    return {
      status: asset.digest ? 'staged_verified' : 'staged_unverified',
      filename: asset.name,
    }
  } catch {
    fs.rmSync(temporary, { force: true })
    return { status: 'download_error' }
  }
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
 * Register the update status endpoint and an opt-in check timer.
 * @param {object} ctx - Cordis context with the Web server service.
 * @param {object} config - background-check and staged-download settings.
 */
export function apply(ctx, config = {}) {
  const resolved = resolveConfig(config)
  const state = {
    ok: true,
    plugin: name,
    currentVersion: CURRENT_VERSION,
    settings: resolved,
    checking: false,
    lastCheck: undefined,
    sources: [],
  }

  async function checkNow() {
    if (state.checking) return
    state.checking = true
    try {
      const results = []
      for (const source of SOURCES) {
        const result = await readRelease(source)
        if (resolved.allowBackgroundAutoUpdate && result.updateAvailable && result.status === 'ok') {
          result.staging = await stageAsset(result)
        }
        results.push(result)
      }
      state.sources = results
      state.lastCheck = new Date().toISOString()
    } finally {
      state.checking = false
    }
  }

  ctx.effect(() => {
    const disposeRoute = ctx.webServer.register({
      kind: 'exact',
      path: PATH,
      handler: (req, res) => {
        if (req.method !== 'GET' && req.method !== 'HEAD') {
          res.setHeader('allow', 'GET, HEAD')
          sendJson(res, 405, { ok: false, error: 'method_not_allowed' })
          return
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
        sendJson(res, 200, state)
      },
    })
    if (!resolved.checkInBackground) return disposeRoute
    const initialCheck = setTimeout(() => void checkNow(), 1_500)
    const interval = setInterval(() => void checkNow(), resolved.intervalHours * 60 * 60 * 1_000)
    return () => {
      clearTimeout(initialCheck)
      clearInterval(interval)
      disposeRoute?.()
    }
  }, 'deepseek-desktop-update-sync: route and timer')
}

export {
  CURRENT_VERSION,
  DEFAULT_INTERVAL_HOURS,
  PATH,
  SOURCES,
  isNewerVersion,
  normalizeVersion,
  pickInstallerAsset,
  resolveConfig,
}
