<##
.SYNOPSIS
Build the self-contained DeepSeek Desktop installer for Windows x64.

.DESCRIPTION
Bundles Node.js, the published Harness runtime, every supported desktop plugin,
the WebView host, and an NSIS installer. Installation performs profile creation
and a real local plugin-chain startup probe, so first launch has no setup work.
##>
[CmdletBinding()]
param(
  [string]$OutputDirectory,
  [string]$LauncherExecutable = $env:DSH_LAUNCHER_EXE,
  [string]$NsisPath = 'D:\DevTools\Scoop\apps\nsis-portable\3.12\nsis-3.12\Bin\makensis.exe',
  [switch]$KeepWork
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$desktopVersion = '0.2.1'
$dshVersion = '0.1.1-rc.2'
$nodeVersion = '24.19.0'
$nodeArchiveName = "node-v$nodeVersion-win-x64.zip"
$nodeUrl = "https://nodejs.org/dist/v$nodeVersion/$nodeArchiveName"
$nodeSha256 = '57f71ab3652e797d84acddc79c81cc9ff1c6ddb2a1974cdb83f00fee9bff4c73'
$webViewPackageVersion = '1.0.4129.50'
$webViewPackageName = "microsoft.web.webview2.$webViewPackageVersion.nupkg"
$webViewPackageUrl = "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$webViewPackageVersion/$webViewPackageName"
$webViewPackageSha256 = 'd3934f482d484b89fb4825df720c710664e1143a1e90f7b3a60794ef33f473d2'
$pnpmVersion = '11.7.0'
$repoRoot = Split-Path -Parent $PSScriptRoot
$distributionRoot = Join-Path $repoRoot 'distribution\windows'
$cacheRoot = Join-Path $distributionRoot 'build\cache'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $distributionRoot 'dist' }
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
$buildBase = Join-Path $env:SystemDrive 'dshb'
$workRoot = Join-Path $buildBase ("dshb-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$payloadRoot = Join-Path $workRoot 'payload'
$runtimeRoot = Join-Path $payloadRoot 'runtime'
$appRoot = Join-Path $payloadRoot 'app'
$pluginRoot = Join-Path $payloadRoot 'plugins'
$defaultsRoot = Join-Path $payloadRoot 'defaults'
$launcherRoot = Join-Path $payloadRoot 'launcher'
$webViewExtract = Join-Path $workRoot 'webview2'
$nodeArchive = Join-Path $cacheRoot $nodeArchiveName
$webViewPackage = Join-Path $cacheRoot $webViewPackageName
$installerPath = Join-Path $outputPath 'Deepseek-desktop-offline.exe'
$compiler = 'D:\Program Files (x86)\visualstudio\MSBuild\Current\Bin\Roslyn\csc.exe'

$networkPluginCatalog = @(
  [pscustomobject]@{
    id = 'dsh-session-export'
    package = 'dsh-session-export'
    spec = 'https://codeload.github.com/bwndlct/dsh-session-export/tar.gz/eb18389192e36934718877fd7c6eb397f5cf1cd4'
  }
  [pscustomobject]@{
    id = 'dsh-mic-input'
    package = 'dsh-mic-input'
    spec = 'https://codeload.github.com/QT-Chen/dsh-mic-input/tar.gz/23a0ba5cccc8bc016a8d7e4382ad22aa47d1c3d0'
  }
  [pscustomobject]@{
    id = 'auto-continue'
    package = 'dsh-client-auto-continue'
    spec = '0.3.2'
  }
  [pscustomobject]@{
    id = 'ui-attention-badge'
    package = 'dsh-web-attention-badge'
    spec = '0.3.2'
  }
)

function Assert-ExternalSuccess([string]$Subject) {
  if ($LASTEXITCODE -ne 0) { throw "$Subject failed with exit code $LASTEXITCODE" }
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
  [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

function Move-DirectoryToRecycleBin([string]$Path) {
  Add-Type -AssemblyName Microsoft.VisualBasic
  [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
    $Path,
    [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
    [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
  )
}

function Get-Sha256([string]$Path) {
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Assert-X64WindowsExecutable([string]$Path) {
  $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  $reader = New-Object IO.BinaryReader($stream)
  try {
    if ($reader.ReadUInt16() -ne 0x5A4D) { throw "Launcher executable is missing the MZ header: $Path" }
    $stream.Position = 0x3C
    $peOffset = $reader.ReadInt32()
    if ($peOffset -lt 0x40 -or $peOffset -gt ($stream.Length - 6)) {
      throw "Launcher executable has an invalid PE offset: $Path"
    }
    $stream.Position = $peOffset
    if ($reader.ReadUInt32() -ne 0x00004550) { throw "Launcher executable is missing the PE header: $Path" }
    if ($reader.ReadUInt16() -ne 0x8664) { throw "Launcher executable is not Windows x64: $Path" }
  } finally {
    $reader.Dispose()
  }
}

function Get-CachedDownload([string]$Path, [string]$Url, [string]$ExpectedSha256) {
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    $cachedHash = Get-Sha256 $Path
    if ($cachedHash -eq $ExpectedSha256) { return }
    throw "Cached download checksum mismatch: $Path"
  }
  $temporary = "$Path.download"
  & curl.exe --fail --location --silent --show-error --output $temporary $Url
  Assert-ExternalSuccess "Download $Url"
  $actualHash = Get-Sha256 $temporary
  if ($actualHash -ne $ExpectedSha256) {
    throw "Downloaded file checksum mismatch: expected $ExpectedSha256, got $actualHash"
  }
  Move-Item -LiteralPath $temporary -Destination $Path
}

function New-MultiSizeIcon([string]$PngPath, [string]$IconPath) {
  Add-Type -AssemblyName System.Drawing
  $sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
  $source = [Drawing.Image]::FromFile($PngPath)
  $entries = New-Object Collections.Generic.List[byte[]]
  try {
    foreach ($size in $sizes) {
      $bitmap = New-Object Drawing.Bitmap($size, $size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
      try {
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
          $graphics.Clear([Drawing.Color]::Transparent)
          $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
          $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
          $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
          $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
          $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
          $graphics.DrawImage($source, 0, 0, $size, $size)
        } finally {
          $graphics.Dispose()
        }
        $stream = New-Object IO.MemoryStream
        try {
          $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
          $entries.Add($stream.ToArray())
        } finally {
          $stream.Dispose()
        }
      } finally {
        $bitmap.Dispose()
      }
    }
  } finally {
    $source.Dispose()
  }

  $file = [IO.File]::Open($IconPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
  $writer = New-Object IO.BinaryWriter($file)
  try {
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]$entries.Count)
    $offset = 6 + (16 * $entries.Count)
    for ($index = 0; $index -lt $entries.Count; $index++) {
      $size = $sizes[$index]
      $dimension = if ($size -eq 256) { [byte]0 } else { [byte]$size }
      $writer.Write($dimension)
      $writer.Write($dimension)
      $writer.Write([byte]0)
      $writer.Write([byte]0)
      $writer.Write([UInt16]1)
      $writer.Write([UInt16]32)
      $writer.Write([UInt32]$entries[$index].Length)
      $writer.Write([UInt32]$offset)
      $offset += $entries[$index].Length
    }
    foreach ($entry in $entries) { $writer.Write($entry) }
  } finally {
    $writer.Dispose()
  }
}

function Copy-EffortSliderPackage {
  $sourceRoot = Join-Path $repoRoot 'packages\client\ui-model-selection'
  if (!(Test-Path -LiteralPath (Join-Path $sourceRoot 'lib\client.js') -PathType Leaf)) {
    $pnpm = (Get-Command pnpm.cmd -ErrorAction SilentlyContinue).Source
    if ([string]::IsNullOrWhiteSpace($pnpm)) { throw 'pnpm.cmd is required to build the effort slider.' }
    Push-Location $repoRoot
    try {
      & $pnpm '--filter' '@deepseek-ai/dsh-client-ui-model-selection' 'bundle'
      Assert-ExternalSuccess 'Effort-slider UI bundle'
    } finally {
      Pop-Location
    }
  }
  $destination = Join-Path $pluginRoot 'dsh-client-ui-model-selection'
  New-Item -ItemType Directory -Force -Path (Join-Path $destination 'lib') | Out-Null
  Copy-Item -LiteralPath (Join-Path $sourceRoot 'lib\client.js') -Destination (Join-Path $destination 'lib\client.js')
  Copy-Item -LiteralPath (Join-Path $sourceRoot 'lib\index.js') -Destination (Join-Path $destination 'lib\index.js')
  Copy-Item -LiteralPath (Join-Path $sourceRoot 'lib\invariant.js') -Destination (Join-Path $destination 'lib\invariant.js')
  Copy-Item -LiteralPath (Join-Path $sourceRoot 'lib\types') -Destination (Join-Path $destination 'lib') -Recurse
  $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $sourceRoot 'package.json') | ConvertFrom-Json
  $manifest.version = $dshVersion
  $manifest.peerDependencies = @{}
  $manifest.devDependencies = @{}
  if ($null -eq $manifest.PSObject.Properties['dependencies']) {
    $manifest | Add-Member -MemberType NoteProperty -Name dependencies -Value @{}
  }
  $manifest.dependencies = @{ clsx = '^2.1.1'; react = '^18.2.0' }
  Write-Utf8NoBom (Join-Path $destination 'package.json') (($manifest | ConvertTo-Json -Depth 10) + "`n")
}

function Write-AppManifest {
  $dependencies = @{
    '@deepseek-ai/dsh' = $dshVersion
    '@deepseek-ai/dsh-client-ui-model-selection' = 'file:../plugins/dsh-client-ui-model-selection'
    'deepseek-desktop-free-fallback' = 'file:../plugins/deepseek-desktop-free-fallback'
    'deepseek-desktop-plugin-helper' = 'file:../plugins/deepseek-desktop-plugin-helper'
    'deepseek-desktop-update-sync' = 'file:../plugins/deepseek-desktop-update-sync'
    'deepseek-desktop-vision-preflight' = 'file:../plugins/deepseek-desktop-vision-preflight'
    'deepseek-desktop-web-diagnostics' = 'file:../plugins/deepseek-desktop-web-diagnostics'
    'dsh-vision-sidecar' = 'file:../plugins/dsh-vision-sidecar'
    'pnpm' = $pnpmVersion
  }
  foreach ($entry in $networkPluginCatalog) { $dependencies[$entry.package] = $entry.spec }
  $manifest = @{
    name = 'deepseek-desktop-runtime'
    version = $desktopVersion
    private = $true
    dependencies = $dependencies
  }
  Write-Utf8NoBom (Join-Path $appRoot 'package.json') (($manifest | ConvertTo-Json -Depth 6) + "`n")
}

function Get-TopLevelPackageManifests {
  $nodeModules = Join-Path $appRoot 'node_modules'
  if (!(Test-Path -LiteralPath $nodeModules -PathType Container)) { return @() }
  $manifests = New-Object Collections.Generic.List[string]
  foreach ($entry in Get-ChildItem -LiteralPath $nodeModules -Directory) {
    if ($entry.Name -eq '.pnpm') { continue }
    if ($entry.Name.StartsWith('@')) {
      foreach ($scopedPackage in Get-ChildItem -LiteralPath $entry.FullName -Directory) {
        $manifestPath = Join-Path $scopedPackage.FullName 'package.json'
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { $manifests.Add($manifestPath) }
      }
      continue
    }
    $manifestPath = Join-Path $entry.FullName 'package.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { $manifests.Add($manifestPath) }
  }
  return $manifests.ToArray()
}

function Add-MissingRuntimePeers {
  $appManifestPath = Join-Path $appRoot 'package.json'
  $appManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $appManifestPath | ConvertFrom-Json
  $added = 0
  foreach ($manifestPath in Get-TopLevelPackageManifests) {
    $packageManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
    if ($null -eq $packageManifest.PSObject.Properties['peerDependencies']) { continue }
    foreach ($peer in $packageManifest.peerDependencies.PSObject.Properties) {
      $optional = $false
      if ($null -ne $packageManifest.PSObject.Properties['peerDependenciesMeta']) {
        $peerMeta = $packageManifest.peerDependenciesMeta.PSObject.Properties[$peer.Name]
        if ($null -ne $peerMeta -and $null -ne $peerMeta.Value.PSObject.Properties['optional']) {
          $optional = [bool]$peerMeta.Value.optional
        }
      }
      if ($optional -or $null -ne $appManifest.dependencies.PSObject.Properties[$peer.Name]) { continue }
      $version = [string]$peer.Value
      if ($peer.Name -eq '@deepseek-ai/dsh' -or $peer.Name.StartsWith('@deepseek-ai/dsh-')) {
        # Published RC packages use stable-only peer ranges. Pinning the same RC
        # explicitly is required because package managers cannot infer it.
        $version = $dshVersion
      }
      $appManifest.dependencies | Add-Member -MemberType NoteProperty -Name $peer.Name -Value $version
      $added++
      Write-Host "Adding explicit runtime peer $($peer.Name)@$version"
    }
  }
  if ($added -gt 0) {
    Write-Utf8NoBom $appManifestPath (($appManifest | ConvertTo-Json -Depth 10) + "`n")
  }
  return $added
}

function Expose-DesktopPluginsToProfiles {
  $dshManifestPath = Join-Path $appRoot 'node_modules\@deepseek-ai\dsh\package.json'
  $dshManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $dshManifestPath | ConvertFrom-Json
  foreach ($packageName in @(
    'deepseek-desktop-free-fallback',
    'deepseek-desktop-plugin-helper',
    'deepseek-desktop-update-sync',
    'deepseek-desktop-vision-preflight',
    'deepseek-desktop-web-diagnostics',
    'dsh-client-auto-continue',
    'dsh-mic-input',
    'dsh-session-export',
    'dsh-vision-sidecar',
    'dsh-web-attention-badge'
  )) {
    $pluginManifestPath = Join-Path $appRoot "node_modules\$packageName\package.json"
    if (!(Test-Path -LiteralPath $pluginManifestPath -PathType Leaf)) {
      throw "Cannot expose missing desktop plugin to Harness profiles: $packageName"
    }
    $pluginManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $pluginManifestPath | ConvertFrom-Json
    if ($null -eq $dshManifest.dependencies.PSObject.Properties[$packageName]) {
      $dshManifest.dependencies | Add-Member -MemberType NoteProperty -Name $packageName -Value ([string]$pluginManifest.version)
    }
  }
  Write-Utf8NoBom $dshManifestPath (($dshManifest | ConvertTo-Json -Depth 20) + "`n")
}

function Patch-DesktopClientCompatibility {
  $clientPath = Join-Path $appRoot 'node_modules\dsh-client-auto-continue\lib\client.js'
  if (!(Test-Path -LiteralPath $clientPath -PathType Leaf)) {
    throw 'Cannot patch the auto-continue client because its bundle is missing.'
  }

  $source = Get-Content -Raw -Encoding UTF8 -LiteralPath $clientPath
  $old = @"
        name: "settings.plugin.item",
        id: "auto-continue",
"@
  $replacement = @"
        name: "settings.plugin.item",
        key: "auto-continue",
        id: "auto-continue",
"@
  $matches = ([regex]::Matches($source, [regex]::Escape($old))).Count
  if ($matches -ne 1) {
    throw "Expected one auto-continue settings slot registration, found $matches. Review the upstream client bundle before updating it."
  }
  Write-Utf8NoBom $clientPath ($source.Replace($old, $replacement))
}

function Compile-DesktopExecutables([string]$IconPath) {
  $desktopSource = Join-Path $workRoot 'DeepSeekDesktop.cs'
  $sourceText = (Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $distributionRoot 'templates\DeepSeekDesktop.cs')).Replace('__DESKTOP_VERSION__', $desktopVersion)
  Write-Utf8NoBom $desktopSource $sourceText
  $desktopResponse = Join-Path $workRoot 'desktop.rsp'
  Write-Utf8NoBom $desktopResponse @"
/nologo
/target:winexe
/platform:x64
/optimize+
/win32icon:"$IconPath"
/win32manifest:"$(Join-Path $distributionRoot 'templates\DeepSeekDesktop.manifest')"
/out:"$(Join-Path $payloadRoot 'DeepSeek Desktop.exe')"
/reference:System.dll
/reference:System.Core.dll
/reference:System.Drawing.dll
/reference:System.Windows.Forms.dll
/reference:"$(Join-Path $payloadRoot 'Microsoft.Web.WebView2.Core.dll')"
/reference:"$(Join-Path $payloadRoot 'Microsoft.Web.WebView2.WinForms.dll')"
"$desktopSource"
"@
  & $compiler "@$desktopResponse"
  Assert-ExternalSuccess 'DeepSeek Desktop compilation'

  $configureResponse = Join-Path $workRoot 'configure.rsp'
  Write-Utf8NoBom $configureResponse @"
/nologo
/target:winexe
/platform:x64
/optimize+
/win32icon:"$IconPath"
/win32manifest:"$(Join-Path $distributionRoot 'templates\DeepSeekDesktop.manifest')"
/out:"$(Join-Path $payloadRoot 'DeepSeek Configure.exe')"
/reference:System.dll
/reference:System.Core.dll
"$(Join-Path $distributionRoot 'templates\DeepSeekConfigure.cs')"
"@
  & $compiler "@$configureResponse"
  Assert-ExternalSuccess 'DeepSeek installer configurator compilation'
}

function Install-OfflineDependencies {
  $pnpm = (Get-Command pnpm.cmd -ErrorAction SilentlyContinue).Source
  if ([string]::IsNullOrWhiteSpace($pnpm)) { throw 'pnpm.cmd is required to assemble the offline dependency tree.' }
  $savedPath = $env:PATH
  try {
    $env:PATH = "$runtimeRoot;$savedPath"
    Push-Location $appRoot
    & $pnpm install '--prod' '--ignore-scripts' '--config.node-linker=hoisted' '--config.auto-install-peers=false' '--config.package-import-method=copy' '--config.fetch-retries=1' '--config.fetch-retry-mintimeout=1000' '--config.fetch-retry-maxtimeout=5000'
    Assert-ExternalSuccess 'Offline dependency installation'
    $closureComplete = $false
    for ($pass = 1; $pass -le 6; $pass++) {
      $added = Add-MissingRuntimePeers
      if ($added -eq 0) {
        $closureComplete = $true
        break
      }
      & $pnpm install '--prod' '--ignore-scripts' '--config.node-linker=hoisted' '--config.auto-install-peers=false' '--config.package-import-method=copy' '--config.fetch-retries=1' '--config.fetch-retry-mintimeout=1000' '--config.fetch-retry-maxtimeout=5000'
      Assert-ExternalSuccess "Offline peer dependency pass $pass"
    }
    if (!$closureComplete -and (Add-MissingRuntimePeers) -ne 0) {
      throw 'Published Harness peer dependency closure did not converge after 6 passes.'
    }
    Patch-DesktopClientCompatibility
    Expose-DesktopPluginsToProfiles
    & $pnpm rebuild 'node-pty' '--config.ignore-scripts=false'
    Assert-ExternalSuccess 'node-pty trusted native rebuild'
  } finally {
    Pop-Location
    $env:PATH = $savedPath
  }
  foreach ($required in @(
    'app\node_modules\@deepseek-ai\dsh\lib\bin.js',
    'app\node_modules\deepseek-desktop-plugin-helper\index.mjs',
    'app\node_modules\dsh-session-export\package.json',
    'app\node_modules\dsh-session-export\lib\index.js',
    'app\node_modules\dsh-mic-input\package.json',
    'app\node_modules\dsh-mic-input\lib\index.js',
    'app\node_modules\dsh-client-auto-continue\package.json',
    'app\node_modules\dsh-web-attention-badge\package.json',
    'runtime\node.exe'
  )) {
    $path = Join-Path $payloadRoot $required
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Offline payload is missing $required" }
  }
  & (Join-Path $runtimeRoot 'node.exe') (Join-Path $appRoot 'node_modules\@deepseek-ai\dsh\lib\bin.js') --help
  Assert-ExternalSuccess 'Bundled Harness command smoke test'
}

$succeeded = $false
try {
  if ([Environment]::Is64BitOperatingSystem -eq $false) { throw 'This installer targets Windows x64 only.' }
  foreach ($requiredTool in @($compiler, $NsisPath, 'D:\DevTools\Scoop\shims\7z.exe')) {
    if (!(Test-Path -LiteralPath $requiredTool -PathType Leaf)) { throw "Required build tool is missing: $requiredTool" }
  }
  if ([string]::IsNullOrWhiteSpace($LauncherExecutable)) {
    throw 'LauncherExecutable is required. Build DSH Launcher as a Windows x64 self-contained single file and pass its path.'
  }
  $launcherSourcePath = [IO.Path]::GetFullPath($LauncherExecutable)
  if (!(Test-Path -LiteralPath $launcherSourcePath -PathType Leaf)) {
    throw "DSH Launcher executable is missing: $launcherSourcePath"
  }
  Assert-X64WindowsExecutable $launcherSourcePath
  $launcherItem = Get-Item -LiteralPath $launcherSourcePath
  if ($launcherItem.Length -gt 200MB) { throw "DSH Launcher exceeds the 200 MB component limit: $($launcherItem.Length) bytes" }
  $launcherVersion = [string]$launcherItem.VersionInfo.FileVersion
  if ([string]::IsNullOrWhiteSpace($launcherVersion)) { throw "DSH Launcher has no file version: $launcherSourcePath" }
  $launcherSha256 = Get-Sha256 $launcherSourcePath
  if (Test-Path -LiteralPath $installerPath) { throw "Refusing to overwrite an existing installer: $installerPath" }
  New-Item -ItemType Directory -Force -Path $outputPath, $cacheRoot, $workRoot, $payloadRoot, $runtimeRoot, $appRoot, $pluginRoot, $defaultsRoot, $launcherRoot | Out-Null

  Write-Host "Preparing Node.js $nodeVersion and WebView2 $webViewPackageVersion..."
  Get-CachedDownload $nodeArchive $nodeUrl $nodeSha256
  Get-CachedDownload $webViewPackage $webViewPackageUrl $webViewPackageSha256
  Expand-Archive -LiteralPath $nodeArchive -DestinationPath $workRoot
  $expandedNode = Join-Path $workRoot "node-v$nodeVersion-win-x64"
  Copy-Item -Path (Join-Path $expandedNode '*') -Destination $runtimeRoot -Recurse
  & 'D:\DevTools\Scoop\shims\7z.exe' x $webViewPackage "-o$webViewExtract" -y | Out-Null
  Assert-ExternalSuccess 'WebView2 binding extraction'
  Copy-Item -LiteralPath (Join-Path $webViewExtract 'lib\net462\Microsoft.Web.WebView2.Core.dll') -Destination $payloadRoot
  Copy-Item -LiteralPath (Join-Path $webViewExtract 'lib\net462\Microsoft.Web.WebView2.WinForms.dll') -Destination $payloadRoot
  Copy-Item -LiteralPath (Join-Path $webViewExtract 'build\native\x64\WebView2Loader.dll') -Destination $payloadRoot

  foreach ($plugin in @(
    'deepseek-desktop-free-fallback',
    'deepseek-desktop-vision-preflight',
    'deepseek-desktop-web-diagnostics',
    'deepseek-desktop-plugin-helper',
    'deepseek-desktop-update-sync',
    'dsh-vision-sidecar'
  )) {
    Copy-Item -LiteralPath (Join-Path $distributionRoot "plugins\$plugin") -Destination $pluginRoot -Recurse
  }
  Copy-EffortSliderPackage
  Copy-Item -LiteralPath (Join-Path $distributionRoot 'templates\default-web.patch.yml') -Destination (Join-Path $defaultsRoot 'cordis.patch.yml')
  Copy-Item -LiteralPath (Join-Path $distributionRoot 'README.zh.md') -Destination (Join-Path $payloadRoot 'README.zh.md')
  Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination $payloadRoot
  Copy-Item -LiteralPath (Join-Path $distributionRoot 'templates\DeepSeek-Black-Logo.png') -Destination $payloadRoot
  Copy-Item -LiteralPath $launcherSourcePath -Destination (Join-Path $launcherRoot 'DSH Launcher.exe')

  $iconPath = Join-Path $payloadRoot 'DeepSeek Desktop.ico'
  New-MultiSizeIcon (Join-Path $distributionRoot 'templates\DeepSeek-Black-Logo.png') $iconPath
  Compile-DesktopExecutables $iconPath
  Write-AppManifest
  Write-Host "Installing @deepseek-ai/dsh@$dshVersion and every plugin into the offline payload..."
  Install-OfflineDependencies

  Write-Utf8NoBom (Join-Path $payloadRoot 'VERSION.txt') "DeepSeek Desktop $desktopVersion`r`nDeepSeek Harness $dshVersion`r`nBundled Node.js $nodeVersion`r`nOptional DSH Launcher $launcherVersion`r`n"
  $manifest = @{
    product = 'DeepSeek Desktop'
    productVersion = $desktopVersion
    dshVersion = $dshVersion
    nodeVersion = $nodeVersion
    launcherVersion = $launcherVersion
    launcherSize = $launcherItem.Length
    launcherSha256 = $launcherSha256
    architecture = 'x64'
    distribution = 'community'
    official = $false
    completeAtInstall = $true
  }
  Write-Utf8NoBom (Join-Path $payloadRoot 'desktop-install-manifest.json') (($manifest | ConvertTo-Json -Depth 4) + "`n")

  $estimatedSize = [int][Math]::Ceiling(((Get-ChildItem -LiteralPath $payloadRoot -File -Recurse | Measure-Object -Property Length -Sum).Sum) / 1KB)
  Write-Host "Compiling the native NSIS installer..."
  $nsisArguments = @(
    '/INPUTCHARSET',
    'UTF8',
    "/DPRODUCT_VERSION=$desktopVersion",
    "/DFILE_VERSION=$desktopVersion.0",
    "/DDSH_VERSION=$dshVersion",
    "/DLAUNCHER_VERSION=$launcherVersion",
    "/DPAYLOAD_ROOT=$payloadRoot",
    "/DOUTPUT_FILE=$installerPath",
    "/DICON_FILE=$iconPath",
    "/DESTIMATED_SIZE_KB=$estimatedSize",
    (Join-Path $distributionRoot 'templates\installer.nsi')
  )
  & $NsisPath @nsisArguments
  Assert-ExternalSuccess 'NSIS installer compilation'
  if (!(Test-Path -LiteralPath $installerPath -PathType Leaf)) { throw 'NSIS did not create the installer.' }
  $item = Get-Item -LiteralPath $installerPath
  if ($item.Length -gt 330MB) { throw "Installer exceeds the 330 MB limit: $($item.Length) bytes" }
  $result = [pscustomobject]@{
    Path = $item.FullName
    Length = $item.Length
    SHA256 = (Get-Sha256 $item.FullName).ToUpperInvariant()
    ProductVersion = $desktopVersion
    DshVersion = $dshVersion
  }
  $result | Format-List
  $succeeded = $true
} finally {
  if (!$KeepWork -and (Test-Path -LiteralPath $workRoot)) {
    $resolvedWork = [IO.Path]::GetFullPath($workRoot)
    $resolvedBuildBase = [IO.Path]::GetFullPath($buildBase).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (!$resolvedWork.StartsWith($resolvedBuildBase, [StringComparison]::OrdinalIgnoreCase) -or !(Split-Path -Leaf $resolvedWork).StartsWith('dshb-')) {
      throw "Refusing to clean unexpected work directory: $resolvedWork"
    }
    Move-DirectoryToRecycleBin $resolvedWork
  }
  if (!$succeeded -and (Test-Path -LiteralPath $installerPath)) {
    Write-Warning "A failed build left an incomplete installer at $installerPath; remove it before retrying."
  }
}
