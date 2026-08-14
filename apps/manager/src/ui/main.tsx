import { useEffect, useMemo, useState } from 'react'
import { createRoot } from 'react-dom/client'
import type { ReactNode } from 'react'
import type {
  CatalogResponse,
  ConversationSummary,
  ExtensionEntry,
  MarketplaceEntry,
  ManagerInstance,
  SkillEntry,
} from '../types.js'
import './styles.css'

type Tab = 'home' | 'instances' | 'extensions' | 'models' | 'agents' | 'conversations' | 'diagnostics'

declare global {
  interface Window {
    chrome?: {
      webview?: {
        postMessage(message: unknown): void
        addEventListener(type: string, listener: (event: MessageEvent) => void): void
        removeEventListener(type: string, listener: (event: MessageEvent) => void): void
      }
    }
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, { ...init, headers: { 'Content-Type': 'application/json', ...(init?.headers ?? {}) } })
  const value = await response.json() as { error?: string } & T
  if (!response.ok) throw new Error(value.error ?? `请求失败（${response.status}）`)
  return value
}

function App() {
  const [tab, setTab] = useState<Tab>('home')
  const [instances, setInstances] = useState<ManagerInstance[]>([])
  const [selectedId, setSelectedId] = useState<string>()
  const [extensions, setExtensions] = useState<ExtensionEntry[]>([])
  const [skills, setSkills] = useState<SkillEntry[]>([])
  const [catalog, setCatalog] = useState<MarketplaceEntry[]>([])
  const [conversations, setConversations] = useState<ConversationSummary[]>([])
  const [logs, setLogs] = useState<string[]>([])
  const [catalogWarning, setCatalogWarning] = useState('')
  const [catalogQuery, setCatalogQuery] = useState('')
  const [folderPath, setFolderPath] = useState('')
  const [instanceName, setInstanceName] = useState('')
  const [instanceDescription, setInstanceDescription] = useState('')
  const [instanceIcon, setInstanceIcon] = useState('D')
  const [skillPath, setSkillPath] = useState('')
  const [error, setError] = useState('')
  const [health, setHealth] = useState('尚未检查')
  const [busy, setBusy] = useState(false)

  const selected = useMemo(() => instances.find(instance => instance.id === selectedId), [instances, selectedId])

  const refreshInstances = async (): Promise<void> => {
    const value = await request<{ instances: ManagerInstance[] }>('/api/instances')
    setInstances(value.instances)
    if (selectedId === undefined && value.instances[0] !== undefined) setSelectedId(value.instances[0].id)
  }

  const refreshSelected = async (id: string): Promise<void> => {
    const [ext, skill, conversation, log] = await Promise.all([
      request<{ extensions: ExtensionEntry[] }>(`/api/instances/${id}/extensions`),
      request<{ skills: SkillEntry[] }>(`/api/instances/${id}/skills`),
      request<{ conversations: ConversationSummary[] }>(`/api/instances/${id}/conversations`),
      request<{ lines: string[] }>(`/api/instances/${id}/logs`),
    ])
    setExtensions(ext.extensions)
    setSkills(skill.skills)
    setConversations(conversation.conversations)
    setLogs(log.lines)
  }

  useEffect(() => {
    void refreshInstances().catch(showError)
    const onNativeMessage = (event: MessageEvent): void => {
      const data = typeof event.data === 'string' ? tryJson(event.data) : event.data
      if (isRecord(data) && data.type === 'folder-selected' && typeof data.path === 'string') setFolderPath(data.path)
    }
    window.chrome?.webview?.addEventListener('message', onNativeMessage)
    return () => window.chrome?.webview?.removeEventListener('message', onNativeMessage)
  }, [])

  useEffect(() => {
    if (selectedId === undefined) return
    void refreshSelected(selectedId).catch(showError)
  }, [selectedId])

  useEffect(() => {
    if (tab !== 'extensions') return
    void loadCatalog(catalogQuery)
  }, [tab, catalogQuery])

  function showError(value: unknown): void { setError(value instanceof Error ? value.message : String(value)) }
  function run(action: () => Promise<void>): void { setError(''); setBusy(true); void action().catch(showError).finally(() => setBusy(false)) }

  function addFolder(): void {
    if (folderPath.trim() === '') { setError('请输入或选择 DSh 文件夹路径。'); return }
    run(async () => {
      const value = await request<{ instance: ManagerInstance }>('/api/instances', { method: 'POST', body: JSON.stringify({ path: folderPath, name: instanceName, description: instanceDescription, icon: instanceIcon }) })
      setFolderPath('')
      setInstanceName('')
      setInstanceDescription('')
      setInstanceIcon('D')
      await refreshInstances()
      setSelectedId(value.instance.id)
      setTab('instances')
    })
  }

  function selectFolder(): void { window.chrome?.webview?.postMessage({ type: 'pick-folder' }); if (window.chrome?.webview === undefined) setError('浏览器预览模式不能打开 Windows 文件夹选择器，请直接输入路径。') }

  function launch(instance: ManagerInstance): void {
    run(async () => {
      const value = await request<{ launch: { url: string } }>(`/api/instances/${instance.id}/launch`, { method: 'POST' })
      await refreshInstances()
      window.open(value.launch.url, '_blank', 'noopener,noreferrer')
    })
  }

  function stop(instance: ManagerInstance): void { run(async () => { await request(`/api/instances/${instance.id}/stop`, { method: 'POST' }); await refreshInstances() }) }

  function restart(instance: ManagerInstance): void {
    run(async () => {
      const value = await request<{ launch: { url: string } }>(`/api/instances/${instance.id}/restart`, { method: 'POST' })
      await refreshInstances()
      window.open(value.launch.url, '_blank', 'noopener,noreferrer')
    })
  }

  function toggleFavorite(instance: ManagerInstance): void {
    run(async () => {
      await request(`/api/instances/${instance.id}`, { method: 'PATCH', body: JSON.stringify({ favorite: !instance.favorite }) })
      await refreshInstances()
    })
  }

  function checkHealth(instance: ManagerInstance): void {
    run(async () => {
      const value = await request<{ healthy: boolean; status: string; statusCode?: number; error?: string }>(`/api/instances/${instance.id}/health`)
      setHealth(value.healthy ? `健康 · HTTP ${value.statusCode ?? 200}` : `未通过 · ${value.error ?? value.status}`)
      await refreshInstances()
    })
  }

  async function loadCatalog(query: string): Promise<void> {
    try {
      const value = await request<CatalogResponse>(`/api/catalog?q=${encodeURIComponent(query)}`)
      setCatalog([...value.entries])
      setCatalogWarning(value.warning ?? '')
    } catch (value) { showError(value) }
  }

  function install(entry: MarketplaceEntry): void {
    if (selected === undefined) { setError('请先选择一个实例。'); return }
    run(async () => {
      await request(`/api/instances/${selected.id}/extensions/install`, { method: 'POST', body: JSON.stringify({ kind: entry.kind, source: entry.source.locator, name: entry.name }) })
      await refreshSelected(selected.id)
    })
  }

  function importSkill(): void {
    if (selected === undefined || skillPath.trim() === '') { setError('请先选择实例并输入 Skill 路径。'); return }
    run(async () => {
      await request(`/api/instances/${selected.id}/skills/import`, { method: 'POST', body: JSON.stringify({ path: skillPath }) })
      setSkillPath('')
      await refreshSelected(selected.id)
    })
  }

  function removeSkill(skill: SkillEntry): void {
    if (selected === undefined || !skill.managed || !window.confirm(`删除实例 Skill“${skill.name}”？`)) return
    run(async () => {
      await request(`/api/instances/${selected.id}/skills/remove`, { method: 'POST', body: JSON.stringify({ path: skill.path }) })
      await refreshSelected(selected.id)
    })
  }

  function setSyncGroup(value: string): void {
    if (selected === undefined) return
    run(async () => {
      await request(`/api/instances/${selected.id}/sync`, { method: 'POST', body: JSON.stringify(value.trim() === '' ? {} : { syncGroupId: value.trim() }) })
      await refreshInstances()
      await refreshSelected(selected.id)
    })
  }

  const pages: Record<Tab, ReactNode> = {
    home: <HomePage
      instances={instances}
      selected={selected}
      onSelect={setSelectedId}
      onLaunch={launch}
      onRestart={restart}
      onStop={stop}
      onToggleFavorite={toggleFavorite}
    />,
    instances: <InstancesPage
      instances={instances}
      selected={selected}
      onSelect={setSelectedId}
      onLaunch={launch}
      onRestart={restart}
      onStop={stop}
      onToggleFavorite={toggleFavorite}
      folderPath={folderPath}
      setFolderPath={setFolderPath}
      instanceName={instanceName}
      setInstanceName={setInstanceName}
      instanceDescription={instanceDescription}
      setInstanceDescription={setInstanceDescription}
      instanceIcon={instanceIcon}
      setInstanceIcon={setInstanceIcon}
      onPickFolder={selectFolder}
      onAdd={addFolder}
    />,
    extensions: <ExtensionsPage
      selected={selected}
      extensions={extensions}
      skills={skills}
      catalog={catalog}
      catalogQuery={catalogQuery}
      setCatalogQuery={setCatalogQuery}
      catalogWarning={catalogWarning}
      onInstall={install}
      skillPath={skillPath}
      setSkillPath={setSkillPath}
      onImportSkill={importSkill}
      onRemoveSkill={removeSkill}
    />,
    models: <InfoPage title="模型与 Provider" icon="◈" items={['DeepSeek 官方 Provider', 'OpenAI-compatible Provider', '每个实例独立的默认模型', 'API 凭据只显示配置状态，不显示明文']} />,
    agents: <InfoPage title="Agent 与工作流" icon="✦" items={['Agent 预设', '系统提示词', '工作流', '子 Agent 能力', '按实例启用和切换']} />,
    conversations: <ConversationsPage selected={selected} conversations={conversations} onSetSync={setSyncGroup} />,
    diagnostics: <DiagnosticsPage
      selected={selected}
      health={health}
      logs={logs}
      onRefresh={() => selected === undefined ? undefined : void refreshSelected(selected.id)}
      onCheckHealth={() => selected === undefined ? undefined : checkHealth(selected)}
    />,
  }

  return <div className="app-shell">
    <header className="topbar">
      <div className="brand"><div className="brand-mark">D</div><div><strong>DSh Manager</strong><span>DeepSeek Harness 管理器</span></div></div>
      <nav>{([['home', '启动'], ['instances', '实例'], ['extensions', '扩展'], ['models', '模型'], ['agents', 'Agent'], ['conversations', '对话'], ['diagnostics', '诊断']] as const).map(([key, label]) => <button key={key} className={tab === key ? 'nav-item active' : 'nav-item'} onClick={() => setTab(key)}>{label}</button>)}</nav>
      <div className="top-status"><span className="status-dot" />本地运行</div>
    </header>
    <main className="page-wrap">
      {error !== '' && <div className="error-banner" role="alert">{error}<button onClick={() => setError('')}>×</button></div>}
      {busy && <div className="busy-line" />}
      {pages[tab]}
    </main>
  </div>
}

