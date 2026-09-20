$ErrorActionPreference = "Stop"

$Repo = "C:\Users\GGPC\Documents\Codex\2026-09-20\work-from-a-fresh-fork-of\work"
$Launcher = Join-Path $Repo "scripts\launch_jev_lab.ps1"

if (-not (Test-Path $Launcher)) {
    throw "Launcher not found: $Launcher"
}

$Desktop = [Environment]::GetFolderPath("Desktop")

$ShortcutPath = Join-Path $Desktop "Jev Lab.lnk"

$PowerShell = Join-Path `
    $env:SystemRoot `
    "System32\WindowsPowerShell\v1.0\powershell.exe"

$Shell = New-Object -ComObject WScript.Shell
$Shortcut = $Shell.CreateShortcut($ShortcutPath)

$Shortcut.TargetPath = $PowerShell
$Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Launcher`""
$Shortcut.WorkingDirectory = $Repo
$Shortcut.Description = "Launch Jev Ultrafast browser lab"
$Shortcut.WindowStyle = 1

# Use Chrome's icon if available.
$ChromeCandidates = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
)

$Chrome = $ChromeCandidates |
    Where-Object { $_ -and (Test-Path $_) } |
    Select-Object -First 1

if ($Chrome) {
    $Shortcut.IconLocation = "$Chrome,0"
}

$Shortcut.Save()

Write-Host "Created desktop shortcut:" -ForegroundColor Green
Write-Host $ShortcutPath
