$ErrorActionPreference = 'Stop'
$InstallMode = '__INSTALL_MODE__'

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$pluginDefinitions = @(
  [pscustomobject]@{ Id = 'deepseek-desktop-plugin-helper'; Title = '桌面插件助手（必需）'; Description = '检查插件安装状态并提供本地诊断接口。'; Default = $true; BuiltIn = $true; Mandatory = $true }
  [pscustomobject]@{ Id = 'deepseek-desktop-update-sync'; Title = '更新同步助手（内置）'; Description = '后台检查官方上游和社区版本；默认只检查，不自动下载或安装。'; Default = $true; BuiltIn = $true; Mandatory = $true }
  [pscustomobject]@{ Id = 'deepseek-desktop-free-fallback'; Title = '免费模型故障切换'; Description = '免费路线首个输出前失败时尝试备用模型。'; Default = $true }
  [pscustomobject]@{ Id = 'deepseek-desktop-vision-preflight'; Title = '视觉输入预检查'; Description = '发送图片前检查模型是否明确支持视觉输入。'; Default = $true }
  [pscustomobject]@{ Id = 'deepseek-desktop-web-diagnostics'; Title = '本地 Web 诊断'; Description = '提供本地诊断地址，帮助定位 WebView 连接问题。'; Default = $true }
  [pscustomobject]@{ Id = 'vision-sidecar'; Title = '托管视觉插件（实验性）'; Description = '使用 LLM7.io 匿名视觉路线；需要图片时再启用。'; Default = $false }
  [pscustomobject]@{ Id = 'effort-slider'; Title = '思考努力值滑杆（内置）'; Description = '模型选择器中的“更快—更聪明”离散滑杆；随桌面 UI 安装。'; Default = $true; BuiltIn = $true }
  [pscustomobject]@{ Id = 'dsh-session-export'; Title = '会话导出（网络下载）'; Description = '导出 Markdown/JSON，便于归档与分享。'; Default = $true; NetworkOnly = $true }
  [pscustomobject]@{ Id = 'dsh-mic-input'; Title = '中文语音输入（网络下载）'; Description = '浏览器语音转写，支持 zh-CN。'; Default = $true; NetworkOnly = $true }
  [pscustomobject]@{ Id = 'auto-continue'; Title = '自动继续（网络下载）'; Description = '网络中断后按规则自动发送“继续”。'; Default = $true; NetworkOnly = $true }
  [pscustomobject]@{ Id = 'ui-attention-badge'; Title = '任务提醒角标（网络下载）'; Description = '等待确认或完成未读时显示角标。'; Default = $true; NetworkOnly = $true }
)