function HomePage(props: {
  instances: ManagerInstance[]
  selected?: ManagerInstance
  onSelect(id: string): void
  onLaunch(instance: ManagerInstance): void
  onRestart(instance: ManagerInstance): void
  onStop(instance: ManagerInstance): void
  onToggleFavorite(instance: ManagerInstance): void
}) {
  return <section><div className="hero"><div><div className="eyebrow">DEEPSEEK HARNESS WORKSPACE</div><h1>选择一个实例，开始工作。</h1><p>像 PCL2 / Prism Launcher 管理游戏版本一样，管理不同的 DSh 运行环境、扩展和对话。</p></div><div className="hero-orbit">DSh</div></div><div className="section-heading"><div><h2>最近实例</h2><p>{props.instances.length === 0 ? '还没有添加实例' : `${props.instances.length} 个实例已准备好`}</p></div><span className="muted">多实例隔离 · 一键启动 · 扩展生态统一管理</span></div><div className="instance-grid">{props.instances.length === 0 ? <EmptyState title="还没有 DSh 实例" detail="进入“实例”页面添加已有文件夹，或把源码项目加入管理器。" /> : props.instances.map(instance => <InstanceCard key={instance.id} instance={instance} selected={props.selected?.id === instance.id} onSelect={() => props.onSelect(instance.id)} onLaunch={() => props.onLaunch(instance)} onRestart={() => props.onRestart(instance)} onStop={() => props.onStop(instance)} onToggleFavorite={() => props.onToggleFavorite(instance)} />)}</div></section>
}

