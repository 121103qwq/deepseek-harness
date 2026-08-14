$ErrorActionPreference = 'Stop'
$InstallMode = '__INSTALL_MODE__'

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$pluginDefinitions = @(
  [pscustomobject]@{ Id = 'deepseek-desktop-free-fallback'; Title = '免费模型故障切换'; Description = '免费路线首个输出前失败时尝试备用模型。'; Default = $true }
  [pscustomobject]@{ Id = 'deepseek-desktop-vision-preflight'; Title = '视觉输入预检查'; Description = '发送图片前检查模型是否明确支持视觉输入。'; Default = $true }
  [pscustomobject]@{ Id = 'deepseek-desktop-web-diagnostics'; Title = '本地 Web 诊断'; Description = '提供本地诊断地址，帮助定位 WebView 连接问题。'; Default = $true }
  [pscustomobject]@{ Id = 'vision-sidecar'; Title = '托管视觉插件（实验性）'; Description = '使用 LLM7.io 匿名视觉路线；需要图片时再启用。'; Default = $false }
  [pscustomobject]@{ Id = 'effort-slider'; Title = '思考努力值滑杆（内置）'; Description = '模型选择器中的“更快—更聪明”离散滑杆；随桌面 UI 安装。'; Default = $true; BuiltIn = $true }
)

function Show-PluginSelection {
  $selected = New-Object System.Collections.ArrayList
  foreach ($definition in $pluginDefinitions) {
    if ($definition.Default) { [void]$selected.Add($definition.Id) }
  }

  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = 'DeepSeek Desktop 安装'
  $dialog.StartPosition = 'CenterScreen'
  $dialog.ClientSize = New-Object System.Drawing.Size(720, 430)
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
  $detail.Text = '思考努力值滑杆属于内置 UI 改进，会随桌面界面一起安装。上面的按钮用于选择可选社区插件。'
  $detail.MaximumSize = New-Object System.Drawing.Size(650, 0)
  $detail.AutoSize = $true
  $detail.Location = New-Object System.Drawing.Point(30, 215)

  $install = New-Object System.Windows.Forms.Button
  $install.Text = '立即安装'
  $install.Size = New-Object System.Drawing.Size(130, 42)
  $install.Location = New-Object System.Drawing.Point(420, 350)
  $install.DialogResult = [System.Windows.Forms.DialogResult]::OK

  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = '取消'
  $cancel.Size = New-Object System.Drawing.Size(130, 42)
  $cancel.Location = New-Object System.Drawing.Point(565, 350)
  $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

  $pluginButton.Add_Click({
    $picker = New-Object System.Windows.Forms.Form
    $picker.Text = '选择可选插件'
    $picker.StartPosition = 'CenterParent'
    $picker.ClientSize = New-Object System.Drawing.Size(640, 330)
    $picker.FormBorderStyle = 'FixedDialog'
    $picker.MaximizeBox = $false
    $picker.MinimizeBox = $false
    $boxes = @()
    $top = 24
    foreach ($definition in $pluginDefinitions) {
      $box = New-Object System.Windows.Forms.CheckBox
      $box.Text = "$($definition.Title)  —  $($definition.Description)"
      $box.Tag = $definition.Id
      $box.AutoSize = $true
      $box.MaximumSize = New-Object System.Drawing.Size(590, 0)
      $box.Location = New-Object System.Drawing.Point(24, $top)
      $box.Checked = $selected.Contains($definition.Id)
      if ($definition.BuiltIn) { $box.Enabled = $false }
      $picker.Controls.Add($box)
      $boxes += $box
      $top += 58
    }
    $apply = New-Object System.Windows.Forms.Button
    $apply.Text = '应用选择'
    $apply.Size = New-Object System.Drawing.Size(130, 38)
    $apply.Location = New-Object System.Drawing.Point(480, 270)
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

  $dialog.Controls.AddRange(@($title, $notice, $pluginButton, $summary, $detail, $install, $cancel))
  $dialog.AcceptButton = $install
  $dialog.CancelButton = $cancel
  if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
  return @($selected)
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
    if ($definition.BuiltIn) { continue }
    $text = Set-PluginEnabled $text $definition.Id ($SelectedIds -contains $definition.Id)
  }
  [IO.File]::WriteAllText($PatchPath, $text, (New-Object Text.UTF8Encoding($false)))
}

$selectedPluginIds = Show-PluginSelection
if ($null -eq $selectedPluginIds) { exit 0 }

$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Desktop'
$menuRoot = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\DeepSeek Desktop'
$payload = Join-Path $PSScriptRoot ("payload-$InstallMode.zip")

if (!(Test-Path -LiteralPath $payload -PathType Leaf)) {
  throw "Installer payload is missing: $payload"
}

New-Item -ItemType Directory -Force -Path $installRoot, $menuRoot | Out-Null
Expand-Archive -LiteralPath $payload -DestinationPath $installRoot -Force

if ($InstallMode -eq 'mirror') {
  $runtimeRoot = Join-Path $installRoot 'runtime'
  $appRoot = Join-Path $installRoot 'app'
  $savedPath = $env:PATH
  try {
    $env:PATH = "$runtimeRoot;$savedPath"
    Push-Location $appRoot
    & (Join-Path $runtimeRoot 'npm.cmd') install '--omit=dev' '--no-audit' '--no-fund' '--package-lock=false' '--registry=https://registry.npmmirror.com' '--fetch-retries=3' '--fetch-timeout=120000'
    if ($LASTEXITCODE -ne 0) { throw "DeepSeek Desktop download failed with exit code $LASTEXITCODE" }
  } finally {
    Pop-Location
    $env:PATH = $savedPath
  }
}

$homeRoot = Join-Path $env:LOCALAPPDATA 'DeepSeek Harness Data'
$profileRoot = Join-Path $homeRoot 'profiles\web'
New-Item -ItemType Directory -Force -Path $profileRoot | Out-Null
if (!(Test-Path -LiteralPath (Join-Path $profileRoot 'cordis.patch.yml'))) {
  Copy-Item -LiteralPath (Join-Path $installRoot 'defaults\cordis.patch.yml') -Destination (Join-Path $profileRoot 'cordis.patch.yml')
}
Apply-PluginSelection (Join-Path $profileRoot 'cordis.patch.yml') $selectedPluginIds
if (!(Test-Path -LiteralPath (Join-Path $homeRoot 'settings.yaml'))) {
@"
ui-onboarding:
  welcomeNoticeVersion: 2026-08-13.1
"@ | Set-Content -LiteralPath (Join-Path $homeRoot 'settings.yaml') -Encoding utf8
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path $menuRoot 'DeepSeek Desktop.lnk'))
$shortcut.TargetPath = Join-Path $installRoot 'Launch DeepSeek Desktop.cmd'
$shortcut.WorkingDirectory = $installRoot
$shortcut.Description = 'Open DeepSeek Desktop'
$shortcut.Save()

& (Join-Path $installRoot 'Launch DeepSeek Desktop.cmd')
