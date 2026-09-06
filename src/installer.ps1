[CmdletBinding()]
param(
  [ValidateSet('Menu','Check','Packages','Download','Bootstrap','Install','Restore','CleanManifests')][string]$Action = 'Menu',
  [string]$GamePath,
  [string]$PackageManifest,
  [string]$SourceId,
  [ValidateSet('NativeBridge','OptiBridge','Feeder')][string]$Method,
  [ValidateSet('Kernel','QuantMotion')][string]$LumeniteProvider = 'Kernel',
  [string]$ExecutablePath,
  [string]$Api
)

$ErrorActionPreference = 'Stop'
$ScriptPath = if ([IO.Path]::IsPathRooted($PSCommandPath)) { $PSCommandPath } else { (Resolve-Path -LiteralPath $PSCommandPath).Path }
$Root = Split-Path -Parent (Split-Path -Parent $ScriptPath)
$Dirs = @{
  Logs = Join-Path $Root 'logs'
  Backups = Join-Path $Root 'backups'
  Packages = Join-Path $Root 'packages'
  Downloads = Join-Path $Root 'downloads'
  Manifests = Join-Path $Root 'manifests'
  Staging = Join-Path $Root 'staging'
}
$Dirs.Values | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }
$SettingsPath = Join-Path $Root 'config\settings.json'
$LocalSettingsPath = Join-Path $Root 'config\settings.local.json'
$CompatibilityPath = Join-Path $Root 'config\compatibility.json'