function InstancesPage(props: {
  instances: ManagerInstance[]
  selected?: ManagerInstance
  onSelect(id: string): void
  onLaunch(instance: ManagerInstance): void
  onRestart(instance: ManagerInstance): void
  onStop(instance: ManagerInstance): void
  onToggleFavorite(instance: ManagerInstance): void
  folderPath: string
  setFolderPath(path: string): void
  instanceName: string
  setInstanceName(value: string): void
  instanceDescription: string
  setInstanceDescription(value: string): void
  instanceIcon: string
  setInstanceIcon(value: string): void
  onPickFolder(): void
  onAdd(): void
}) {
  return <section><PageTitle title="实例管理" detail="DSh 安装版和源码项目都可以添加到同一个启动器；两者在运行卡片中明确区分。" /><div className="two-column"><aside className="folder-panel"><div className="panel-title">文件夹列表</div><div className="folder-root"><span className="folder-icon">⌂</span><div><strong>DeepSeek</strong><small>%USERPROFILE%\Documents\DeepSeek</small></div></div>{props.instances.map(instance => <button className={props.selected?.id === instance.id ? 'folder-row selected' : 'folder-row'} key={instance.id} onClick={() => props.onSelect(instance.id)}><span className="folder-icon">{instance.icon ?? (instance.kind === 'source' ? '⌘' : '▣')}</span><div><strong>{instance.name}</strong><small>{instance.kind === 'source' ? 'source 源码实例' : 'installed 安装实例'}</small></div></button>)}<div className="folder-actions"><input value={props.folderPath} onChange={event => props.setFolderPath(event.target.value)} placeholder="输入文件夹路径" /><input value={props.instanceName} onChange={event => props.setInstanceName(event.target.value)} placeholder="实例名称（可选）" /><input value={props.instanceDescription} onChange={event => props.setInstanceDescription(event.target.value)} placeholder="实例描述（可选）" /><input value={props.instanceIcon} onChange={event => props.setInstanceIcon(event.target.value.slice(0, 2))} placeholder="图标字符" /><button className="secondary" onClick={props.onPickFolder}>选择文件夹</button><button className="primary full" onClick={props.onAdd}>添加已有文件夹</button></div></aside><div><div className="section-heading compact"><div><h2>已添加实例</h2><p>每个实例拥有独立的设置、扩展和 DSh Home；同一同步组首版只允许运行一个实例。</p></div></div><div className="stack">{props.instances.length === 0 ? <EmptyState title="列表为空" detail="添加一个 DSh 安装目录或源码项目。" /> : props.instances.map(instance => <InstanceCard key={instance.id} instance={instance} selected={props.selected?.id === instance.id} onSelect={() => props.onSelect(instance.id)} onLaunch={() => props.onLaunch(instance)} onRestart={() => props.onRestart(instance)} onStop={() => props.onStop(instance)} onToggleFavorite={() => props.onToggleFavorite(instance)} expanded />)}</div></div></div></section>
}

