#requires -Version 7.0
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$File,
  [switch]$Admin,
  [switch]$AutoPick,                 # autoplukker nr. 1
  [int]$Pick = 1,                    # eller velg 1-baserte indeks
  [switch]$DeleteOthers,             # (ikke brukt her; bruk karantene-kommandoen under i stedet)
  [int]$DeleteAfterMinutes = 15,     # auto-slett karantene
  [switch]$ExtendedSearch,           # søk også utvidede røtter
  [switch]$IncludeSimilar,           # inkluder "lik navnekjerne"
  [int]$MaxSizeDeltaPercent = 20     # maks avvik i % for similar
)

$ErrorActionPreference = 'Stop'
function W($m,$c='Cyan'){ Write-Host "==> $m" -ForegroundColor $c }
function OK($m){ Write-Host "✓ $m" -ForegroundColor Green }
function WARN($m){ Write-Host "⚠ $m" -ForegroundColor DarkYellow }
function ERR($m){ Write-Host "✗ $m" -ForegroundColor Red }

function Format-Size([long]$bytes){
  if($bytes -ge 1GB){ return ("{0:N1} GB" -f ($bytes/1GB)) }
  if($bytes -ge 1MB){ return ("{0:N1} MB" -f ($bytes/1MB)) }
  if($bytes -ge 1KB){ return ("{0:N0} KB" -f ($bytes/1KB)) }
  return ("{0} B" -f $bytes)
}
function NameKey([string]$path){
  $b = [IO.Path]::GetFileNameWithoutExtension($path)
  ($b -replace '[\d_ .\-]+','' ).ToLowerInvariant()
}
function Parse-IndexSpec([string]$spec,[int]$max){
  $out = New-Object System.Collections.Generic.HashSet[int]
  foreach($part in ($spec -split ',')){
    $t = $part.Trim()
    if([string]::IsNullOrWhiteSpace($t)){ continue }
    if($t -match '^\d+\-\d+$'){
      $a,$b = $t -split '-'; $a=[int]$a; $b=[int]$b
      if($a -gt $b){ $tmp=$a; $a=$b; $b=$tmp }
      for($i=$a;$i -le $b;$i++){ if($i -ge 1 -and $i -le $max){ [void]$out.Add($i) } }
    } elseif($t -as [int]) {
      $n=[int]$t; if($n -ge 1 -and $n -le $max){ [void]$out.Add($n) }
    }
  }
  return [int[]]($out.ToArray() | Sort-Object)
}
function Get-Candidates([string]$clicked,[switch]$ext,[switch]$similar,[int]$pct){
  $name = Split-Path -Leaf $clicked
  $baseKey = NameKey $clicked
  $startDir = Split-Path -Parent $clicked

  $roots = New-Object System.Collections.Generic.List[string]
  $roots.Add($startDir)
  $roots.Add((Get-Location).Path)
  if($env:USERPROFILE){ $roots.Add($env:USERPROFILE) }
  if($env:OneDrive){ $roots.Add($env:OneDrive) }
  if($ext){
    $roots.Add([Environment]::GetFolderPath('MyDocuments'))
    $roots.Add([Environment]::GetFolderPath('Desktop'))
    $rp = Join-Path $env:USERPROFILE 'RiderProjects'
    if(Test-Path $rp){ $roots.Add($rp) }
    $dl = [Environment]::GetFolderPath('Downloads')
    if(Test-Path $dl){ $roots.Add($dl) }
  }
  $roots = $roots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
  $hits = @()
  foreach($r in $roots){
    try { $hits += Get-ChildItem -Path $r -Filter *.ps1 -File -Recurse -ErrorAction SilentlyContinue } catch {}
  }
  if(-not $hits){ return @() }

  $clickedInfo = Get-Item -LiteralPath $clicked -ErrorAction SilentlyContinue
  $clickedLen = if($clickedInfo){ [double]$clickedInfo.Length } else { 0.0 }

  $filtered = $hits | Where-Object {
    if($_.Name -ieq $name){ return $true }
    if($similar){
      $nk = NameKey $_.FullName
      if($nk -ne $baseKey){ return $false }
      if($clickedLen -le 0){ return $true }
      $delta = [math]::Abs(([double]$_.Length - $clickedLen)) / $clickedLen * 100.0
      return ($delta -le $pct)
    }
    return $false
  }

  $filtered | Sort-Object LastWriteTime, Length -Descending
}
function Quarantine-And-DeleteLater([System.IO.FileInfo[]]$others,[int]$minutes){
  if(-not $others -or $others.Count -eq 0){ return }
  $qRoot = Join-Path $env:TEMP 'PSSmartRunner\Quarantine'
  New-Item -ItemType Directory -Path $qRoot -Force | Out-Null
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $qDir = Join-Path $qRoot $stamp
  New-Item -ItemType Directory -Path $qDir -Force | Out-Null
  foreach($o in $others){
    try{
      $rel = ($o.FullName -replace '^[A-Za-z]:\\','').Replace(':','_')
      $dest = Join-Path $qDir $rel
      New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
      Move-Item -LiteralPath $o.FullName -Destination $dest -Force
      OK ("Karantene: {0}" -f $o.FullName)
    } catch { WARN ("Flytting feilet {0}: {1}" -f $o.FullName, $_.Exception.Message) }
  }
  Start-Job -Name "PSSR-Clean-$stamp" -ScriptBlock {
    param($dir,$minutes)
    Start-Sleep -Seconds ($minutes*60)
    try { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop } catch {}
    $root = Split-Path $dir -Parent
    Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } |
      ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force } catch {} }
  } -ArgumentList $qDir,$minutes | Out-Null
  OK ("Karantene auto-slettes om {0} min" -f $minutes)
}
function Find-ProjectRoot([string]$startDir){
  $d = Resolve-Path $startDir
  while($d -and (Test-Path $d)){
    $sln = Get-ChildItem -Path $d -Filter *.sln -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $cs  = Get-ChildItem -Path $d -Filter *.csproj -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if($sln -or $cs){ return $d }
    $parent = Split-Path $d -Parent
    if($parent -eq $d){ break }
    $d = $parent
  }
  return $null
}
function Smart-Test([string]$file){
  Write-Host ""
  Write-Host "— SmartTest: $file" -ForegroundColor Cyan
  $ok = $true
  try { $text = Get-Content -Path $file -Raw -ErrorAction Stop } catch {
    Write-Host "  Kunne ikke lese filen: $($_.Exception.Message)" -ForegroundColor DarkYellow
    return $false
  }
  if($text -match '^\s*#\!'){ Write-Host "  Shebang oppdaget" -ForegroundColor DarkGray }
  $requires = Select-String -InputObject $text -Pattern '^\s*#requires\s+-\w+' -AllMatches
  if($requires){ $requires.Matches | ForEach-Object { Write-Host ("  $_") -ForegroundColor DarkGray } }
  if($text -match '^\s*param\s*\('){ Write-Host "  Param()-blokk funnet" -ForegroundColor DarkGray }
  $mods = Select-String -InputObject $text -Pattern '^\s*Import-Module\s+([^\r\n]+)' -AllMatches
  if($mods){ Write-Host "  Import-Module:" -ForegroundColor DarkGray; $mods.Matches | ForEach-Object { Write-Host ("    " + $_.Groups[1].Value.Trim()) -ForegroundColor DarkGray } }
  try { $null = [ScriptBlock]::Create($text); Write-Host "  Syntaks: OK" -ForegroundColor Green } catch {
    Write-Host ("  Syntaksfeil: {0}" -f $_.Exception.Message) -ForegroundColor Red; $ok = $false
  }
  try { $fi = Get-Item -LiteralPath $file; Write-Host ("  Størrelse: {0}" -f (("{0:N0} KB" -f ($fi.Length/1KB)))) -ForegroundColor DarkGray; Write-Host ("  Sist endret: {0:yyyy-MM-dd HH:mm}" -f $fi.LastWriteTime) -ForegroundColor DarkGray } catch {}
  return $ok
}
function Propose-Relocation([string]$file){
  $curDir  = Split-Path -Parent $file
  $proj    = Find-ProjectRoot $curDir
  $target1 = $null
  $target2 = Join-Path 'C:\Tools\Scripts' (Split-Path -Leaf $file)
  if($proj){
    $scripts1 = Join-Path $proj 'Scripts'
    if(-not (Test-Path $scripts1)){ New-Item -ItemType Directory -Path $scripts1 -Force | Out-Null }
    $target1 = Join-Path $scripts1 (Split-Path -Leaf $file)
  }
  Write-Host ""
  Write-Host "— Plassering:" -ForegroundColor Cyan
  Write-Host ("  1) Kjør her (nå):   {0}" -f $curDir) -ForegroundColor DarkGray
  if($target1){ Write-Host ("  2) Flytt til prosjekt Scripts:  {0}" -f (Split-Path $target1 -Parent)) -ForegroundColor DarkGray }
  Write-Host ("  3) Flytt til system Scripts:    {0}" -f (Split-Path $target2 -Parent)) -ForegroundColor DarkGray
  $default = if($target1){ '2' } else { '1' }
  $ans = Read-Host ("Velg (Enter={0})" -f $default)
  if([string]::IsNullOrWhiteSpace($ans)){ $ans = $default }
  switch($ans){
    '1' { return $file }
    '2' {
      if(-not $target1){ return $file }
      try { Move-Item -LiteralPath $file -Destination $target1 -Force; Write-Host ("  Flyttet → {0}" -f $target1) -ForegroundColor Green; return $target1 } catch { Write-Host ("  Flytt feilet: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow; return $file }
    }
    '3' {
      try {
        $tDir = Split-Path $target2 -Parent
        if(-not (Test-Path $tDir)){ New-Item -ItemType Directory -Path $tDir -Force | Out-Null }
        Move-Item -LiteralPath $file -Destination $target2 -Force
        Write-Host ("  Flyttet → {0}" -f $target2) -ForegroundColor Green
        return $target2
      } catch { Write-Host ("  Flytt feilet: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow; return $file }
    }
    default { return $file }
  }
}

# 0) Valider inngang
if (-not (Test-Path $File)){ ERR "Filen finnes ikke: $File"; exit 1 }

# 1) Søkemodus og utvidet søk (Enter-flow)
Write-Host ""
W "Høyreklikk-kjøring (PS7) • Fil: $File" 'Magenta'
Write-Host "Søkemodus:" -ForegroundColor Cyan
Write-Host "  1) Eksakt navn (default)" -ForegroundColor DarkGray
Write-Host "  2) Lik navnekjerne (similar)" -ForegroundColor DarkGray
$mode = Read-Host "Velg (Enter=1)"
if ([string]::IsNullOrWhiteSpace($mode)) { $mode = '1' }
$IncludeSimilar = ($mode -eq '2')
$askExt = Read-Host "Utvidet søk i flere røtter? (y/N)"
$ExtendedSearch = $askExt -match '^(y|j|yes|ja)$'
if ($IncludeSimilar) {
  $ansPct = Read-Host ("Maks størrelse-avvik i % (Enter={0})" -f $MaxSizeDeltaPercent)
  if ($ansPct -as [int]) { $MaxSizeDeltaPercent = [int]$ansPct }
}

# 2) Finn kandidater
$candidates = Get-Candidates -clicked (Resolve-Path $File).Path -ext:$ExtendedSearch -similar:$IncludeSimilar -pct:$MaxSizeDeltaPercent
if (-not $candidates -or $candidates.Count -eq 0){
  ERR "Ingen kandidater funnet (prøv ExtendedSearch/Similar)"; exit 1
}

# 3) Vis og velg (støtter 1,3,5-7)
Write-Host ""
Write-Host "Kandidater (nyeste/største først):" -ForegroundColor Cyan
$i=0
foreach($c in $candidates){
  $i++
  Write-Host (" {0,2}) {1}  [{2}, {3:yyyy-MM-dd HH:mm}]" -f $i, $c.FullName, (("{0:N0} KB" -f ($c.Length/1KB))), $c.LastWriteTime) -ForegroundColor DarkGray
}
$sel = Read-Host "Velg nr (Enter=1, q=avbryt, flere: 1,3,5-7)"
if ([string]::IsNullOrWhiteSpace($sel)) { $sel = '1' }
if ($sel -eq 'q') { Write-Host "Avbrutt." -ForegroundColor Yellow; exit 0 }
$indices = Parse-IndexSpec -spec $sel -max $candidates.Count
if ($indices.Count -eq 0) { ERR "Ugyldig valg."; exit 1 }

# 4) SmartTest på valgte → velg første som passerer, ellers spør
$tests = @()
foreach($idx in $indices){
  $f = $candidates[$idx-1].FullName
  $ok = Smart-Test -file $f
  $tests += [pscustomobject]@{ Index=$idx; File=$f; Passed=$ok }
}
$chosen = $null
$pass = $tests | Where-Object { $_.Passed }
if ($pass.Count -gt 0){
  $best = $pass | Sort-Object Index | Select-Object -First 1
  Write-Host ("→ Velger #{0}: {1}" -f $best.Index, $best.File) -ForegroundColor DarkGray
  $chosen = $candidates[$best.Index-1]
} else {
  $ask = Read-Host "Ingen passerte syntaks. Kjør likevel første valgte? (y/N)"
  if ($ask -notmatch '^(y|j|yes|ja)$'){ Write-Host "Avbrutt." -ForegroundColor Yellow; exit 1 }
  $chosen = $candidates[$indices[0]-1]
}

# 5) Foreslå flytting før kjøring
$runPath = Propose-Relocation -file $chosen.FullName

# 6) Karantene: én-linje “kommando”
Write-Host ""
Write-Host "Karantene (auto-slett etter $DeleteAfterMinutes min):" -ForegroundColor Cyan
Write-Host "  Enter=none | all | keep:1,3,5-7 | del:2,4 | invert:1,3 | + optional 'timer:MIN'" -ForegroundColor DarkGray
$qr = Read-Host "Valg"
$toQuarantine = @()
$timer = $DeleteAfterMinutes
if (-not [string]::IsNullOrWhiteSpace($qr)) {
  if ($qr -match 'timer\s*:\s*(\d+)'){
    $timer = [int]$Matches[1]
    $qr = ($qr -replace 'timer\s*:\s*\d+','').Trim()
  }
  switch -Regex ($qr) {
    '^all$'        { $toQuarantine = ($candidates | Where-Object { $_.FullName -ne $runPath }) }
    '^none$'       { }
    '^others$'     { $toQuarantine = ($candidates | Where-Object { $_.FullName -ne $runPath }) }
    '^only:(.+)$'  { $keepIdx = Parse-IndexSpec -spec $Matches[1] -max $candidates.Count; $keepPaths = $keepIdx | ForEach-Object { $candidates[$_-1].FullName }; $toQuarantine = $candidates | Where-Object { $keepPaths -notcontains $_.FullName } }
    '^keep:(.+)$'  { $keepIdx = Parse-IndexSpec -spec $Matches[1] -max $candidates.Count; $keepPaths = $keepIdx | ForEach-Object { $candidates[$_-1].FullName }; $toQuarantine = $candidates | Where-Object { $keepPaths -notcontains $_.FullName } }
    '^del:(.+)$'   { $delIdx = Parse-IndexSpec -spec $Matches[1] -max $candidates.Count; $delPaths = $delIdx | ForEach-Object { $candidates[$_-1].FullName }; $toQuarantine = $candidates | Where-Object { $delPaths -contains $_.FullName -and $_.FullName -ne $runPath } }
    '^invert:(.+)$'{ $keepIdx = Parse-IndexSpec -spec $Matches[1] -max $candidates.Count; $keepPaths = $keepIdx | ForEach-Object { $candidates[$_-1].FullName }; $toQuarantine = $candidates | Where-Object { $keepPaths -notcontains $_.FullName } }
    default { }
  }
}
if ($toQuarantine.Count -gt 0){
  Quarantine-And-DeleteLater -others $toQuarantine -minutes $timer
}

# 7) Start i PS7
$pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
if (-not (Test-Path $pwsh)) { $pwsh = 'pwsh' }
$wd = Split-Path $runPath -Parent
$args = @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File', $runPath)
W ("Starter: {0}" -f $runPath)
try{
  if ($Admin){
    Start-Process -FilePath $pwsh -ArgumentList $args -WorkingDirectory $wd -Verb RunAs | Out-Null
  } else {
    Start-Process -FilePath $pwsh -ArgumentList $args -WorkingDirectory $wd | Out-Null
  }
  OK "Startet i ny PS7-terminal"
} catch {
  ERR ("Kunne ikke starte: {0}" -f $_.Exception.Message); exit 1
}
