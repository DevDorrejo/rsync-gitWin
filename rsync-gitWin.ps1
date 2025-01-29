# Get the script path at the beginning
$scriptPath = $MyInvocation.MyCommand.Path

# Detect the current shell
$CurrentShell = $PSVersionTable.PSEdition
$IsPwshAvailable = $null -ne (Get-Command pwsh -ErrorAction SilentlyContinue)

# Determine the best course of action
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

function ask_for_admin {
    # Check if running as Administrator
    $isAdmin = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($isAdmin)
    $adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator

    if (-Not $principal.IsInRole($adminRole)) {
        Write-Host "`nThis script should be run with Administrator privileges." -ForegroundColor Red
        $response = Read-Host "`nDo you want to relaunch it as Administrator? (Y/N)"

        if ($response -match "^[yY]$") {
            Write-Host "`nRelaunching the script with Administrator privileges..." -ForegroundColor Yellow
            Start-Sleep -Seconds 1

            # Relaunch the script with Administrator privileges
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
ask_for_admin

Write-Host "✅ Script is running with Administrator privileges!" -ForegroundColor Green

# Configure the temporary working directory
$TempDir = [System.IO.Path]::GetTempPath() + "msys2_download"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

# Target Git usr directory
$GitUsrPath = "C:\Program Files\Git\usr"
$GitBinDir = "$GitUsrPath\bin"
$GitBinPath = "$GitBinDir\zstd.exe"

# MSYS2 repository URL
$Msys2URL = "https://repo.msys2.org/msys/x86_64/"

# List of required packages
$RequiredPackages = @("zstd", "liblz4", "libxxhash", "libzstd", "rsync", "libopenssl")

# Fetch MSYS2 package list
$PageContent = Invoke-WebRequest -Uri $Msys2URL -UseBasicParsing
$Files = $PageContent.Links | Where-Object { $_.href -match "^(.*?)-\d+\.\d+\.\d+-\d+-x86_64\.pkg\.tar\.zst$" } | ForEach-Object { $_.href }

# Get only the latest version of each package (fixed version sorting)
$LatestPackages = $RequiredPackages | ForEach-Object {
    $Package = $_

    # Get all versions of the package
    $PackageVersions = $Files | Where-Object { $_ -match "^$Package-(\d+\.\d+\.\d+)-\d+-x86_64\.pkg\.tar\.zst$" } |
    Sort-Object {
        if ($_ -match "$Package-(\d+\.\d+\.\d+)-\d+") {
            [Version]$matches[1]
        }
        else {
            [Version]"0.0.0"  # Default version if no match
        }
    } -Descending | Select-Object -First 1

    $PackageVersions
}

# Download only the filtered files
foreach ($File in $LatestPackages) {
    $FileUrl = "$Msys2URL$File"
    $DestinationFile = "$TempDir\$File"

    if (-not (Test-Path $DestinationFile)) {
        Write-Host "Downloading: $FileUrl"
        Invoke-WebRequest -Uri $FileUrl -OutFile $DestinationFile
    }
    else {
        Write-Host "File already exists: $DestinationFile"
    }
}

# Download and extract zstd if not already installed
$ZstdURL = "https://github.com/facebook/zstd/releases/download/v1.5.6/zstd-v1.5.6-win64.zip"
$ZstdZip = "$TempDir\zstd-v1.5.6-win64.zip"
$ZstdExtractPath = "$TempDir\zstd-extract"

if (-not (Test-Path $GitBinPath)) {
    if (-not (Test-Path $ZstdZip)) {
        Write-Host "Downloading: $ZstdURL"
        Invoke-WebRequest -Uri $ZstdURL -OutFile $ZstdZip
    }

    # Extract zstd
    Write-Host "Extracting zstd..."
    Expand-Archive -Path $ZstdZip -DestinationPath $ZstdExtractPath -Force

    # Move zstd.exe to C:\Program Files\Git\usr\bin
    $ZstdExe = Get-ChildItem -Path $ZstdExtractPath -Recurse -Filter "zstd.exe" | Select-Object -First 1
    if ($ZstdExe) {
        Write-Host "Moving zstd.exe to $GitBinDir..."
        Move-Item -Path $ZstdExe.FullName -Destination $GitBinPath -Force
    }
    else {
        Write-Host "❌ Error: zstd.exe not found after extraction." -ForegroundColor Red
    }

    # Clean up zstd temporary files
    Remove-Item -Path $ZstdZip -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $ZstdExtractPath -Recurse -Force -ErrorAction SilentlyContinue
}

# Decompress .pkg.tar.zst files using zstd.exe
foreach ($File in $LatestPackages) {
    $FileZst = "$TempDir\$File"
    $FileTar = $FileZst -replace "\.zst$", ""

    if (Test-Path $FileZst) {
        Write-Host "Decompressing: $FileZst"
        Start-Process -FilePath $GitBinPath -ArgumentList "-d `"$FileZst`"" -NoNewWindow -Wait

        # Extract the .tar file in the temporary directory
        if (Test-Path $FileTar) {
            Write-Host "Extracting: $FileTar to temporary directory"
            tar -xf $FileTar -C $TempDir --exclude=".*"
            Remove-Item -Path $FileTar -Force

            # Copy only the contents of usr to Git usr
            if (Test-Path "$TempDir\usr") {
                Write-Host "Copying only contents of usr to $GitUsrPath"
                Copy-Item -Path "$TempDir\usr\*" -Destination $GitUsrPath -Recurse -Force
                Remove-Item -Path "$TempDir\usr" -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # Remove the original .zst file after decompression
        Remove-Item -Path $FileZst -Force
    }
}

# Clean up temporary directory
Write-Host "Cleaning up temporary files..."
Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "✅ Extraction and setup completed in: $GitUsrPath" -ForegroundColor Green

# Wait for user input before closing
Write-Host "`nPress any key to exit..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")