function Show-PluginSelection {
  $selected = New-Object System.Collections.ArrayList
  foreach ($definition in $pluginDefinitions) {
    if ($definition.Mandatory -or ($definition.Default -and !($definition.NetworkOnly -and $InstallMode -eq 'offline'))) {
      [void]$selected.Add($definition.Id)
    }
  }

  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = 'DeepSeek Desktop 安装'
  $dialog.StartPosition = 'CenterScreen'
  $dialog.ClientSize = New-Object System.Drawing.Size(760, 470)
  $dialog.FormBorderStyle = 'FixedDialog'
  $dialog.MaximizeBox = $false
  $dialog.MinimizeBox = $false

  $title = New-Object System.Windows.Forms.Label
  $title.Text = '选择 DeepSeek Desktop 安装选项'
  $title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 16, [System.Drawing.FontStyle]::Bold)
  $title.AutoSize = $true
  $title.Location = New-Object System.Drawing.Point(28, 22)

  $notice = New-Object System.Windows.Forms.Label
  $notice.Text = '这是社区分发版本，不是 DeepSeek 官方安装程序。插件不会包含 API key；你可以稍后在应用内修改配置。'
  $notice.ForeColor = [System.Drawing.Color]::DarkRed
  $notice.MaximumSize = New-Object System.Drawing.Size(650, 0)
  $notice.AutoSize = $true
  $notice.Location = New-Object System.Drawing.Point(30, 68)

  $pluginButton = New-Object System.Windows.Forms.Button
  $pluginButton.Text = '选择插件…'
  $pluginButton.Size = New-Object System.Drawing.Size(150, 38)
  $pluginButton.Location = New-Object System.Drawing.Point(30, 150)

  $summary = New-Object System.Windows.Forms.Label
  $summary.Text = "已选择 $($selected.Count) 个插件"
  $summary.AutoSize = $true
  $summary.Location = New-Object System.Drawing.Point(200, 160)

  $detail = New-Object System.Windows.Forms.Label
  $detail.Text = if ($InstallMode -eq 'offline') {
    '思考努力值滑杆与插件助手会随应用安装。网络插件在离线版中保留为未启用状态；在线版安装时会从固定来源下载。'
  } else {
    '思考努力值滑杆与插件助手会随应用安装。已勾选的网络插件会在点击安装后下载并验证挂载。'
  }
  $detail.MaximumSize = New-Object System.Drawing.Size(650, 0)
  $detail.AutoSize = $true
  $detail.Location = New-Object System.Drawing.Point(30, 215)

  $checkUpdates = New-Object System.Windows.Forms.CheckBox
  $checkUpdates.Text = '后台检查官方上游和社区版本（默认开启）'
  $checkUpdates.AutoSize = $true
  $checkUpdates.Checked = $true
  $checkUpdates.Location = New-Object System.Drawing.Point(30, 275)

  $autoUpdates = New-Object System.Windows.Forms.CheckBox
  $autoUpdates.Text = '允许后台自动下载更新（默认关闭；不会自动安装）'
  $autoUpdates.AutoSize = $true
  $autoUpdates.Checked = $false
  $autoUpdates.Location = New-Object System.Drawing.Point(30, 305)

  $install = New-Object System.Windows.Forms.Button
  $install.Text = '立即安装'
  $install.Size = New-Object System.Drawing.Size(130, 42)
  $install.Location = New-Object System.Drawing.Point(460, 390)
  $install.DialogResult = [System.Windows.Forms.DialogResult]::OK

  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = '取消'
  $cancel.Size = New-Object System.Drawing.Size(130, 42)
  $cancel.Location = New-Object System.Drawing.Point(605, 390)
  $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

  $pluginButton.Add_Click({
    $picker = New-Object System.Windows.Forms.Form
    $picker.Text = '选择可选插件'
    $picker.StartPosition = 'CenterParent'
    $picker.ClientSize = New-Object System.Drawing.Size(760, 520)
    $picker.FormBorderStyle = 'FixedDialog'
    $picker.MaximizeBox = $false
    $picker.MinimizeBox = $false
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(12, 12)
    $panel.Size = New-Object System.Drawing.Size(728, 420)
    $panel.AutoScroll = $true
    $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $picker.Controls.Add($panel)
    $boxes = @()
    $top = 18
    foreach ($definition in $pluginDefinitions) {
      $box = New-Object System.Windows.Forms.CheckBox
      $box.Text = "$($definition.Title)`r`n$($definition.Description)"
      $box.Tag = $definition.Id
      $box.AutoSize = $false
      $box.Size = New-Object System.Drawing.Size(690, 50)
      $box.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
      $box.UseCompatibleTextRendering = $true
      $box.Location = New-Object System.Drawing.Point(18, $top)
      $box.Checked = $selected.Contains($definition.Id)
      if ($definition.BuiltIn -or $definition.Mandatory) { $box.Enabled = $false }
      if ($definition.NetworkOnly -and $InstallMode -eq 'offline') { $box.Enabled = $false; $box.Checked = $false }
      $panel.Controls.Add($box)
      $boxes += $box
      $top += 58
    }
    $apply = New-Object System.Windows.Forms.Button
    $apply.Text = '应用选择'
    $apply.Size = New-Object System.Drawing.Size(130, 38)
    $apply.Location = New-Object System.Drawing.Point(610, 450)
    $apply.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $picker.Controls.Add($apply)
    $picker.AcceptButton = $apply
    if ($picker.ShowDialog($dialog) -eq [System.Windows.Forms.DialogResult]::OK) {
      $selected.Clear()
      foreach ($box in $boxes) {
        if ($box.Checked) { [void]$selected.Add([string]$box.Tag) }
      }
      $summary.Text = "已选择 $($selected.Count) 个插件"
    }
  })

  $dialog.Controls.AddRange(@($title, $notice, $pluginButton, $summary, $detail, $checkUpdates, $autoUpdates, $install, $cancel))
  $dialog.AcceptButton = $install
  $dialog.CancelButton = $cancel
  if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
  return [pscustomobject]@{
    PluginIds = [string[]]$selected.ToArray()
    CheckUpdates = [bool]$checkUpdates.Checked
    AllowAutoUpdate = [bool]$autoUpdates.Checked
  }
}

