[CmdletBinding()]
param(
  [ValidateSet('Menu','Check','Packages','Install','Restore')][string]$Action = 'Menu',
  [string]$GamePath,
  [string]$PackageManifest
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$Dirs = @{
  Logs = Join-Path $Root 'logs'
  Backups = Join-Path $Root 'backups'
  Packages = Join-Path $Root 'packages'
  Manifests = Join-Path $Root 'manifests'
  Staging = Join-Path $Root 'staging'
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
  $dlss = @($files | Where-Object { $_.Name -match '^(nvngx_dlss|nvngx_dlssg|nvngx_dlssnr|dlss).*\.dll' })
  $proxy = @($files | Where-Object { $_.Name -match '^(dxgi|d3d11|d3d12|ReShade.*)\.dll' })
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
function Test-SafeRelativePath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or $Path.Replace('/','\') -match '(^|\\)\.\.([\\]|$)') { return $false }
  return $true
}
function Get-PackageManifest([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw (T 'Manifest пакета не найден.' 'Package manifest was not found.') }
  $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  foreach ($required in @('id','version','method','archive','sha256','source','files')) {
    if ($null -eq $manifest.$required) { throw ("Package manifest is missing: {0}" -f $required) }
  }
  if ($manifest.method -notin @('NativeBridge','OptiScaler','Feeder')) { throw (T 'Неизвестный метод в manifest.' 'Unknown method in package manifest.') }
  $archive = Join-Path $Dirs.Packages ([IO.Path]::GetFileName([string]$manifest.archive))
  if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw (T 'Архив пакета отсутствует в packages.' 'Package archive is missing from packages.') }
  if ((Get-Sha256 $archive) -ne ([string]$manifest.sha256).ToLowerInvariant()) { throw (T 'SHA-256 архива не совпадает с manifest.' 'Archive SHA-256 does not match the manifest.') }
  foreach ($entry in @($manifest.files)) {
    if (-not (Test-SafeRelativePath ([string]$entry.path)) -or [string]::IsNullOrWhiteSpace([string]$entry.sha256)) { throw (T 'Некорректный список файлов manifest.' 'Invalid file list in package manifest.') }
  }
  $manifest | Add-Member -NotePropertyName _archivePath -NotePropertyValue $archive -Force
  return $manifest
}
function Get-InstalledPackageManifest {
  @(Get-ChildItem -LiteralPath $Dirs.Manifests -Filter 'install-*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
}
function Ensure-Admin([string]$InstallGamePath,[string]$ManifestPath) {
  $probe = Join-Path $InstallGamePath ('.dlss5-write-test-' + [guid]::NewGuid().ToString('N'))
  try { New-Item -ItemType File -Path $probe -Force | Out-Null; Remove-Item -LiteralPath $probe -Force; return $true } catch { }
  $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return $true }
  if ($Settings.warnBeforeElevation) {
    $answer = Read-Host (T 'Установка может потребовать права администратора. Перезапустить с повышенными правами? (y/n)' 'Installation may require administrator rights. Relaunch elevated? (y/n)')
    if ($answer -notmatch '^(y|yes|д|да)$') { return $false }
  }
  $args = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action Install -GamePath `"$InstallGamePath`" -PackageManifest `"$ManifestPath`""
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $args | Out-Null
  return $false
}
function Run-Install([string]$Path,[string]$ManifestPath) {
  if (-not $ManifestPath) { $ManifestPath = Read-Host (T 'Укажите путь к manifest пакета (например packages\opti.manifest.json)' 'Enter package manifest path (for example packages\opti.manifest.json)') }
  $game = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
  $info = Get-GameInspection $game
  Show-MethodComparison $info
  $manifest = Get-PackageManifest (Resolve-Path -LiteralPath $ManifestPath).Path
  Write-Host (T ("Выбран пакет {0} {1}, метод {2}. Источник: {3}" -f $manifest.id,$manifest.version,$manifest.method,$manifest.source) ("Selected package {0} {1}, method {2}. Source: {3}" -f $manifest.id,$manifest.version,$manifest.method,$manifest.source)) -ForegroundColor Yellow
  if ((Read-Host (T 'Продолжить установку? (y/n)' 'Continue installation? (y/n)')) -notmatch '^(y|yes|д|да)$') { return }
  if (-not (Ensure-Admin $game $ManifestPath)) { return }
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $stage = Join-Path $Dirs.Staging $stamp
  New-Item -ItemType Directory -Force -Path $stage | Out-Null
  Expand-Archive -LiteralPath $manifest._archivePath -DestinationPath $stage -Force
  $backupRoot = Join-Path $Dirs.Backups $stamp
  $records = @()
  foreach ($entry in @($manifest.files)) {
    $relative = ([string]$entry.path).Replace('/','\')
    $source = Join-Path $stage $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw ("Archive is missing manifest file: {0}" -f $relative) }
    if ((Get-Sha256 $source) -ne ([string]$entry.sha256).ToLowerInvariant()) { throw ("Staged file SHA-256 mismatch: {0}" -f $relative) }
    $destination = Join-Path $game $relative
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
      $backup = Join-Path $backupRoot $relative
      New-Item -ItemType Directory -Force -Path (Split-Path $backup) | Out-Null
      Copy-Item -LiteralPath $destination -Destination $backup -Force
      $records += [ordered]@{ path=$relative; existed=$true; originalSha256=Get-Sha256 $destination; backup=$backup }
    } else { $records += [ordered]@{ path=$relative; existed=$false; originalSha256=$null; backup=$null } }
    New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
  }
  $install = [ordered]@{ timestamp=(Get-Date).ToUniversalTime().ToString('o'); gamePath=$game; packageId=$manifest.id; packageVersion=$manifest.version; method=$manifest.method; files=$records }
  $installPath = Save-JsonManifest 'install' $install
  Write-Log ("INSTALL {0}; manifest={1}" -f $game,$installPath)
  Write-Host (T 'Установка завершена. Для отката используйте пункт Restore.' 'Installation completed. Use Restore to roll back.') -ForegroundColor Green
}
function Run-Restore {
  $items = Get-InstalledPackageManifest
  if ($items.Count -eq 0) { Write-Host (T 'Установок для отката не найдено.' 'No installations to restore.') -ForegroundColor Yellow; return }
  $selected = $items[0]
  $install = Get-Content -LiteralPath $selected.FullName -Raw | ConvertFrom-Json
  $game = [string]$install.gamePath
  if (-not (Test-Path -LiteralPath $game -PathType Container)) { throw (T 'Папка игры из manifest не найдена.' 'Game folder from manifest was not found.') }
  if (-not (Ensure-Admin $game $selected.FullName)) { return }
  foreach ($entry in @($install.files)) {
    $destination = Join-Path $game ([string]$entry.path)
    if ($entry.existed -and (Test-Path -LiteralPath $entry.backup -PathType Leaf)) { Copy-Item -LiteralPath $entry.backup -Destination $destination -Force }
    elseif (-not $entry.existed -and (Test-Path -LiteralPath $destination -PathType Leaf)) { Remove-Item -LiteralPath $destination -Force }
  }
  Write-Log ("RESTORE {0}; source={1}" -f $game,$selected.FullName)
  Write-Host (T 'Откат завершён.' 'Restore completed.') -ForegroundColor Green
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
  if ($Action -eq 'Install') { if (-not $GamePath) { throw (T 'Для установки нужна папка игры.' 'Install requires a game folder.') }; Run-Install $GamePath $PackageManifest; return }
  if ($Action -eq 'Restore') { Run-Restore; return }
  Write-Host ''; Write-Host 'DLSS5 Universal Installer' -ForegroundColor Cyan
  Write-Host (T '1. Проверить игру' '1. Check game')
  Write-Host (T '2. Проверить packages и SHA-256' '2. Inventory packages and SHA-256')
  Write-Host (T '3. Установка проверенного пакета' '3. Install a verified package')
  Write-Host (T '4. Восстановление последней установки' '4. Restore latest installation')
  Write-Host (T '5. Язык' '5. Language')
  switch (Read-Host (T 'Выберите действие' 'Choose action')) {
    '1' { $p = if ($GamePath) { $GamePath } else { Read-Host (T 'Укажите папку игры' 'Enter game folder') }; Run-Check $p }
    '2' { Run-Packages }
    '3' { $p = if ($GamePath) { $GamePath } else { Read-Host (T 'Укажите папку игры' 'Enter game folder') }; Run-Install $p $PackageManifest }
    '4' { Run-Restore }
    '5' { Set-Language }
    default { Write-Host (T 'Отмена.' 'Cancelled.') }
  }
}
try { Main } catch { Write-Error $_; exit 1 }
