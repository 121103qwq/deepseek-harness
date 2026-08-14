import { randomUUID } from 'node:crypto'
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http'
import { createConnection } from 'node:net'
import { cp, mkdir, readdir, readFile, realpath, rm, stat, writeFile } from 'node:fs/promises'
import { dirname, extname, join, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { homedir } from 'node:os'
import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process'
import { promisify } from 'node:util'
import type {
  CatalogResponse,
  ConversationSummary,
  ExtensionEntry,
  ExtensionKind,
  InstanceKind,
  InstanceStatus,
  ManagerInstance,
  MarketplaceEntry,
  SkillEntry,
} from './types.js'

const execFile = promisify((await import('node:child_process')).execFile)
const sourceDirectory = dirname(fileURLToPath(import.meta.url))
const managerRoot = resolve(process.env.DSH_MANAGER_DATA_ROOT
  ?? join(process.env.LOCALAPPDATA ?? join(homedir(), 'AppData', 'Local'), 'DeepSeek Harness Manager'))
const managedDocumentsRoot = resolve(process.env.DSH_MANAGER_DOCUMENTS_ROOT
  ?? join(homedir(), 'Documents', 'DeepSeek'))
const registryPath = join(managerRoot, 'registry.json')
const staticRoot = join(sourceDirectory, 'ui')
const portArgIndex = process.argv.findIndex(value => value === '--port')
const defaultPort = Number(process.env.DSH_MANAGER_PORT ?? (portArgIndex >= 0 ? process.argv[portArgIndex + 1] : 3210))

interface StoredInstance {
  readonly id: string
  readonly name: string
  readonly icon?: string
  readonly description?: string
  readonly rootPath: string
  readonly kind: InstanceKind
  readonly homePath: string
  readonly syncGroupId?: string
  readonly lastLaunchedAt?: string
  readonly favorite?: boolean
  readonly port?: number
  readonly pid?: number
  readonly error?: string
}

interface StoredCatalogSource {
  readonly id: string
  readonly url: string
  readonly name: string
}

interface RegistryFile {
  readonly schemaVersion: 1
  readonly instances: StoredInstance[]
  readonly catalogs: StoredCatalogSource[]
}

interface RunningInstance {
  readonly process: ChildProcessWithoutNullStreams
  readonly port: number
  readonly url: string
  readonly logPath: string
  readonly lines: string[]
  status: Extract<InstanceStatus, 'starting' | 'running'>
  logWrite: Promise<void>
  processError?: Error
}

interface JsonRecord {
  readonly [key: string]: unknown
}

const running = new Map<string, RunningInstance>()
let registry: RegistryFile = { schemaVersion: 1, instances: [], catalogs: [] }
let registryWrite = Promise.resolve()

await initialize()
const server = createServer((request, response) => {
  void handleRequest(request, response).catch((error) => {
    respondJson(response, 500, { error: errorMessage(error) })
  })
})

server.listen(defaultPort, '127.0.0.1', () => {
  console.log(`DSh Manager listening on http://127.0.0.1:${defaultPort}`)
})

process.once('SIGINT', () => { void shutdown(0) })
process.once('SIGTERM', () => { void shutdown(0) })

async function initialize(): Promise<void> {
  await mkdir(managerRoot, { recursive: true })
  await mkdir(managedDocumentsRoot, { recursive: true })
  try {
    const parsed = JSON.parse(await readFile(registryPath, 'utf8')) as Partial<RegistryFile>
    if (parsed.schemaVersion === 1 && Array.isArray(parsed.instances) && Array.isArray(parsed.catalogs)) {
      registry = {
        schemaVersion: 1,
        instances: parsed.instances.filter(isStoredInstance).map(instance => ({ ...instance, port: undefined, pid: undefined })),
        catalogs: parsed.catalogs.filter(isStoredCatalogSource),
      }
      await persistRegistry()
    }
  } catch {
    await persistRegistry()
  }
}

async function shutdown(code: number): Promise<void> {
  for (const id of [...running.keys()]) await stopInstance(id)
  server.close(() => process.exit(code))
}

async function handleRequest(request: IncomingMessage, response: ServerResponse): Promise<void> {
  const url = new URL(request.url ?? '/', `http://${request.headers.host ?? '127.0.0.1'}`)
  if (url.pathname === '/api/health') {
    respondJson(response, 200, { ok: true, managerRoot, managedDocumentsRoot })
    return
  }
  if (url.pathname.startsWith('/api/')) {
    await handleApi(request, response, url)
    return
  }
  await serveStatic(url.pathname, response)
}

async function handleApi(request: IncomingMessage, response: ServerResponse, url: URL): Promise<void> {
  const method = request.method ?? 'GET'
  const segments = url.pathname.split('/').filter(Boolean).slice(1)
  if (segments[0] === 'instances') {
    await handleInstances(request, response, method, segments.slice(1))
    return
  }
  if (segments[0] === 'catalog') {
    await handleCatalog(request, response, method, url, segments.slice(1))
    return
  }
  respondJson(response, 404, { error: 'Unknown manager API route.' })
}

async function handleInstances(
  request: IncomingMessage,
  response: ServerResponse,
  method: string,
  segments: string[],
): Promise<void> {
  if (segments.length === 0 && method === 'GET') {
    respondJson(response, 200, { instances: await listInstances() })
    return
  }
  if (segments.length === 0 && method === 'POST') {
    const body = await readJson(request)
    const rootPath = stringValue(body.path)
    if (rootPath === undefined) throw new HttpError(400, '请选择一个 DSh 文件夹。')
    const instance = await addInstance(rootPath, stringValue(body.name), stringValue(body.icon), stringValue(body.description))
    respondJson(response, 201, { instance })
    return
  }
  const id = segments[0]
  if (id === undefined) throw new HttpError(404, '实例不存在。')
  const instance = findStoredInstance(id)
  if (instance === undefined) throw new HttpError(404, '实例不存在。')
  const action = segments[1]
  if (action === undefined && method === 'DELETE') {
    if (running.has(id)) throw new HttpError(409, '请先停止运行中的实例。')
    registry = { ...registry, instances: registry.instances.filter(item => item.id !== id) }
    await persistRegistry()
    respondJson(response, 200, { ok: true })
    return
  }
  if (action === undefined && method === 'PATCH') {
    const body = await readJson(request)
    const updated = await updateInstance(instance, body)
    respondJson(response, 200, { instance: await publicInstance(updated) })
    return
  }
  if (action === 'launch' && method === 'POST') {
    respondJson(response, 200, { launch: await launchInstance(instance) })
    return
  }
  if (action === 'restart' && method === 'POST') {
    await stopInstance(id)
    const refreshed = findStoredInstance(id)
    if (refreshed === undefined) throw new HttpError(404, '实例不存在。')
    respondJson(response, 200, { launch: await launchInstance(refreshed) })
    return
  }
  if (action === 'stop' && method === 'POST') {
    await stopInstance(id)
    const stopped = findStoredInstance(id)
    respondJson(response, 200, { ok: true, ...(stopped === undefined ? {} : { instance: await publicInstance(stopped) }) })
    return
  }
  if (action === 'health' && method === 'GET') {
    respondJson(response, 200, await checkInstanceHealth(instance))
    return
  }
  if (action === 'sync' && method === 'POST') {
    if (running.has(id)) throw new HttpError(409, '运行中的实例不能切换对话同步组。')
    const body = await readJson(request)
    const syncGroupId = stringValue(body.syncGroupId)
    const updated = syncGroupId === undefined
      ? withoutSyncGroup(instance)
      : { ...instance, syncGroupId }
    registry = { ...registry, instances: registry.instances.map(item => item.id === id ? updated : item) }
    await persistRegistry()
    respondJson(response, 200, { instance: await publicInstance(updated) })
    return
  }
  if (action === 'logs' && method === 'GET') {
    respondJson(response, 200, { lines: await readLogs(instance) })
    return
  }
  if (action === 'extensions' && method === 'GET') {
    respondJson(response, 200, { extensions: await listExtensions(instance) })
    return
  }
  if (action === 'skills' && method === 'GET') {
    respondJson(response, 200, { skills: await listSkills(instance) })
    return
  }
  if (action === 'skills' && segments[2] === 'import' && method === 'POST') {
    const body = await readJson(request)
    const sourcePath = stringValue(body.path)
    if (sourcePath === undefined) throw new HttpError(400, 'Skill 源路径不能为空。')
    await importSkill(instance, sourcePath, stringValue(body.name))
    respondJson(response, 201, { skills: await listSkills(instance) })
    return
  }
  if (action === 'skills' && segments[2] === 'remove' && method === 'POST') {
    const body = await readJson(request)
    const skillPath = stringValue(body.path)
    if (skillPath === undefined) throw new HttpError(400, 'Skill 路径不能为空。')
    await removeManagedSkill(instance, skillPath)
    respondJson(response, 200, { skills: await listSkills(instance) })
    return
  }
  if (action === 'extensions' && segments[2] === 'install' && method === 'POST') {
    const body = await readJson(request)
    const kind = extensionKind(body.kind)
    const source = stringValue(body.source)
    if (kind === undefined || source === undefined) throw new HttpError(400, '扩展类型或来源不能为空。')
    await installExtension(instance, kind, source, stringValue(body.name))
    respondJson(response, 201, { extensions: await listExtensions(instance) })
    return
  }
  if (segments.length === 1 && method === 'GET') {
    respondJson(response, 200, { instance: await publicInstance(instance) })
    return
  }
  if (action === 'conversations' && method === 'GET') {
    respondJson(response, 200, { conversations: await listConversations(instance) })
    return
  }
  respondJson(response, 404, { error: 'Unknown instance API route.' })
}

async function handleCatalog(
  request: IncomingMessage,
  response: ServerResponse,
  method: string,
  url: URL,
  segments: string[],
): Promise<void> {
  if (segments.length === 0 && method === 'GET') {
    const result = await discoverCatalog(url.searchParams.get('q') ?? '')
    respondJson(response, 200, result)
    return
  }
  if (segments[0] === 'sources' && method === 'GET') {
    respondJson(response, 200, { sources: registry.catalogs })
    return
  }
  if (segments[0] === 'sources' && method === 'POST') {
    const body = await readJson(request)
    const sourceUrl = stringValue(body.url)
    const name = stringValue(body.name) ?? sourceUrl ?? '社区目录'
    if (sourceUrl === undefined || !/^https?:\/\//i.test(sourceUrl)) {
      throw new HttpError(400, '目录地址必须是 HTTP(S) URL。')
    }
    const source: StoredCatalogSource = { id: randomUUID(), url: sourceUrl, name }
    registry = { ...registry, catalogs: [...registry.catalogs, source] }
    await persistRegistry()
    respondJson(response, 201, { sources: registry.catalogs })
    return
  }
  respondJson(response, 404, { error: 'Unknown catalog API route.' })
}

async function addInstance(
  inputPath: string,
  requestedName?: string,
  requestedIcon?: string,
  requestedDescription?: string,
): Promise<ManagerInstance> {
  const rootPath = await realpath(resolve(inputPath)).catch(() => { throw new HttpError(400, 'DSh 文件夹不存在。') })
  const info = await stat(rootPath)
  if (!info.isDirectory()) throw new HttpError(400, 'DSh 路径必须是文件夹。')
  if (registry.instances.some(instance => instance.rootPath.toLowerCase() === rootPath.toLowerCase())) {
    throw new HttpError(409, '这个文件夹已经添加过了。')
  }
  const detected = await detectInstance(rootPath)
  if (detected === undefined) throw new HttpError(400, '没有识别为 DSh 安装目录或 DSh 源码项目。')
  const id = randomUUID()
  const name = requestedName?.trim() || rootPath.split(sep).filter(Boolean).at(-1) || 'DSh 实例'
  const stored: StoredInstance = {
    id,
    name,
    ...(requestedIcon === undefined ? {} : { icon: requestedIcon }),
    ...(requestedDescription === undefined ? {} : { description: requestedDescription }),
    rootPath,
    kind: detected.kind,
    homePath: join(managerRoot, 'instances', id, 'home'),
    favorite: false,
  }
  registry = { ...registry, instances: [...registry.instances, stored] }
  await mkdir(stored.homePath, { recursive: true })
  await persistRegistry()
  return await publicInstance(stored)
}

async function detectInstance(rootPath: string): Promise<{ kind: InstanceKind; version?: string } | undefined> {
  const manifest = await readJsonFile(join(rootPath, 'package.json'))
  const source = await isDirectory(join(rootPath, 'apps', 'cli', 'src'))
    && (await fileExists(join(rootPath, 'pnpm-workspace.yaml')) || await fileExists(join(rootPath, 'pnpm-lock.yaml')))
  if (source) return { kind: 'source', version: stringField(manifest, 'version') }
  const dshBin = join(rootPath, 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js')
  const packageDsh = dependencyValue(manifest, '@deepseek-ai/dsh')
  if (await fileExists(dshBin) || packageDsh !== undefined) {
    return { kind: 'installed', version: packageDsh }
  }
  return undefined
}

async function listInstances(): Promise<ManagerInstance[]> {
  const instances = await Promise.all(registry.instances.map(publicInstance))
  return instances.sort((left, right) => Number(right.favorite) - Number(left.favorite) || (right.lastLaunchedAt ?? '').localeCompare(left.lastLaunchedAt ?? '') || left.name.localeCompare(right.name))
}

async function publicInstance(instance: StoredInstance): Promise<ManagerInstance> {
  const live = running.get(instance.id)
  const runtime = await runtimeStatus(instance)
  return {
    id: instance.id,
    name: instance.name,
    ...(instance.icon === undefined ? {} : { icon: instance.icon }),
    ...(instance.description === undefined ? {} : { description: instance.description }),
    rootPath: instance.rootPath,
    kind: instance.kind,
    homePath: instance.homePath,
    ...(instance.syncGroupId === undefined ? {} : { syncGroupId: instance.syncGroupId }),
    status: live?.status ?? (instance.error === undefined ? 'stopped' : 'error'),
    runtimeStatus: runtime.status,
    ...(runtime.version === undefined ? {} : { detectedVersion: runtime.version }),
    ...(instance.lastLaunchedAt === undefined ? {} : { lastLaunchedAt: instance.lastLaunchedAt }),
    favorite: instance.favorite === true,
    ...(live === undefined ? {} : { port: live.port, pid: live.process.pid, url: live.url }),
    ...(instance.error === undefined ? {} : { error: instance.error }),
  }
}

async function updateInstance(instance: StoredInstance, body: JsonRecord): Promise<StoredInstance> {
  const name = body.name === undefined ? instance.name : stringValue(body.name)
  if (name === undefined) throw new HttpError(400, '实例名称不能为空。')
  const icon = body.icon === undefined ? instance.icon : stringValue(body.icon)
  const description = body.description === undefined ? instance.description : stringValue(body.description)
  const updated: StoredInstance = {
    ...instance,
    name,
    ...(icon === undefined ? { icon: undefined } : { icon }),
    ...(description === undefined ? { description: undefined } : { description }),
    ...(typeof body.favorite === 'boolean' ? { favorite: body.favorite } : {}),
  }
  registry = { ...registry, instances: registry.instances.map(item => item.id === instance.id ? updated : item) }
  await persistRegistry()
  return updated
}

async function runtimeStatus(instance: StoredInstance): Promise<{ status: ManagerInstance['runtimeStatus']; version?: string }> {
  const manifest = await readJsonFile(join(instance.rootPath, 'package.json'))
  if (instance.kind === 'source') {
    if (!(await isDirectory(join(instance.rootPath, 'node_modules')))) return { status: 'needs-install' }
    if (!(await fileExists(join(instance.rootPath, 'apps', 'cli', 'src', 'bin.ts')))) return { status: 'broken' }
    return { status: 'ready', version: stringField(manifest, 'version') }
  }
  const bin = join(instance.rootPath, 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js')
  if (!(await fileExists(bin))) return { status: 'needs-install', version: dependencyValue(manifest, '@deepseek-ai/dsh') }
  return { status: 'ready', version: dependencyValue(manifest, '@deepseek-ai/dsh') }
}

async function launchInstance(instance: StoredInstance): Promise<{ url: string; port: number; reused: boolean }> {
  const existing = running.get(instance.id)
  if (existing !== undefined) return { url: existing.url, port: existing.port, reused: true }
  const groupConflict = instance.syncGroupId === undefined
    ? undefined
    : registry.instances.find(candidate => candidate.id !== instance.id
      && candidate.syncGroupId === instance.syncGroupId
      && running.has(candidate.id))
  if (groupConflict !== undefined) throw new HttpError(409, `同步组“${instance.syncGroupId}”已有实例运行：${groupConflict.name}。首版同步组只允许同时运行一个实例。`)
  await ensureDependencies(instance)
  await mkdir(instance.homePath, { recursive: true })
  const port = await findFreePort()
  const patch = await writeSyncPatch(instance)
  const command = await resolveLaunchCommand(instance, port, patch)
  const logDirectory = join(instance.homePath, 'logs')
  await mkdir(logDirectory, { recursive: true })
  const logPath = join(logDirectory, 'manager-launch.log')
  const child = spawn(command.command, command.args, {
    cwd: instance.rootPath,
    env: { ...process.env, DSH_HOME: instance.homePath },
    windowsHide: true,
    shell: process.platform === 'win32' && /\.cmd$/i.test(command.command),
    stdio: ['pipe', 'pipe', 'pipe'],
  })
  const state: RunningInstance = { process: child, port, url: `http://127.0.0.1:${port}`, logPath, lines: [], status: 'starting', logWrite: Promise.resolve() }
  running.set(instance.id, state)
  child.stdout.on('data', chunk => appendLog(state, String(chunk)))
  child.stderr.on('data', chunk => appendLog(state, String(chunk)))
  child.once('error', (error) => { state.processError = error; appendLog(state, errorMessage(error)) })
  child.once('exit', (code, signal) => { void handleChildExit(instance.id, state, code, signal) })
  await updateRuntimeFields(instance.id, { port, pid: child.pid, error: undefined })
  try {
    await waitForPort(port, 30000, state)
    await waitForHttp(state.url, 30000, state)
    state.status = 'running'
    await updateRuntimeFields(instance.id, { lastLaunchedAt: new Date().toISOString(), error: undefined })
  } catch (error) {
    await stopInstance(instance.id)
    const message = errorMessage(error)
    await updateRuntimeFields(instance.id, { error: message })
    throw new HttpError(500, `DSh 启动失败：${message}`)
  }
  return { url: state.url, port, reused: false }
}

async function handleChildExit(id: string, state: RunningInstance, code: number | null, signal: NodeJS.Signals | null): Promise<void> {
  if (running.get(id) !== state) return
  running.delete(id)
  await state.logWrite
  const message = code === 0 ? undefined : `DSh 进程已退出（code=${code ?? 'unknown'}${signal === null ? '' : `, signal=${signal}`}）。`
  await updateRuntimeFields(id, { port: undefined, pid: undefined, ...(message === undefined ? {} : { error: message }) })
}

async function updateRuntimeFields(id: string, fields: Partial<StoredInstance>): Promise<void> {
  const current = findStoredInstance(id)
  if (current === undefined) return
  const updated = { ...current, ...fields }
  registry = { ...registry, instances: registry.instances.map(item => item.id === id ? updated : item) }
  await persistRegistry()
}

async function checkInstanceHealth(instance: StoredInstance): Promise<{
  healthy: boolean
  status: InstanceStatus
  port?: number
  pid?: number
  url?: string
  statusCode?: number
  error?: string
}> {
  const live = running.get(instance.id)
  if (live === undefined) return { healthy: false, status: instance.error === undefined ? 'stopped' : 'error', ...(instance.error === undefined ? {} : { error: instance.error }) }
  try {
    const response = await fetch(live.url, { signal: AbortSignal.timeout(2000) })
    return { healthy: response.ok, status: live.status, port: live.port, pid: live.process.pid, url: live.url, statusCode: response.status }
  } catch (error) {
    return { healthy: false, status: live.status, port: live.port, pid: live.process.pid, url: live.url, error: errorMessage(error) }
  }
}

async function waitForHttp(url: string, timeoutMs: number, state: RunningInstance): Promise<void> {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    if (state.processError !== undefined) throw state.processError
    if (state.process.exitCode !== null) throw new Error(`进程已退出，代码 ${state.process.exitCode}`)
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(1000) })
      if (response.ok) return
    } catch { /* The service may still be warming up. */ }
    await new Promise(resolvePromise => setTimeout(resolvePromise, 250))
  }
  throw new Error('DSh HTTP 页面在 30 秒内没有通过健康检查。')
}

