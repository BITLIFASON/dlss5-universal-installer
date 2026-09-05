[CmdletBinding()]
param([switch]$CheckOnly)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$Dirs = @{ Logs = Join-Path $Root 'logs'; Backups = Join-Path $Root 'backups'; Packages = Join-Path $Root 'packages'; Manifests = Join-Path $Root 'manifests' }
$Dirs.Values | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }
$SettingsPath = Join-Path $Root 'config\settings.json'
function Get-Settings {
  if (-not (Test-Path $SettingsPath)) {
    $default = [ordered]@{
      language = 'ru'
      supportedApis = @('DX11','DX12')
      compareBeforeInstall = $true
      warnBeforeElevation = $true
      useLocalPackagesFirst = $true
      allowAutomaticDownloads = $false
      deleteUnknownFiles = $false
    }
    $default | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $SettingsPath
  }
  Get-Content -Raw $SettingsPath | ConvertFrom-Json
}
$Settings = Get-Settings
function T($ru,$en) { if ($Settings.language -eq 'en') { $en } else { $ru } }
function Log($m) { $line = "$(Get-Date -Format o) $m"; Add-Content (Join-Path $Dirs.Logs 'installer.log') $line; Write-Host $m }
function Hash($p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Find-Game([string]$path) {
  if (-not (Test-Path $path -PathType Container)) { throw (T 'Папка не найдена.' 'Folder not found.') }
  $exes = @(Get-ChildItem -LiteralPath $path -Filter *.exe -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\(redist|support|tools|crash)\\' } | Sort-Object Length -Descending)
  if ($exes.Count -eq 0) { throw (T 'EXE не найден.' 'No executable found.') }
  $exes | Select-Object -First 10
}
function Inspect([string]$path) {
  $files = Get-ChildItem -LiteralPath $path -File -Recurse -ErrorAction SilentlyContinue
  $dlss = @($files | Where-Object Name -match '^(nvngx_dlss|nvngx_dlssg|nvngx_dlssnr|dlss).*\.dll$')
  $reshade = @($files | Where-Object Name -match '^(dxgi|d3d12|ReShade.*)\.dll$')
  $api = if ($files.Name -contains 'd3d12.dll' -or $files.Name -contains 'dxgi.dll') { 'DX11/DX12 candidate' } else { 'Unknown (confirm in game documentation)' }
  [pscustomobject]@{ API=$api; NativeDLSS=($dlss.Count -gt 0); ReShade=($reshade.Count -gt 0); Files=$files.Count; DLSSFiles=($dlss.Name -join ', ') }
}
function CompareMethods($info) {
  Write-Host ''; Write-Host (T 'Доступные методы:' 'Available methods:') -ForegroundColor Cyan
  if ($info.NativeDLSS) { Write-Host '1. Native/Bridge  - native DLSS detected; lowest overhead; best first choice.' }
  else { Write-Host '1. Native/Bridge  - not recommended: native DLSS was not detected.' -ForegroundColor DarkGray }
  Write-Host '2. OptiScaler      - broad compatibility; replaces/intercepts upscaler; DLL conflicts possible.'
  Write-Host '3. ReShade + Feeder - works without native DLSS; highest overhead; needs depth/motion vectors.'
}
function PickMethod($info) {
  do { $v = Read-Host (T 'Выберите метод (1-3, 0 отмена)' 'Choose method (1-3, 0 cancel)') } while ($v -notmatch '^[0-3]$')
  if ($v -eq '0') { return $null }; @('NativeBridge','OptiScaler','Feeder')[[int]$v-1]
}
function Backup-File($file,$game,$stamp) {
  $rel = $file.FullName.Substring($game.Length).TrimStart('\\'); $dest = Join-Path (Join-Path $Dirs.Backups $stamp) $rel
  New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null; Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
  [pscustomobject]@{ RelativePath=$rel; OriginalHash=(Hash $file.FullName); BackupPath=$dest }
}
function Main {
  if (-not (Test-Path $SettingsPath)) { $script:Settings = Get-Settings }
  Write-Host ''; Write-Host 'DLSS5 Universal Installer' -ForegroundColor Cyan
  Write-Host '1. Check only'; Write-Host '2. Install'; Write-Host '3. Restore backup'; Write-Host '4. Set language'
  $action = Read-Host (T 'Выберите действие' 'Choose action')
  if ($action -eq '4') { $l=Read-Host 'ru/en'; if ($l -match '^(ru|en)$') { $Settings.language = $l; $Settings | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $SettingsPath; $script:Settings = Get-Settings }; return }
  $game = Read-Host (T 'Укажите папку игры' 'Enter game folder')
  $exes = Find-Game $game; Write-Host (T 'Найденные EXE:' 'Detected EXEs:'); $exes | ForEach-Object { Write-Host " $($_.FullName)" }
  $info = Inspect $game; $info | Format-List
  CompareMethods $info
  if ($action -eq '1' -or $CheckOnly) { Log "CHECK $game"; return }
  if ($action -eq '2') { $method=PickMethod $info; if ($null -eq $method) { return }; Write-Host (T 'Установка пакетов выполняется только из packages и требует проверки manifest.' 'Packages are installed only from packages and require manifest verification.') -ForegroundColor Yellow; Write-Host "Selected: $method"; Log "SELECT $method for $game"; return }
  if ($action -eq '3') { Write-Host (T 'Восстановление будет добавлено после первого manifest.' 'Restore will be available after the first manifest.') -ForegroundColor Yellow; return }
}
try { Main } catch { Write-Error $_; exit 1 }
