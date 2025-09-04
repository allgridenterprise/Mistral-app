#requires -Version 7.0
$runner = 'C:\Tools\PSSmartRunner\ps-smart-runner.ps1'
$pwsh   = 'C:\Program Files\PowerShell\7\pwsh.exe'
if(-not (Test-Path $runner)){ Write-Host "✗ Finner ikke $runner" -ForegroundColor Red; exit 1 }
if(-not (Test-Path $pwsh)){ $pwsh = 'pwsh' }

$cmd = '"{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}" -File "%1"' -f $pwsh,$runner
$cmdAdmin = '"{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}" -File "%1" -Admin' -f $pwsh,$runner

# File class for .ps1
$base1 = 'HKCU:\Software\Classes\Microsoft.PowerShellScript.1\shell'
New-Item -Path "$base1\Run with PS7 (Smart)" -Force | Out-Null
New-Item -Path "$base1\Run with PS7 (Smart)\command" -Force | Out-Null
Set-ItemProperty -Path "$base1\Run with PS7 (Smart)" -Name Icon -Value ('"{0}"' -f $pwsh)
Set-ItemProperty -Path "$base1\Run with PS7 (Smart)\command" -Name '(default)' -Value $cmd

New-Item -Path "$base1\Run with PS7 (Smart, Admin)" -Force | Out-Null
New-Item -Path "$base1\Run with PS7 (Smart, Admin)\command" -Force | Out-Null
Set-ItemProperty -Path "$base1\Run with PS7 (Smart, Admin)" -Name Icon -Value ('"{0}"' -f $pwsh)
Set-ItemProperty -Path "$base1\Run with PS7 (Smart, Admin)" -Name HasLUAShield -Value ''
Set-ItemProperty -Path "$base1\Run with PS7 (Smart, Admin)\command" -Name '(default)' -Value $cmdAdmin

# SystemFileAssociations for .ps1
$base2 = 'HKCU:\Software\Classes\SystemFileAssociations\.ps1\shell'
New-Item -Path "$base2\Run with PS7 (Smart)" -Force | Out-Null
New-Item -Path "$base2\Run with PS7 (Smart)\command" -Force | Out-Null
Set-ItemProperty -Path "$base2\Run with PS7 (Smart)" -Name Icon -Value ('"{0}"' -f $pwsh)
Set-ItemProperty -Path "$base2\Run with PS7 (Smart)\command" -Name '(default)' -Value $cmd

New-Item -Path "$base2\Run with PS7 (Smart, Admin)" -Force | Out-Null
New-Item -Path "$base2\Run with PS7 (Smart, Admin)\command" -Force | Out-Null
Set-ItemProperty -Path "$base2\Run with PS7 (Smart, Admin)" -Name Icon -Value ('"{0}"' -f $pwsh)
Set-ItemProperty -Path "$base2\Run with PS7 (Smart, Admin)" -Name HasLUAShield -Value ''
Set-ItemProperty -Path "$base2\Run with PS7 (Smart, Admin)\command" -Name '(default)' -Value $cmdAdmin

Write-Host "✓ Høyreklikk-kommandoer er registrert (brukerkontekst)" -ForegroundColor Green