async function resolveLaunchCommand(instance: StoredInstance, port: number, patch?: string): Promise<{ command: string; args: string[] }> {
  const extra = patch === undefined ? [] : ['--patch', patch]
  const node = await resolveNodeCommand(instance)
  if (instance.kind === 'source') {
    return { command: node, args: ['--import', 'tsx/esm', join(instance.rootPath, 'apps', 'cli', 'src', 'bin.ts'), 'web', ...extra, '--port', String(port)] }
  }
  const bin = join(instance.rootPath, 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js')
  return { command: node, args: [bin, 'web', ...extra, '--port', String(port)] }
}

async function resolveNodeCommand(instance: StoredInstance): Promise<string> {
  const configured = process.env.DSH_MANAGER_NODE
  if (configured !== undefined && await fileExists(configured)) return configured
  const bundled = join(instance.rootPath, 'node.exe')
  if (await fileExists(bundled)) return bundled
  const scoopNode = 'D:\\DevTools\\Scoop\\apps\\nodejs-lts\\current\\bin\\node.exe'
  if (process.platform === 'win32' && await fileExists(scoopNode)) return scoopNode
  return 'node'
}

async function ensureDependencies(instance: StoredInstance): Promise<void> {
  const status = await runtimeStatus(instance)
  if (status.status === 'ready') return
  const packageManager = process.env.DSH_MANAGER_PNPM ?? (await fileExists(join(instance.rootPath, 'pnpm-lock.yaml')) ? 'pnpm.cmd' : 'npm.cmd')
  const args = packageManager.toLowerCase().includes('npm') ? ['install', '--no-audit', '--no-fund'] : ['install']
  const result = await runCommand(packageManager, args, instance.rootPath, 10 * 60 * 1000)
  if (result.code !== 0) throw new HttpError(500, `依赖安装失败：${result.output.slice(-1600)}`)
  const after = await runtimeStatus(instance)
  if (after.status !== 'ready') throw new HttpError(500, '依赖安装完成，但仍未找到可启动的 DSh。')
}

async function writeSyncPatch(instance: StoredInstance): Promise<string | undefined> {
  if (instance.syncGroupId === undefined) return undefined
  const root = join(managerRoot, 'sync-groups', instance.syncGroupId, 'sessions')
  await mkdir(root, { recursive: true })
  const patchPath = join(managerRoot, 'instances', instance.id, 'sync.patch.yml')
  await mkdir(dirname(patchPath), { recursive: true })
  const escaped = root.replace(/'/g, "''")
  await writeFile(patchPath, `- id: session-persistence-jsonl\n  config:\n    root: '${escaped}'\n`, 'utf8')
  return patchPath
}

async function stopInstance(id: string): Promise<void> {
  const live = running.get(id)
  if (live === undefined) {
    await updateRuntimeFields(id, { port: undefined, pid: undefined })
    return
  }
  running.delete(id)
  if (process.platform === 'win32') {
    try { await execFile('taskkill.exe', ['/pid', String(live.process.pid), '/t', '/f']) } catch { /* The process may have exited. */ }
  } else {
    live.process.kill('SIGTERM')
  }
  await new Promise<void>((resolvePromise) => {
    if (live.process.exitCode !== null) { resolvePromise(); return }
    const timer = setTimeout(resolvePromise, 3000)
    live.process.once('exit', () => { clearTimeout(timer); resolvePromise() })
  })
  await live.logWrite
  await updateRuntimeFields(id, { port: undefined, pid: undefined })
}

function appendLog(state: RunningInstance, chunk: string): void {
  const lines = chunk.split(/\r?\n/).filter(Boolean)
  if (lines.length === 0) return
  state.lines.push(...lines)
  if (state.lines.length > 500) state.lines.splice(0, state.lines.length - 500)
  const text = `${lines.map(line => `${new Date().toISOString()} ${line}`).join('\n')}\n`
  state.logWrite = state.logWrite
    .catch((error) => { console.error(`DSh Manager log write failed: ${errorMessage(error)}`) })
    .then(() => writeFile(state.logPath, text, { encoding: 'utf8', flag: 'a' }))
}

async function readLogs(instance: StoredInstance): Promise<string[]> {
  const live = running.get(instance.id)
  if (live !== undefined) return live.lines.slice(-300)
  const path = join(instance.homePath, 'logs', 'manager-launch.log')
  const text = await readFile(path, 'utf8').catch(() => '')
  return text.split(/\r?\n/).filter(Boolean).slice(-300)
}

async function listExtensions(instance: StoredInstance): Promise<ExtensionEntry[]> {
  const entries: ExtensionEntry[] = []
  const profile = await readJsonFile(join(instance.homePath, 'profiles', 'web', 'package.json'))
  for (const [name, value] of Object.entries(dependencies(profile))) {
    entries.push({ id: name, kind: 'plugin', name, version: String(value), source: 'profile package.json', enabled: true, managed: true })
  }
  const local = await readJsonFile(join(instance.homePath, '.dsh-manager', 'extensions.json'))
  const installed = Array.isArray(local.extensions) ? local.extensions : []
  for (const value of installed) {
    if (!isRecord(value) || typeof value.id !== 'string' || typeof value.kind !== 'string') continue
    entries.push({
      id: value.id,
      kind: extensionKind(value.kind) ?? 'plugin',
      name: typeof value.name === 'string' ? value.name : value.id,
      ...(typeof value.version === 'string' ? { version: value.version } : {}),
      ...(typeof value.description === 'string' ? { description: value.description } : {}),
      source: typeof value.source === 'string' ? value.source : 'manager',
      enabled: value.enabled !== false,
      managed: true,
    })
  }
  return deduplicate(entries)
}

async function listSkills(instance: StoredInstance): Promise<SkillEntry[]> {
  const roots: Array<{ path: string; source: SkillEntry['source']; managed: boolean }> = [
    { path: join(instance.homePath, 'skills'), source: 'instance', managed: true },
    { path: join(instance.rootPath, '.dsh', 'skills'), source: 'project-dsh', managed: false },
    { path: join(instance.rootPath, '.agents', 'skills'), source: 'project-agents', managed: false },
  ]
  const result: SkillEntry[] = []
  for (const root of roots) {
    const children = await readdir(root.path, { withFileTypes: true }).catch(() => [])
    for (const child of children) {
      const candidate = child.isDirectory() ? join(root.path, child.name, 'SKILL.md') : join(root.path, child.name)
      if (!child.isDirectory() && !child.name.endsWith('.md')) continue
      if (!(await fileExists(candidate))) continue
      const frontmatter = await parseSkill(candidate)
      if (frontmatter === undefined) continue
      result.push({
        id: `${root.source}:${candidate}`,
        name: frontmatter.name,
        description: frontmatter.description,
        path: candidate,
        source: root.source,
        managed: root.managed,
        modelInvocable: frontmatter.modelInvocable,
        userInvocable: frontmatter.userInvocable,
      })
    }
  }
  return result.sort((left, right) => left.name.localeCompare(right.name))
}

async function importSkill(instance: StoredInstance, sourcePath: string, requestedName?: string): Promise<void> {
  const source = await realpath(resolve(sourcePath)).catch(() => { throw new HttpError(400, 'Skill 源路径不存在。') })
  const sourceInfo = await stat(source)
  const name = requestedName?.trim() || source.split(sep).filter(Boolean).at(-1)?.replace(/\.md$/i, '') || 'skill'
  const target = join(instance.homePath, 'skills', safeSegment(name))
  await mkdir(dirname(target), { recursive: true })
  if (await fileExists(target)) throw new HttpError(409, '实例中已经存在同名 Skill。')
  await cp(source, target, { recursive: sourceInfo.isDirectory() })
}

async function removeManagedSkill(instance: StoredInstance, skillPath: string): Promise<void> {
  const root = resolve(join(instance.homePath, 'skills'))
  const target = resolve(skillPath)
  const child = relative(root, target)
  if (child === '' || child.startsWith(`..${sep}`) || child === '..' || resolve(target) === root) {
    throw new HttpError(400, '只能删除实例自己的 Skill。')
  }
  await rm(target, { recursive: true, force: false }).catch(() => { throw new HttpError(404, 'Skill 文件不存在。') })
}

async function installExtension(instance: StoredInstance, kind: ExtensionKind, source: string, requestedName?: string): Promise<void> {
  if (kind === 'plugin') {
    const node = await resolveNodeCommand(instance)
    const command = instance.kind === 'source'
      ? { command: node, args: ['--import', 'tsx/esm', join(instance.rootPath, 'apps', 'cli', 'src', 'bin.ts'), 'plugin', '--profile', 'web', 'add', source] }
      : { command: node, args: [join(instance.rootPath, 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js'), 'plugin', '--profile', 'web', 'add', source] }
    const result = await runCommand(
      command.command,
      command.args,
      instance.rootPath,
      10 * 60 * 1000,
      { ...process.env, DSH_HOME: instance.homePath },
    )
    if (result.code !== 0) throw new HttpError(500, `插件安装失败：${result.output.slice(-1600)}`)
    return
  }
  if (kind === 'skill' && /^https?:\/\//i.test(source) && source.includes('github.com')) {
    const target = join(instance.homePath, 'skills', safeSegment(requestedName ?? source.split('/').filter(Boolean).at(-1) ?? 'skill'))
    if (await fileExists(target)) throw new HttpError(409, '实例中已经存在同名 Skill。')
    await mkdir(dirname(target), { recursive: true })
    const result = await runCommand('git', ['clone', '--depth', '1', source, target], instance.homePath, 10 * 60 * 1000)
    if (result.code !== 0) throw new HttpError(500, `Skill 安装失败：${result.output.slice(-1600)}`)
    return
  }
  const local = await readJsonFile(join(instance.homePath, '.dsh-manager', 'extensions.json'))
  const values = Array.isArray(local.extensions) ? local.extensions.filter(isRecord) : []
  const id = requestedName ?? source
  values.push({ id, kind, name: requestedName ?? id, source, enabled: true })
  await mkdir(join(instance.homePath, '.dsh-manager'), { recursive: true })
  await writeFile(join(instance.homePath, '.dsh-manager', 'extensions.json'), JSON.stringify({ extensions: values }, null, 2), 'utf8')
}

async function discoverCatalog(query: string): Promise<CatalogResponse> {
  const entries: MarketplaceEntry[] = [
    { id: '@deepseek-ai/dsh-skill-filesystem', kind: 'plugin', name: 'DSh Skill Filesystem', description: '本地 SKILL.md 发现和热更新。', source: { type: 'npm', locator: '@deepseek-ai/dsh-skill-filesystem' }, verified: true, permissions: ['读取 Skill 文件'] },
    { id: '@deepseek-ai/dsh-mcp-client', kind: 'plugin', name: 'DSh MCP Client', description: '连接 MCP 服务并注册工具。', source: { type: 'npm', locator: '@deepseek-ai/dsh-mcp-client' }, verified: true, permissions: ['启动外部 MCP 进程', '访问网络'] },
  ]
  const warning: string[] = []
  try {
    const response = await fetch(`https://api.github.com/search/repositories?q=topic%3Adsh-plugin${query ? `%20${encodeURIComponent(query)}` : ''}&per_page=30`, { headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'dsh-manager' } })
    if (!response.ok) throw new Error(`GitHub HTTP ${response.status}`)
    const payload = await response.json() as JsonRecord
    const items = Array.isArray(payload.items) ? payload.items : []
    for (const item of items) {
      if (!isRecord(item) || typeof item.full_name !== 'string' || typeof item.name !== 'string') continue
      entries.push({
        id: `github:${item.full_name}`,
        kind: 'plugin',
        name: item.name,
        description: typeof item.description === 'string' ? item.description : 'GitHub DSh 插件',
        source: { type: 'github', locator: typeof item.clone_url === 'string' ? item.clone_url : `https://github.com/${item.full_name}.git` },
        repository: `https://github.com/${item.full_name}`,
        verified: Boolean(item.owner && isRecord(item.owner) && item.owner.login === 'deepseek-ai'),
        permissions: ['执行插件代码（请先检查仓库）'],
      })
    }
  } catch (error) {
    warning.push(`GitHub 目录不可用：${errorMessage(error)}`)
  }
  try {
    const response = await fetch(`https://registry.npmjs.org/-/v1/search?text=${encodeURIComponent(`@deepseek-ai/dsh- ${query}`)}&size=30`, { headers: { Accept: 'application/json', 'User-Agent': 'dsh-manager' } })
    if (!response.ok) throw new Error(`npm HTTP ${response.status}`)
    const payload = await response.json() as JsonRecord
    const objects = Array.isArray(payload.objects) ? payload.objects : []
    for (const object of objects) {
      if (!isRecord(object) || !isRecord(object.package) || typeof object.package.name !== 'string' || !object.package.name.startsWith('@deepseek-ai/dsh-')) continue
      entries.push({ id: object.package.name, kind: 'plugin', name: object.package.name, description: typeof object.package.description === 'string' ? object.package.description : 'DeepSeek Harness 官方包', source: { type: 'npm', locator: object.package.name }, repository: typeof object.package.links === 'object' && object.package.links !== null && 'repository' in object.package.links && typeof object.package.links.repository === 'string' ? object.package.links.repository : undefined, verified: true, permissions: ['执行插件代码'] })
    }
  } catch (error) {
    warning.push(`npm 目录不可用：${errorMessage(error)}`)
  }
  for (const catalog of registry.catalogs) {
    try {
      const response = await fetch(catalog.url, { headers: { Accept: 'application/json', 'User-Agent': 'dsh-manager' } })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const payload = await response.json() as JsonRecord
      const values = Array.isArray(payload.entries) ? payload.entries : []
      for (const value of values) {
        const entry = marketplaceEntry(value)
        if (entry !== undefined) entries.push({ ...entry, verified: false })
      }
    } catch (error) {
      warning.push(`${catalog.name} 不可用：${errorMessage(error)}`)
    }
  }
  const filtered = deduplicateMarketplace(entries)
    .filter(entry => !query || `${entry.name} ${entry.description}`.toLowerCase().includes(query.toLowerCase()))
    .sort((left, right) => Number(right.verified) - Number(left.verified) || left.name.localeCompare(right.name))
  return { entries: filtered, ...(warning.length === 0 ? {} : { warning: warning.join('；') }) }
}

async function listConversations(instance: StoredInstance): Promise<ConversationSummary[]> {
  const root = instance.syncGroupId === undefined ? join(instance.homePath, 'sessions') : join(managerRoot, 'sync-groups', instance.syncGroupId, 'sessions')
  const result: ConversationSummary[] = []
  await walk(root, async (path) => {
    if (!/\.jsonl(?:\.zstd)?$/i.test(path)) return
    const info = await stat(path)
    result.push({ id: relative(root, path), location: path, sizeBytes: info.size, updatedAt: info.mtime.toISOString() })
  }, 3)
  return result.sort((left, right) => right.updatedAt.localeCompare(left.updatedAt)).slice(0, 100)
}

async function walk(root: string, visit: (path: string) => Promise<void>, depth: number): Promise<void> {
  if (depth < 0) return
  const children = await readdir(root, { withFileTypes: true }).catch(() => [])
  for (const child of children) {
    const path = join(root, child.name)
    if (child.isDirectory()) await walk(path, visit, depth - 1)
    else await visit(path)
  }
}

async function runCommand(
  command: string,
  args: string[],
  cwd: string,
  timeoutMs: number,
  environment: NodeJS.ProcessEnv = process.env,
): Promise<{ code: number; output: string }> {
  return await new Promise((resolvePromise) => {
    const child = spawn(command, args, { cwd, env: environment, windowsHide: true, shell: process.platform === 'win32' && /\.cmd$/i.test(command), stdio: ['ignore', 'pipe', 'pipe'] })
    let output = ''
    const timer = setTimeout(() => {
      child.kill()
      resolvePromise({ code: 124, output: `${output}\n命令超时。` })
    }, timeoutMs)
    child.stdout.on('data', (chunk) => { output += String(chunk) })
    child.stderr.on('data', (chunk) => { output += String(chunk) })
    child.once('error', (error) => { clearTimeout(timer); resolvePromise({ code: 1, output: `${output}\n${errorMessage(error)}` }) })
    child.once('exit', (code) => { clearTimeout(timer); resolvePromise({ code: code ?? 1, output }) })
  })
}

async function waitForPort(port: number, timeoutMs: number, state: RunningInstance): Promise<void> {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    if (state.processError !== undefined) throw state.processError
    if (state.process.exitCode !== null) throw new Error(`进程已退出，代码 ${state.process.exitCode}`)
    const ready = await new Promise<boolean>((resolvePromise) => {
      const socket = createConnection({ host: '127.0.0.1', port })
      socket.once('connect', () => { socket.destroy(); resolvePromise(true) })
      socket.once('error', () => { socket.destroy(); resolvePromise(false) })
    })
    if (ready) return
    await new Promise(resolvePromise => setTimeout(resolvePromise, 250))
  }
  throw new Error('本地服务在 30 秒内没有监听端口。')
}

async function findFreePort(): Promise<number> {
  return await new Promise((resolvePromise, reject) => {
    const socket = createServer()
    socket.once('error', reject)
    socket.listen(0, '127.0.0.1', () => {
      const address = socket.address()
      socket.close(() => {
        if (typeof address === 'object' && address !== null) resolvePromise(address.port)
        else reject(new Error('无法分配本地端口。'))
      })
    })
  })
}

async function serveStatic(pathname: string, response: ServerResponse): Promise<void> {
  const requested = pathname === '/' ? 'index.html' : pathname.replace(/^\//, '')
  const candidate = resolve(staticRoot, requested)
  const child = relative(staticRoot, candidate)
  const path = child === '' || child.startsWith(`..${sep}`) || child === '..' ? join(staticRoot, 'index.html') : candidate
  const content = await readFile(path).catch(async () => await readFile(join(staticRoot, 'index.html')))
  const extension = extname(path).toLowerCase()
  const type = extension === '.js' ? 'text/javascript; charset=utf-8' : extension === '.css' ? 'text/css; charset=utf-8' : extension === '.svg' ? 'image/svg+xml' : 'text/html; charset=utf-8'
  response.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' })
  response.end(content)
}

async function readJson(request: IncomingMessage): Promise<JsonRecord> {
  const body = await new Promise<string>((resolvePromise, reject) => {
    let content = ''
    request.setEncoding('utf8')
    request.on('data', (chunk) => { content += chunk })
    request.on('end', () => resolvePromise(content))
    request.on('error', reject)
  })
  if (body.trim() === '') return {}
  try {
    const parsed = JSON.parse(body) as unknown
    if (!isRecord(parsed)) throw new Error('JSON body must be an object.')
    return parsed
  } catch (error) {
    throw new HttpError(400, `请求数据无效：${errorMessage(error)}`)
  }
}

function respondJson(response: ServerResponse, status: number, value: unknown): void {
  response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' })
  response.end(JSON.stringify(value))
}

class HttpError extends Error {
  constructor(readonly status: number, message: string) { super(message) }
}

function findStoredInstance(id: string): StoredInstance | undefined { return registry.instances.find(instance => instance.id === id) }
function withoutSyncGroup(instance: StoredInstance): StoredInstance {
  const { syncGroupId: _syncGroupId, ...rest } = instance
  return rest
}
function isStoredInstance(value: unknown): value is StoredInstance { return isRecord(value) && typeof value.id === 'string' && typeof value.name === 'string' && typeof value.rootPath === 'string' && (value.kind === 'installed' || value.kind === 'source') && typeof value.homePath === 'string' }
function isStoredCatalogSource(value: unknown): value is StoredCatalogSource { return isRecord(value) && typeof value.id === 'string' && typeof value.url === 'string' && typeof value.name === 'string' }
function isRecord(value: unknown): value is JsonRecord { return typeof value === 'object' && value !== null && !Array.isArray(value) }
function stringValue(value: unknown): string | undefined { return typeof value === 'string' && value.trim() !== '' ? value.trim() : undefined }
function stringField(value: JsonRecord, key: string): string | undefined { return stringValue(value[key]) }
function dependencyValue(value: JsonRecord, name: string): string | undefined { return stringValue(dependencies(value)[name]) }
function dependencies(value: JsonRecord): Record<string, unknown> {
  return {
    ...(isRecord(value.dependencies) ? value.dependencies : {}),
    ...(isRecord(value.devDependencies) ? value.devDependencies : {}),
  }
}
function extensionKind(value: unknown): ExtensionKind | undefined { return value === 'plugin' || value === 'skill' || value === 'mcp' || value === 'workflow' || value === 'preset' ? value : undefined }
function safeSegment(value: string): string { return value.replace(/[^a-zA-Z0-9._-]+/g, '-').replace(/^-+|-+$/g, '') || 'skill' }
function errorMessage(error: unknown): string { return error instanceof Error ? error.message : String(error) }
function deduplicate(entries: ExtensionEntry[]): ExtensionEntry[] { return [...new Map(entries.map(entry => [entry.id, entry])).values()] }
function deduplicateMarketplace(entries: MarketplaceEntry[]): MarketplaceEntry[] {
  return [...new Map(entries.map(entry => [entry.id, entry])).values()]
}
function marketplaceEntry(value: unknown): MarketplaceEntry | undefined {
  if (!isRecord(value) || typeof value.id !== 'string' || typeof value.name !== 'string' || typeof value.description !== 'string' || !isRecord(value.source) || typeof value.source.type !== 'string' || typeof value.source.locator !== 'string') return undefined
  const kind = extensionKind(value.kind)
  if (kind === undefined || (value.source.type !== 'npm' && value.source.type !== 'github' && value.source.type !== 'local')) return undefined
  return { id: value.id, kind, name: value.name, description: value.description, source: { type: value.source.type, locator: value.source.locator }, ...(typeof value.version === 'string' ? { version: value.version } : {}), verified: false, permissions: Array.isArray(value.permissions) ? value.permissions.filter((item): item is string => typeof item === 'string') : [] }
}
async function readJsonFile(path: string): Promise<JsonRecord> { try { const value = JSON.parse(await readFile(path, 'utf8')) as unknown; return isRecord(value) ? value : {} } catch { return {} } }
async function fileExists(path: string): Promise<boolean> { try { return (await stat(path)).isFile() } catch { return false } }
async function isDirectory(path: string): Promise<boolean> { try { return (await stat(path)).isDirectory() } catch { return false } }
async function parseSkill(path: string): Promise<{
  name: string
  description: string
  modelInvocable: boolean
  userInvocable: boolean
} | undefined> {
  const raw = await readFile(path, 'utf8').catch(() => '')
  const match = raw.match(/^---\s*\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/)
  if (match === null) return undefined
  const field = (key: string): string | undefined => match[1].split(/\r?\n/).find(line => line.startsWith(`${key}:`))?.slice(key.length + 1).trim().replace(/^['"]|['"]$/g, '')
  const name = field('name')
  const description = field('description')
  if (name === undefined || description === undefined) return undefined
  const disabled = field('disable-model-invocation')
  const user = field('user-invocable')
  return { name, description, modelInvocable: !['true', 'yes', 'on', '1'].includes(disabled?.toLowerCase() ?? ''), userInvocable: !['false', 'no', 'off', '0'].includes(user?.toLowerCase() ?? '') }
}
async function persistRegistry(): Promise<void> { registryWrite = registryWrite.then(() => writeFile(registryPath, JSON.stringify(registry, null, 2), 'utf8')); await registryWrite }
