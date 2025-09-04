<#
.SYNOPSIS
    Ressurskonfigurasjon for MistralApp
.DESCRIPTION
    Definerer og setter opp optimal ressursallokering for MistralApp
    basert på systemkonfigurasjon og samtidighetsbehov med Adobe DC + Evermap
#>

# System Spesifikasjoner
$SystemSpecs = @{
    CPU = @{
        Model = "Ryzen 7 5800X"
        Cores = 8              # 8 fysiske kjerner
        Threads = 16          # 16 tråder (2 per kjerne)
        BaseSpeed = "3.8 GHz"
        BoostSpeed = "4.7 GHz"
        SMT = $true           # Simultaneous Multi-Threading aktivert
    }
    RAM = @{
        Total = 64  # GB
        Speed = 3600  # MHz
        Type = "DDR4"
    }
    GPU = @{
        Model = "GeForce RTX 3070"
        VRAM = 8  # GB
    }
    Storage = @{
        Model = "Samsung 990 Pro"
        Capacity = 2048  # GB
        Type = "NVMe"
    }
}

# Ressursallokering for MistralApp
$MistralResources = @{
    CPU = @{
        MaxCores = 6              # 75% av kjernene
        MaxThreads = 12           # 75% av trådene
        Priority = "AboveNormal"  # Høyere prioritet for rask respons
    }
    RAM = @{
        MaxUsage = 24            # GB (ca. 37.5% av total RAM)
        MinReserved = 4          # GB (minimum garantert)
        DynamicScaling = $true   # Tillat dynamisk skalering
    }
    GPU = @{
        MaxUsage = 60            # Prosent av tilgjengelig GPU
        CudaCores = "Auto"       # Automatisk CUDA-kjerne allokering
    }
    Disk = @{
        MaxIOPS = 70            # Prosent av maks IOPS
        BufferSize = 512        # MB for disk buffer
    }
}

# System Reserve - Garantert tilgjengelig for Windows og andre applikasjoner
$SystemReserve = @{
    RAM = @{
        Reserved = 12           # GB alltid tilgjengelig for system
        MinFree = 8            # GB minimum ledig RAM
    }
    CPU = @{
        ReservedThreads = 4    # 2 kjerner (4 tråder) alltid tilgjengelige
        MaxLoadTarget = 85     # Prosent maks CPU-last før throttling
    }
    ResponseThreshold = @{
        CPU = 90              # Prosent CPU-bruk før aktiv throttling
        RAM = 85              # Prosent RAM-bruk før swapping prevention
    }
}

# Adobe DC + Evermap Ressursreservasjon - Med dynamisk skalering
$AdobeResources = @{
    RAM = @{
        BaseReserved = 24      # GB normal reservasjon
        DynamicExtra = 16      # GB tilgjengelig ved OCR/store dokumenter
        OcrBoost = @{
            Trigger = "OCR"    
            MaxBoost = 38      # Maks RAM under OCR (holder tilbake SystemReserve)
            Duration = 300     
            AutoScale = $true  # Skalerer ned ved systemaktivitet
        }
    }
    CPU = @{
        BaseThreads = 6        # 3 kjerner (6 tråder) normalt
        MaxThreads = 10        # 5 kjerner (10 tråder) under OCR
        Priority = "High"      
        DynamicScaling = @{
            Enabled = $true
            ScaleDownTrigger = 80  # Prosent systemlast før nedskallering
            MinThreads = 4     # Minimum tråder under høy systemlast
        }
    }
}