function ExtensionsPage(props: {
  selected?: ManagerInstance
  extensions: ExtensionEntry[]
  skills: SkillEntry[]
  catalog: MarketplaceEntry[]
  catalogQuery: string
  setCatalogQuery(query: string): void
  catalogWarning: string
  onInstall(entry: MarketplaceEntry): void
  skillPath: string
  setSkillPath(path: string): void
  onImportSkill(): void
  onRemoveSkill(skill: SkillEntry): void
}) {
  return <section><PageTitle title="扩展中心" detail={props.selected === undefined ? '选择实例后管理插件、Skill、MCP 和工作流。' : `当前实例：${props.selected.name}`} /><div className="extension-toolbar"><div className="pill-group"><span className="pill active">全部</span><span className="pill">插件</span><span className="pill">Skill</span><span className="pill">MCP</span><span className="pill">工作流</span></div><input className="search" value={props.catalogQuery} onChange={event => props.setCatalogQuery(event.target.value)} placeholder="搜索 GitHub dsh-plugin 与 npm 官方包" /></div><div className="two-column extension-layout"><div><div className="section-heading compact"><div><h2>实例已安装</h2><p>{props.extensions.length} 个扩展 · {props.skills.length} 个 Skill</p></div></div><div className="stack">{props.extensions.map(entry => <ExtensionCard key={`${entry.kind}:${entry.id}`} entry={entry} />)}{props.skills.map(skill => <SkillCard key={skill.id} skill={skill} onRemove={() => props.onRemoveSkill(skill)} />)}{props.selected !== undefined && <div className="import-box"><strong>导入本地 Skill</strong><p>将 Skill 复制到当前实例的独立 skills 目录。</p><input value={props.skillPath} onChange={event => props.setSkillPath(event.target.value)} placeholder="C:\path\to\SKILL.md 或文件夹" /><button className="secondary" onClick={props.onImportSkill}>导入 Skill</button></div>}{props.extensions.length === 0 && props.skills.length === 0 && props.selected === undefined && <EmptyState title="尚未选择实例" detail="先从左侧启动页或实例页选择一个运行环境。" />}</div></div><div><div className="section-heading compact"><div><h2>扩展商店</h2><p>官方包和带有 GitHub dsh-plugin 标志的社区扩展。</p></div></div>{props.catalogWarning !== '' && <div className="warning-banner">{props.catalogWarning}</div>}<div className="stack">{props.catalog.map(entry => <CatalogCard key={entry.id} entry={entry} onInstall={() => props.onInstall(entry)} />)}</div></div></div></section>
}

