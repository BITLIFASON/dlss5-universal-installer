[CmdletBinding()]
param(
  [ValidateSet('Menu','Check','Packages','Download','Bootstrap','Install','Restore')][string]$Action = 'Menu',
  [string]$GamePath,
  [string]$PackageManifest,
  [string]$SourceId,
  [ValidateSet('NativeBridge','OptiScaler','Feeder')][string]$Method,
  [string]$ExecutablePath,
  [string]$Api
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
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
function Get-GameInspection([string]$Path) {
  $resolved = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
  $files = @(Get-ChildItem -LiteralPath $resolved -File -Recurse -ErrorAction SilentlyContinue)
  $executables = @(Find-GameExecutables $resolved)
  $dlss = @($files | Where-Object { $_.Name -match '^(nvngx_dlss|nvngx_dlssg|nvngx_dlssnr|dlss).*\.dll' })
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
    nativeDlssDetected = ($dlss.Count -gt 0)
    dlssFiles = @($dlss | ForEach-Object { Get-RelativePath $resolved $_.FullName })
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
  Write-Host (T '2. OptiScaler — широкая совместимость; возможны конфликты DLL-прокси.' '2. OptiScaler — broad compatibility; proxy DLL conflicts are possible.')
  Write-Host (T '3. ReShade + Feeder — постобработка; требует буфер глубины и векторы движения, обычно снижает FPS.' '3. ReShade + Feeder — post-processing; needs depth/motion vectors and usually costs more FPS.')
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
function Get-SourceLock {
  $path = Join-Path $Root 'config\sources.lock.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw (T 'Файл sources.lock.json не найден.' 'sources.lock.json was not found.') }
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
function Prepare-SourcePackage($Manifest) {
  if ($Manifest.sourcePackage -eq 'dlss5-bridge') { Ensure-LockedDownload 'dlss5-bridge' | Split-Path -Parent; return $Dirs.Downloads }
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
  if ($manifest.method -notin @('NativeBridge','OptiScaler','Feeder')) { throw (T 'В манифесте указан неизвестный метод.' 'Unknown method in package manifest.') }
  if (-not $manifest.sourcePackage) {
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
function Show-InstallPlan($Manifest,[string]$InstallRoot) {
  Write-Host ''; Write-Host (T 'План установки:' 'Installation plan:') -ForegroundColor Cyan
  foreach ($entry in @($Manifest.files)) {
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
  if ((Read-Input 'Запустить выбранный EXE для проверки? (y/n)' 'Launch the selected executable for verification? (y/n)') -match '^(y|yes|д|да)$') {
    Start-Process -FilePath $ExecutablePath | Out-Null
    Write-Log ("LAUNCH {0}" -f $ExecutablePath)
  }
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
  @(Get-ChildItem -LiteralPath $Dirs.Manifests -Filter 'install-*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
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
function Invoke-TrackedReShade([string]$Installer,[string]$Api,[string]$Executable,[string]$InstallRoot,[string]$BackupRoot) {
  $before = Get-FileSnapshot $InstallRoot
  $process = Start-Process -FilePath $Installer -ArgumentList @('--headless','--api',$Api,$Executable) -Wait -PassThru
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
    throw ("ReShade setup failed with exit code {0}" -f $process.ExitCode)
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
  $args = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action Install -GamePath `"$InstallGamePath`" -PackageManifest `"$ManifestPath`" -ExecutablePath `"$SelectedExecutable`""
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $args | Out-Null
  return $false
}
function Ensure-AdminBootstrap([string]$InstallGamePath,[string]$SelectedMethod,[string]$Api) {
  $probe = Join-Path $InstallGamePath ('.dlss5-bootstrap-write-test-' + [guid]::NewGuid().ToString('N'))
  try { New-Item -ItemType File -Path $probe -Force | Out-Null; Remove-Item -LiteralPath $probe -Force; return $true } catch { }
  $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return $true }
  if ($Settings.warnBeforeElevation) {
    $answer = Read-Input 'Автоматическая установка может потребовать права администратора. Перезапустить мастер с повышенными правами? (y/n)' 'Automatic installation may require administrator rights. Relaunch the wizard elevated? (y/n)'
    if ($answer -notmatch '^(y|yes|д|да)$') { return $false }
  }
  $args = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action Bootstrap -GamePath `"$InstallGamePath`" -Method $SelectedMethod"
  if ($Api) { $args += " -Api `"$Api`"" }
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $args | Out-Null
  return $false
}
function Run-Install([string]$Path,[string]$ManifestPath,[string]$ExecutablePath,[object[]]$PreRecords,[string]$PreBackupRoot,[string]$PreStamp,[bool]$AlreadyConfirmed = $false) {
  if (-not $ManifestPath) { $ManifestPath = Read-Input 'Укажите путь к manifest пакета (например packages\opti.manifest.json)' 'Enter package manifest path (for example packages\opti.manifest.json)' }
  $game = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
  $info = Get-GameInspection $game
  Show-MethodComparison $info
  if (-not $ExecutablePath) { $ExecutablePath = Select-Executable $info }
  $manifest = Get-PackageManifest (Resolve-Path -LiteralPath $ManifestPath).Path
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
  if ($manifest.sourcePackage) { $sourceRoot = Prepare-SourcePackage $manifest }
  else { Expand-Package $manifest._archivePath $stage }
  $backupRoot = if ($PreBackupRoot) { $PreBackupRoot } else { Join-Path $Dirs.Backups $stamp }
  $records = @($PreRecords)
  $recordByPath = @{}
  foreach ($pre in $records) { if ($pre.path) { $recordByPath[[string]$pre.path] = $pre } }
  try {
   foreach ($entry in @($manifest.files)) {
    $relative = ([string]$entry.path).Replace('/','\')
    $sourceRelative = if ($entry.sourcePath) { ([string]$entry.sourcePath).Replace('/','\') } else { $relative }
    $source = Join-Path $sourceRoot $sourceRelative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw ("Archive is missing manifest file: {0}" -f $relative) }
    if ((Get-Sha256 $source) -ne ([string]$entry.sha256).ToLowerInvariant()) { throw ("Staged file SHA-256 mismatch: {0}" -f $relative) }
    $destination = Join-Path $installRoot $relative
    if ($recordByPath.ContainsKey($relative)) {
      $record = $recordByPath[$relative]
    } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
      $backup = Join-Path $backupRoot $relative
      New-Item -ItemType Directory -Force -Path (Split-Path $backup) | Out-Null
      $record = [ordered]@{ installRoot=$installRoot; path=$relative; existed=$true; originalSha256=Get-Sha256 $destination; backup=$backup; installedSha256=$null }
      Copy-Item -LiteralPath $destination -Destination $backup -Force
    } else { $record = [ordered]@{ installRoot=$installRoot; path=$relative; existed=$false; originalSha256=$null; backup=$null; installedSha256=$null } }
    if (-not $recordByPath.ContainsKey($relative)) {
      $records += $record
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
  $install = [ordered]@{ timestamp=(Get-Date).ToUniversalTime().ToString('o'); gamePath=$game; installRoot=$installRoot; packageId=$manifest.id; packageVersion=$manifest.version; method=$manifest.method; files=$records }
  $installPath = Save-JsonManifest 'install' $install
  Write-Log ("INSTALL {0}; manifest={1}" -f $game,$installPath)
  Write-Host (T 'Установка завершена. Для отката выберите нужную запись в пункте «Восстановление».' 'Installation completed. Select the required entry in Restore to roll back.') -ForegroundColor Green
  Save-GameProfile $info $ExecutablePath $manifest $info.apiHint
  Offer-Launch $ExecutablePath
}
function Run-Bootstrap([string]$Path,[string]$SelectedMethod,[string]$Api) {
  if (-not $Path) { $Path = Read-GamePath }
  $info = Get-GameInspection $Path
  if (-not $SelectedMethod) {
    Show-MethodComparison $info
    $SelectedMethod = @('NativeBridge','OptiScaler','Feeder')[[int](Read-Input 'Метод (1-3)' 'Method (1-3)') - 1]
  }
  $map = @{ NativeBridge='packages\dlss5-bridge.manifest.json'; OptiScaler='packages\optiscaler.manifest.json'; Feeder='packages\dlss5-feeder.manifest.json' }
  $manifestPath = Join-Path $Root $map[$SelectedMethod]
  if (-not (Test-Path -LiteralPath $manifestPath)) { throw (T 'Подготовленный манифест метода не найден.' 'Prepared method manifest was not found.') }
  $exe = Select-Executable $info
  if ((Read-Input ("Установить метод {0} в выбранный EXE? (y/n)" -f $SelectedMethod) ("Install method {0} into the selected EXE? (y/n)" -f $SelectedMethod)) -notmatch '^(y|yes|д|да)$') { return }
  if (-not (Ensure-AdminBootstrap $Path $SelectedMethod $Api)) { return }
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $backupRoot = Join-Path $Dirs.Backups $stamp
  $preRecords = @()
  if ($SelectedMethod -eq 'OptiScaler') {
    $archive = Ensure-LockedDownload 'optiscaler'
    Copy-Item -LiteralPath $archive -Destination (Join-Path $Dirs.Packages (Split-Path $archive -Leaf)) -Force
  } elseif ($SelectedMethod -eq 'NativeBridge') { Ensure-LockedDownload 'dlss5-bridge' | Out-Null }
  elseif ($SelectedMethod -eq 'Feeder') { Ensure-LockedDownload 'dlss5-aio-v1.2.5-part1' | Out-Null }
  if ($SelectedMethod -in @('NativeBridge','Feeder')) {
    $reshade = Ensure-LockedDownload 'reshade-full-addons'
    if (-not $Api) { $Api = if ($info.apiHint -match 'DX12') { 'd3d12' } else { 'd3d11' } }
    Write-Host (T 'Автоматическая установка ReShade...' 'Installing ReShade automatically...')
    $preRecords = Invoke-TrackedReShade $reshade $Api $exe (Split-Path -Parent $exe) $backupRoot
  }
  Run-Install $Path $manifestPath $exe $preRecords $backupRoot $stamp $true
}
function Run-Restore {
  $items = Get-InstalledPackageManifest
  if ($items.Count -eq 0) { Write-Host (T 'Установок для отката не найдено.' 'No installations to restore.') -ForegroundColor Yellow; return }
  Write-Host ''; Write-Host (T 'Доступные установки для отката:' 'Installations available for restore:') -ForegroundColor Cyan
  for ($i = 0; $i -lt $items.Count; $i++) {
    $entry = Get-Content -LiteralPath $items[$i].FullName -Raw | ConvertFrom-Json
    Write-Host ("{0}. {1} | {2} {3} | {4}" -f ($i + 1),$entry.gamePath,$entry.packageId,$entry.packageVersion,$items[$i].Name)
  }
  $choice = Read-Input 'Выберите номер установки' 'Choose an installation number'
  $index = 0
  if (-not [int]::TryParse($choice,[ref]$index) -or $index -lt 1 -or $index -gt $items.Count) { throw (T 'Некорректный номер установки.' 'Invalid installation number.') }
  $selected = $items[$index - 1]
  $install = Get-Content -LiteralPath $selected.FullName -Raw | ConvertFrom-Json
  $game = [string]$install.gamePath
  $installRoot = if ($install.installRoot) { [string]$install.installRoot } else { $game }
  if (-not (Test-Path -LiteralPath $game -PathType Container)) { throw (T 'Папка игры из манифеста не найдена.' 'Game folder from manifest was not found.') }
  $conflicts = @()
  foreach ($entry in @($install.files)) {
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
  foreach ($entry in @($install.files)) {
    $destination = Join-Path $installRoot ([string]$entry.path)
    if ($entry.existed -and (Test-Path -LiteralPath $entry.backup -PathType Leaf)) { Copy-Item -LiteralPath $entry.backup -Destination $destination -Force }
    elseif (-not $entry.existed -and (Test-Path -LiteralPath $destination -PathType Leaf)) { Remove-Item -LiteralPath $destination -Force }
  }
  Write-Log ("RESTORE {0}; source={1}" -f $game,$selected.FullName)
  Write-Host (T 'Откат завершён.' 'Restore completed.') -ForegroundColor Green
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
    Write-Host (T '8. Выход' '8. Exit')
    switch (Read-Input 'Выберите действие' 'Choose action') {
      '1' { Run-Bootstrap $GamePath $Method $null }
      '2' { $p = if ($GamePath) { $GamePath } else { Read-GamePath }; Run-Check $p }
      '3' { Run-Packages }
      '4' { $s = if ($SourceId) { $SourceId } else { Read-Input 'ID источника' 'Source ID' }; Run-Download $s }
      '5' { $p = if ($GamePath) { $GamePath } else { Read-GamePath }; Run-Install $p $PackageManifest }
      '6' { Run-Restore }
      '7' { Invoke-SettingsMenu }
      '8' { return $false }
      default { Write-Host (T 'Неизвестный пункт.' 'Unknown menu item.') -ForegroundColor Yellow }
    }
    return $true
  } catch [System.OperationCanceledException] {
    Write-Host (T 'Операция отменена. Возврат в главное меню.' 'Operation cancelled. Returning to the main menu.') -ForegroundColor Yellow
    return $true
  } catch {
    Write-Error $_
    return $true
  }
}
function Main {
  if ($Action -eq 'Check') { if (-not $GamePath) { $GamePath = Read-GamePath }; Run-Check $GamePath; return }
  if ($Action -eq 'Packages') { Run-Packages; return }
  if ($Action -eq 'Download') { if (-not $SourceId) { $SourceId = Read-Input 'ID источника из sources.lock.json' 'Source ID from sources.lock.json' }; Run-Download $SourceId; return }
  if ($Action -eq 'Bootstrap') { Run-Bootstrap $GamePath $Method $Api; return }
  if ($Action -eq 'Install') { if (-not $GamePath) { throw (T 'Для установки нужна папка игры.' 'Install requires a game folder.') }; Run-Install $GamePath $PackageManifest $ExecutablePath; return }
  if ($Action -eq 'Restore') { Run-Restore; return }
  while (Invoke-Menu) { }
}
try { Main } catch { Write-Error $_; exit 1 }







