<#
.SYNOPSIS
    Windows host path: builds the images described by config/*.ini with
    cloudbase/windows-openstack-imaging-tools (New-WindowsOnlineImage).

.DESCRIPTION
    Requirements (see README, "Alternative: Windows host"):
      - Windows 10/11 or Windows Server with Hyper-V and an external
        virtual switch named as in the ini files ("external");
      - Windows ADK Deployment Tools;
      - a clone of https://github.com/cloudbase/windows-openstack-imaging-tools
        with its submodules (git submodule update --init);
      - YOUR Windows Server ISO mounted (its install.wim path is -WimFilePath);
      - the virtio-win ISO (https://github.com/virtio-win/virtio-win-pkg-scripts).

    For each ini file a copy is written to the output directory with absolute
    paths, then New-WindowsOnlineImage runs on it. Run from an elevated
    PowerShell prompt.

.EXAMPLE
    .\scripts\build-all-editions.ps1 -ImagingToolsPath C:\src\windows-openstack-imaging-tools `
        -WimFilePath E:\sources\install.wim -VirtioIsoPath C:\iso\virtio-win.iso `
        -OutputPath C:\oic\output -Filter 'standard-*.ini'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ImagingToolsPath,
    [Parameter(Mandatory = $true)][string]$WimFilePath,
    [Parameter(Mandatory = $true)][string]$VirtioIsoPath,
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\output'),
    [string]$Filter = '*.ini'
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ImagingToolsPath = (Resolve-Path $ImagingToolsPath).Path
$WimFilePath = (Resolve-Path $WimFilePath).Path
$VirtioIsoPath = (Resolve-Path $VirtioIsoPath).Path
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$OutputPath = (Resolve-Path $OutputPath).Path

Import-Module (Join-Path $ImagingToolsPath 'WinImageBuilder.psm1')
Import-Module (Join-Path $ImagingToolsPath 'Config.psm1')
Import-Module (Join-Path $ImagingToolsPath 'UnattendResources\ini.psm1')

$iniFiles = Get-ChildItem -Path (Join-Path $repoRoot 'config') -Filter $Filter -File
if (-not $iniFiles) { throw "No ini file matches $Filter in config\" }

$failed = @()
foreach ($file in $iniFiles) {
    $name = $file.BaseName
    $config = Join-Path $OutputPath "$name.ini"
    Copy-Item -Path $file.FullName -Destination $config -Force

    $set = @{
        'DEFAULT'        = @{
            'wim_file_path' = $WimFilePath
            'image_path'    = (Join-Path $OutputPath "windows-server-2022-$name.qcow2")
        }
        'drivers'        = @{ 'virtio_iso_path' = $VirtioIsoPath }
        'cloudbase_init' = @{
            'cloudbase_init_config_path'            = (Join-Path $repoRoot 'config\cloud\cloudbase-init.conf')
            'cloudbase_init_unattended_config_path' = (Join-Path $repoRoot 'config\cloud\cloudbase-init-unattend.conf')
        }
    }
    foreach ($section in $set.Keys) {
        foreach ($key in $set[$section].Keys) {
            Set-IniFileValue -Path $config -Section $section -Key $key -Value $set[$section][$key]
        }
    }

    Write-Host "Building $name from $config"
    try {
        New-WindowsOnlineImage -ConfigFilePath $config
        Write-Host "Built $name"
    } catch {
        Write-Error "Build of $name failed: $_" -ErrorAction Continue
        $failed += $name
    }
}

if ($failed.Count -gt 0) {
    throw "Failed builds: $($failed -join ', ')"
}
