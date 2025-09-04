param(
    [string]$CsprojPath = (Join-Path $PSScriptRoot '..\MistralApp.csproj'),
    [switch]$EnableInstaller
)

$ErrorActionPreference = 'Stop'

function W([string]$msg,[string]$color='Cyan'){ Write-Host "==> $msg" -ForegroundColor $color }
function OK([string]$msg){ Write-Host "✓ $msg" -ForegroundColor Green }
function WARN([string]$msg){ Write-Host "⚠ $msg" -ForegroundColor DarkYellow }
function ERR([string]$msg){ Write-Host "✗ $msg" -ForegroundColor Red }

if (-not (Test-Path $CsprojPath)) {
    ERR "Fant ikke MistralApp.csproj: $CsprojPath"
    exit 1
}

W ("Forbereder build-profil (DOM): {0} (EnableInstaller={1})" -f $CsprojPath, [bool]$EnableInstaller)

# Backup én gang pr dato
$projDir  = Split-Path $CsprojPath -Parent
$backupDir = Join-Path $projDir 'Output\backups'
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$stamp  = Get-Date -Format 'yyyyMMdd'
$backup = Join-Path $backupDir ("MistralApp.$stamp.backup.csproj")
if (-not (Test-Path $backup)) {
    Copy-Item $CsprojPath $backup -Force
    OK "Backup lagret: $backup"
}

# Last XML og bevar whitespace
[xml]$xml = New-Object System.Xml.XmlDocument
$xml.PreserveWhitespace = $true
$xml.Load($CsprojPath)

# Finn <Project> uavhengig av namespace
$project = $xml.SelectSingleNode("/*[local-name()='Project']")
if (-not $project) { ERR "Ugyldig csproj (mangler <Project>)"; exit 1 }

function Ensure-Property([System.Xml.XmlElement]$propGroup, [string]$name, [string]$value) {
    $node = $propGroup.SelectSingleNode("*[local-name()='$name']")
    if (-not $node) {
        $node = $xml.CreateElement($name)
        $node.InnerText = $value
        [void]$propGroup.AppendChild($node)
    } else {
        $node.InnerText = $value
    }
}
function Ensure-Using([string]$include) {
    $existing = $project.SelectSingleNode("*[local-name()='ItemGroup']/*[local-name()='Using' and @Include='$include']")
    if ($existing) { return }
    $ig = $xml.CreateElement("ItemGroup")
    $u  = $xml.CreateElement("Using")
    $incAttr = $xml.CreateAttribute("Include")
    $incAttr.Value = $include
    [void]$u.Attributes.Append($incAttr)
    [void]$ig.AppendChild($u)
    [void]$project.AppendChild($ig)
}
function Add-ItemGroupWithNodes([System.Xml.XmlElement[]]$nodes) {
    $ig = $xml.CreateElement("ItemGroup")
    foreach($n in $nodes) { [void]$ig.AppendChild($n) }
    [void]$project.AppendChild($ig)
}
function New-Node([string]$name, [hashtable]$attrs) {
    $n = $xml.CreateElement($name)
    foreach($k in $attrs.Keys){
        $a = $xml.CreateAttribute([string]$k)
        $a.Value = [string]$attrs[$k]
        [void]$n.Attributes.Append($a)
    }
    return $n
}
function Remove-NodesByLocalNameAttr([string]$localName, [string]$attrName, [string]$value) {
    $list = $project.SelectNodes("*[local-name()='ItemGroup']/*[local-name()='$localName' and @$attrName='$value']")
    if ($list) { foreach($n in @($list)) { $null = $n.ParentNode.RemoveChild($n) } }
}
function Remove-PackageReferencesByPrefix([string]$prefix) {
    $list = $project.SelectNodes("*[local-name()='ItemGroup']/*[local-name()='PackageReference' and starts-with(@Include,'$prefix')]")
    if ($list) { foreach($n in @($list)) { $null = $n.ParentNode.RemoveChild($n) } }
}
function Select-PackageReference([string]$include) {
    return $project.SelectSingleNode("*[local-name()='ItemGroup']/*[local-name()='PackageReference' and @Include='$include']")
}