function Get-Settings {
  if (-not (Test-Path -LiteralPath $SettingsPath)) {
    [ordered]@{
      _comments = 'Edit values as needed. Automatic downloads are limited to HTTPS sources with a pinned SHA-256.'
      language = 'en'
      supportedApis = @('DX11','DX12')
      compareBeforeInstall = $true
      warnBeforeElevation = $true
      useLocalPackagesFirst = $true
      allowAutomaticDownloads = $true
      deleteUnknownFiles = $false
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
  }
  $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
  if (Test-Path -LiteralPath $LocalSettingsPath -PathType Leaf) {
    $local = Get-Content -LiteralPath $LocalSettingsPath -Raw | ConvertFrom-Json
    foreach ($property in $local.PSObject.Properties) {
      if ($property.Name -ne '_comments') { $settings | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force }
    }
  }
  return $settings
}
$Settings = Get-Settings

function Get-CompatibilityRecords {
  if (-not (Test-Path -LiteralPath $CompatibilityPath -PathType Leaf)) { return @() }
  try {
    $data = Get-Content -LiteralPath $CompatibilityPath -Raw | ConvertFrom-Json
    return @($data.records)
  } catch {
    Write-Log ("COMPATIBILITY_CONFIG_ERROR {0}" -f $_.Exception.Message)
    return @()
  }
}
function Find-KnownCompatibilityIssue($Info,[string]$SelectedMethod) {
  $folderName = Split-Path -Leaf ([string]$Info.gamePath).TrimEnd('\')
  $exeName = if ($Info.primaryExecutable) { [IO.Path]::GetFileName([string]$Info.primaryExecutable) } else { '' }
  foreach ($record in @(Get-CompatibilityRecords)) {
    if ([string]$record.method -ne $SelectedMethod) { continue }
    $folderMatch = @($record.gameFolderNames | Where-Object { $_ -and $_.ToString().Equals($folderName,[StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    $exeMatch = @($record.executableNames | Where-Object { $_ -and $_.ToString().Equals($exeName,[StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    if ($folderMatch -or $exeMatch) { return $record }
  }
  return $null
}

function T([string]$ru,[string]$en) { if ($Settings.language -eq 'en') { return $en }; return $ru }
function Read-Input([string]$ru,[string]$en) {
  $value = Read-Host (T "$ru (0 = отмена)" "$en (0 = cancel)")
  if ($value -match '^(0|q|quit|cancel|отмена)$') { throw [System.OperationCanceledException]::new('Operation cancelled by user.') }
  return $value
}
function Select-GameFolder {
  Add-Type -AssemblyName System.Windows.Forms
  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  $dialog.Description = (T 'Выберите папку игры' 'Select the game folder')
  $dialog.ShowNewFolderButton = $false
  if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dialog.SelectedPath }
  throw [System.OperationCanceledException]::new('Folder selection cancelled.')
}
function Read-GamePath {
  $value = Read-Input 'Укажите путь к игре или введите 1 для выбора через Explorer' 'Enter the game path or type 1 to browse with Explorer'
  if ($value -eq '1') { return Select-GameFolder }
  return $value
}
function Show-Inspection($Info) {
  Write-Host ''; Write-Host (T 'Обнаружено:' 'Inspection:') -ForegroundColor Cyan
  if ($Settings.interfaceMode -eq 'advanced') {
    $Info | ConvertTo-Json -Depth 8 | Write-Host
    return
  }
  Write-Host ((T "Игра: {0}" "Game: {0}") -f $Info.gamePath)
  Write-Host ((T "Основной EXE: {0}" "Primary EXE: {0}") -f $Info.primaryExecutable)
  Write-Host ((T "Архитектура: {0}" "Architecture: {0}") -f $Info.primaryArchitecture)
  Write-Host ((T "API: {0}" "API: {0}") -f $Info.apiHint)
  $dlss = if ($Info.nativeDlssDetected) { T 'найден' 'detected' } else { T 'не найден' 'not detected' }
  Write-Host ((T "Native DLSS: {0}" "Native DLSS: {0}") -f $dlss)
  Write-Host ((T "FSR/XeSS путей: {0}" "FSR/XeSS paths: {0}") -f @($Info.upscalerFiles).Count)
  Write-Host ((T "Файлов проверено: {0}" "Files inspected: {0}") -f $Info.fileCount)
  Write-Host ((T "Процесс игры: {0}" "Game process: {0}") -f (if ($Info.processRunning) { T 'запущен' 'running' } else { T 'не запущен' 'not running' }))
  Write-Host ((T "Proxy DLL найдено: {0}" "Proxy DLLs found: {0}") -f @($Info.proxyFiles).Count)
}
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
function Get-ApiHint([string]$ExecutablePath) {
  try {
    $bytes = [IO.File]::ReadAllBytes($ExecutablePath)
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    $has12 = $text -match '(?i)d3d12\.dll'
    $has11 = $text -match '(?i)d3d11\.dll'
    if ($has12 -and $has11) { return 'DX11/DX12 candidate (PE imports)' }
    if ($has12) { return 'DX12 candidate (PE imports)' }
    if ($has11) { return 'DX11 candidate (PE imports)' }
  } catch { }
  return 'Unknown (confirm in game documentation)'
}
function Test-GameProcess([string]$ExecutablePath) {
  $name = [IO.Path]::GetFileNameWithoutExtension($ExecutablePath)
  return $null -ne (Get-Process -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1)
}
function Get-ExecutableScore($Exe,[string]$Root) {
  $score = 0
  $name = $Exe.BaseName.ToLowerInvariant()
  $relative = $Exe.FullName.Substring($Root.Length).TrimStart('\').ToLowerInvariant()
  if ($relative -match '\\binaries\\win64\\') { $score += 100 }
  if ($name -match 'shipping|game|client') { $score += 50 }
  if ($name -match 'launcher|crash|unins|setup|updater|redist') { $score -= 100 }
  if ($Exe.Length -gt 50MB) { $score += 20 }
  return $score
}
function Test-TechnicalExecutable($Exe,[string]$Root) {
  $name = $Exe.BaseName.ToLowerInvariant()
  $relative = $Exe.FullName.Substring($Root.Length).TrimStart('\').ToLowerInvariant()
  if ($relative -match '\\engine\\binaries\\|\\editor\\') { return $true }
  if ($name -match 'unrealcefsubprocess|crashreportclient|shadercompileworker|unrealeditor|ue4editor|unitycrashhandler|unitylicensingclient|automationtool|dedicatedserver') { return $true }
  if ($name -match '(-editor|-server)$') { return $true }
  return $false
}
function Find-GameExecutables([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw (T 'Папка игры не найдена.' 'Game folder was not found.') }
  $items = @(Get-ChildItem -LiteralPath $Path -Filter '*.exe' -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\(redist|support|tools|crash|_commonredist)\\' -and -not (Test-TechnicalExecutable $_ $Path) } |
    Sort-Object Length -Descending)
  if ($items.Count -eq 0) { throw (T 'В папке не найден исполняемый файл.' 'No executable was found in the folder.') }
  foreach ($item in $items) { Add-Member -InputObject $item -NotePropertyName candidateScore -NotePropertyValue (Get-ExecutableScore $item $Path) -Force }
  return @($items | Sort-Object candidateScore,Length -Descending | Select-Object -First 20)
}
function Get-ManagedInstalledPaths([string]$GamePath) {
  $paths = @{}
  foreach ($manifestFile in @(Get-InstalledPackageManifest)) {
    try {
      $install = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json
      if ([string]$install.gamePath -ne $GamePath) { continue }
      $root = if ($install.installRoot) { [string]$install.installRoot } else { [string]$install.gamePath }
      foreach ($entry in @($install.files)) {
        if ($entry.path) { $paths[(Join-Path $root ([string]$entry.path)).ToLowerInvariant()] = $true }
      }
    } catch { }
  }
  return $paths
}
function Get-GameInspection([string]$Path) {
  $resolved = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
  $files = @(Get-ChildItem -LiteralPath $resolved -File -Recurse -ErrorAction SilentlyContinue)
  $executables = @(Find-GameExecutables $resolved)
  $dlss = @($files | Where-Object { $_.Name -match '^(nvngx_dlss|nvngx_dlssg|nvngx_dlssnr|dlss).*\.dll' })
  $managed = Get-ManagedInstalledPaths $resolved
  $feederMarker = @($files | Where-Object { $_.Name -in @('dlss5-feed.addon64','renodx-dlss5.addon64') })
  $managedDlss = @($dlss | Where-Object { $managed.ContainsKey($_.FullName.ToLowerInvariant()) -or ($feederMarker.Count -gt 0 -and $_.DirectoryName -eq $feederMarker[0].DirectoryName -and $_.Name -in @('nvngx_dlss.dll','nvngx_dlssnr.dll')) })
  $managedDlssPaths = @($managedDlss | ForEach-Object { $_.FullName.ToLowerInvariant() })
  $nativeDlss = @($dlss | Where-Object { $managedDlssPaths -notcontains $_.FullName.ToLowerInvariant() })
  $upscaler = @($files | Where-Object { $_.Name -match '(?i)^(ffx_fsr|amd_fidelityfx|libxess|xess|OptiScaler).*\.(dll|ini)$' })
  $proxy = @($files | Where-Object { $_.Name -match '^(dxgi|d3d11|d3d12|ReShade.*)\.dll' })
  $apiHint = Get-ApiHint $executables[0].FullName
  if ($apiHint -eq 'Unknown (confirm in game documentation)') {
    $apiHint = if ($files.Name -contains 'd3d12.dll') { 'DX12 candidate' } elseif ($files.Name -contains 'd3d11.dll') { 'DX11 candidate' } else { $apiHint }
  }
  [ordered]@{
    timestamp = (Get-Date).ToUniversalTime().ToString('o')
    gamePath = $resolved
    primaryExecutable = $executables[0].FullName
    primaryArchitecture = Get-PeArchitecture $executables[0].FullName
    executables = @($executables | ForEach-Object { [ordered]@{ path = $_.FullName; size = $_.Length; architecture = Get-PeArchitecture $_.FullName; candidateScore = $_.candidateScore } })
    apiHint = $apiHint
    processRunning = Test-GameProcess $executables[0].FullName
    nativeDlssDetected = ($nativeDlss.Count -gt 0)
    dlssFiles = @($dlss | ForEach-Object { Get-RelativePath $resolved $_.FullName })
    managedDlssFiles = @($managedDlss | ForEach-Object { Get-RelativePath $resolved $_.FullName })
    nativeDlssFiles = @($nativeDlss | ForEach-Object { Get-RelativePath $resolved $_.FullName })
    upscalerFiles = @($upscaler | ForEach-Object { Get-RelativePath $resolved $_.FullName })
    proxyFiles = @($proxy | ForEach-Object { Get-RelativePath $resolved $_.FullName })
    fileCount = $files.Count
  }
}
function Select-Executable($Info) {
  $candidates = @($Info.executables)
  if ($candidates.Count -eq 1) { return [string]$candidates[0].path }
  Write-Host ''; Write-Host (T 'Кандидаты исполняемых файлов для установки:' 'Executable candidates for installation:') -ForegroundColor Cyan
  for ($i = 0; $i -lt $candidates.Count; $i++) {
    $candidate = $candidates[$i]
    Write-Host ("{0}. {1} | {2} | score={3}" -f ($i + 1),$candidate.path,$candidate.architecture,$candidate.candidateScore)
  }
  $choice = Read-Input 'Выберите номер EXE' 'Choose the executable number'
  $index = 0
  if (-not [int]::TryParse($choice,[ref]$index) -or $index -lt 1 -or $index -gt $candidates.Count) { throw (T 'Некорректный номер исполняемого файла.' 'Invalid executable number.') }
  return [string]$candidates[$index - 1].path
}
function Show-MethodComparison($Info) {
  Write-Host ''; Write-Host (T 'Сравнение методов:' 'Method comparison:') -ForegroundColor Cyan
  if ($Info.nativeDlssDetected) { Write-Host (T '1. Native/Bridge — обнаружен штатный DLSS; обычно минимальная нагрузка.' '1. Native/Bridge — native DLSS detected; usually lowest overhead.') } else { Write-Host (T '1. Native/Bridge — штатный DLSS не найден, сначала проверить вручную.' '1. Native/Bridge — native DLSS not detected; verify manually first.') -ForegroundColor DarkGray }
  if (@($Info.upscalerFiles).Count -gt 0) { Write-Host ((T '2. OptiScaler Bridge + DLSS5 — найдены пути FSR/XeSS ({0}); прокси переводит их в DLSS5, возможны конфликты DLL.' '2. OptiScaler Bridge + DLSS5 — FSR/XeSS paths detected ({0}); the proxy routes them into DLSS5, proxy DLL conflicts are possible.') -f @($Info.upscalerFiles).Count) } else { Write-Host (T '2. OptiScaler Bridge + DLSS5 — FSR/XeSS автоматически не обнаружены; установка остаётся экспериментальной.' '2. OptiScaler Bridge + DLSS5 — FSR/XeSS were not detected automatically; installation remains experimental.') }
  Write-Host (T '3. ReShade + Feeder — постобработка; требует буфер глубины и векторы движения, обычно снижает FPS.' '3. ReShade + Feeder — post-processing; needs depth/motion vectors and usually costs more FPS.')
}
function Confirm-MethodCompatibility($Info,[string]$SelectedMethod) {
  $warning = $false
  if ($SelectedMethod -eq 'OptiBridge') {
    Write-Host (T 'OptiScaler Bridge + DLSS5 требует выбрать в игре FSR или XeSS; обычный OptiScaler отдельно не устанавливается.' 'OptiScaler Bridge + DLSS5 requires FSR or XeSS to be selected in-game; standalone OptiScaler is not installed.') -ForegroundColor Yellow
    $knownIssue = Find-KnownCompatibilityIssue $Info $SelectedMethod
    if ($knownIssue) {
      Write-Host (T ("Предупреждение совместимости: {0}" -f $knownIssue.reason_ru) ("Compatibility warning: {0}" -f $knownIssue.reason_en)) -ForegroundColor Red
      Write-Host (T ("Тест: {0}; доказательство: {1}" -f $knownIssue.tested,$knownIssue.evidence) ("Tested: {0}; evidence: {1}" -f $knownIssue.tested,$knownIssue.evidence)) -ForegroundColor DarkGray
      $warning = $true
    }
  }
  if ($SelectedMethod -eq 'NativeBridge' -and -not $Info.nativeDlssDetected) {
    Write-Host (T 'Предупреждение: native DLSS не найден. Этот метод может не дать результата.' 'Warning: native DLSS was not detected. This method may not work.') -ForegroundColor Yellow
    $warning = $true
  }
  if ($SelectedMethod -eq 'OptiBridge' -and @($Info.upscalerFiles).Count -eq 0) {
    Write-Host (T 'Предупреждение: для OptiScaler Bridge + DLSS5 FSR/XeSS автоматически не найдены. Установка остаётся экспериментальной.' 'Warning: OptiScaler Bridge + DLSS5 did not detect FSR/XeSS automatically. Installation remains experimental.') -ForegroundColor Yellow
    $warning = $true
  }
  if ($warning -and (Read-Input 'Продолжить с этим методом? (y/n)' 'Continue with this method? (y/n)') -notmatch '^(y|yes|д|да)$') { return $false }
  return $true
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
  Show-Inspection $info
  Show-MethodComparison $info
  $manifest = Save-JsonManifest 'check' $info
  Write-Log ("CHECK {0}; manifest={1}" -f $info.gamePath,$manifest)
}
function Run-Packages {
  $inventory = Get-PackageInventory
  if ($inventory.Count -eq 0) { Write-Host (T 'В папке пакетов пока нет архивов или DLL.' 'No archives or DLLs found in packages yet.') -ForegroundColor Yellow }
  else { $inventory | Format-Table name,extension,size,sha256 -AutoSize }
  $manifest = Save-JsonManifest 'packages' $inventory
  Write-Log ("PACKAGES; manifest={0}" -f $manifest)
}
function Run-CleanManifests {
  $files = @(Get-ChildItem -LiteralPath $Dirs.Manifests -File -ErrorAction SilentlyContinue)
  $automatic = @($files | Where-Object { $_.Name -match '^(check|packages)-.*\.json$' })
  $protected = @($files | Where-Object { $_.Name -notmatch '^(check|packages)-.*\.json$' })
  foreach ($file in $automatic) { Remove-Item -LiteralPath $file.FullName -Force; Write-Log ("MANIFEST_REMOVED {0}" -f $file.FullName) }
  if ($automatic.Count -gt 0) { Write-Host (T ("Удалено без подтверждения: {0} check/packages manifest." -f $automatic.Count) ("Removed without confirmation: {0} check/packages manifest(s)." -f $automatic.Count)) -ForegroundColor Green }
  if ($protected.Count -eq 0) {
    if ($automatic.Count -eq 0) { Write-Host (T 'Манифесты для очистки не найдены.' 'No manifests to clean were found.') -ForegroundColor Yellow }
    return
  }
  Write-Host ''; Write-Host (T 'Для удаления с подтверждением найдены:' 'The following manifests require confirmation:') -ForegroundColor Yellow
  $protected | ForEach-Object { Write-Host (" - {0}" -f $_.Name) }
  if ((Read-Input 'Удалить эти манифесты? (y/n)' 'Delete these manifests? (y/n)') -match '^(y|yes|д|да)$') {
    foreach ($file in $protected) { Remove-Item -LiteralPath $file.FullName -Force; Write-Log ("MANIFEST_REMOVED {0}" -f $file.FullName) }
    Write-Host (T 'Подтверждённые манифесты удалены.' 'Confirmed manifests removed.') -ForegroundColor Green
  } else { Write-Host (T 'Манифесты с подтверждением сохранены.' 'Confirmation-required manifests were kept.') -ForegroundColor Yellow }
}
function Get-SourceLock {
  $candidates = @(
    (Join-Path $Root 'config\sources.lock.json'),
    (Join-Path (Get-Location) 'config\sources.lock.json')
  )
  $cursor = Split-Path -Parent $ScriptPath
  for ($i = 0; $i -lt 4 -and $cursor; $i++) {
    $candidates += Join-Path $cursor 'config\sources.lock.json'
    $parent = Split-Path -Parent $cursor
    if ($parent -eq $cursor) { break }
    $cursor = $parent
  }
  $path = @($candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
  if (-not $path) { throw (T ("Файл sources.lock.json не найден. Root: {0}; Script: {1}" -f $Root,$ScriptPath) ("sources.lock.json was not found. Root: {0}; script: {1}" -f $Root,$ScriptPath)) }
  Write-Log ("SOURCE_LOCK {0}" -f $path)
  Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}
function Get-SourceDownloadUrl($Source) {
  if ($Source.downloadUrl) { return [string]$Source.downloadUrl }
  if ($Source.url) { return [string]$Source.url }
  if ($Source.provider -eq 'github' -and $Source.repository -and $Source.tag -and $Source.asset) {
    return ("https://github.com/{0}/releases/download/{1}/{2}" -f $Source.repository,$Source.tag,$Source.asset)
  }
  throw ("Locked source has no resolvable download URL: {0}" -f $Source.id)
}
function Invoke-ProgressDownload([string]$Url,[string]$Destination) {
  $temporary = "$Destination.download"
  if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
  $request = [Net.HttpWebRequest]::Create($Url)
  $request.UserAgent = 'DLSS5-Universal-Installer/1.0'
  $response = $null
  $inputStream = $null
  $outputStream = $null
  try {
    $response = $request.GetResponse()
    $inputStream = $response.GetResponseStream()
    $outputStream = [IO.File]::Open($temporary,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $buffer = New-Object byte[] (1024 * 1024)
    $total = [int64]$response.ContentLength
    $received = [int64]0
    while (($read = $inputStream.Read($buffer,0,$buffer.Length)) -gt 0) {
      $outputStream.Write($buffer,0,$read)
      $received += $read
      if ($total -gt 0) {
        $percent = [math]::Min(100,[math]::Floor(($received * 100) / $total))
        Write-Progress -Activity (T 'Скачивание компонента' 'Downloading component') -Status ("{0:N1} / {1:N1} MB" -f ($received/1MB),($total/1MB)) -PercentComplete $percent
      } else {
        Write-Progress -Activity (T 'Скачивание компонента' 'Downloading component') -Status ("{0:N1} MB" -f ($received/1MB))
      }
    }
    $outputStream.Close(); $outputStream = $null
    if ($response) { $response.Close(); $response = $null }
    Write-Progress -Activity (T 'Скачивание компонента' 'Downloading component') -Completed
    Move-Item -LiteralPath $temporary -Destination $Destination -Force
  } catch {
    if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    throw
  } finally {
    if ($outputStream) { $outputStream.Dispose() }
    if ($inputStream) { $inputStream.Dispose() }
    if ($response) { $response.Close() }
  }
}
function Ensure-LockedDownload([string]$Id) {
  $lock = Get-SourceLock
  $source = @($lock.sources | Where-Object { $_.id -eq $Id }) | Select-Object -First 1
  if ($null -eq $source) { throw ("Unknown locked source: {0}" -f $Id) }
  $url = Get-SourceDownloadUrl $source
  if ($url -notmatch '^https://') { throw ("Locked source is not HTTPS: {0}" -f $Id) }
  if ([string]$source.sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw ("Locked source has no valid SHA-256: {0}" -f $Id) }
  $name = [IO.Path]::GetFileName(([Uri]$url).AbsolutePath)
  $path = Join-Path $Dirs.Downloads $name
  if (Test-Path -LiteralPath $path -PathType Leaf) {
    if ((Get-Sha256 $path) -eq ([string]$source.sha256).ToLowerInvariant()) { return $path }
    Remove-Item -LiteralPath $path -Force
  }
  Invoke-ProgressDownload $url $path
  if ((Get-Sha256 $path) -ne ([string]$source.sha256).ToLowerInvariant()) { Remove-Item -LiteralPath $path -Force; throw ("SHA-256 mismatch for source: {0}" -f $Id) }
  return $path
}
function Get-LumeniteProviderConfig([string]$Provider = 'Kernel') {
  if ($Provider -eq 'QuantMotion') { return [ordered]@{ name='QuantMotion'; code=4; technique='lumenite_QuantMotion@lumenite_QuantMotion.fx' } }
  return [ordered]@{ name='Kernel'; code=3; technique='Lumenite_Kernel@lumenite_Kernel.fx' }
}
function Find-GameNativeDlssRuntime([string]$GamePath) {
  if (-not $GamePath -or -not (Test-Path -LiteralPath $GamePath -PathType Container)) { return $null }
  $candidates = @(Get-ChildItem -LiteralPath $GamePath -Recurse -File -Filter 'nvngx_dlss.dll' -ErrorAction SilentlyContinue | ForEach-Object {
    $full = $_.FullName
    $score = 0
    if ($full -match '(?i)\\Engine\\Plugins\\Marketplace\\DLSS\\Binaries\\ThirdParty\\Win64\\nvngx_dlss\.dll$') { $score = 100 }
    elseif ($full -match '(?i)\\(?:Plugins\\Marketplace\\)?DLSS\\Binaries\\ThirdParty\\Win64\\nvngx_dlss\.dll$') { $score = 90 }
    elseif ($full -match '(?i)\\(?:Plugins\\)?DLSS[^\\]*\\.*\\nvngx_dlss\.dll$') { $score = 70 }
    elseif ($full -match '(?i)\\Streamline[^\\]*\\.*\\nvngx_dlss\.dll$') { $score = 60 }
    if ($score -gt 0) { [pscustomobject]@{ Path=$full; Score=$score } }
  } | Sort-Object Score -Descending)
  if ($candidates.Count -gt 0) { return [string]$candidates[0].Path }
  return $null
}
function Prepare-SourcePackage($Manifest,[string]$Provider = 'Kernel',[string]$GamePath = $null) {
  if ($Manifest.sourcePackage -eq 'dlss5-bridge') {
    Ensure-LockedDownload 'dlss5-bridge' | Out-Null
    return $Dirs.Downloads
  }
  if ($Manifest.sourcePackage -eq 'dlss5-native-bridge') {
    $seven = Ensure-LockedDownload '7zr-26.03'
    $bridge = Ensure-LockedDownload 'dlss5-bridge'
    Ensure-LockedDownload 'dlss5-aio-v1.2.5-part1' | Out-Null
    Ensure-LockedDownload 'dlss5-aio-v1.2.5-part2' | Out-Null
    Ensure-LockedDownload 'dlss5-aio-v1.2.5-part3' | Out-Null
    $out = Join-Path $Dirs.Staging ('bootstrap-native-bridge-' + $Manifest.version)
    $aioRoot = Join-Path $out 'DLSS5-AIO'
    $filesRoot = Join-Path $out 'files'
    $model = Join-Path $aioRoot '02-DLSS5-Neural-Rendering\nvngx_dlssnr.dll'
    $neuralAddon = Join-Path $aioRoot '02-DLSS5-Neural-Rendering\renodx-dlss5.addon64'
    $runtime = Join-Path $aioRoot '01-Official-NVIDIA-DLLs\nvngx_dlss.dll'
    if (-not (Test-Path -LiteralPath $model -PathType Leaf) -or -not (Test-Path -LiteralPath $neuralAddon -PathType Leaf)) {
      New-Item -ItemType Directory -Force -Path $out | Out-Null
      & $seven x (Join-Path $Dirs.Downloads 'DLSS5-AIO-v1.2.5.7z.001') "-o$out" -y | Out-Null
      if ($LASTEXITCODE -ne 0) { throw 'DLSS5-AIO extraction failed.' }
    }
    New-Item -ItemType Directory -Force -Path $filesRoot | Out-Null
    Copy-Item -LiteralPath $bridge -Destination (Join-Path $filesRoot 'dlss5-bridge.addon64') -Force
    Copy-Item -LiteralPath $model -Destination (Join-Path $filesRoot 'nvngx_dlssnr.dll') -Force
    Copy-Item -LiteralPath $neuralAddon -Destination (Join-Path $filesRoot 'renodx-dlss5.addon64') -Force
    # Prefer the game's own Unreal DLSS runtime. The bridge only searches beside
    # the add-on and beside the executable, so nested Marketplace binaries are
    # copied to the executable directory during installation. Keep the pinned
    # AIO runtime as a fallback for games that do not ship one.
    $nativeRuntime = Find-GameNativeDlssRuntime $GamePath
    if ($nativeRuntime) {
      Copy-Item -LiteralPath $nativeRuntime -Destination (Join-Path $filesRoot 'nvngx_dlss.dll') -Force
      Set-Content -LiteralPath (Join-Path $filesRoot 'nvngx_dlss.dll.source') -Value $nativeRuntime -Encoding UTF8
    } else {
      if (-not (Test-Path -LiteralPath $runtime -PathType Leaf)) { throw 'Neither the game-native nvngx_dlss.dll nor the pinned AIO runtime was found.' }
      Copy-Item -LiteralPath $runtime -Destination (Join-Path $filesRoot 'nvngx_dlss.dll') -Force
    }
    return $out
  }
  if ($Manifest.sourcePackage -eq 'opti-dlss5') {
    $seven = Ensure-LockedDownload '7zr-26.03'
    $optiArchive = Ensure-LockedDownload 'optiscaler'
    Ensure-LockedDownload 'dlss5-aio-v1.2.5-part1' | Out-Null
    Ensure-LockedDownload 'dlss5-aio-v1.2.5-part2' | Out-Null
    Ensure-LockedDownload 'dlss5-aio-v1.2.5-part3' | Out-Null
    $out = Join-Path $Dirs.Staging ('bootstrap-opti-dlss5-' + $Manifest.version)
    $optiRoot = Join-Path $out 'OptiScaler'
    $aioRoot = Join-Path $out 'DLSS5-AIO'
    if (-not (Test-Path -LiteralPath (Join-Path $optiRoot 'OptiScaler.dll') -PathType Leaf)) {
      New-Item -ItemType Directory -Force -Path $optiRoot | Out-Null
      & $seven x $optiArchive "-o$optiRoot" -y | Out-Null
      if ($LASTEXITCODE -ne 0) { throw 'OptiScaler extraction failed.' }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $aioRoot 'DLSS5-AIO\02-DLSS5-Neural-Rendering\renodx-dlss5.addon64') -PathType Leaf)) {
      New-Item -ItemType Directory -Force -Path $out | Out-Null
      & $seven x (Join-Path $Dirs.Downloads 'DLSS5-AIO-v1.2.5.7z.001') "-o$out" -y | Out-Null
      if ($LASTEXITCODE -ne 0) { throw 'DLSS5-AIO extraction failed.' }
    }
    $generated = Join-Path $out 'generated\OptiScaler.ini'
    New-Item -ItemType Directory -Force -Path (Split-Path $generated) | Out-Null
    Copy-Item -LiteralPath (Join-Path $Root 'config\optiscaler-dlss5.ini') -Destination $generated -Force
    return $out
  }
  if ($Manifest.sourcePackage -eq 'dlss5-aio') {
    $seven = Ensure-LockedDownload '7zr-26.03'
    Ensure-LockedDownload 'dlss5-aio-v1.2.5-part1' | Out-Null
    Ensure-LockedDownload 'dlss5-aio-v1.2.5-part2' | Out-Null
    Ensure-LockedDownload 'dlss5-aio-v1.2.5-part3' | Out-Null
    $out = Join-Path $Dirs.Staging ('bootstrap-aio-' + $Manifest.version)
    $root = Join-Path $out 'DLSS5-AIO'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
      New-Item -ItemType Directory -Force -Path $out | Out-Null
      & $seven x (Join-Path $Dirs.Downloads 'DLSS5-AIO-v1.2.5.7z.001') "-o$out" -y | Out-Null
      if ($LASTEXITCODE -ne 0) { throw 'DLSS5-AIO extraction failed.' }
    }
    if ($Manifest.sourcePackages -contains 'lumenitefx') {
      if ($Manifest.sourcePackages -contains 'dlss5-feeder-upstream') {
        $feederArchive = Ensure-LockedDownload 'dlss5-feeder-v0.13.1-beta.1'
        $feederOut = Join-Path $out 'dlss5-feeder-upstream'
        if (-not (Test-Path -LiteralPath $feederOut -PathType Container)) { Expand-Package $feederArchive $feederOut }
        $newAddon = Get-ChildItem -LiteralPath $feederOut -File -Recurse -Filter 'dlss5-feed.addon64' | Select-Object -First 1
        $newShader = Get-ChildItem -LiteralPath $feederOut -File -Recurse -Filter 'DLSS5_Feed.fx' | Select-Object -First 1
        if ($null -eq $newAddon -or $null -eq $newShader) { throw 'Pinned DLSS5-Feeder archive is missing the x64 add-on or shader.' }
        Copy-Item -LiteralPath $newAddon.FullName -Destination (Join-Path $root '04-DLSS5-Feeder\dlss5-feed.addon64') -Force
        Copy-Item -LiteralPath $newShader.FullName -Destination (Join-Path $root '04-DLSS5-Feeder\DLSS5_Feed.fx') -Force
      }
      $lumeniteArchive = Ensure-LockedDownload 'lumenitefx-mainline-76fa3e4d'
      $lumeniteOut = Join-Path $out 'lumenitefx-source'
      if (-not (Test-Path -LiteralPath $lumeniteOut -PathType Container)) { Expand-Package $lumeniteArchive $lumeniteOut }
      foreach ($relative in @('Shaders\lumenite_Kernel.fx','Shaders\lumenite_QuantMotion.fx','Shaders\include\lumenite_ColorManagement.fxh','Shaders\include\lumenite_Compute.fxh','Shaders\include\lumenite_Helpers.fxh','Shaders\include\lumenite_Projections.fxh','Textures\lumenite_bluenoise256.png')) {
        $source = Get-ChildItem -LiteralPath $lumeniteOut -File -Recurse -Filter ([IO.Path]::GetFileName($relative)) -ErrorAction SilentlyContinue | Select-Object -First 1
        $destination = Join-Path $root ('lumenitefx\' + $relative)
        if ($null -eq $source) { throw ("LumeniteFX archive is missing: {0}" -f $relative) }
        New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
        Copy-Item -LiteralPath $source.FullName -Destination $destination -Force
      }
      $preset = Join-Path $root 'installer-generated\ReShadePreset.ini'
      New-Item -ItemType Directory -Force -Path (Split-Path $preset) | Out-Null
      $providerConfig = Get-LumeniteProviderConfig $Provider
      $presetText = "[GENERAL]`r`nPreprocessorDefinitions=DLSS5_MV_PROVIDER=$($providerConfig.code)`r`nTechniques=$($providerConfig.technique),DLSS5_Feed@DLSS5_Feed.fx`r`nTechniqueSorting=$($providerConfig.technique),DLSS5_Feed@DLSS5_Feed.fx`r`n`r`n[DLSS5_Feed.fx]`r`nGEOM_ENABLE=0`r`nVALIDATE_LUMA=1`r`nVALIDATE_DEPTH=1`r`nVALIDATE_MV=1`r`nVALIDATE_STATIC=1`r`nSTATIC_HYSTERESIS=1`r`nSTATIC_MIN_CONTRAST=0.02`r`nMV_LOWRES_FILTER=0`r`n"
      [IO.File]::WriteAllText($preset, $presetText, (New-Object System.Text.UTF8Encoding($false)))
    }
    return $root
  }
  return $null
}
function Run-Download([string]$Id) {
  if (-not $Settings.allowAutomaticDownloads) { throw (T 'Автоскачивание отключено в config/settings.json. Сначала явно включите allowAutomaticDownloads.' 'Automatic downloads are disabled in config/settings.json. Explicitly enable allowAutomaticDownloads first.') }
  $lock = Get-SourceLock
  $source = @($lock.sources | Where-Object { $_.id -eq $Id }) | Select-Object -First 1
  if ($null -eq $source) { throw ("Unknown locked source: {0}" -f $Id) }
  $url = Get-SourceDownloadUrl $source
  if ([string]::IsNullOrWhiteSpace($url) -or $url -notmatch '^https://') { throw (T 'Для источника нужен HTTPS URL.' 'A HTTPS URL is required for the source.') }
  if ([string]$source.sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw (T 'Для источника не задан ожидаемый SHA-256.' 'Expected SHA-256 is not set for this source.') }
  $name = [IO.Path]::GetFileName(([Uri]$url).AbsolutePath)
  if ([string]::IsNullOrWhiteSpace($name) -or $name -eq '/') { $name = "$($source.id)-$($source.version).download" }
  $download = Join-Path $Dirs.Downloads $name
  Write-Host (T ("Скачивание {0} {1}..." -f $source.id,$source.version) ("Downloading {0} {1}..." -f $source.id,$source.version))
  Invoke-ProgressDownload $url $download
  $actual = Get-Sha256 $download
  if ($actual -ne ([string]$source.sha256).ToLowerInvariant()) { Remove-Item -LiteralPath $download -Force; throw (T 'SHA-256 скачанного файла не совпал; файл удалён.' 'Downloaded SHA-256 did not match; file was removed.') }
  Copy-Item -LiteralPath $download -Destination (Join-Path $Dirs.Packages $name) -Force
  Write-Log ("DOWNLOAD {0} {1}; sha256={2}" -f $source.id,$source.version,$actual)
  Write-Host (T 'Проверенный архив помещён в папку пакетов.' 'Verified archive copied to packages.') -ForegroundColor Green
}
function Test-SafeRelativePath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or $Path.Replace('/','\') -match '(^|\\)\.\.([\\]|$)') { return $false }
  return $true
}
function Get-PackageManifest([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw (T 'Манифест пакета не найден.' 'Package manifest was not found.') }
  $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  foreach ($required in @('id','version','method','source','files')) {
    if ($null -eq $manifest.$required) { throw ("Package manifest is missing: {0}" -f $required) }
  }
  if ($manifest.method -notin @('NativeBridge','OptiBridge','Feeder')) { throw (T 'В манифесте указан неизвестный метод.' 'Unknown method in package manifest.') }
  if (-not $manifest.sourcePackage -and -not $manifest.sourcePackages) {
    if ($null -eq $manifest.archive -or $null -eq $manifest.sha256) { throw (T 'В манифесте отсутствуют archive или sha256.' 'Manifest is missing archive or sha256.') }
    $archive = Join-Path $Dirs.Packages ([IO.Path]::GetFileName([string]$manifest.archive))
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw (T 'Архив пакета отсутствует в папке пакетов.' 'Package archive is missing from packages.') }
    if ((Get-Sha256 $archive) -ne ([string]$manifest.sha256).ToLowerInvariant()) { throw (T 'SHA-256 архива не совпадает с манифестом.' 'Archive SHA-256 does not match the manifest.') }
    $manifest | Add-Member -NotePropertyName _archivePath -NotePropertyValue $archive -Force
  }
  foreach ($entry in @($manifest.files)) {
    if (-not (Test-SafeRelativePath ([string]$entry.path)) -or [string]::IsNullOrWhiteSpace([string]$entry.sha256)) { throw (T 'Некорректный список файлов в манифесте.' 'Invalid file list in package manifest.') }
    if ($entry.sourcePath -and -not (Test-SafeRelativePath ([string]$entry.sourcePath))) { throw (T 'Некорректный sourcePath в манифесте.' 'Invalid sourcePath in package manifest.') }
  }
  return $manifest
}
function Show-ConflictReport($Info) {
  if (@($Info.proxyFiles).Count -eq 0) {
    Write-Host (T 'Конфликтующие proxy DLL не обнаружены.' 'No proxy DLL conflicts detected.') -ForegroundColor Green
    return
  }
  Write-Host (T 'Обнаружены потенциально конфликтующие DLL:' 'Potentially conflicting DLLs detected:') -ForegroundColor Yellow
  @($Info.proxyFiles) | ForEach-Object { Write-Host (" - {0}" -f $_) }
}
function Test-InstallEntryForApi($Entry,[string]$Api) {
  if (-not $Entry.installWhenApi -or [string]::IsNullOrWhiteSpace($Api)) { return $true }
  return @($Entry.installWhenApi | ForEach-Object { [string]$_ }) -contains $Api
}
function Show-InstallPlan($Manifest,[string]$InstallRoot) {
  Write-Host ''; Write-Host (T 'План установки:' 'Installation plan:') -ForegroundColor Cyan
  foreach ($entry in @($Manifest.files)) {
    if (-not (Test-InstallEntryForApi $entry $script:InstallApi)) { continue }
    $destination = Join-Path $InstallRoot ([string]$entry.path)
    $action = if (Test-Path -LiteralPath $destination -PathType Leaf) { T 'замена' 'replace' } else { T 'новый файл' 'new file' }
    Write-Host (" - [{0}] {1}" -f $action,$destination)
  }
}
function Save-GameProfile($Info,[string]$ExecutablePath,$Manifest,[string]$Api) {
  $path = Join-Path $Root 'config\game-profiles.local.json'
  $profiles = @()
  if (Test-Path -LiteralPath $path -PathType Leaf) { $profiles = @(Get-Content $path -Raw | ConvertFrom-Json) }
  $profiles = @($profiles | Where-Object { $_.gamePath -ne $Info.gamePath })
  $profiles += [ordered]@{ gamePath=$Info.gamePath; executable=$ExecutablePath; api=$Api; method=$Manifest.method; packageId=$Manifest.id; packageVersion=$Manifest.version; updated=(Get-Date).ToUniversalTime().ToString('o') }
  $profiles | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
}
function Offer-Launch([string]$ExecutablePath) {
  try {
    if ((Read-Input 'Запустить выбранный EXE для проверки? (y/n)' 'Launch the selected executable for verification? (y/n)') -match '^(y|yes|д|да)$') {
      Start-Process -FilePath $ExecutablePath -WorkingDirectory (Split-Path -Parent $ExecutablePath) -ErrorAction Stop | Out-Null
      Write-Log ("LAUNCH {0}" -f $ExecutablePath)
    }
  } catch [System.OperationCanceledException] {
    Write-Log ("LAUNCH_CANCELLED {0}" -f $ExecutablePath)
    Write-Host (T 'Запуск отменён. Установка уже завершена; игру можно запустить вручную.' 'Launch cancelled. Installation is complete; you can start the game manually.') -ForegroundColor Yellow
  } catch {
    Write-Log ("LAUNCH_FAILED {0}; error={1}" -f $ExecutablePath,$_.Exception.Message)
    Write-Host (T ("Не удалось запустить EXE для проверки: {0}. Установка уже завершена." -f $_.Exception.Message) ("The verification launch failed: {0}. Installation is complete." -f $_.Exception.Message)) -ForegroundColor Yellow
  }
}
function Convert-ReShadeLoaderForOptiBridge([string]$InstallRoot,[object[]]$Records) {
  $record = @($Records | Where-Object { [string]$_.path -match '^(dxgi|d3d12)\.dll$' } | Select-Object -First 1)
  if ($record.Count -eq 0) { throw (T 'После установки ReShade не найден loader DLL для OptiBridge.' 'ReShade loader DLL was not found after OptiBridge setup.') }
  $source = Join-Path $InstallRoot ([string]$record[0].path)
  $target = Join-Path $InstallRoot 'ReShade64.dll'
  if (Test-Path -LiteralPath $target -PathType Leaf) { throw (T 'ReShade64.dll уже существует. Сначала удалите или восстановите старую установку.' 'ReShade64.dll already exists. Restore or remove the previous installation first.') }
  Move-Item -LiteralPath $source -Destination $target -Force
  $record[0].path = 'ReShade64.dll'
  $record[0].installedSha256 = Get-Sha256 $target
  return @($Records)
}
function Select-ReShadeApi($Info) {
  $hint = [string]$Info.apiHint
  if ($hint -match 'DX11/DX12') {
    Write-Host (T 'Обнаружены признаки DX11 и DX12. Выберите API, который игра использует для запуска.' 'Both DX11 and DX12 indicators were found. Select the API the game uses at launch.') -ForegroundColor Yellow
  } elseif ($hint -match 'DX12') {
    return 'dxgi'
  } elseif ($hint -match 'DX11') {
    return 'd3d11'
  } else {
    Write-Host (T 'API игры не удалось определить автоматически. Выберите API для ReShade.' 'The game API could not be detected automatically. Select the ReShade API.') -ForegroundColor Yellow
  }
  Write-Host (T '1. DXGI (рекомендуется для DirectX 10/11/12)' '1. DXGI (recommended for DirectX 10/11/12)')
  Write-Host (T '2. Direct3D 12 (прямой hook)' '2. Direct3D 12 (direct hook)')
  $choice = Read-Input 'API (1-2)' 'API (1-2)'
  if ($choice -eq '1') { return 'dxgi' }
  if ($choice -eq '2') { return 'd3d12' }
  throw (T 'Некорректный выбор API.' 'Invalid API selection.')
}
function Expand-Package([string]$Archive,[string]$Destination) {
  $extension = [IO.Path]::GetExtension($Archive).ToLowerInvariant()
  if ($extension -eq '.zip') { Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force; return }
  if ($extension -in @('.7z','.rar')) {
    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if ($null -eq $tar) { throw (T 'Для 7z/rar нужен tar.exe или распакуйте архив вручную.' '7z/rar requires tar.exe or manual extraction.') }
    & $tar.Source -xf $Archive -C $Destination
    if ($LASTEXITCODE -ne 0) { throw ("Archive extraction failed: {0}" -f $Archive) }
    return
  }
  throw (T 'Поддерживаются только ZIP, 7z и RAR.' 'Only ZIP, 7z and RAR are supported.')
}
function Get-InstalledPackageManifest {
  @(Get-ChildItem -LiteralPath $Dirs.Manifests -Filter 'install-*.json' -File -ErrorAction SilentlyContinue | Sort-Object @{ Expression = {
    try {
      $record = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
      if ($record.timestamp) { return [datetime]$record.timestamp }
    } catch { }
    return $_.LastWriteTimeUtc
  }; Descending = $true })
}
function Archive-RestoredManifest([System.IO.FileInfo]$ManifestFile) {
  $archiveDir = Join-Path $Dirs.Manifests 'restored'
  New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null
  $archivePath = Join-Path $archiveDir $ManifestFile.Name
  if (Test-Path -LiteralPath $archivePath -PathType Leaf) {
    $archivePath = Join-Path $archiveDir ('{0}-{1}.json' -f [IO.Path]::GetFileNameWithoutExtension($ManifestFile.Name),(Get-Date -Format 'yyyyMMdd-HHmmss'))
  }
  Move-Item -LiteralPath $ManifestFile.FullName -Destination $archivePath -Force
  return $archivePath
}
function Get-ManifestTimestamp($ManifestFile,$Record) {
  if ($Record.timestamp) {
    try { return [datetime]$Record.timestamp } catch { }
  }
  return $ManifestFile.LastWriteTimeUtc
}
function Get-RelatedInstallManifests($SelectedRecord) {
  $gamePath = [string]$SelectedRecord.gamePath
  $installRoot = if ($SelectedRecord.installRoot) { [string]$SelectedRecord.installRoot } else { $gamePath }
  $related = @()
  foreach ($manifestFile in @(Get-InstalledPackageManifest)) {
    try {
      $record = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json
      $recordRoot = if ($record.installRoot) { [string]$record.installRoot } else { [string]$record.gamePath }
      if ([string]$record.gamePath -eq $gamePath -and $recordRoot -eq $installRoot) {
        $related += [pscustomobject]@{ File=$manifestFile; Record=$record; Timestamp=(Get-ManifestTimestamp $manifestFile $record) }
      }
    } catch { }
  }
  return @($related | Sort-Object Timestamp)
}
function Get-RestoreCandidates {
  $latestByGame = @{}
  foreach ($manifestFile in @(Get-InstalledPackageManifest)) {
    try {
      $record = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json
      $root = if ($record.installRoot) { [string]$record.installRoot } else { [string]$record.gamePath }
      $key = (([string]$record.gamePath) + '|' + $root).ToLowerInvariant()
      if (-not $latestByGame.ContainsKey($key)) { $latestByGame[$key] = $manifestFile }
    } catch { }
  }
  return @($latestByGame.Values | Sort-Object LastWriteTime -Descending)
}
function Get-StackRestoreRecords($RelatedManifests,[bool]$Pristine) {
  $recordsByPath = @{}
  $ordered = if ($Pristine) { @($RelatedManifests | Sort-Object Timestamp) } else { @($RelatedManifests | Sort-Object Timestamp -Descending | Select-Object -First 1) }
  foreach ($item in $ordered) {
    foreach ($entry in @($item.Record.files)) {
      $key = [string]$entry.path
      if (-not $recordsByPath.ContainsKey($key)) { $recordsByPath[$key] = $entry }
    }
  }
  return @($recordsByPath.Values)
}
function Get-LatestStackRecords($RelatedManifests) {
  $recordsByPath = @{}
  foreach ($item in @($RelatedManifests | Sort-Object Timestamp -Descending)) {
    foreach ($entry in @($item.Record.files)) {
      $key = [string]$entry.path
      if (-not $recordsByPath.ContainsKey($key)) { $recordsByPath[$key] = $entry }
    }
  }
  return @($recordsByPath.Values)
}
function Get-PreviousInstallRecord([string]$GamePath,[string]$InstallRoot,[string]$RelativePath) {
  foreach ($manifestFile in @(Get-InstalledPackageManifest)) {
    try { $install = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json } catch { continue }
    $recordRoot = if ($install.installRoot) { [string]$install.installRoot } else { [string]$install.gamePath }
    if ([string]$install.gamePath -ne $GamePath -or $recordRoot -ne $InstallRoot) { continue }
    foreach ($record in @($install.files)) {
      if ([string]$record.path -eq $RelativePath -and $record.installedSha256) {
        if (-not $record.existed -or (Test-Path -LiteralPath $record.backup -PathType Leaf)) { return $record }
      }
    }
  }
  return $null
}
function Restore-Records($Records) {
  foreach ($entry in @($Records | Sort-Object path -Descending)) {
    $destination = Join-Path ([string]$entry.installRoot) ([string]$entry.path)
    try {
      if ($entry.existed -and $entry.backup -and (Test-Path -LiteralPath $entry.backup -PathType Leaf)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
        Copy-Item -LiteralPath $entry.backup -Destination $destination -Force
      } elseif (-not $entry.existed -and (Test-Path -LiteralPath $destination -PathType Leaf)) {
        Remove-Item -LiteralPath $destination -Force
      }
    } catch { Write-Warning ("Rollback failed for {0}: {1}" -f $destination,$_.Exception.Message) }
  }
}
function Normalize-InstallRecord($Record) {
  [ordered]@{
    installRoot = [string]$Record.installRoot
    path = [string]$Record.path
    existed = [bool]$Record.existed
    originalSha256 = if ($Record.originalSha256) { [string]$Record.originalSha256 } else { $null }
    backup = if ($Record.backup) { [string]$Record.backup } else { $null }
    installedSha256 = if ($Record.installedSha256) { [string]$Record.installedSha256 } else { $null }
  }
}
function Get-FileSnapshot([string]$Root) {
  $snapshot = @{}
  if (Test-Path -LiteralPath $Root -PathType Container) {
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -File -Recurse -ErrorAction SilentlyContinue)) {
      $relative = Get-RelativePath $Root $file.FullName
      $snapshot[$relative] = [ordered]@{ path=$relative; fullPath=$file.FullName; sha256=Get-Sha256 $file.FullName }
    }
  }
  return $snapshot
}
function Get-ReShadeState([string]$InstallRoot) {
  $hooks = @(Get-ChildItem -LiteralPath $InstallRoot -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(dxgi|d3d9|d3d10|d3d11|d3d12|opengl32|dinput8|ReShade64)\.dll$' })
  foreach ($hook in $hooks) {
    try {
      $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($hook.FullName))
      if ($text -match 'ReShade') {
        return [ordered]@{ installed=$true; path=$hook.FullName; addonSupport=($text -match 'Searching for add-ons') }
      }
    } catch { }
  }
  return [ordered]@{ installed=$false; path=$null; addonSupport=$false }
}
function Repair-ReShadeSearchPaths([string]$InstallRoot,[bool]$Feeder = $false,[string]$Provider = 'Kernel') {
  $ini = Join-Path $InstallRoot 'ReShade.ini'
  if (-not (Test-Path -LiteralPath $ini -PathType Leaf)) { return $false }
  $text = [IO.File]::ReadAllText($ini)
  $updated = $text
  $updated = $updated -replace '(?m)^EffectSearchPaths=.*$', 'EffectSearchPaths=.\reshade-shaders\Shaders\'
  $updated = $updated -replace '(?m)^TextureSearchPaths=.*$', 'TextureSearchPaths=.\reshade-shaders\Textures\'
  if ($Feeder) {
    $providerConfig = Get-LumeniteProviderConfig $Provider
    $providerDefinition = "DLSS5_MV_PROVIDER=$($providerConfig.code)"
    if ($updated -match '(?m)^PreprocessorDefinitions=.*DLSS5_MV_PROVIDER=\d+') { $updated = $updated -replace '(?m)^PreprocessorDefinitions=(.*)DLSS5_MV_PROVIDER=\d+(.*)$', "PreprocessorDefinitions=`$1$providerDefinition`$2" }
    elseif ($updated -match '(?m)^PreprocessorDefinitions=(.*)$') { $updated = $updated -replace '(?m)^PreprocessorDefinitions=(.*)$', "PreprocessorDefinitions=`$1,$providerDefinition" }
    else { $updated += "`r`nPreprocessorDefinitions=$providerDefinition`r`n" }
  }
  if ($Feeder) {
    $presetPath = (Join-Path $InstallRoot 'ReShadePreset.ini').Replace('\','/')
    if ($updated -match '(?m)^PresetPath=.*$') { $updated = $updated -replace '(?m)^PresetPath=.*$', "PresetPath=$presetPath" }
    else { $updated += "`r`nPresetPath=$presetPath`r`n" }
    if ($updated -match '(?m)^StartupPresetPath=.*$') { $updated = $updated -replace '(?m)^StartupPresetPath=.*$', "StartupPresetPath=$presetPath" }
    else { $updated += "`r`nStartupPresetPath=$presetPath`r`n" }
    if ($updated -match '(?m)^AutoSavePreset=.*$') { $updated = $updated -replace '(?m)^AutoSavePreset=.*$', 'AutoSavePreset=0' }
    else { $updated += "`r`nAutoSavePreset=0`r`n" }
  }
  if ($updated -eq $text) { return $false }
  [IO.File]::WriteAllText($ini, $updated, (New-Object System.Text.UTF8Encoding($false)))
  Write-Log ("RESHADE_PATHS_REPAIRED {0}" -f $ini)
  return $true
}
function Test-FeederMotionProvider([string]$InstallRoot) {
  $shaderRoot = Join-Path $InstallRoot 'reshade-shaders\Shaders'
  $names = @('lumenite_Kernel.fx','lumenite_QuantMotion.fx','vort_Motion.fx','MartysMods_LAUNCHPAD.fx','dh_uber_motion.fx','ReshadeMotionEstimation.fx')
  $found = @($names | Where-Object { Test-Path -LiteralPath (Join-Path $shaderRoot $_) -PathType Leaf })
  if ($found.Count -eq 0) {
    Write-Host (T 'Предупреждение: motion-vector provider не найден. DLSS5_Feed может загрузиться, но не сможет получить корректные векторы движения. Установите совместимый provider и включите его выше DLSS5_Feed.' 'Warning: no motion-vector provider was found. DLSS5_Feed may load but cannot receive valid motion vectors. Install a compatible provider and enable it above DLSS5_Feed.') -ForegroundColor Yellow
    return $false
  }
  Write-Log ("FEEDER_MOTION_PROVIDER {0}" -f ($found -join ','))
  return $true
}
function Remove-DetectedReShade([string]$InstallRoot,$State) {
  $knownAddons = @('dlss5-feed.addon64','dlss5-bridge.addon64','dlss5-dx11-bridge.addon64','renodx-dlss5.addon64','nvngx_dlssnr.dll')
  $targets = @($State.path,(Join-Path $InstallRoot 'ReShade.ini'),(Join-Path $InstallRoot 'ReShade.log'),(Join-Path $InstallRoot 'ReShadePreset.ini'))
  foreach ($name in $knownAddons) { $targets += Join-Path $InstallRoot $name }
  $targets = @($targets | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) })
  if ($targets.Count -eq 0) { Write-Host (T 'Известные компоненты для удаления не найдены.' 'No known components to remove were found.') -ForegroundColor Yellow; return }
  $stamp = 'untracked-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
  $backupRoot = Join-Path $Dirs.Backups $stamp
  $records = @()
  foreach ($target in $targets) {
    $relative = Get-RelativePath $InstallRoot $target
    $backup = Join-Path $backupRoot $relative
    New-Item -ItemType Directory -Force -Path (Split-Path $backup) | Out-Null
    Copy-Item -LiteralPath $target -Destination $backup -Force
    $records += [ordered]@{ installRoot=$InstallRoot; path=$relative; existed=$true; originalSha256=Get-Sha256 $target; backup=$backup; installedSha256=Get-Sha256 $target }
  }
  try {
    foreach ($target in $targets) { Remove-Item -LiteralPath $target -Force; Write-Log ("RESHADE_REMOVED {0}" -f $target) }
  } catch {
    Restore-Records $records
    throw
  }
  $manifest = [ordered]@{ timestamp=(Get-Date).ToUniversalTime().ToString('o'); gamePath=$InstallRoot; installRoot=$InstallRoot; packageId='untracked-cleanup'; packageVersion='manual-snapshot'; method='UntrackedCleanup'; files=$records }
  $manifestPath = Save-JsonManifest 'install' $manifest
  Write-Log ("UNTRACKED_CLEANUP {0}; manifest={1}" -f $InstallRoot,$manifestPath)
  Write-Host (T 'Компоненты удалены. Точечная копия сохранена; Restore вернёт ручную установку, но не оригинальные файлы игры.' 'Components removed. A point snapshot was saved; Restore will bring back the manual installation, not the original game files.') -ForegroundColor Yellow
}
function Prepare-OptiBridgeTarget([string]$InstallRoot) {
  $state = Get-ReShadeState $InstallRoot
  if (-not $state.installed) { return $true }
  Write-Host (T 'Для OptiScaler Bridge обнаружен существующий ReShade hook. Начните с чистой игры или используйте Restore.' 'An existing ReShade hook was detected for OptiScaler Bridge. Start from a clean game or use Restore.') -ForegroundColor Yellow
  Write-Host (T '1. Удалить обнаруженный ReShade hook и конфигурацию, сохранить точечную копию и продолжить OptiScaler' '1. Remove the detected ReShade hook and configuration, save a point snapshot, and continue with OptiScaler')
  Write-Host (T '2. Отменить установку и вернуться в главное меню' '2. Cancel the installation and return to the main menu')
  $choice = Read-Input 'Выберите действие' 'Choose an action'
  if ($choice -ne '1') { return $false }
  $tracked = @(Get-InstalledPackageManifest | Where-Object {
    try {
      $entry = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
      $root = if ($entry.installRoot) { [string]$entry.installRoot } else { [string]$entry.gamePath }
      $root.Equals($InstallRoot,[StringComparison]::OrdinalIgnoreCase) -and @($entry.files | Where-Object { [string]$_.path -match '(?i)^(d3d12|dxgi)\.dll$|^ReShade(?:\.ini|\.log|Preset\.ini)$' }).Count -gt 0
    } catch { $false }
  })
  if ($tracked.Count -gt 0) {
    Write-Host (T 'Найдена отслеживаемая ReShade-установка. Сначала используйте Restore; удаление не выполняется.' 'A tracked ReShade installation was found. Use Restore first; no removal was performed.') -ForegroundColor Yellow
    return $false
  }
  Write-Host (T 'Установка считается ручной или неотслеживаемой. Pristine backup отсутствует; заменённые игровые DLL этой операцией восстановить нельзя.' 'The installation is treated as manual or untracked. No pristine backup exists; this operation cannot restore replaced game DLLs.') -ForegroundColor Red
  if ((Read-Input 'Удалить ReShade hook и конфигурацию? (y/n)' 'Remove the ReShade hook and configuration? (y/n)') -notmatch '^(y|yes|д|да)$') { return $false }
  Remove-DetectedReShade $InstallRoot $state
  return $true
}
function Invoke-TrackedReShade([string]$Installer,[string]$Api,[string]$Executable,[string]$InstallRoot,[string]$BackupRoot,[bool]$Feeder = $false,[string]$Provider = 'Kernel') {
  $state = Get-ReShadeState $InstallRoot
  $forceReinstall = $false
  if ($state.installed) {
    Write-Host (T 'В папке уже обнаружен ReShade или его proxy DLL.' 'An existing ReShade installation or proxy DLL was detected.') -ForegroundColor Yellow
    Write-Host (T '1. Переустановить поверх текущей установки' '1. Reinstall over the current installation')
    Write-Host (T '2. Удалить hook, конфигурацию и известные DLSS5-файлы, затем вернуться в главное меню' '2. Remove the hook, configuration, and known DLSS5 files, then return to the main menu')
    Write-Host (T '3. Отменить' '3. Cancel')
    $choice = Read-Input 'Выберите действие' 'Choose an action'
    if ($choice -eq '2') {
      $ownership = Read-Input 'Эту установку делала текущая утилита? (y/n)' 'Was this installation made by this utility? (y/n)'
      if ($ownership -match '^(y|yes|д|да)$') {
        $tracked = @(Get-InstalledPackageManifest | Where-Object {
          try {
            $entry = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
            $gamePath = if ($entry.gamePath) { [string]$entry.gamePath } else { '' }
            $root = [string]$InstallRoot
            $gamePath -and ($root.Equals($gamePath,[StringComparison]::OrdinalIgnoreCase) -or $root.StartsWith($gamePath.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase))
          } catch { $false }
        })
        if ($tracked.Count -gt 0) {
          Write-Host (T 'Найдена отслеживаемая установка. Используйте пункт Restore для штатного отката; удаление не выполняется.' 'A tracked installation was found. Use Restore for the normal rollback; no files will be removed here.') -ForegroundColor Yellow
          throw [System.OperationCanceledException]::new('Tracked installation found; returning to the main menu.')
        }
        Write-Host (T 'Manifest установки не найден. Backup-папки могут быть неполными, поэтому восстановить все оригинальные игровые DLL нельзя гарантировать.' 'The installation manifest was not found. Backup folders may be incomplete, so restoring every original game DLL cannot be guaranteed.') -ForegroundColor Red
      } else {
        Write-Host (T 'Установка считается ручной. Pristine backup отсутствует; заменённые игровые DLL этой операцией восстановить нельзя.' 'The installation is treated as manual. No pristine backup exists; this operation cannot restore replaced game DLLs.') -ForegroundColor Red
      }
      Write-Host (T 'Удаление может сломать ReShade, preset или игру.' 'Removal may break ReShade, the preset, or the game.') -ForegroundColor Red
      if ((Read-Input 'Удалить обнаруженные компоненты? (y/n)' 'Remove the detected components? (y/n)') -match '^(y|yes|д|да)$') {
        Remove-DetectedReShade $InstallRoot $state
        throw [System.OperationCanceledException]::new('Untracked components were removed by user; returning to the main menu.')
      }
      throw [System.OperationCanceledException]::new('Existing ReShade removal cancelled; returning to the main menu.')
    }
    if ($choice -eq '3') { throw [System.OperationCanceledException]::new('Existing ReShade operation cancelled.') }
    if ($choice -ne '1') { throw (T 'Некорректный пункт.' 'Invalid choice.') }
    $forceReinstall = $true
  }
  if ($state.installed -and $state.addonSupport -and -not $forceReinstall) {
    Write-Log ("RESHADE_REUSED {0}; addonSupport=true" -f $state.path)
    return @()
  }
  $before = Get-FileSnapshot $InstallRoot
  $argumentText = '--headless --api "{0}" "{1}"' -f $Api,$Executable
  if ($state.installed) { $argumentText += ' --state update' }
  $diagBase = Join-Path $Dirs.Logs ('reshade-setup-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
  $stdoutPath = $diagBase + '.stdout.log'
  $stderrPath = $diagBase + '.stderr.log'
  $process = Start-Process -FilePath $Installer -ArgumentList $argumentText -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
  Repair-ReShadeSearchPaths $InstallRoot $Feeder $Provider | Out-Null
  $after = Get-FileSnapshot $InstallRoot
  $records = @()
  foreach ($relative in $after.Keys) {
    $current = $after[$relative]
    $previous = if ($before.ContainsKey($relative)) { $before[$relative] } else { $null }
    if ($null -eq $previous -or $previous.sha256 -ne $current.sha256) {
      if ($previous) {
        $backup = Join-Path $BackupRoot $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $backup) | Out-Null
        Copy-Item -LiteralPath $previous.fullPath -Destination $backup -Force
        $records += [ordered]@{ installRoot=$InstallRoot; path=$relative; existed=$true; originalSha256=$previous.sha256; backup=$backup; installedSha256=$current.sha256 }
      } else {
        $records += [ordered]@{ installRoot=$InstallRoot; path=$relative; existed=$false; originalSha256=$null; backup=$null; installedSha256=$current.sha256 }
      }
    }
  }
  if ($process.ExitCode -ne 0) {
    Restore-Records $records
    $diagnostic = @()
    foreach ($diag in @($stdoutPath,$stderrPath)) {
      if (Test-Path -LiteralPath $diag -PathType Leaf) {
        $diagnostic += @(Get-Content -LiteralPath $diag -ErrorAction SilentlyContinue | Select-Object -Last 8)
      }
    }
    $detail = if ($diagnostic.Count -gt 0) { ' Diagnostic: ' + ($diagnostic -join ' | ') } else { '' }
    throw ("ReShade setup failed with exit code {0} (API: {1}, executable: {2}). Existing ReShade: {3}; add-on support: {4}.{5} Logs: {6}" -f $process.ExitCode,$Api,$Executable,$state.installed,$state.addonSupport,$detail,$diagBase)
  }
  return @($records)
}
function Ensure-Admin([string]$InstallGamePath,[string]$ManifestPath,[string]$SelectedExecutable) {
  $probe = Join-Path $InstallGamePath ('.dlss5-write-test-' + [guid]::NewGuid().ToString('N'))
  try { New-Item -ItemType File -Path $probe -Force | Out-Null; Remove-Item -LiteralPath $probe -Force; return $true } catch { }
  $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return $true }
  if ($Settings.warnBeforeElevation) {
    $answer = Read-Input 'Установка может потребовать права администратора. Перезапустить с повышенными правами? (y/n)' 'Installation may require administrator rights. Relaunch elevated? (y/n)'
    if ($answer -notmatch '^(y|yes|д|да)$') { return $false }
  }
  $args = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Action Install -GamePath `"$InstallGamePath`" -PackageManifest `"$ManifestPath`" -ExecutablePath `"$SelectedExecutable`""
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -WorkingDirectory $Root -ArgumentList $args | Out-Null
  return $false
}
function Ensure-AdminBootstrap([string]$InstallGamePath,[string]$SelectedMethod,[string]$Api,[string]$Provider = 'Kernel') {
  $probe = Join-Path $InstallGamePath ('.dlss5-bootstrap-write-test-' + [guid]::NewGuid().ToString('N'))
  try { New-Item -ItemType File -Path $probe -Force | Out-Null; Remove-Item -LiteralPath $probe -Force; return $true } catch { }
  $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return $true }
  if ($Settings.warnBeforeElevation) {
    $answer = Read-Input 'Автоматическая установка может потребовать права администратора. Перезапустить мастер с повышенными правами? (y/n)' 'Automatic installation may require administrator rights. Relaunch the wizard elevated? (y/n)'
    if ($answer -notmatch '^(y|yes|д|да)$') { return $false }
  }
  $args = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Action Bootstrap -GamePath `"$InstallGamePath`" -Method $SelectedMethod -LumeniteProvider $Provider"
  if ($Api) { $args += " -Api `"$Api`"" }
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -WorkingDirectory $Root -ArgumentList $args | Out-Null
  return $false
}
function Invoke-InstallCore([string]$Path,[string]$ManifestPath,[string]$ExecutablePath,[object[]]$PreRecords,[string]$PreBackupRoot,[string]$PreStamp,[bool]$AlreadyConfirmed = $false,[string]$Provider = 'Kernel',[string]$Api = $null,[string]$InstallApi = $null) {
  if (-not $ManifestPath) { $ManifestPath = Read-Input 'Укажите путь к manifest пакета (например packages\opti.manifest.json)' 'Enter package manifest path (for example packages\opti.manifest.json)' }
  $game = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
  $info = Get-GameInspection $game
  Show-MethodComparison $info
  if (-not $ExecutablePath) { $ExecutablePath = Select-Executable $info }
  $manifest = Get-PackageManifest (Resolve-Path -LiteralPath $ManifestPath).Path
  $script:InstallApi = if ($InstallApi) { $InstallApi } else { $Api }
  $installRoot = $game
  if ($manifest.installRelativeTo -eq 'primaryExecutableDirectory') { $installRoot = Split-Path -Parent $ExecutablePath }
  Show-ConflictReport $info
  Show-InstallPlan $manifest $installRoot
  Write-Host (T ("Выбран пакет {0} {1}, метод {2}. Источник: {3}" -f $manifest.id,$manifest.version,$manifest.method,$manifest.source) ("Selected package {0} {1}, method {2}. Source: {3}" -f $manifest.id,$manifest.version,$manifest.method,$manifest.source)) -ForegroundColor Yellow
  if (-not $AlreadyConfirmed -and (Read-Input 'Продолжить установку? (y/n)' 'Continue installation? (y/n)') -notmatch '^(y|yes|д|да)$') { return }
  if (-not (Ensure-Admin $installRoot $ManifestPath $ExecutablePath)) { return }
  $stamp = if ($PreStamp) { $PreStamp } else { Get-Date -Format 'yyyyMMdd-HHmmss' }
  $stage = Join-Path $Dirs.Staging $stamp
  New-Item -ItemType Directory -Force -Path $stage | Out-Null
  $sourceRoot = $stage
  if ($manifest.sourcePackage -or $manifest.sourcePackages) { $sourceRoot = Prepare-SourcePackage $manifest $Provider $game }
  else { Expand-Package $manifest._archivePath $stage }
  $backupRoot = if ($PreBackupRoot) { $PreBackupRoot } else { Join-Path $Dirs.Backups $stamp }
  $records = New-Object 'System.Collections.Generic.List[object]'
  foreach ($pre in @($PreRecords)) { if ($null -ne $pre) { $records.Add($pre) } }
  $recordByPath = @{}
  foreach ($pre in $records) { if ($pre.path) { $recordByPath[[string]$pre.path] = $pre } }
  try {
   foreach ($entry in @($manifest.files)) {
    if (-not (Test-InstallEntryForApi $entry $Api)) { continue }
    $relative = ([string]$entry.path).Replace('/','\')
    $sourceRelative = if ($entry.sourcePath) { ([string]$entry.sourcePath).Replace('/','\') } else { $relative }
    $source = Join-Path $sourceRoot $sourceRelative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw ("Archive is missing manifest file: {0}" -f $relative) }
    $expectedSha = [string]$entry.sha256
    if ($manifest.method -eq 'Feeder' -and $relative -eq 'ReShadePreset.ini' -and $manifest.providerPresetSha256) { $expectedSha = [string]$manifest.providerPresetSha256.$Provider }
    if ($entry.sourceFromGame -and (Test-Path -LiteralPath ($source + '.source') -PathType Leaf)) {
      $expectedSha = Get-Sha256 $source
    }
    if ([string]::IsNullOrWhiteSpace($expectedSha) -or (Get-Sha256 $source) -ne $expectedSha.ToLowerInvariant()) { throw ("Staged file SHA-256 mismatch: {0}" -f $relative) }
    $destination = Join-Path $installRoot $relative
    if ($recordByPath.ContainsKey($relative)) {
      $record = $recordByPath[$relative]
    } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
      $previous = Get-PreviousInstallRecord $game $installRoot $relative
      if ($previous) {
        $record = [ordered]@{ installRoot=$installRoot; path=$relative; existed=[bool]$previous.existed; originalSha256=$previous.originalSha256; backup=$previous.backup; installedSha256=$null }
      } else {
        $backup = Join-Path $backupRoot $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $backup) | Out-Null
        $record = [ordered]@{ installRoot=$installRoot; path=$relative; existed=$true; originalSha256=Get-Sha256 $destination; backup=$backup; installedSha256=$null }
        Copy-Item -LiteralPath $destination -Destination $backup -Force
      }
    } else { $record = [ordered]@{ installRoot=$installRoot; path=$relative; existed=$false; originalSha256=$null; backup=$null; installedSha256=$null } }
    if (-not $recordByPath.ContainsKey($relative)) {
      $records.Add($record)
      $recordByPath[$relative] = $record
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
    $record.installedSha256 = Get-Sha256 $destination
   }
  } catch {
    Restore-Records $records
    throw
  }
  $records = @($records | ForEach-Object { Normalize-InstallRecord $_ })
  $script:LastInstallRecords = @($records)
  $install = [ordered]@{ timestamp=(Get-Date).ToUniversalTime().ToString('o'); gamePath=$game; installRoot=$installRoot; packageId=$manifest.id; packageVersion=$manifest.version; method=$manifest.method; provider=if($manifest.method -eq 'Feeder'){$Provider}else{$null}; files=$records }
  $installPath = Save-JsonManifest 'install' $install
  $script:LastInstallManifestPath = $installPath
  Write-Log ("INSTALL {0}; manifest={1}" -f $game,$installPath)
  if ($manifest.method -eq 'Feeder') { Test-FeederMotionProvider $installRoot | Out-Null }
  Write-Host (T 'Установка завершена. Для отката выберите нужную запись в пункте «Восстановление».' 'Installation completed. Select the required entry in Restore to roll back.') -ForegroundColor Green
  Save-GameProfile $info $ExecutablePath $manifest $info.apiHint
  Offer-Launch $ExecutablePath
}
function Run-Install([string]$Path,[string]$ManifestPath,[string]$ExecutablePath,[object[]]$PreRecords,[string]$PreBackupRoot,[string]$PreStamp,[bool]$AlreadyConfirmed = $false,[string]$Provider = 'Kernel',[string]$Api = $null,[string]$InstallApi = $null) {
  $script:LastInstallRecords = @()
  $script:LastInstallManifestPath = $null
  $effectiveStamp = if ($PreStamp) { $PreStamp } else { Get-Date -Format 'yyyyMMdd-HHmmss' }
  try {
    Invoke-InstallCore $Path $ManifestPath $ExecutablePath $PreRecords $PreBackupRoot $effectiveStamp $AlreadyConfirmed $Provider $Api $InstallApi
  } catch [System.OperationCanceledException] {
    $rollback = @($script:LastInstallRecords) + @($PreRecords)
    if ($rollback.Count -gt 0) { Restore-Records $rollback }
    if ($script:LastInstallManifestPath -and (Test-Path -LiteralPath $script:LastInstallManifestPath -PathType Leaf)) {
      Remove-Item -LiteralPath $script:LastInstallManifestPath -Force -ErrorAction SilentlyContinue
    }
    Write-Host (T 'Установка отменена. Изменения этой попытки откатированы.' 'Installation cancelled. Changes from this attempt were rolled back.') -ForegroundColor Yellow
  } catch {
    $rollback = @($script:LastInstallRecords) + @($PreRecords)
    if ($rollback.Count -gt 0) { Restore-Records $rollback }
    if ($script:LastInstallManifestPath -and (Test-Path -LiteralPath $script:LastInstallManifestPath -PathType Leaf)) {
      Remove-Item -LiteralPath $script:LastInstallManifestPath -Force -ErrorAction SilentlyContinue
    }
    $stage = Join-Path $Dirs.Staging $effectiveStamp
    if (Test-Path -LiteralPath $stage -PathType Container) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    try { Write-Log ("INSTALL_ROLLBACK {0}; error={1}" -f $Path,$_.Exception.Message) } catch { }
    Write-Host (T ("Установка не завершена и изменения этой попытки откатированы: {0}" -f $_.Exception.Message) ("Installation failed and changes from this attempt were rolled back: {0}" -f $_.Exception.Message)) -ForegroundColor Red
  }
}
function Run-Bootstrap([string]$Path,[string]$SelectedMethod,[string]$Api,[string]$Provider = 'Kernel') {
  if (-not $Path) { $Path = Read-GamePath }
  $info = Get-GameInspection $Path
  if (-not $SelectedMethod) {
    Show-MethodComparison $info
    $SelectedMethod = @('NativeBridge','OptiBridge','Feeder')[[int](Read-Input 'Метод (1-3)' 'Method (1-3)') - 1]
  }
  if (-not (Confirm-MethodCompatibility $info $SelectedMethod)) { return }
  if ($SelectedMethod -eq 'Feeder') {
    Write-Host (T 'Активный motion-vector provider (оба файла LumeniteFX будут установлены):' 'Active motion-vector provider (both LumeniteFX files will be installed):') -ForegroundColor Cyan
    Write-Host (T '1. Kernel — рекомендуемый базовый вариант' '1. Kernel — recommended baseline')
    Write-Host (T '2. QuantMotion — альтернативный estimator для сравнения' '2. QuantMotion — alternative estimator for comparison')
    $providerChoice = Read-Input 'Активный режим LumeniteFX (1-2)' 'Active LumeniteFX mode (1-2)'
    if ($providerChoice -eq '2') { $Provider = 'QuantMotion' } elseif ($providerChoice -eq '1') { $Provider = 'Kernel' } else { throw (T 'Некорректный вариант LumeniteFX.' 'Invalid LumeniteFX variant.') }
  }
  $map = @{ NativeBridge='packages\dlss5-bridge.manifest.json'; OptiBridge='packages\opti-dlss5.manifest.json'; Feeder='packages\dlss5-feeder.manifest.json' }
  $manifestPath = Join-Path $Root $map[$SelectedMethod]
  if (-not (Test-Path -LiteralPath $manifestPath)) { throw (T 'Подготовленный манифест метода не найден.' 'Prepared method manifest was not found.') }
  $exe = Select-Executable $info
  if ((Read-Input ("Установить метод {0} в выбранный EXE? (y/n)" -f $SelectedMethod) ("Install method {0} into the selected EXE? (y/n)" -f $SelectedMethod)) -notmatch '^(y|yes|д|да)$') { return }
  if (-not (Ensure-AdminBootstrap $Path $SelectedMethod $Api $Provider)) { return }
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $backupRoot = Join-Path $Dirs.Backups $stamp
  $preRecords = @()
  $installApi = if ([string]$info.apiHint -match 'DX11/DX12') { $null } elseif ([string]$info.apiHint -match '^DX12') { 'dx12' } elseif ([string]$info.apiHint -match '^DX11') { 'd3d11' } elseif ([string]$info.apiHint -match 'Vulkan') { 'vulkan' } else { $null }
  $script:LastInstallRecords = @()
  $script:LastInstallManifestPath = $null
  try {
    if ($SelectedMethod -eq 'OptiBridge') {
      $archive = Ensure-LockedDownload 'optiscaler'
      Copy-Item -LiteralPath $archive -Destination (Join-Path $Dirs.Packages (Split-Path $archive -Leaf)) -Force
    } elseif ($SelectedMethod -eq 'NativeBridge') { Ensure-LockedDownload 'dlss5-bridge' | Out-Null }
    elseif ($SelectedMethod -eq 'Feeder') { Ensure-LockedDownload 'dlss5-aio-v1.2.5-part1' | Out-Null }
    if ($SelectedMethod -in @('NativeBridge','OptiBridge','Feeder')) {
      if ($SelectedMethod -eq 'OptiBridge' -and -not (Prepare-OptiBridgeTarget (Split-Path -Parent $exe))) { return }
      $reshade = Ensure-LockedDownload 'reshade-full-addons'
      if (-not $Api) { $Api = Select-ReShadeApi $info }
      Write-Host (T 'Автоматическая установка ReShade...' 'Installing ReShade automatically...')
      $preRecords = Invoke-TrackedReShade $reshade $Api $exe (Split-Path -Parent $exe) $backupRoot ($SelectedMethod -eq 'Feeder') $Provider
      if ($SelectedMethod -eq 'OptiBridge') { $preRecords = Convert-ReShadeLoaderForOptiBridge (Split-Path -Parent $exe) $preRecords }
    }
    Run-Install $Path $manifestPath $exe $preRecords $backupRoot $stamp $true $Provider $Api $installApi
  } catch [System.OperationCanceledException] {
    if (@($preRecords).Count -gt 0) { Restore-Records $preRecords }
    Write-Host (T 'Установка отменена. Возврат в главное меню.' 'Installation cancelled. Returning to the main menu.') -ForegroundColor Yellow
    return
  } catch {
    $rollback = @($script:LastInstallRecords) + @($preRecords)
    if ($rollback.Count -gt 0) { Restore-Records $rollback }
    if ($script:LastInstallManifestPath -and (Test-Path -LiteralPath $script:LastInstallManifestPath -PathType Leaf)) {
      Remove-Item -LiteralPath $script:LastInstallManifestPath -Force -ErrorAction SilentlyContinue
    }
    $stage = Join-Path $Dirs.Staging $stamp
    if (Test-Path -LiteralPath $stage -PathType Container) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    try { Write-Log ("INSTALL_ROLLBACK {0}; error={1}" -f $Path,$_.Exception.Message) } catch { }
    Write-Host (T ("Установка не завершена и изменения этой попытки откатированы: {0}" -f $_.Exception.Message) ("Installation failed and changes from this attempt were rolled back: {0}" -f $_.Exception.Message)) -ForegroundColor Red
    return
  }
}
function Run-Restore {
  $items = Get-RestoreCandidates
  if ($items.Count -eq 0) { Write-Host (T 'Установок для отката не найдено.' 'No installations to restore.') -ForegroundColor Yellow; return }
  Write-Host ''; Write-Host (T 'Последняя активная установка для каждой игры (сначала новые):' 'Latest active installation for each game (newest first):') -ForegroundColor Cyan
  Write-Host (T 'Старые слои сохраняются для полного отката. После успешного отката выбранная запись перемещается в manifests\restored.' 'Older layers are kept for a full restore. After a successful restore, the selected record moves to manifests\restored.') -ForegroundColor DarkGray
  $seenGames = @{}
  for ($i = 0; $i -lt $items.Count; $i++) {
    $entry = Get-Content -LiteralPath $items[$i].FullName -Raw | ConvertFrom-Json
    $when = $items[$i].LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    if ($entry.timestamp) {
      try { $when = ([datetime]$entry.timestamp).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') } catch { }
    }
    $kind = if ([string]$entry.gamePath -match '(?i)\\local-tests(?:\\|$)') { T '[локальный тест]' '[local test]' } else { '' }
    $gameKey = ([string]$entry.gamePath).ToLowerInvariant()
    $latest = if (-not $seenGames.ContainsKey($gameKey)) { $seenGames[$gameKey] = $true; T '[последняя для игры]' '[latest for game]' } else { '' }
    $layers = @(Get-RelatedInstallManifests $entry).Count
    $layerText = (T ('слоёв: {0}' -f $layers) ('layers: {0}' -f $layers))
    Write-Host ("{0}. [{1}] {2} | {3} {4} | {5} | {6} {7} {8}" -f ($i + 1),$when,$entry.gamePath,$entry.packageId,$entry.packageVersion,$layerText,$items[$i].Name,$latest,$kind)
  }
  $choice = Read-Input 'Выберите номер установки' 'Choose an installation number'
  $index = 0
  if (-not [int]::TryParse($choice,[ref]$index) -or $index -lt 1 -or $index -gt $items.Count) { throw (T 'Некорректный номер установки.' 'Invalid installation number.') }
  $selected = $items[$index - 1]
  $install = Get-Content -LiteralPath $selected.FullName -Raw | ConvertFrom-Json
  $game = [string]$install.gamePath
  $installRoot = if ($install.installRoot) { [string]$install.installRoot } else { $game }
  if (-not (Test-Path -LiteralPath $game -PathType Container)) { throw (T 'Папка игры из манифеста не найдена.' 'Game folder from manifest was not found.') }
  $related = Get-RelatedInstallManifests $install
  $fullRestore = $false
  if ($related.Count -gt 1) {
    Write-Host ''; Write-Host ((T 'Для этой игры найдено связанных установочных слоёв: {0}.' 'Related installation layers found for this game: {0}.') -f $related.Count) -ForegroundColor Yellow
    Write-Host (T '1. Откатить только выбранный слой' '1. Restore only the selected layer')
    Write-Host (T '2. Полностью вернуть состояние до первой отслеживаемой установки' '2. Fully restore the state from before the first tracked installation')
    $restoreMode = Read-Input 'Режим отката (1-2)' 'Restore mode (1-2)'
    if ($restoreMode -eq '2') { $fullRestore = $true } elseif ($restoreMode -ne '1') { throw (T 'Некорректный режим отката.' 'Invalid restore mode.') }
  }
  $restoreEntries = if ($fullRestore) { Get-StackRestoreRecords $related $true } else { @($install.files) }
  $latestEntries = if ($fullRestore) { Get-LatestStackRecords $related } else { @($install.files) }
  $conflicts = @()
  foreach ($entry in $latestEntries) {
    if (-not $entry.installedSha256) { continue }
    $destination = Join-Path $installRoot ([string]$entry.path)
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
      $current = Get-Sha256 $destination
      if ($current -ne ([string]$entry.installedSha256).ToLowerInvariant()) { $conflicts += [string]$entry.path }
    }
  }
  if ($conflicts.Count -gt 0) {
    Write-Host (T ("Изменённые после установки файлы: {0}" -f ($conflicts -join ', ')) ("Files changed after installation: {0}" -f ($conflicts -join ', '))) -ForegroundColor Yellow
    if ((Read-Input 'Продолжить откат и перезаписать их? (y/n)' 'Continue restore and overwrite them? (y/n)') -notmatch '^(y|yes|д|да)$') { return }
  }
  if (-not (Ensure-Admin $game $selected.FullName)) { return }
  foreach ($entry in $restoreEntries) {
    $destination = Join-Path $installRoot ([string]$entry.path)
    if ($entry.existed -and (Test-Path -LiteralPath $entry.backup -PathType Leaf)) { Copy-Item -LiteralPath $entry.backup -Destination $destination -Force }
    elseif (-not $entry.existed -and (Test-Path -LiteralPath $destination -PathType Leaf)) { Remove-Item -LiteralPath $destination -Force }
  }
  if ($fullRestore) {
    $archived = @($related | ForEach-Object { Archive-RestoredManifest $_.File })
    Write-Log ("RESTORE_FULL {0}; layers={1}" -f $game,$related.Count)
    $archived | ForEach-Object { Write-Log ("RESTORE_ARCHIVED {0}" -f $_) }
    Write-Host (T 'Полный откат завершён. Все связанные записи перемещены в архив восстановленных установок.' 'Full restore completed. All related records were moved to the restored-installations archive.') -ForegroundColor Green
  } else {
    Write-Log ("RESTORE {0}; source={1}" -f $game,$selected.FullName)
    $archived = Archive-RestoredManifest $selected
    Write-Log ("RESTORE_ARCHIVED {0}" -f $archived)
    Write-Host (T 'Откат выбранного слоя завершён. Запись перемещена в архив восстановленных установок.' 'Selected-layer restore completed. The record was moved to the restored-installations archive.') -ForegroundColor Green
  }
}
function Set-Language {
  $value = Read-Input 'Язык (ru/en)' 'Language (ru/en)'
  if ($value -notmatch '^(ru|en)$') { throw (T 'Допустимы только ru или en.' 'Only ru or en are accepted.') }
  $Settings.language = $value
  Save-LocalSettings
  $script:Settings = Get-Settings
}
function Set-InterfaceMode {
  Write-Host (T '1. Упрощённый интерфейс' '1. Simple interface')
  Write-Host (T '2. Продвинутый интерфейс' '2. Advanced interface')
  $value = Read-Input 'Выберите режим' 'Choose interface mode'
  if ($value -eq '1') { $Settings.interfaceMode = 'simple' }
  elseif ($value -eq '2') { $Settings.interfaceMode = 'advanced' }
  else { throw (T 'Допустимы только 1 или 2.' 'Only 1 or 2 are accepted.') }
  Save-LocalSettings
  $script:Settings = Get-Settings
  Write-Host (T 'Режим интерфейса сохранён.' 'Interface mode saved.') -ForegroundColor Green
}
function Save-LocalSettings {
  $local = [ordered]@{}
  foreach ($name in @('language','interfaceMode','allowAutomaticDownloads','warnBeforeElevation','deleteUnknownFiles')) {
    if ($Settings.PSObject.Properties.Name -contains $name) { $local[$name] = $Settings.$name }
  }
  $local | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $LocalSettingsPath -Encoding UTF8
}
function Set-BooleanSetting([string]$Property,[string]$ru,[string]$en) {
  $current = [bool]$Settings.$Property
  $state = if ($current) { T 'включено' 'enabled' } else { T 'выключено' 'disabled' }
  Write-Host ((T "Текущее состояние: {0}" "Current state: {0}") -f $state)
  $value = Read-Input "$ru (y/n)" "$en (y/n)"
  if ($value -match '^(y|yes|д|да)$') { $Settings.$Property = $true }
  elseif ($value -match '^(n|no|н|нет)$') { $Settings.$Property = $false }
  else { throw (T 'Введите y или n.' 'Enter y or n.') }
  Save-LocalSettings
  $script:Settings = Get-Settings
  Write-Host (T 'Настройка сохранена.' 'Setting saved.') -ForegroundColor Green
}
function Invoke-SettingsMenu {
  while ($true) {
    try {
      Write-Host ''; Write-Host (T 'Настройки' 'Settings') -ForegroundColor Cyan
      Write-Host (T '1. Язык' '1. Language')
      Write-Host (T '2. Режим интерфейса' '2. Interface mode')
      Write-Host (T '3. Автоматические загрузки' '3. Automatic downloads')
      Write-Host (T '4. Предупреждение перед правами администратора' '4. Elevation warning')
      Write-Host (T '5. Назад' '5. Back')
      switch (Read-Input 'Выберите настройку' 'Choose a setting') {
        '1' { Set-Language }
        '2' { Set-InterfaceMode }
        '3' { Set-BooleanSetting 'allowAutomaticDownloads' 'Автоматические загрузки' 'Automatic downloads' }
        '4' { Set-BooleanSetting 'warnBeforeElevation' 'Предупреждение перед правами администратора' 'Elevation warning' }
        '5' { return }
        default { Write-Host (T 'Неизвестный пункт.' 'Unknown menu item.') -ForegroundColor Yellow }
      }
    } catch [System.OperationCanceledException] {
      Write-Host (T 'Настройки закрыты. Возврат в главное меню.' 'Settings closed. Returning to the main menu.') -ForegroundColor Yellow
      return
    } catch {
      Write-Error $_
    }
  }
}
function Invoke-Menu {
  try {
    Write-Host ''; Write-Host 'DLSS5 Universal Installer' -ForegroundColor Cyan
    Write-Host (T '1. Автоматическая установка' '1. Automatic installation')
    Write-Host (T '2. Проверить игру' '2. Check game')
    Write-Host (T '3. Проверить пакеты и SHA-256' '3. Inventory packages and SHA-256')
    Write-Host (T '4. Скачать зафиксированный пакет' '4. Download a locked package')
    Write-Host (T '5. Установка произвольного локального пакета' '5. Install a custom local package')
    Write-Host (T '6. Восстановление выбранной установки' '6. Restore a selected installation')
    Write-Host (T '7. Настройки' '7. Settings')
    Write-Host (T '8. Очистить манифесты' '8. Clean generated manifests')
    Write-Host (T '9. Выход' '9. Exit')
    switch (Read-Input 'Выберите действие' 'Choose action') {
      '1' { Run-Bootstrap $GamePath $Method $null $LumeniteProvider }
      '2' { $p = if ($GamePath) { $GamePath } else { Read-GamePath }; Run-Check $p }
      '3' { Run-Packages }
      '4' { $s = if ($SourceId) { $SourceId } else { Read-Input 'ID источника' 'Source ID' }; Run-Download $s }
      '5' { $p = if ($GamePath) { $GamePath } else { Read-GamePath }; Run-Install $p $PackageManifest }
      '6' { Run-Restore }
      '7' { Invoke-SettingsMenu }
      '8' { Run-CleanManifests }
      '9' { return $false }
      default { Write-Host (T 'Неизвестный пункт.' 'Unknown menu item.') -ForegroundColor Yellow }
    }
    return $true
  } catch [System.OperationCanceledException] {
    Write-Host (T 'Операция отменена. Возврат в главное меню.' 'Operation cancelled. Returning to the main menu.') -ForegroundColor Yellow
    return $true
  } catch {
    try { Write-Log ("MENU_ERROR {0}`n{1}" -f $_.Exception.Message,$_.ScriptStackTrace) } catch { }
    Write-Error $_
    return $true
  }
}
function Main {
  if ($Action -eq 'Check') { if (-not $GamePath) { $GamePath = Read-GamePath }; Run-Check $GamePath; return }
  if ($Action -eq 'Packages') { Run-Packages; return }
  if ($Action -eq 'Download') { if (-not $SourceId) { $SourceId = Read-Input 'ID источника из sources.lock.json' 'Source ID from sources.lock.json' }; Run-Download $SourceId; return }
  if ($Action -eq 'Bootstrap') { Run-Bootstrap $GamePath $Method $Api $LumeniteProvider; return }
  if ($Action -eq 'Install') { if (-not $GamePath) { throw (T 'Для установки нужна папка игры.' 'Install requires a game folder.') }; Run-Install $GamePath $PackageManifest $ExecutablePath @() $null $null $false $LumeniteProvider; return }
  if ($Action -eq 'Restore') { Run-Restore; return }
  if ($Action -eq 'CleanManifests') { Run-CleanManifests; return }
  while (Invoke-Menu) { }
}
try { Main } catch {
  try { Write-Log ("ERROR {0}`n{1}" -f $_.Exception.Message,$_.ScriptStackTrace) } catch { }
  Write-Error $_
  exit 1
}







