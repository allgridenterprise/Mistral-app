#######################################################
# Build-MistralApp.ps1
# Complete script for building and installing Mistral app
#######################################################

Write-Host "`n===== Mistral App Build & Installation =====" -ForegroundColor Cyan
Write-Host "This script handles deletion, building, and installation of Mistral Suite" -ForegroundColor Cyan

# Constants
$projectPath = "C:\Users\DanSolberg\RiderProjects\Mistral app"
$buildPath = Join-Path $projectPath "build"
$distPath = Join-Path $projectPath "dist"
$setupDir = Join-Path $projectPath "Setup"
$innoSetupCompiler = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
$msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe"
if (-not (Test-Path $msbuild))
{
    # Try to find MSBuild in default locations
    $msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
    if (-not (Test-Path $msbuild))
    {
        $msbuild = "C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe"
    }
}
$solutionFile = Join-Path $projectPath "MistralSuite.sln"

# Status Icons
$successIcon = "✅"
$warningIcon = "⚠️"
$errorIcon = "❌"
$infoIcon = "ℹ️"

function Write-StepHeader
{
    param([string]$stepText)
    Write-Host "`n==> $stepText" -ForegroundColor Magenta
}

function Write-Status
{
    param(
        [string]$label,
        [string]$value,
        [string]$status = "info"
    )

    $statusIcon = switch ($status)
    {
        "success" {
            $successIcon
        }
        "warning" {
            $warningIcon
        }
        "error" {
            $errorIcon
        }
        default {
            $infoIcon
        }
    }

    Write-Host "$statusIcon $label : " -NoNewline

    $color = switch ($status)
    {
        "success" {
            "Green"
        }
        "warning" {
            "Yellow"
        }
        "error" {
            "Red"
        }
        default {
            "White"
        }
    }

    Write-Host $value -ForegroundColor $color
}

# Step 1: Clean up previous builds
Write-StepHeader "Step 1: Cleaning up previous builds"

try
{
    # Check if build directory exists
    if (Test-Path $buildPath)
    {
        Write-Status "Build Directory" "Found at $buildPath" "info"
        $deleteBuild = Read-Host "Delete previous build artifacts? (y/n)"

        if ($deleteBuild -eq "y")
        {
            Remove-Item -Path $buildPath -Recurse -Force
            Write-Status "Cleanup" "Build directory removed" "success"
        }
    }
    else
    {
        Write-Status "Build Directory" "Not found - nothing to clean" "info"
    }

    # Check if dist directory exists
    if (Test-Path $distPath)
    {
        Write-Status "Distribution Directory" "Found at $distPath" "info"
        $deleteDist = Read-Host "Delete previous distribution packages? (y/n)"

        if ($deleteDist -eq "y")
        {
            Remove-Item -Path $distPath -Recurse -Force
            Write-Status "Cleanup" "Distribution directory removed" "success"
        }
    }
    else
    {
        Write-Status "Distribution Directory" "Not found - nothing to clean" "info"
    }

    # Create directories if they don't exist
    if (-not (Test-Path $buildPath))
    {
        New-Item -ItemType Directory -Path $buildPath | Out-Null
        Write-Status "Created" "Build directory" "success"
    }

    if (-not (Test-Path $distPath))
    {
        New-Item -ItemType Directory -Path $distPath | Out-Null
        Write-Status "Created" "Distribution directory" "success"
    }

    if (-not (Test-Path $setupDir))
    {
        New-Item -ItemType Directory -Path $setupDir | Out-Null
        Write-Status "Created" "Setup directory" "success"
    }
}
catch
{
    Write-Status "Cleanup Error" $_.Exception.Message "error"
}

# Step 2: Build the Mistral application
Write-StepHeader "Step 2: Building Mistral application"