function Set-PluginEnabled([string]$Text, [string]$Id, [bool]$Enabled) {
  $pattern = "(?ms)^- id: " + [regex]::Escape($Id) + "\r?\n(?:(?!^- id: ).)*"
  $match = [regex]::Match($Text, $pattern)
  if (!$match.Success) { throw "Installer profile is missing plugin row: $Id" }
  $block = $match.Value
  $block = [regex]::Replace($block, '(?m)^\s+disabled:\s+(?:true|false)\r?\n', '')
  if (!$Enabled) { $block = $block.TrimEnd() + "`r`n  disabled: true`r`n" }
  return $Text.Substring(0, $match.Index) + $block + $Text.Substring($match.Index + $match.Length)
}

function Apply-PluginSelection([string]$PatchPath, [string[]]$SelectedIds) {
  $text = [IO.File]::ReadAllText($PatchPath, [Text.Encoding]::UTF8)
  foreach ($definition in $pluginDefinitions) {
    if ($definition.Mandatory) {
      $text = Set-PluginEnabled $text $definition.Id $true
      continue
    }
    if ($definition.BuiltIn) { continue }
    $text = Set-PluginEnabled $text $definition.Id ($SelectedIds -contains $definition.Id)
  }
  [IO.File]::WriteAllText($PatchPath, $text, (New-Object Text.UTF8Encoding($false)))
}

function Set-UpdateSyncConfig([string]$PatchPath, [bool]$CheckUpdates, [bool]$AllowAutoUpdate) {
  $text = [IO.File]::ReadAllText($PatchPath, [Text.Encoding]::UTF8)
  $pattern = "(?ms)^- id: deepseek-desktop-update-sync\r?\n(?:(?!^- id: ).)*"
  $match = [regex]::Match($text, $pattern)
  if (!$match.Success) { throw 'Installer profile is missing the update synchronization plugin row.' }
  $block = $match.Value
  $checkValue = if ($CheckUpdates) { 'true' } else { 'false' }
  $autoValue = if ($AllowAutoUpdate) { 'true' } else { 'false' }
  $block = [regex]::Replace($block, '(?m)^    checkInBackground:\s*(?:true|false)\r?\n', "    checkInBackground: $checkValue`r`n")
  $block = [regex]::Replace($block, '(?m)^    allowBackgroundAutoUpdate:\s*(?:true|false)\r?\n', "    allowBackgroundAutoUpdate: $autoValue`r`n")
  if ($block -notmatch '(?m)^    checkInBackground:') {
    $block = $block -replace '(?m)^(  config:\r?\n)', "`$1    checkInBackground: $checkValue`r`n"
  }
  if ($block -notmatch '(?m)^    allowBackgroundAutoUpdate:') {
    $block = $block -replace '(?m)^(  config:\r?\n)', "`$1    allowBackgroundAutoUpdate: $autoValue`r`n"
  }
  $text = $text.Substring(0, $match.Index) + $block + $text.Substring($match.Index + $match.Length)
  [IO.File]::WriteAllText($PatchPath, $text, (New-Object Text.UTF8Encoding($false)))
}