# Ressursovervåkning og tilpasning
function Watch-SystemResources {
    $timer = New-Object System.Timers.Timer
    $timer.Interval = 2000  # 2 sekunder mellom sjekk

    $timer.Add_Elapsed({
        # Sjekk systemlast
        $cpuLoad = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue
        $availableRAM = Get-Counter '\Memory\Available MBytes' -ErrorAction SilentlyContinue

        if ($cpuLoad.CounterSamples.CookedValue -gt $SystemReserve.ResponseThreshold.CPU) {
            Write-Host "Høy CPU-last oppdaget, justerer ressursbruk..." -ForegroundColor Yellow
            Reduce-AppResourceUsage
        }

        $availableRAMGB = $availableRAM.CounterSamples.CookedValue / 1024
        if ($availableRAMGB -lt $SystemReserve.RAM.MinFree) {
            Write-Host "Lav tilgjengelig RAM, frigjør minne..." -ForegroundColor Yellow
            Free-SystemMemory
        }
    })

    $timer.Start()
}

# Dynamisk ressursjustering
function Reduce-AppResourceUsage {
    $mistralProc = Get-Process -Name "MistralApp" -ErrorAction SilentlyContinue
    $adobeProc = Get-Process -Name "Acrobat" -ErrorAction SilentlyContinue

    if ($mistralProc) {
        $mistralProc.PriorityClass = "BelowNormal"
    }

    if ($adobeProc) {
        # Behold normal prioritet for Adobe under OCR
        if (-not $script:InOCRMode) {
            $adobeProc.PriorityClass = "BelowNormal"
        }
    }
}

# Minnefrigjøring
function Free-SystemMemory {
    [System.GC]::Collect(2, $true, $true)

    # Reduser RAM-bruk for ikke-kritiske operasjoner
    if ($script:InOCRMode) {
        $AdobeResources.RAM.DynamicExtra = [Math]::Max(
            8,  # Minimum ekstra RAM under OCR
            $AdobeResources.RAM.DynamicExtra - 4  # Reduser med 4GB
        )
    }
}

# OCR-modus håndtering med systemhensyn
function Set-OcrMode {
    param([bool]$Enable)

    $script:InOCRMode = $Enable

    if ($Enable) {
        # Sjekk systemtilstand før OCR-boost
        $availableRAM = Get-Counter '\Memory\Available MBytes' -ErrorAction SilentlyContinue
        $availableRAMGB = $availableRAM.CounterSamples.CookedValue / 1024

        if ($availableRAMGB -lt $SystemReserve.RAM.MinFree) {
            Write-Warning "Begrenset RAM tilgjengelig. OCR-ytelse kan påvirkes."
            $AdobeResources.RAM.DynamicExtra = 8  # Redusert boost
        }
    }
    else {
        # Gjenopprett normal modus gradvis
        Start-GradualResourceRecovery
    }
}

# Start ressursovervåkning
Watch-SystemResources

# Justert MistralApp ressursallokering
$MistralResources = @{
    CPU = @{
        MaxCores = 4              # 4 kjerner
        MaxThreads = 8            # 8 tråder (2 per kjerne)
        Priority = "AboveNormal"  # Beholder høy prioritet
        DynamicScaling = $true    # Kan scale ned under OCR
        ThreadAffinity = @(1,3,5,7)  # Dedikerte kjerner for MistralApp
    }
    RAM = @{
        MaxUsage = 16            # Redusert til 16GB normalt
        MinReserved = 8          # Økt minimum til 8GB
        DynamicScaling = $true   # Kan reduseres til MinReserved under OCR
    }
    GPU = @{
        MaxUsage = 60            # Uendret
        CudaCores = "Auto"
    }
    Disk = @{
        MaxIOPS = 70            # Uendret
        BufferSize = 512        # MB
    }
}

