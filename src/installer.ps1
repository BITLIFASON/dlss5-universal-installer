[CmdletBinding()]
param(
  [ValidateSet('Menu','Check','Packages')][string]$Action = 'Menu',
  [string]$GamePath
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$Dirs = @{
  Logs = Join-Path $Root 'logs'
  Backups = Join-Path $Root 'backups'
  Packages = Join-Path $Root 'packages'
  Manifests = Join-Path $Root 'manifests'
}
$Dirs.Values | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }
$SettingsPath = Join-Path $Root 'config\settings.json'

function Get-Settings {
  if (-not (Test-Path -LiteralPath $SettingsPath)) {
    [ordered]@{
      _comments = 'Edit values as needed. Keep automatic downloads disabled until a source and hash are verified.'
      language = 'ru'
      supportedApis = @('DX11','DX12')
      compareBeforeInstall = $true
      warnBeforeElevation = $true
      useLocalPackagesFirst = $true
      allowAutomaticDownloads = $false
      deleteUnknownFiles = $false
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
  }
  Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
}
$Settings = Get-Settings

function T([string]$ru,[string]$en) { if ($Settings.language -eq 'en') { return $en }; return $ru }
function Write-Log([string]$Message) {
  $line = "$(Get-Date -Format o) $Message"
  Add-Content -LiteralPath (Join-Path $Dirs.Logs 'installer.log') -Value $line -Encoding UTF8
  Write-Host $Message
}
function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-RelativePath([string]$Base,[string]$Path) {
  $baseUri = [Uri]((Resolve-Path -LiteralPath $Base).Path.TrimEnd('\') + '\')
  $pathUri = [Uri](Resolve-Path -LiteralPath $Path).Path
  [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/','\')
}
function Get-PeArchitecture([string]$Path) {
  try {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) { return 'Unknown' }
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
    if ($peOffset -lt 0 -or $peOffset + 6 -gt $bytes.Length) { return 'Unknown' }
    $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
    if ($machine -eq 0x8664) { return 'x64' }
    if ($machine -eq 0x14c) { return 'x86' }
    return ('0x{0:X4}' -f $machine)
  } catch { return 'Unknown' }
}
function Find-GameExecutables([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw (T 'Папка игры не найдена.' 'Game folder was not found.') }
  $items = @(Get-ChildItem -LiteralPath $Path -Filter '*.exe' -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\(redist|support|tools|crash|_commonredist)\\' } |
    Sort-Object Length -Descending)
  if ($items.Count -eq 0) { throw (T 'В папке не найден EXE.' 'No executable was found in the folder.') }
  return @($items | Select-Object -First 20)
}
function Get-GameInspection([string]$Path) {
  $resolved = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
  $files = @(Get-ChildItem -LiteralPath $resolved -File -Recurse -ErrorAction SilentlyContinue)
  $executables = @(Find-GameExecutables $resolved)
  $dlss = @($files | Where-Object { $_.Name -match '^(nvngx_dlss|nvngx_dlssg|nvngx_dlssnr|dlss).*\\.dll' })
  $proxy = @($files | Where-Object { $_.Name -match '^(dxgi|d3d11|d3d12|ReShade.*)\\.dll' })
  $apiHint = if ($files.Name -contains 'd3d12.dll') { 'DX12 candidate' } elseif ($files.Name -contains 'd3d11.dll') { 'DX11 candidate' } else { 'Unknown (confirm in game documentation)' }
  [ordered]@{
    timestamp = (Get-Date).ToUniversalTime().ToString('o')
    gamePath = $resolved
    primaryExecutable = $executables[0].FullName
    primaryArchitecture = Get-PeArchitecture $executables[0].FullName
    executables = @($executables | ForEach-Object { [ordered]@{ path = $_.FullName; size = $_.Length; architecture = Get-PeArchitecture $_.FullName } })
    apiHint = $apiHint
    nativeDlssDetected = ($dlss.Count -gt 0)
    dlssFiles = @($dlss | ForEach-Object { Get-RelativePath $resolved $_.FullName })
    proxyFiles = @($proxy | ForEach-Object { Get-RelativePath $resolved $_.FullName })
    fileCount = $files.Count
  }
}
function Show-MethodComparison($Info) {
  Write-Host ''; Write-Host (T 'Сравнение методов:' 'Method comparison:') -ForegroundColor Cyan
  if ($Info.nativeDlssDetected) { Write-Host (T '1. Native/Bridge — обнаружен штатный DLSS; обычно минимальная нагрузка.' '1. Native/Bridge — native DLSS detected; usually lowest overhead.') } else { Write-Host (T '1. Native/Bridge — штатный DLSS не найден, сначала проверить вручную.' '1. Native/Bridge — native DLSS not detected; verify manually first.') -ForegroundColor DarkGray }
  Write-Host (T '2. OptiScaler — широкая совместимость; возможны конфликты proxy DLL.' '2. OptiScaler — broad compatibility; proxy DLL conflicts are possible.')
  Write-Host (T '3. ReShade + Feeder — постобработка; требует depth/motion vectors и обычно дороже по FPS.' '3. ReShade + Feeder — post-processing; needs depth/motion vectors and usually costs more FPS.')
}
function Save-JsonManifest([string]$Prefix,$Object) {
  $name = '{0}-{1}.json' -f $Prefix,(Get-Date -Format 'yyyyMMdd-HHmmss')
  $path = Join-Path $Dirs.Manifests $name
  $items = @($Object)
  $json = if ($items.Count -eq 0) { '[]' } else { $items | ConvertTo-Json -Depth 8 }
  Set-Content -LiteralPath $path -Value $json -Encoding UTF8
  return $path
}
function Get-PackageInventory {
  $files = @(Get-ChildItem -LiteralPath $Dirs.Packages -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @('.zip','.7z','.rar','.exe','.dll') })
  @($files | ForEach-Object { [ordered]@{ name = $_.Name; path = $_.FullName; extension = $_.Extension.ToLowerInvariant(); size = $_.Length; sha256 = Get-Sha256 $_.FullName; modified = $_.LastWriteTimeUtc.ToString('o') } })
}
function Run-Check([string]$Path) {
  $info = Get-GameInspection $Path
  Write-Host ''; Write-Host (T 'Обнаружено:' 'Inspection:') -ForegroundColor Cyan
  $info | ConvertTo-Json -Depth 8 | Write-Host
  Show-MethodComparison $info
  $manifest = Save-JsonManifest 'check' $info
  Write-Log ("CHECK {0}; manifest={1}" -f $info.gamePath,$manifest)
}
function Run-Packages {
  $inventory = Get-PackageInventory
  if ($inventory.Count -eq 0) { Write-Host (T 'В packages пока нет архивов или DLL.' 'No archives or DLLs found in packages yet.') -ForegroundColor Yellow }
  else { $inventory | Format-Table name,extension,size,sha256 -AutoSize }
  $manifest = Save-JsonManifest 'packages' $inventory
  Write-Log ("PACKAGES; manifest={0}" -f $manifest)
}
function Set-Language {
  $value = Read-Host (T 'Язык (ru/en)' 'Language (ru/en)')
  if ($value -notmatch '^(ru|en)$') { throw (T 'Допустимы только ru или en.' 'Only ru or en are accepted.') }
  $Settings.language = $value
  $Settings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
  $script:Settings = Get-Settings
}
function Main {
  if ($Action -eq 'Check') { if (-not $GamePath) { $GamePath = Read-Host (T 'Укажите папку игры' 'Enter game folder') }; Run-Check $GamePath; return }
  if ($Action -eq 'Packages') { Run-Packages; return }
  Write-Host ''; Write-Host 'DLSS5 Universal Installer' -ForegroundColor Cyan
  Write-Host (T '1. Проверить игру' '1. Check game')
  Write-Host (T '2. Проверить packages и SHA-256' '2. Inventory packages and SHA-256')
  Write-Host (T '3. Установка (следующий этап)' '3. Install (next stage)')
  Write-Host (T '4. Восстановление (следующий этап)' '4. Restore (next stage)')
  Write-Host (T '5. Язык' '5. Language')
  switch (Read-Host (T 'Выберите действие' 'Choose action')) {
    '1' { $p = if ($GamePath) { $GamePath } else { Read-Host (T 'Укажите папку игры' 'Enter game folder') }; Run-Check $p }
    '2' { Run-Packages }
    '3' { Write-Host (T 'Установка будет добавлена после проверки реальных пакетов и manifest.' 'Installation will be added after real package and manifest verification.') -ForegroundColor Yellow }
    '4' { Write-Host (T 'Восстановление будет добавлено после первой установки.' 'Restore will be added after the first installation.') -ForegroundColor Yellow }
    '5' { Set-Language }
    default { Write-Host (T 'Отмена.' 'Cancelled.') }
  }
}
try { Main } catch { Write-Error $_; exit 1 }