function ConversationsPage(props: { selected?: ManagerInstance; conversations: ConversationSummary[]; onSetSync(value: string): void }) { return <section><PageTitle title="对话记录" detail="只有加入同一同步组的实例共享对话记录；插件和设置不会随对话同步。" /><div className="sync-card"><div className="sync-symbol">↔</div><div><strong>{props.selected?.syncGroupId === undefined ? '当前实例未加入同步组' : `同步组 ${props.selected.syncGroupId}`}</strong><p>同步组只共享会话目录；实例的插件、Skill、模型和权限仍然独立。</p></div><button className="secondary" onClick={() => { const value = window.prompt('输入同步组名称；留空可解除同步：', props.selected?.syncGroupId ?? '') ?? ''; props.onSetSync(value) }}>管理同步组</button></div><div className="section-heading compact"><div><h2>最近对话</h2><p>{props.conversations.length} 条本地记录</p></div></div><div className="conversation-list">{props.conversations.length === 0 ? <EmptyState title="还没有可显示的对话" detail="启动实例并发送第一条消息后，对话会出现在这里。" /> : props.conversations.map(conversation => <div className="conversation-row" key={conversation.id}><span className="conversation-icon">◌</span><div><strong>{conversation.id}</strong><small>{conversation.location}</small></div><span className="muted">{formatBytes(conversation.sizeBytes)}</span></div>)}</div></section> }

