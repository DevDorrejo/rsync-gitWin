<#
.SYNOPSIS
    Installs MSYS2-based components (like rsync) into Git for Windows.

.DESCRIPTION
    Demonstrates manual argument parsing so that:
      - Unknown parameters show a usage message instead of causing a parse error.
      - -h or --help shows usage.
      - -InstallPath <value> sets the install path; defaults to "C:\Program Files\Git" if omitted or "".

#>

function Show-Usage {
    Write-Host "Usage:"
    Write-Host "  .\rsync-gitWin.ps1 [-InstallPath <path>] [-h | --help]"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host '  .\rsync-gitWin.ps1                      (uses default "C:\Program Files\Git")'
    Write-Host '  .\rsync-gitWin.ps1 -InstallPath "D:\Git" (installs to D:\Git\usr)'
    Write-Host '  .\rsync-gitWin.ps1 -h                    (displays help)'
    Write-Host ""
    Write-Host "If an unknown parameter is given, usage will be shown."
}

$InstallPath = "C:\Program Files\Git"
$ShowHelp = $false

for ($i = 0; $i -lt $args.Count; $i++) {
    $arg = $args[$i].ToLower()

    switch ($arg) {
        "-h" {
            $ShowHelp = $true
        }
        "--help" {
            $ShowHelp = $true
        }
        "-installpath" {
            # Check if there's another argument for the path
            if ($i + 1 -lt $args.Count) {
                $i++
                $InstallPath = $args[$i]
            }
            else {
                # The user typed "-InstallPath" but didn't provide the path
                Write-Host "Missing value after -InstallPath."
                Show-Usage
                return
            }
        }
        default {
            Write-Host "Unrecognized parameter: '$($args[$i])'"
            Show-Usage
            return
        }
    }
}

# If the user requested help, show usage and exit immediately
if ($ShowHelp) {
    Show-Usage
    return
}

# If InstallPath is empty or whitespace, revert to default
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = "C:\Program Files\Git"
}

# Store the full path of the script
$scriptPath = $MyInvocation.MyCommand.Path

# Detect the current shell
$CurrentShell = $PSVersionTable.PSEdition
$IsPwshAvailable = $null -ne (Get-Command pwsh -ErrorAction SilentlyContinue)

# Ensure we are in PowerShell 7 or relaunch if possible
if ($CurrentShell -eq "Core") {
    Write-Host "✅ Running in PowerShell 7 (pwsh). Proceeding..." -ForegroundColor Green
}
elseif ($IsPwshAvailable) {
    Write-Host "⚠️ This script requires PowerShell 7 (pwsh). Relaunching in pwsh..." -ForegroundColor Yellow
    Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}
else {
    Write-Host "❌ PowerShell 7 (pwsh) is not installed. Please install it from:" -ForegroundColor Red
    Write-Host "   🔗 https://aka.ms/powershell" -ForegroundColor Cyan
    Write-Host "   Then, re-run this script using pwsh." -ForegroundColor Yellow
    exit 1
}

function Request-Admin {
    # Check if running with Administrator privileges
    $isAdmin = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($isAdmin)
    $adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator

    if (-not $principal.IsInRole($adminRole)) {
        Write-Host "`nThis script should be run with Administrator privileges." -ForegroundColor Red
        $response = Read-Host "`nDo you want to relaunch it as Administrator? (Y/N)"

        if ($response -match "^[yY]$") {
            Write-Host "`nRelaunching the script with Administrator privileges..." -ForegroundColor Yellow
            Start-Sleep -Seconds 1

            Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
            exit
        }
        else {
            Write-Host "`nExiting..."
            exit 1
        }
    }
}

# Ask for Administrator privileges
Request-Admin
Write-Host "✅ Script is running with Administrator privileges!" -ForegroundColor Green

# Validate the base installation path
try {
    if (-not (Test-Path -LiteralPath $InstallPath)) {
        Write-Host "❌ The installation path '$InstallPath' does not exist. Aborting." -ForegroundColor Red
        Show-Usage
        exit 1
    }
}
catch {
    Write-Host "❌ Error verifying path '$($InstallPath)': $($_)" -ForegroundColor Red
    Show-Usage
    exit 1
}

# Define 'usr' and 'bin' subfolders
$GitUsrPath = Join-Path $InstallPath "usr"
if (-not (Test-Path $GitUsrPath)) {
    Write-Host "❌ Folder 'usr' not found in '$InstallPath'. Aborting." -ForegroundColor Red
    Show-Usage
    exit 1
}

$GitBinDir = Join-Path $GitUsrPath "bin"
$GitBinPath = Join-Path $GitBinDir  "zstd.exe"
if (-not (Test-Path $GitBinDir)) {
    Write-Host "❌ Folder 'bin' not found in '$GitUsrPath'. Aborting." -ForegroundColor Red
    Show-Usage
    exit 1
}

Write-Host "`nProceeding with MSYS2 installation in '$InstallPath'..."
Write-Host "Usr folder: $GitUsrPath"
Write-Host "Bin folder: $GitBinDir"

# Temporary download directory
$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "msys2_download"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

