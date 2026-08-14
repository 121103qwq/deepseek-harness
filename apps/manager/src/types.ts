export type InstanceKind = 'installed' | 'source'
export type InstanceStatus = 'stopped' | 'starting' | 'running' | 'error'
export type RuntimeStatus = 'ready' | 'needs-install' | 'needs-build' | 'broken'
export type ExtensionKind = 'plugin' | 'skill' | 'mcp' | 'workflow' | 'preset'

export interface ManagerInstance {
  readonly id: string
  readonly name: string
  readonly icon?: string
  readonly description?: string
  readonly rootPath: string
  readonly kind: InstanceKind
  readonly homePath: string
  readonly syncGroupId?: string
  readonly status: InstanceStatus
  readonly runtimeStatus: RuntimeStatus
  readonly detectedVersion?: string
  readonly lastLaunchedAt?: string
  readonly favorite: boolean
  readonly port?: number
  readonly pid?: number
  readonly url?: string
  readonly error?: string
}

export interface SkillEntry {
  readonly id: string
  readonly name: string
  readonly description: string
  readonly path: string
  readonly source: 'instance' | 'project-dsh' | 'project-agents'
  readonly managed: boolean
  readonly modelInvocable: boolean
  readonly userInvocable: boolean
}

export interface ExtensionEntry {
  readonly id: string
  readonly kind: ExtensionKind
  readonly name: string
  readonly version?: string
  readonly description?: string
  readonly source: string
  readonly enabled: boolean
  readonly managed: boolean
}

export interface MarketplaceEntry {
  readonly id: string
  readonly kind: ExtensionKind
  readonly name: string
  readonly version?: string
  readonly description: string
  readonly source: { readonly type: 'npm' | 'github' | 'local'; readonly locator: string }
  readonly repository?: string
  readonly verified: boolean
  readonly permissions: readonly string[]
}

export interface ConversationSummary {
  readonly id: string
  readonly location: string
  readonly sizeBytes: number
  readonly updatedAt: string
}

export interface CatalogResponse {
  readonly entries: readonly MarketplaceEntry[]
  readonly warning?: string
}