function DiagnosticsPage(props: {
  selected?: ManagerInstance
  health: string
  logs: string[]
  onRefresh(): void
  onCheckHealth(): void
}) {
  return <section><PageTitle title="诊断与设置" detail="识别运行时、检查 HTTP 健康、查看端口/PID、日志和 DSh Home。" /><div className="diagnostic-grid">{[['运行环境', props.selected?.runtimeStatus ?? '未选择实例'], ['生命周期', props.selected?.status === 'starting' ? '启动中' : props.selected?.status === 'running' ? '运行中' : props.selected?.status === 'error' ? '错误' : '已停止'], ['实例类型', props.selected?.kind === 'source' ? 'source 源码实例' : props.selected?.kind === 'installed' ? 'installed 安装实例' : '—'], ['DSh 版本', props.selected?.detectedVersion ?? '尚未检测'], ['本地端口 / PID', props.selected?.port ? `${props.selected.port} / ${props.selected.pid ?? '—'}` : '未运行'], ['健康检查', props.health], ['独立 Home', props.selected?.homePath ?? '—'], ['对话同步', props.selected?.syncGroupId ?? '未加入'], ['最后启动', props.selected?.lastLaunchedAt ?? '尚未启动']].map(([label, value]) => <div className="diagnostic-card" key={label}><span>{label}</span><strong>{value}</strong></div>)}</div><div className="diagnostic-actions"><button className="secondary" onClick={props.onRefresh}>重新识别</button><button className="primary" onClick={props.onCheckHealth}>检查健康状态</button></div><div className="section-heading compact log-heading"><div><h2>运行日志</h2><p>最近 {props.logs.length} 行，按启动顺序记录 stdout/stderr。</p></div></div><pre className="log-viewer">{props.logs.length === 0 ? '当前实例还没有日志。' : props.logs.join('\n')}</pre></section>
}

