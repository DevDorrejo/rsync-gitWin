# rsync-gitWin: Install rsync in Git-Bash

## Overview
This PowerShell script installs `rsync` along with its dependencies in a Git-Bash terminal within an existing Git for Windows installation.

## Features
- Supports manual argument parsing.
- Displays usage instructions when unknown parameters are provided.
- Allows specifying a custom installation path.
- Ensures execution with PowerShell 7 (pwsh) and administrator privileges.
- Downloads and installs `rsync` and its required dependencies.
- Cleans up temporary files after installation.

## Usage
Run the script with the following options:

```
 .\rsync-gitWin.ps1 [-InstallPath <path>] [-h | --help]
```

### Examples
```powershell
 .\rsync-gitWin.ps1                      # Uses default "C:\Program Files\Git"
 .\rsync-gitWin.ps1 -InstallPath "D:\Git" # Installs to D:\Git\usr
 .\rsync-gitWin.ps1 -h                    # Displays help
```

### Parameters
- **`-InstallPath <path>`**: Specifies the installation directory. Defaults to `C:\Program Files\Git` if omitted.
- **`-h | --help`**: Displays usage instructions.

## Requirements
- Windows OS.
- Git for Windows installed.
- PowerShell 7 (pwsh) installed.
- Administrator privileges to run the script.

## Installation Process
1. The script verifies PowerShell 7 and restarts itself in `pwsh` if necessary.
2. It ensures administrator privileges are granted.
3. It validates the installation path and verifies the required `usr` and `bin` folders.
4. It downloads necessary MSYS2 packages containing `rsync` and its dependencies from the official repository.
5. It decompresses and installs the required binaries into the Git-Bash environment.
6. It cleans up temporary files.

## Troubleshooting
- **PowerShell 7 not installed:** Install PowerShell 7 from [Microsoft's official site](https://aka.ms/powershell).
- **Administrator privileges required:** Run the script with elevated permissions.
- **Invalid install path:** Ensure Git for Windows is installed in the specified directory.
- **Download errors:** Check internet connectivity or firewall settings.

## License
This script is provided under the MIT License.

## Author
Developed by Walddys Emmanuel Dorrejo Céspedes.