try
{
    # Check if solution file exists
    if (-not (Test-Path $solutionFile))
    {
        # Try to find any solution file
        $solutionFiles = Get-ChildItem -Path $projectPath -Filter "*.sln" -File

        if ($solutionFiles.Count -gt 0)
        {
            $solutionFile = $solutionFiles[0].FullName
            Write-Status "Solution File" "Found alternative: $solutionFile" "info"
        }
        else
        {
            Write-Status "Solution File" "No .sln file found in project directory" "error"
            exit 1
        }
    }
    else
    {
        Write-Status "Solution File" "Found at $solutionFile" "success"
    }

    # Check if MSBuild exists
    if (-not (Test-Path $msbuild))
    {
        Write-Status "MSBuild" "Could not find MSBuild at $msbuild" "error"
        Write-Host "Please install Visual Studio or specify the correct path to MSBuild" -ForegroundColor Red
        exit 1
    }
    else
    {
        Write-Status "MSBuild" "Found at $msbuild" "success"
    }

    # Build the solution
    Write-Status "Building" "Starting build process..." "info"

    $buildConfig = Read-Host "Enter build configuration (Debug/Release)"
    if (-not $buildConfig)
    {
        $buildConfig = "Release"  # Default to Release if not specified
    }

    $buildCommand = "& `"$msbuild`" `"$solutionFile`" /t:Clean,Build /p:Configuration=$buildConfig /p:Platform=`"Any CPU`" /p:OutDir=`"$buildPath\`""
    Write-Host "Executing: $buildCommand" -ForegroundColor Yellow

    Invoke-Expression $buildCommand

    if ($LASTEXITCODE -eq 0)
    {
        Write-Status "Build" "Successfully built Mistral application" "success"
    }
    else
    {
        Write-Status "Build" "Failed with exit code $LASTEXITCODE" "error"
        exit 1
    }
}
catch
{
    Write-Status "Build Error" $_.Exception.Message "error"
    exit 1
}

# Step 3: Create an installer with Inno Setup
Write-StepHeader "Step 3: Creating installer with Inno Setup"

try
{
    # Check if Inno Setup compiler exists
    if (-not (Test-Path $innoSetupCompiler))
    {
        Write-Status "Inno Setup" "Could not find Inno Setup compiler at $innoSetupCompiler" "error"
        Write-Host "Please install Inno Setup or specify the correct path" -ForegroundColor Red

        # Alternative path check
        $altInnoSetupCompiler = "C:\Program Files (x86)\Inno Setup 6\Compil32.exe"
        if (Test-Path $altInnoSetupCompiler)
        {
            Write-Status "Inno Setup" "Found alternative compiler at $altInnoSetupCompiler" "warning"
            $innoSetupCompiler = $altInnoSetupCompiler
        }
        else
        {
            exit 1
        }
    }
    else
    {
        Write-Status "Inno Setup" "Found at $innoSetupCompiler" "success"
    }

    # Find Inno Setup script
    $innoScripts = Get-ChildItem -Path $setupDir -Filter "*.iss" -File

    if ($innoScripts.Count -gt 0)
    {
        $innoScript = $innoScripts[0].FullName
        Write-Status "Setup Script" "Found at $innoScript" "success"

        # Run Inno Setup compiler
        Write-Status "Compiling" "Creating installer..." "info"

        $innoCommand = "& `"$innoSetupCompiler`" `"$innoScript`" /DOutputDir=`"$distPath`""
        Write-Host "Executing: $innoCommand" -ForegroundColor Yellow

        Invoke-Expression $innoCommand

        if ($LASTEXITCODE -eq 0)
        {
            $installerFiles = Get-ChildItem -Path $distPath -Filter "*.exe" -File
            if ($installerFiles.Count -gt 0)
            {
                Write-Status "Installer" "Successfully created at $( $installerFiles[0].FullName )" "success"
            }
            else
            {
                Write-Status "Installer" "Compilation successful but no installer found" "warning"
            }
        }
        else
        {
            Write-Status "Installer" "Compilation failed with exit code $LASTEXITCODE" "error"
        }
    }
    else
    {
        Write-Status "Setup Script" "No .iss files found in $setupDir" "error"

        # Search for ISS files in the main project directory
        $innoScripts = Get-ChildItem -Path $projectPath -Filter "*.iss" -File -Recurse

        if ($innoScripts.Count -gt 0)
        {
            Write-Status "Setup Script" "Found $( $innoScripts.Count ) .iss files in project directory" "warning"

            foreach ($script in $innoScripts)
            {
                Write-Host "  - $( $script.FullName )" -ForegroundColor Yellow
            }

            $useInnoScript = Read-Host "Select a script to use (enter full path or leave empty to skip)"

            if ($useInnoScript -and (Test-Path $useInnoScript))
            {
                $innoScript = $useInnoScript

                # Run Inno Setup compiler
                Write-Status "Compiling" "Creating installer..." "info"

                $innoCommand = "& `"$innoSetupCompiler`" `"$innoScript`" /DOutputDir=`"$distPath`""
                Write-Host "Executing: $innoCommand" -ForegroundColor Yellow

                Invoke-Expression $innoCommand

                if ($LASTEXITCODE -eq 0)
                {
                    $installerFiles = Get-ChildItem -Path $distPath -Filter "*.exe" -File
                    if ($installerFiles.Count -gt 0)
                    {
                        Write-Status "Installer" "Successfully created at $( $installerFiles[0].FullName )" "success"
                    }
                    else
                    {
                        Write-Status "Installer" "Compilation successful but no installer found" "warning"
                    }
                }
                else
                {
                    Write-Status "Installer" "Compilation failed with exit code $LASTEXITCODE" "error"
                }
            }
            else
            {
                Write-Status "Setup Script" "No script selected - skipping installer creation" "warning"
            }
        }
        else
        {
            Write-Status "Setup Script" "No .iss files found in the project" "error"
            Write-Host "Please create an Inno Setup script (.iss) to build an installer" -ForegroundColor Red
        }
    }
}
catch
{
    Write-Status "Installer Error" $_.Exception.Message "error"
}

# Step 4: Verify the build and installation package
Write-StepHeader "Step 4: Verifying build and installation package"

try
{
    # Check build output
    $exeFiles = Get-ChildItem -Path $buildPath -Filter "*.exe" -File -Recurse
    $dllFiles = Get-ChildItem -Path $buildPath -Filter "*.dll" -File -Recurse

    if ($exeFiles.Count -gt 0)
    {
        Write-Status "Executables" "Found $( $exeFiles.Count ) .exe files" "success"

        # Display the main executable
        foreach ($exe in $exeFiles | Where-Object { $_.Name -like "*Mistral*" -or $_.Name -eq "MistralSuite.exe" })
        {
            Write-Status "Main Executable" "$( $exe.Name ) ($([math]::Round($exe.Length / 1KB, 2) ) KB)" "success"
        }
    }
    else
    {
        Write-Status "Executables" "No .exe files found in build output" "error"
    }

    if ($dllFiles.Count -gt 0)
    {
        Write-Status "Libraries" "Found $( $dllFiles.Count ) .dll files" "success"
    }
    else
    {
        Write-Status "Libraries" "No .dll files found in build output" "warning"
    }

    # Check installer
    $installerFiles = Get-ChildItem -Path $distPath -Filter "*.exe" -File

    if ($installerFiles.Count -gt 0)
    {
        $installer = $installerFiles[0]
        Write-Status "Installer" "$( $installer.Name ) ($([math]::Round($installer.Length / 1MB, 2) ) MB)" "success"
        Write-Status "Ready for Distribution" "Yes" "success"

        # Offer to run the installer
        $runInstaller = Read-Host "Would you like to run the installer now? (y/n)"
        if ($runInstaller -eq "y")
        {
            Start-Process -FilePath $installer.FullName
            Write-Status "Installation" "Installer started" "info"
        }
    }
    else
    {
        Write-Status "Installer" "No installer found in $distPath" "warning"
        Write-Status "Ready for Distribution" "No - missing installer" "warning"
    }
}
catch
{
    Write-Status "Verification Error" $_.Exception.Message "error"
}

Write-StepHeader "Build and Installation Process Complete"