function InstanceCard(props: { instance: ManagerInstance; selected: boolean; onSelect(): void; onLaunch(): void; onRestart(): void; onStop(): void; onToggleFavorite(): void; expanded?: boolean }) { const running = props.instance.status === 'running'; const starting = props.instance.status === 'starting'; const failed = props.instance.status === 'error'; return <article className={props.selected ? 'instance-card selected' : 'instance-card'} onClick={props.onSelect}><div className="card-top"><button className="favorite-button" aria-label={props.instance.favorite ? '取消收藏' : '收藏'} onClick={(event) => { event.stopPropagation(); props.onToggleFavorite() }}>{props.instance.favorite ? '★' : '☆'}</button><div className="instance-icon">{props.instance.icon ?? (props.instance.kind === 'source' ? '⌘' : 'D')}</div><div className="instance-name"><strong>{props.instance.name}</strong><span>{props.instance.kind === 'source' ? 'source · 源码实例' : 'installed · 安装实例'} · {props.instance.runtimeStatus === 'ready' ? '运行环境就绪' : props.instance.runtimeStatus === 'needs-install' ? '需要安装依赖' : '需要检查'}</span>{props.instance.description && <small>{props.instance.description}</small>}</div><span className={running ? 'state running' : failed ? 'state error' : 'state'}><i />{starting ? '启动中' : running ? '运行中' : failed ? '启动失败' : '已停止'}</span></div><p className="path">{props.instance.rootPath}</p><div className="card-bottom"><span>{props.instance.syncGroupId === undefined ? '独立对话' : `同步组 ${props.instance.syncGroupId}`} · {props.instance.lastLaunchedAt ? `上次 ${formatDate(props.instance.lastLaunchedAt)}` : '尚未启动'}</span><div>{running ? <><button className="secondary" onClick={(event) => { event.stopPropagation(); props.onRestart() }}>重启</button><button className="secondary" onClick={(event) => { event.stopPropagation(); props.onStop() }}>停止</button></> : <button className="primary" disabled={starting} onClick={(event) => { event.stopPropagation(); props.onLaunch() }}>{starting ? '启动中…' : failed ? '重试启动' : '启动 DSh'}</button>}</div></div>{props.expanded && <div className="card-meta"><span>Home：{props.instance.homePath}</span>{props.instance.port && <span>端口 / PID：{props.instance.port} / {props.instance.pid ?? '—'}</span>}{props.instance.url && <span>地址：{props.instance.url}</span>}{props.instance.error && <span className="error-text">错误：{props.instance.error}</span>}</div>}</article> }
function ExtensionCard({ entry }: { entry: ExtensionEntry }) { return <article className="extension-card"><div className="extension-icon">{entry.kind === 'plugin' ? 'P' : entry.kind === 'mcp' ? 'M' : '✦'}</div><div className="extension-info"><strong>{entry.name}</strong><span>{entry.kind} · {entry.version ?? '本地'} · {entry.source}</span>{entry.description && <p>{entry.description}</p>}</div><span className="installed">{entry.enabled ? '已启用' : '已禁用'}</span></article> }
function SkillCard({ skill, onRemove }: { skill: SkillEntry; onRemove(): void }) { return <article className="extension-card"><div className="extension-icon skill">✦</div><div className="extension-info"><strong>{skill.name}</strong><span>Skill · {skill.source} · {skill.modelInvocable ? '模型可调用' : '仅用户调用'}</span><p>{skill.description}</p></div><span className="installed">{skill.managed ? '实例 Skill' : '项目 Skill'}</span>{skill.managed && <button className="text-button" onClick={onRemove}>删除</button>}</article> }
function CatalogCard({ entry, onInstall }: { entry: MarketplaceEntry; onInstall(): void }) { return <article className="catalog-card"><div className="catalog-heading"><div className="extension-icon">{entry.verified ? '✓' : '◇'}</div><div><strong>{entry.name}</strong><span>{entry.verified ? '官方来源' : '社区来源 · 未验证'}</span></div></div><p>{entry.description}</p><small>{entry.source.locator}</small><button className="secondary" onClick={onInstall}>安装到当前实例</button></article> }
function InfoPage(props: { title: string; icon: string; items: string[] }) { return <section><PageTitle title={props.title} detail="这些能力按实例保存，切换实例不会意外改变当前配置。" /><div className="info-grid">{props.items.map(item => <div className="info-card" key={item}><span className="info-icon">{props.icon}</span><strong>{item}</strong><small>独立实例配置</small></div>)}</div></section> }
function PageTitle({ title, detail }: { title: string; detail: string }) { return <div className="page-title"><div><div className="eyebrow">DSH MANAGER</div><h1>{title}</h1><p>{detail}</p></div></div> }
function EmptyState({ title, detail }: { title: string; detail: string }) { return <div className="empty"><div className="empty-mark">D</div><strong>{title}</strong><p>{detail}</p></div> }
function tryJson(value: string): unknown { try { return JSON.parse(value) as unknown } catch { return value } }
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === 'object' && value !== null }
function formatBytes(value: number): string { return value < 1024 ? `${value} B` : value < 1024 * 1024 ? `${(value / 1024).toFixed(1)} KB` : `${(value / 1024 / 1024).toFixed(1)} MB` }
function formatDate(value: string): string { return new Date(value).toLocaleString('zh-CN', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' }) }

const root = document.getElementById('root')
if (root === null) throw new Error('DSh Manager root element is missing')
createRoot(root).render(<App />)