function New-InstallProgress {
  $form = New-Object System.Windows.Forms.Form
  $form.Text = 'DeepSeek Desktop 安装'
  $form.StartPosition = 'CenterScreen'
  $form.ClientSize = New-Object System.Drawing.Size(620, 190)
  $form.FormBorderStyle = 'FixedDialog'
  $form.MaximizeBox = $false
  $form.MinimizeBox = $false
  $form.ControlBox = $false

  $title = New-Object System.Windows.Forms.Label
  $title.Text = '正在安装 DeepSeek Desktop'
  $title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 14, [System.Drawing.FontStyle]::Bold)
  $title.AutoSize = $true
  $title.Location = New-Object System.Drawing.Point(26, 22)

  $stage = New-Object System.Windows.Forms.Label
  $stage.Text = '准备安装…'
  $stage.AutoSize = $true
  $stage.Location = New-Object System.Drawing.Point(28, 66)

  $bar = New-Object System.Windows.Forms.ProgressBar
  $bar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
  $bar.Minimum = 0
  $bar.Maximum = 100
  $bar.Value = 0
  $bar.Size = New-Object System.Drawing.Size(564, 24)
  $bar.Location = New-Object System.Drawing.Point(28, 96)

  $hint = New-Object System.Windows.Forms.Label
  $hint.Text = '网络插件仅在在线版安装时下载；请勿关闭窗口。'
  $hint.ForeColor = [System.Drawing.Color]::DimGray
  $hint.AutoSize = $true
  $hint.Location = New-Object System.Drawing.Point(28, 135)

  $form.Controls.AddRange(@($title, $stage, $bar, $hint))
  $form.Show()
  [System.Windows.Forms.Application]::DoEvents()
  return [pscustomobject]@{ Form = $form; Stage = $stage; Bar = $bar }
}

function Set-InstallProgress($Progress, [string]$Message, [int]$Value) {
  $Progress.Stage.Text = $Message
  $Progress.Bar.Value = [Math]::Max(0, [Math]::Min(100, $Value))
  $Progress.Form.Refresh()
  [System.Windows.Forms.Application]::DoEvents()
}

function Add-NetworkPluginDependencies([string]$AppRoot, [string[]]$SelectedIds, [string]$CatalogPath) {
  $catalog = @(Get-Content -Raw -Encoding UTF8 $CatalogPath | ConvertFrom-Json)
  $manifestPath = Join-Path $AppRoot 'package.json'
  $manifest = Get-Content -Raw -Encoding UTF8 $manifestPath | ConvertFrom-Json
  if ($null -eq $manifest.dependencies) { $manifest | Add-Member -NotePropertyName dependencies -NotePropertyValue ([pscustomobject]@{}) }
  foreach ($entry in $catalog) {
    if ($SelectedIds -contains [string]$entry.id) {
      $manifest.dependencies | Add-Member -NotePropertyName ([string]$entry.package.Split('@')[0]) -NotePropertyValue ([string]$entry.spec) -Force
    }
  }
  $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8
}

function Assert-NetworkPluginDependencies([string]$AppRoot, [string[]]$SelectedIds, [string]$CatalogPath, $Progress) {
  $catalog = @(Get-Content -Raw -Encoding UTF8 $CatalogPath | ConvertFrom-Json)
  foreach ($entry in $catalog) {
    if ($SelectedIds -contains [string]$entry.id) {
      $packageName = [string]$entry.package.Split('@')[0]
      Set-InstallProgress $Progress "正在验证插件 $packageName…" 74
      $packageRoot = Join-Path $AppRoot (Join-Path 'node_modules' $packageName)
      if (!(Test-Path -LiteralPath $packageRoot -PathType Container)) {
        throw "网络插件未能安装：$packageName"
      }
    }
  }
}

function Invoke-NpmInstallWithFallback([string]$AppRoot, [string]$RuntimeRoot, $Progress) {
  $registries = @('https://registry.npmmirror.com', 'https://registry.npmjs.org')
  $savedPath = $env:PATH
  try {
    $env:PATH = "$RuntimeRoot;$savedPath"
    Push-Location $AppRoot
    foreach ($registry in $registries) {
      Set-InstallProgress $Progress "正在下载依赖（$registry）…" 55
      & (Join-Path $RuntimeRoot 'npm.cmd') install '--omit=dev' '--ignore-scripts' '--no-audit' '--no-fund' '--package-lock=false' '--install-links' '--fetch-retries=3' '--fetch-timeout=120000' "--registry=$registry"
      if ($LASTEXITCODE -eq 0) { return }
    }
  } finally {
    Pop-Location
    $env:PATH = $savedPath
  }
  throw 'DeepSeek Desktop 网络依赖下载失败：国内镜像和 npm 官方源均不可用。'
}

