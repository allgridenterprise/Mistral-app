#requires -Version 7.0
$paths = @(
  'HKCU:\Software\Classes\Microsoft.PowerShellScript.1\shell\Run with PS7 (Smart)',
  'HKCU:\Software\Classes\Microsoft.PowerShellScript.1\shell\Run with PS7 (Smart, Admin)',
  'HKCU:\Software\Classes\SystemFileAssociations\.ps1\shell\Run with PS7 (Smart)',
  'HKCU:\Software\Classes\SystemFileAssociations\.ps1\shell\Run with PS7 (Smart, Admin)'
)
foreach($p in $paths){
  try{ if(Test-Path $p){ Remove-Item -Path $p -Recurse -Force } } catch {}
}
Write-Host "✓ Høyreklikk-kommandoer er fjernet (brukerkontekst)" -ForegroundColor Yellow
