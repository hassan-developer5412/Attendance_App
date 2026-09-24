$ErrorActionPreference = 'Stop'

Write-Host 'Enabling Flutter Windows desktop support...'
flutter config --enable-windows-desktop

if (-not (Test-Path 'windows')) {
    Write-Host 'Generating the Windows platform files for this project...'
    flutter create --platforms=windows .
} else {
    Write-Host 'windows/ already exists; leaving it unchanged.'
}

Write-Host 'Windows support is ready. Run: flutter run -d windows'