$selection = Show-PluginSelection
if ($null -eq $selection) { exit 0 }
$selectedPluginIds = [string[]]$selection.PluginIds

$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Desktop'
$menuRoot = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\DeepSeek Desktop'
$payload = Join-Path $PSScriptRoot ("payload-$InstallMode.zip")

if (!(Test-Path -LiteralPath $payload -PathType Leaf)) {
  throw "Installer payload is missing: $payload"
}

$progress = New-InstallProgress
try {
  New-Item -ItemType Directory -Force -Path $installRoot, $menuRoot | Out-Null
  Set-InstallProgress $progress '正在解压桌面运行文件…' 25
  Expand-Archive -LiteralPath $payload -DestinationPath $installRoot -Force

  if ($InstallMode -eq 'online') {
    $runtimeRoot = Join-Path $installRoot 'runtime'
    $appRoot = Join-Path $installRoot 'app'
    $catalogPath = Join-Path $installRoot 'defaults\network-plugins.json'
    Add-NetworkPluginDependencies $appRoot $selectedPluginIds $catalogPath
    Invoke-NpmInstallWithFallback $appRoot $runtimeRoot $progress
    Assert-NetworkPluginDependencies $appRoot $selectedPluginIds $catalogPath $progress
  }

  Set-InstallProgress $progress '正在写入用户配置和插件选择…' 82
  $homeRoot = Join-Path $env:LOCALAPPDATA 'DeepSeek Harness Data'
  $profileRoot = Join-Path $homeRoot 'profiles\web'
  New-Item -ItemType Directory -Force -Path $profileRoot | Out-Null
  if (!(Test-Path -LiteralPath (Join-Path $profileRoot 'cordis.patch.yml'))) {
    Copy-Item -LiteralPath (Join-Path $installRoot 'defaults\cordis.patch.yml') -Destination (Join-Path $profileRoot 'cordis.patch.yml')
  }
  Apply-PluginSelection (Join-Path $profileRoot 'cordis.patch.yml') $selectedPluginIds
  Set-UpdateSyncConfig (Join-Path $profileRoot 'cordis.patch.yml') $selection.CheckUpdates $selection.AllowAutoUpdate
  if (!(Test-Path -LiteralPath (Join-Path $homeRoot 'settings.yaml'))) {
@"
ui-onboarding:
  welcomeNoticeVersion: 2026-08-13.1
"@ | Set-Content -LiteralPath (Join-Path $homeRoot 'settings.yaml') -Encoding utf8
  }

  Set-InstallProgress $progress '正在创建开始菜单快捷方式…' 94
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut((Join-Path $menuRoot 'DeepSeek Desktop.lnk'))
  $shortcut.TargetPath = Join-Path $installRoot 'Launch DeepSeek Desktop.cmd'
  $shortcut.WorkingDirectory = $installRoot
  $shortcut.Description = 'Open DeepSeek Desktop'
  $shortcut.Save()
  $managerShortcut = $shell.CreateShortcut((Join-Path $menuRoot 'DSh Manager.lnk'))
  $managerShortcut.TargetPath = Join-Path $installRoot 'DSH luncher.exe'
  $managerShortcut.WorkingDirectory = $installRoot
  $managerShortcut.Description = 'Open DSh Manager'
  $managerShortcut.Save()
  Set-InstallProgress $progress '安装完成，正在启动 DeepSeek Desktop…' 100
  Start-Sleep -Milliseconds 350
} catch {
  $message = $_.Exception.Message
  if ($null -ne $progress) { Set-InstallProgress $progress '安装失败' 0 }
  [System.Windows.Forms.MessageBox]::Show("安装失败：$message", 'DeepSeek Desktop', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
  exit 1
} finally {
  if ($null -ne $progress) { $progress.Form.Close(); $progress.Form.Dispose() }
}

& (Join-Path $installRoot 'Launch DeepSeek Desktop.cmd')