# 1) Properties og Using
$propGroup = $project.SelectSingleNode("*[local-name()='PropertyGroup']")
if (-not $propGroup) { $propGroup = $xml.CreateElement("PropertyGroup"); [void]$project.PrependChild($propGroup) }

Ensure-Property $propGroup "Nullable" "enable"
Ensure-Property $propGroup "ImplicitUsings" "enable"
Ensure-Property $propGroup "ApplicationManifest" "app.manifest"

Ensure-Using "System"
Ensure-Using "System.Collections.Generic"
Ensure-Using "System.Threading.Tasks"

# 2) Pakker og Installer branch
Remove-NodesByLocalNameAttr 'PackageReference' 'Include' 'WixSharp.CommonTasks'

if ($EnableInstaller) {
    $wix = Select-PackageReference 'WixSharp'
    if ($wix) {
        $ver = $wix.Attributes.GetNamedItem("Version")
        if (-not $ver) { $ver = $xml.CreateAttribute("Version"); [void]$wix.Attributes.Append($ver) }
        $ver.Value = "1.20.0"
    } else {
        $pr = New-Node "PackageReference" @{ Include="WixSharp"; Version="1.20.0" }
        Add-ItemGroupWithNodes @($pr)
    }
    # Ikke ekskluder installer-koden og fjern eksplisitte Include/Remove
    Remove-NodesByLocalNameAttr 'Compile' 'Remove' 'MistralInstaller\**\*.cs'
    Remove-NodesByLocalNameAttr 'None'    'Remove' 'MistralInstaller\**\*'
    Remove-NodesByLocalNameAttr 'Compile' 'Include' 'MistralInstaller\**\*.cs'
    Remove-NodesByLocalNameAttr 'None'    'Include' 'MistralInstaller\**\*'
} else {
    # Deaktiver MSI: fjern alle WixSharp* og ekskluder installer-koden
    Remove-PackageReferencesByPrefix 'WixSharp'
    Remove-NodesByLocalNameAttr 'Compile' 'Remove' 'MistralInstaller\**\*.cs'
    Remove-NodesByLocalNameAttr 'None'    'Remove' 'MistralInstaller\**\*'
    Add-ItemGroupWithNodes @(
        (New-Node "Compile" @{ Remove="MistralInstaller\**\*.cs" }),
        (New-Node "None"    @{ Remove="MistralInstaller\**\*" })
    )
}

# 3) Ekskluderinger for Integration, PythonScripts, Views(uferdige), MainWindow i rot
$patternsCompile = @(
    "Services\Integration\**\*.cs",
    "**\Services\Integration\**\*.cs",
    "PythonScripts\**\*.cs",
    "Views\FileBrowserView.xaml.cs",
    "Views\ConfiguratorView.xaml.cs",
    "MainWindow.xaml.cs"
)
$patternsPage = @(
    "PythonScripts\**\*.xaml",
    "Views\FileBrowserView.xaml",
    "Views\ConfiguratorView.xaml",
    "MainWindow.xaml"
)
foreach($p in $patternsCompile) { Remove-NodesByLocalNameAttr 'Compile' 'Remove' $p }
foreach($p in $patternsPage)    { Remove-NodesByLocalNameAttr 'Page'    'Remove' $p }

Add-ItemGroupWithNodes @(
    (New-Node "Compile" @{ Remove="Services\Integration\**\*.cs" }),
    (New-Node "Compile" @{ Remove="**\Services\Integration\**\*.cs" })
)
Add-ItemGroupWithNodes @(
    (New-Node "Compile" @{ Remove="PythonScripts\**\*.cs" }),
    (New-Node "Page"    @{ Remove="PythonScripts\**\*.xaml" })
)
# Ikke legg til Remove for Views/* eller MainWindow.* – disse skal bygges som del av GUI

# 4) Rydd tekstnoder under ItemGroup
$igNodes = $project.SelectNodes("*[local-name()='ItemGroup']")
if ($igNodes) {
    foreach ($ig in @($igNodes)) {
        $textNodes = $ig.SelectNodes("text()")
        if ($textNodes) {
            foreach ($t in @($textNodes)) { $null = $ig.RemoveChild($t) }
        }
    }
}

# 5) Lagre
$xml.Save($CsprojPath)
OK "MistralApp.csproj oppdatert (DOM) – EnableInstaller=$EnableInstaller"

exit 0