# MSYS2 repository URL and required packages
$Msys2URL = "https://repo.msys2.org/msys/x86_64/"
$RequiredPackages = @("zstd", "liblz4", "libxxhash", "libzstd", "rsync", "libopenssl")

Write-Host "`nDownloading MSYS2 package list..." -ForegroundColor Cyan
try {
    $PageContent = Invoke-WebRequest -Uri $Msys2URL -UseBasicParsing
}
catch {
    Write-Host "❌ Error downloading the package list: $($_)" -ForegroundColor Red
    exit 1
}

$Files = $PageContent.Links | Where-Object { $_.href -match "^(.*?)-\d+\.\d+\.\d+-\d+-x86_64\.pkg\.tar\.zst$" } | ForEach-Object { $_.href }

# Get the latest version of each required package
$LatestPackages = $RequiredPackages | ForEach-Object {
    $Package = $_

    $PackageVersions = $Files | Where-Object { $_ -match "^$Package-(\d+\.\d+\.\d+)-\d+-x86_64\.pkg\.tar\.zst$" } |
    Sort-Object {
        if ($_ -match "$Package-(\d+\.\d+\.\d+)-\d+") {
            [Version]$matches[1]
        }
        else {
            [Version]"0.0.0"
        }
    } -Descending | Select-Object -First 1

    $PackageVersions
}

# Download the filtered .zst files
foreach ($File in $LatestPackages) {
    if ([string]::IsNullOrEmpty($File)) {
        Write-Host "❌ Could not find a valid version for one of the required packages. Aborting." -ForegroundColor Red
        exit 1
    }

    $FileUrl = "$Msys2URL$File"
    $DestinationFile = Join-Path $TempDir $File

    if (-not (Test-Path $DestinationFile)) {
        Write-Host "Downloading: $FileUrl"
        try {
            Invoke-WebRequest -Uri $FileUrl -OutFile $DestinationFile
        }
        catch {
            Write-Host "❌ Error downloading $($FileUrl): $($_)" -ForegroundColor Red
            exit 1
        }
    }
    else {
        Write-Host "File already exists: $DestinationFile"
    }
}

# Download and extract zstd if not installed
$ZstdURL = "https://github.com/facebook/zstd/releases/download/v1.5.6/zstd-v1.5.6-win64.zip"
$ZstdZip = Join-Path $TempDir "zstd-v1.5.6-win64.zip"
$ZstdExtractPath = Join-Path $TempDir "zstd-extract"

if (-not (Test-Path $GitBinPath)) {
    if (-not (Test-Path $ZstdZip)) {
        Write-Host "Downloading: $ZstdURL"
        try {
            Invoke-WebRequest -Uri $ZstdURL -OutFile $ZstdZip
        }
        catch {
            Write-Host "❌ Error downloading zstd: $($_)" -ForegroundColor Red
            exit 1
        }
    }

    Write-Host "Extracting zstd..."
    try {
        Expand-Archive -Path $ZstdZip -DestinationPath $ZstdExtractPath -Force
    }
    catch {
        Write-Host "❌ Error extracting $($ZstdZip): $($_)" -ForegroundColor Red
        exit 1
    }

    $ZstdExe = Get-ChildItem -Path $ZstdExtractPath -Recurse -Filter "zstd.exe" | Select-Object -First 1
    if ($ZstdExe) {
        Write-Host "Moving zstd.exe to $GitBinDir..."
        Move-Item -Path $ZstdExe.FullName -Destination $GitBinDir -Force
    }
    else {
        Write-Host "❌ Error: zstd.exe was not found after extraction." -ForegroundColor Red
    }

    Remove-Item -Path $ZstdZip -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $ZstdExtractPath -Recurse -Force -ErrorAction SilentlyContinue
}

# Decompress .pkg.tar.zst files using zstd.exe
foreach ($File in $LatestPackages) {
    $FileZst = Join-Path $TempDir $File
    $FileTar = $FileZst -replace "\.zst$", ""

    if (Test-Path $FileZst) {
        Write-Host "Decompressing: $FileZst"
        Start-Process -FilePath $GitBinPath -ArgumentList "-d `"$FileZst`"" -NoNewWindow -Wait

        if (Test-Path $FileTar) {
            Write-Host "Extracting: $FileTar to the temporary directory"
            tar -xf $FileTar -C $TempDir --exclude=".*"
            Remove-Item -Path $FileTar -Force

            # Copy only usr contents to the final usr folder
            if (Test-Path (Join-Path $TempDir "usr")) {
                Write-Host "Copying the contents of 'usr' to $GitUsrPath"
                Copy-Item -Path (Join-Path $TempDir "usr\*") -Destination $GitUsrPath -Recurse -Force
                Remove-Item -Path (Join-Path $TempDir "usr") -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        Remove-Item -Path $FileZst -Force
    }
}

# Clean up temporary directory
Write-Host "`nCleaning up temporary files..."
Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n✅ Process completed! The packages were installed or updated in: $GitUsrPath" -ForegroundColor Green

# Pause before closing
Write-Host "`nPress any key to exit..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
