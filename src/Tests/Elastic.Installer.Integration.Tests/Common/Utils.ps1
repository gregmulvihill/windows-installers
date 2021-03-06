function Write-Log {
    [CmdletBinding()]
    Param
    (
        [Parameter(Position=0, Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias("M")]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [Alias("P")]
        [string]$Path,

        [Parameter(Mandatory=$false)]
        [Alias("L")]
        [ValidateSet("Error","Warn","Info","Debug","Default")]
        [string]$Level="Default",

        [Parameter(Mandatory=$false)]
        [Alias("N")]
        [switch]$DoNotOverwrite
    )

    Begin {
        $VerbosePreference = 'Continue'
        $DebugPreference = 'Continue'
    }
    Process {
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $LogMessage = "[$FormattedDate] [$($Level.ToUpper().PadRight(7, ' '))] $Message"
        switch ($Level)
        {
            'Error' {
                Write-Error $LogMessage
            }
            'Warn' {
                Write-Warning $LogMessage
            }
            'Info' {
                Write-Verbose $LogMessage
            }
            'Debug' {
                Write-Debug $LogMessage
            }
            'Default' {
                Write-Host $LogMessage
            }
        }

        if ($Path) {
            if ((Test-Path $Path) -and $DoNotOverwrite) {
                Write-Error "Log file $Path already exists but you specified not to overwrite. Either delete the file or specify a different name."
                return
            }
            elseif (!(Test-Path $Path)) {
                Write-Verbose "Creating $Path."
                New-Item $Path -Force -ItemType File | Out-Null
            }
            $LogMessage | Out-File -FilePath $Path -Append
        }
    }
    End {
    }
}

Set-Alias -Name log -Value Write-Log -Description "logs a message to console and optionally to file"

function Set-DebugMode() {
    log "setting Debug Mode" -l Debug
    $Global:DebugPreference = "Continue"
    $Global:VerbosePreference = "Continue"
    Set-StrictMode -version Latest
}

function Set-ProductionMode() {
    log "setting Production Mode" -l Debug
    $Global:DebugPreference = "SilentlyContinue"
    $Global:VerbosePreference = "SilentlyContinue"
    Set-StrictMode -Off
}

function Get-ProgramFilesFolder() {
    return ([Environment]::GetEnvironmentVariable("ProgramW6432"), [Environment]::GetFolderPath("ProgramFiles") -ne $null)[0]
}

function Set-RemoteSignedExecutionPolicy() {
    $policy = "RemoteSigned"
    $current = Get-ExecutionPolicy
    if ($current -ne $policy)
    {
        log "setting execution policy to $policy, currently $current" -l Debug
        Set-ExecutionPolicy $policy -Force
    }
}

function Add-Chocolatey() {
    $choco = where.exe choco
    if (!$choco) {
        log "chocolatey not installed on machine. installing now" -l Debug
        Set-RemoteSignedExecutionPolicy
        Invoke-WebRequest https://chocolatey.org/install.ps1 -UseBasicParsing | Invoke-Expression
        RefreshEnv | Out-Null
    }
}

function Test-AtlasToken() {
    $token = Get-ChildItem env:ATLAS_TOKEN
    if (!$token) {
        log "No ATLAS_TOKEN environment variable detected. Ensure that you have set up an account on https://atlas.hashicorp.com and generate an access token at https://atlas.hashicorp.com/settings/tokens" -l Error
        Exit
    }
}

function Test-HyperV() {
    Write-Host "run Hyper-V check"
    #Requires -RunAsAdministrator
    $HyperV = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All

    if ($HyperV -and ($HyperV.State -eq "Enabled")) {
        log "Hyper-V is enabled. If VirtualBox cannot start a VM, you _may_ need to disable this (Turn off in Windows features then restart) to allow VirtualBox to work" -l Warn
    }
    Write-Host "finished Hyper-V check"
}

function Add-Vagrant() {
    $vagrant = where.exe vagrant
    if (!$vagrant) {
        log "vagrant not installed on machine. installing now" -l Debug
        Add-Chocolatey
        choco install vagrant -y
        RefreshEnv | Out-Null
    }

    Add-Cygpath
}

function Add-Git() {
    $gitpath = where.exe git
    if (!$gitpath) {
        log "git not installed on machine. installing now" -l Debug
        Add-Chocolatey
        choco install git -y
        RefreshEnv | Out-Null
    }
}

# required to be in the PATH for Vagrant
function Add-Cygpath() {
    $cygpath = where.exe cygpath
    if (!$cygpath) {
        Add-Git
        $gitpath = where.exe git
        $parentDir = $gitpath | Split-Path | Split-Path
        $cygpath = Join-Path -Path $parentDir -ChildPath "usr\bin"
        log "Adding $cygpath to PATH Environment Variable" -l Debug
        $env:path += ";$cygpath"
        RefreshEnv | Out-Null
    }
}

function Invoke-IntegrationTests($location, $version) {
    cd $location
    vagrant up
    # run the pester bootstrapper on the target machine, from the target machine's synced folder.
    # TODO: Get other streams written back to host e.g. error stream, debug stream, etc.
    vagrant powershell -c "C:\common\PesterBootstrap.ps1 -Version $version"
    vagrant destroy -f
}

function Get-Installer([string] $location) {
    $exe = "elasticsearch*.msi"
    if ($location) {
        $exePath = Join-Path -Path $location -ChildPath $exe
        Write-Log "get windows installer from $exePath" -l Debug
        return Get-ChildItem -Path $exePath
    }
    else {
        return Get-ChildItem .\..\out\$exe
    }
}

function Add-Quotes (
        [System.Collections.ArrayList]
        [Parameter(Position=0)]
        $Exeargs)
{

    if (!$Exeargs) {
        return New-Object "System.Collections.ArrayList"
    }

    # double quote all argument values
    for ($i=0;$i -lt $Exeargs.Count; $i++) {
	    $Item = ([string]$Exeargs[$i]).Split('=')
        $Key = $Item[0]
        $Value = $Item[1]

        if (! $($Value.StartsWith("`""))) {
            $Value = "`"$Value"
        }
        if (($Value -eq "`"") -or (! $($Value.EndsWith("`"")))) {
            $Value = "$Value`""
        }
        $Exeargs[$i] = "$Key=$Value"
    }

    return $Exeargs
}

function Invoke-SilentInstall {
    [CmdletBinding()]
    Param (
        [System.Collections.ArrayList]
        [Parameter(Position=0)]
        $Exeargs
    )

    $QuotedArgs = Add-Quotes $Exeargs
    $Exe = Get-Installer
    log "running installer: msiexec.exe /i $Exe /qn /l install.log $QuotedArgs"
    $ExitCode = (Start-Process C:\Windows\System32\msiexec.exe -ArgumentList "/i $Exe /qn /l install.log $QuotedArgs" -Wait -PassThru).ExitCode

    if ($ExitCode) {
        Write-Host "last exit code not zero: $ExitCode"
        log "last exit code not zero: $ExitCode" -l Error
    }

    return $ExitCode
}

function Invoke-SilentUninstall {
    [CmdletBinding()]
    Param (
        [System.Collections.ArrayList]
        [Parameter(Position=0)]
        $Exeargs
    )

    $QuotedArgs = Add-Quotes $Exeargs
    $Exe = Get-Installer
    log "running installer: msiexec.exe /x $Exe /qn /l uninstall.log $QuotedArgs"
    $ExitCode = (Start-Process C:\Windows\System32\msiexec.exe -ArgumentList "/x $Exe /qn /l uninstall.log $QuotedArgs" -Wait -PassThru).ExitCode

    if ($ExitCode) {
        Write-Host "last exit code not zero: $ExitCode"
        log "last exit code not zero: $ExitCode" -l Error
    }

    return $ExitCode
}

function Ping-Node([System.Timespan]$Timeout) {
    if (!$Timeout) {
        $Timeout = New-Timespan -Seconds 3
    }

    $Result = @{
        Success = $false
        ShieldInstalled = $false
    }

    $StopWatch = [Diagnostics.Stopwatch]::StartNew()
    do {
        try {
            $Response = Invoke-RestMethod http://localhost:9200
            log "Elasticsearch version $($Response.version.number) running"
            $Result.Success = $true
            return $Result
        }
        catch {
            $Code = $_.Exception.Response.StatusCode.value__
            $Description = $_.Exception.Response.StatusDescription

            if ($_) {
                $Response = $_ | ConvertFrom-Json
                if ($Response -and $Response.status -and ($Response.status -eq 401)) {
                    # Shield has been set up on the node and we received an authenticated response back
                    log "Elasticsearch is running; received $Code authentication response back: $_" -l Debug
                    $Result.Success = $true
                    $Result.ShieldInstalled = $true
                    return $Result
                }
            }
            else {
                log "code: $Code, description: $Description" -l Warn
            }
        }
    } until ($StopWatch.Elapsed -gt $timeout)

    return $Result
}


function Get-ElasticsearchService() {
    return Get-Service elasticsearch*
}

function Get-ElasticsearchWin32Service() {
    return Get-WmiObject Win32_Service | Where-Object { $_.Name -match "Elasticsearch" }
}

function Get-ElasticsearchWin32Product() {
    return Get-WmiObject Win32_Product | Where-Object { $_.Vendor -match 'Elastic' }
}

function Get-MachineEnvironmentVariable($Name) {
    return [Environment]::GetEnvironmentVariable($Name,"Machine")
}

function Get-TotalPhysicalMemory() {
    return (Get-WmiObject Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1mb
}

function Add-ShieldCredentials($Username, $Password, $Roles) {
    if (!$Roles) {
        $Roles = @("superuser")
    }

    $Service = Get-ElasticsearchService
    $Service | Stop-Service

    $EsHome = Get-MachineEnvironmentVariable "ES_HOME"
    $EsConfig = Get-MachineEnvironmentVariable "ES_CONFIG"
    $EsUsersBat = Join-Path -Path $EsHome -ChildPath "bin\x-pack\users.bat"
    $ConcatRoles = [string]::Join(",", $Roles)

    # path.conf has to be double quoted to be passed as the complete argument for -E in PowerShell AND the value
    # itself has to also be double quoted to be passed to the batch script, so the inner double quotes need to be
    # escaped
    $ExitCode = & "$EsUsersBat" useradd $Username -p $Password -r $ConcatRoles -E "`"path.conf=$EsConfig`""
    if ($ExitCode) {
        throw "Last exit code : $ExitCode"
    }

    $Service | Start-Service
}
function Merge-Hashtables {
    $Output = @{}
    foreach ($Hashtable in ($Input + $Args)) {
        if ($Hashtable -is [Hashtable]) {
            foreach ($Key in $Hashtable.Keys) {
                $Output.$Key = $Hashtable.$Key
            }
        }
    }
    return $Output
}
