$ErrorActionPreference = "Stop"

$iniFiles = Get-ChildItem -Path "config" -Filter "*.ini"

foreach ($file in $iniFiles) {
    Write-Host "▶️ Building image from $($file.FullName)..."

    & .\WindowsImageGenerator.ps1 -ConfigurationFilePath $file.FullName

    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Failed to build image from $($file.Name)"
        exit 1
    } else {
        Write-Host "✅ Successfully built image from $($file.Name)"
    }
}
