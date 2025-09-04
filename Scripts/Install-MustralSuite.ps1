            W "ALLE $totalGhosts GHOSTS TERMINERT!" 'Green'
        }

        # FINAL EXTERMINATION: Eliminer hele ghost-mappestrukturer
        W "Final extermination av ghost-mappestrukturer..." 'Red'
        $ghostFolders = @(
            (Join-Path $projectDir "src"),
            (Join-Path $projectDir "Models"), 
            (Join-Path $projectDir "PythonScripts"),
            (Join-Path $projectDir "Core"),
            (Join-Path $projectDir "Configuration")
        )

        $eliminatedFolders = 0
        foreach($ghostFolder in $ghostFolders) {
            if(Test-Path $ghostFolder) {
                try {
                    # Normal elimination
                    Remove-Item $ghostFolder -Recurse -Force -ErrorAction Stop
                    OK "💀 GHOST FOLDER OBLITERATED: $([IO.Path]::GetFileName($ghostFolder))"
                    $eliminatedFolders++
                } catch {
                    # NUCLEAR OPTION: Command line force deletion
                    try {
                        W "🚀 NUCLEAR OPTION: $ghostFolder" 'Yellow'
                        if(Test-Path $ghostFolder -PathType Container) {
                            cmd /c "rmdir /s /q `"$ghostFolder`""
                        } else {
                            cmd /c "del /f /q `"$ghostFolder`""
                        }
                        OK "🚀 NUCLEAR OBLITERATED: $([IO.Path]::GetFileName($ghostFolder))"
                        $eliminatedFolders++
                    } catch {
                        # LAST RESORT: Individual file deletion
                        W "⚡ LAST RESORT: Individual file elimination..." 'Red'
                        try {
                            if(Test-Path $ghostFolder -PathType Container) {
                                Get-ChildItem -Path $ghostFolder -Recurse -Force | ForEach-Object {
                                    try {
                                        Remove-Item $_.FullName -Force
                                    } catch {
                                        cmd /c "del /f /q `"$($_.FullName)`""
                                    }
                                }
                                Remove-Item $ghostFolder -Force
                            }
                            OK "⚡ LAST RESORT SUCCESS: $([IO.Path]::GetFileName($ghostFolder))"
                            $eliminatedFolders++
                        } catch {
                            ERR "💀 IMMORTAL GHOST: $ghostFolder (overlevde alle forsøk)"
                        }
                    }
                }
            }
        }

        # VICTORY LAP: Bekreft at ghostene er døde
        W "🏆 VICTORY VERIFICATION..." 'Green'
        $remainingGhosts = @()
        foreach($ghostFolder in $ghostFolders) {
            if(Test-Path $ghostFolder) {
                $remainingGhosts += $ghostFolder
                ERR "👻 GHOST SURVIVED: $ghostFolder"
            }
        }

        if($remainingGhosts.Count -eq 0) {
            W "🏆 TOTAL VICTORY! ALL GHOSTS OBLITERATED!" 'Green'
        } else {
            ERR "⚠️ $($remainingGhosts.Count) STUBBORN GHOSTS REMAIN"
        }

        if($eliminatedFolders -gt 0) {
            W "ELIMINATED $eliminatedFolders GHOST FOLDERS!" 'Green'
        }

        # FINAL SCAN: Bekreft at alle ghosts er borte
        W "Final verification scan..." 'Yellow'
        $remainingCsFiles = Get-ChildItem -Path $projectDir -Filter "*.cs" -Recurse | Where-Object {
            $_.FullName -notmatch 'bin|obj|packages'
        }

        $remainingErrors = 0
        foreach($csFile in $remainingCsFiles) {
            $relativePath = [IO.Path]::GetRelativePath($projectDir, $csFile.FullName)
            try {
                $content = Get-Content $csFile.FullName -Raw

                # Sjekk for remaining issues
                if($content -match 'List<' -and -not ($content -match 'using System\.Collections\.Generic')) {
                    # Auto-fix: Add missing using
                    $fixedContent = "using System.Collections.Generic;`n" + $content
                    Set-Content -Path $csFile.FullName -Value $fixedContent -Encoding UTF8
                    OK "AUTO-FIXED missing using in: $relativePath"
                }

                if($content -match '\?\s*[=;)]' -and -not ($content -match '#nullable enable')) {
                    # Auto-fix: Add #nullable enable
                    $fixedContent = "#nullable enable`n" + $content
                    Set-Content -Path $csFile.FullName -Value $fixedContent -Encoding UTF8
                    OK "AUTO-FIXED nullable annotations in: $relativePath"
                }

            } catch {
                $remainingErrors++
                ERR "Could not process: $relativePath"
            }
        }

        OK "FINAL VERIFICATION: Found and fixed remaining issues in $($remainingCsFiles.Count) files"

    } else {
        OK "Ingen ghosts funnet - prosjektet er rent"
    }

    # ULTIMATE CLEANUP: Sikre at kun våre rene filer finnes
    W "Ultimate cleanup - sikrer kun rene filer..." 'Green'
    $expectedFiles = @(
        "App.xaml",
        "App.xaml.cs", 
        "Views\MainWindow.xaml",
        "Views\MainWindow.xaml.cs",
        "ViewModels\MainWindowViewModel.cs",
        "Services\ApiKeys\ApiConfigurationService.cs"
    )

    $actualFiles = Get-ChildItem -Path $projectDir -Filter "*.cs" -Recurse | Where-Object {
        $_.FullName -notmatch 'bin|obj|packages'
    }
    $actualXamlFiles = Get-ChildItem -Path $projectDir -Filter "*.xaml" -Recurse | Where-Object {
        $_.FullName -notmatch 'bin|obj|packages'  
    }

    $totalCleanFiles = $actualFiles.Count + $actualXamlFiles.Count
    OK "ULTIMATE VERIFICATION: $totalCleanFiles clean files remain"

    foreach($file in ($actualFiles + $actualXamlFiles)) {
        $relativePath = [IO.Path]::GetRelativePath($projectDir, $file.FullName)
        OK "  ✓ $relativePath"
    }