# Ny funksjon for OCR-optimalisering
function Set-OcrOptimizedMode {
    param([bool]$Enable)

    if ($Enable) {
        Write-Host "Aktiverer OCR-optimalisert modus..." -ForegroundColor Cyan
        # Øk Adobe's ressurser
        $process = Get-Process -Name "Acrobat" -ErrorAction SilentlyContinue
        if ($process) {
            $process.PriorityClass = "High"
        }

        # Reduser MistralApp midlertidig
        $mistralProcess = Get-Process -Name "MistralApp" -ErrorAction SilentlyContinue
        if ($mistralProcess) {
            $mistralProcess.PriorityClass = "BelowNormal"
        }

        # Start timer for å gjenopprette normal modus
        $script:OcrTimer = New-Object System.Timers.Timer
        $script:OcrTimer.Interval = $AdobeResources.RAM.OcrBoost.Duration * 1000
        $script:OcrTimer.Add_Elapsed({
            Set-OcrOptimizedMode -Enable $false
            $script:OcrTimer.Stop()
        })
        $script:OcrTimer.Start()
    }
    else {
        Write-Host "Gjenoppretter normal ressursfordeling..." -ForegroundColor Cyan
        # Gjenopprett normal prioritet
        $processes = @("Acrobat", "MistralApp")
        foreach ($procName in $processes) {
            $proc = Get-Process -Name $procName -ErrorAction SilentlyContinue
            if ($proc) {
                $proc.PriorityClass = "Normal"
            }
        }
    }
}

# System Ressurs Management
function Set-MistralResourceLimits {
    # Sett prosess-prioritet
    $process = Get-Process -Name "MistralApp" -ErrorAction SilentlyContinue
    if ($process) {
        $process.PriorityClass = "AboveNormal"
    }

    # Konfigurer .NET garbage collection
    [System.Runtime.GCSettings]::LargeObjectHeapCompactionMode = 'CompactOnce'

    # Sett minnegrenser
    $maxMemory = [long]($MistralResources.RAM.MaxUsage * 1024 * 1024 * 1024)
    [System.GC]::MaxGeneration = 2

    # Konfigurer thread pool
    [int]$minWorkerThreads = [Math]::Max(4, $MistralResources.CPU.MaxThreads / 2)
    [int]$minIOThreads = [Math]::Max(4, $MistralResources.CPU.MaxThreads / 4)
    [System.Threading.ThreadPool]::SetMinThreads($minWorkerThreads, $minIOThreads)
    [System.Threading.ThreadPool]::SetMaxThreads($MistralResources.CPU.MaxThreads, $MistralResources.CPU.MaxThreads)
}

# Ressursovervåkning
function Start-ResourceMonitoring {
    $timer = New-Object System.Timers.Timer
    $timer.Interval = 5000  # 5 sekunder

    $timer.Add_Elapsed({
        $process = Get-Process -Name "MistralApp" -ErrorAction SilentlyContinue
        if ($process) {
            $ramUsage = $process.WorkingSet64 / 1GB
            $cpuUsage = $process.CPU

            if ($ramUsage -gt $MistralResources.RAM.MaxUsage) {
                Write-Warning "MistralApp overskrider RAM-grense: $([Math]::Round($ramUsage, 2)) GB"
                [System.GC]::Collect(2, $true, $true)
            }
        }
    })

    $timer.Start()
}

# Eksporter konfigurasjon
$Config = @{
    System = $SystemSpecs
    Mistral = $MistralResources
    Adobe = $AdobeResources
}

# Initialiser ressurshåndtering
function Initialize-ResourceManagement {
    Set-MistralResourceLimits
    Start-ResourceMonitoring

    Write-Host "Ressurskonfigurasjon initialisert:" -ForegroundColor Cyan
    Write-Host "- CPU: $($MistralResources.CPU.MaxCores) kjerner, $($MistralResources.CPU.MaxThreads) tråder"
    Write-Host "- RAM: $($MistralResources.RAM.MaxUsage) GB maks, $($MistralResources.RAM.MinReserved) GB minimum"
    Write-Host "- GPU: $($MistralResources.GPU.MaxUsage)% maks bruk"
    Write-Host "- Adobe reservert: $($AdobeResources.RAM.Reserved) GB RAM, $($AdobeResources.CPU.ReservedCores) kjerner"
}

Export-ModuleMember -Function Initialize-ResourceManagement -Variable Config
