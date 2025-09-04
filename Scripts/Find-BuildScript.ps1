#######################################################
# Find-BuildScript.ps1
# Finds comprehensive build scripts in the project
#######################################################

Write-Host "`n===== Searching for Comprehensive Build Scripts =====" -ForegroundColor Cyan

# Project root directory
$projectPath = "C:\Users\DanSolberg\RiderProjects\Mistral app"

# Search patterns for build scripts
$patterns = @(
    "*build*.ps1",
    "*deploy*.ps1",
    "*compile*.ps1",
    "*mistral*build*.ps1",
    "*mistral*deploy*.ps1",
    "*setup*.ps1",
    "*install*.ps1",
    "*package*.ps1",
    "*release*.ps1"
)

Write-Host "Searching for build scripts in: $projectPath" -ForegroundColor Yellow
Write-Host "This might take a minute for large projects..." -ForegroundColor Yellow

# Create empty array for results
$results = @()

# Search for each pattern
foreach ($pattern in $patterns)
{
    $files = Get-ChildItem -Path $projectPath -Recurse -Filter $pattern -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notlike "*node_modules*" -and $_.FullName -notlike "*.git*" }

    if ($files)
    {
        $results += $files
    }
}

# Remove duplicates and sort by size (largest first)
$results = $results | Sort-Object -Property Length -Descending | Get-Unique -AsString

# Display results
if ($results.Count -gt 0)
{
    Write-Host "`nFound $( $results.Count ) potential build scripts:" -ForegroundColor Green

    $index = 1
    foreach ($file in $results)
    {
        # Get file size in KB
        $sizeKB = [Math]::Round($file.Length / 1KB, 2)

        # Check if file contains relevant keywords indicating complexity
        $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
        $complexity = 0

        # Check for indicators of complexity
        if ($content -match "api")
        {
            $complexity += 1
        }
        if ($content -match "cs files" -or $content -match "\.cs")
        {
            $complexity += 1
        }
        if ($content -match "integration")
        {
            $complexity += 1
        }
        if ($content -match "nuget")
        {
            $complexity += 1
        }
        if ($content -match "dotnet")
        {
            $complexity += 1
        }
        if ($content -match "msbuild")
        {
            $complexity += 1
        }

        # Determine complexity rating
        $complexityRating = switch ($complexity)
        {
            { $_ -ge 5 } {
                "Very High"
            }
            { $_ -ge 3 } {
                "High"
            }
            { $_ -ge 2 } {
                "Medium"
            }
            default {
                "Low"
            }
        }

        # Determine if this might be the script we're looking for
        $likelyMatch = $complexity -ge 3 -and $sizeKB -gt 20
        $indicator = if ($likelyMatch)
        {
            "⭐ "
        }
        else
        {
            "  "
        }

        # Line count
        $lineCount = ($content -split "`n").Count

        Write-Host "$indicator$index. $( $file.Name )" -ForegroundColor $( if ($likelyMatch)
        {
            "Green"
        }
        else
        {
            "White"
        } )
        Write-Host "   Path: $( $file.FullName )" -ForegroundColor Gray
        Write-Host "   Size: $sizeKB KB | Lines: $lineCount | Complexity: $complexityRating" -ForegroundColor $( if ($likelyMatch)
        {
            "Yellow"
        }
        else
        {
            "Gray"
        } )
        Write-Host ""

        $index++
    }

    Write-Host "⭐ Stars indicate scripts that are more likely to be your comprehensive build script." -ForegroundColor Yellow
    Write-Host "Examine the largest and most complex scripts first." -ForegroundColor Yellow

    # Offer to open the most promising script
    $largestScript = $results[0]
    $mostComplex = $results | Where-Object {
        $content = Get-Content -Path $_.FullName -Raw -ErrorAction SilentlyContinue
        ($content -match "api") -and ($content -match "\.cs") -and ($content -match "integration")
    } | Select-Object -First 1

    if ($mostComplex)
    {
        $openScript = Read-Host "Would you like to open the most promising script ($( $mostComplex.Name ))? (y/n)"
        if ($openScript -eq "y")
        {
            notepad $mostComplex.FullName
        }
    }
    elseif ($largestScript)
    {
        $openScript = Read-Host "Would you like to open the largest script ($( $largestScript.Name ))? (y/n)"
        if ($openScript -eq "y")
        {
            notepad $largestScript.FullName
        }
    }
}
else
{
    Write-Host "`nNo build scripts found matching the search criteria." -ForegroundColor Red

    # Suggest checking common directories
    $commonDirs = @("scripts", "tools", "build", "deployment", "ci", ".build", "pipeline")
    $dirsToCheck = @()

    foreach ($dir in $commonDirs)
    {
        $dirPath = Join-Path $projectPath $dir
        if (Test-Path $dirPath)
        {
            $dirsToCheck += $dir
        }
    }

    if ($dirsToCheck.Count -gt 0)
    {
        Write-Host "Consider checking these directories manually:" -ForegroundColor Yellow
        foreach ($dir in $dirsToCheck)
        {
            Write-Host "- $dir" -ForegroundColor Yellow
        }
    }
}

