$ErrorActionPreference = "Stop"

$Repo = "C:\Users\GGPC\Documents\Codex\2026-09-20\work-from-a-fresh-fork-of\work"
$Cdp  = "http://127.0.0.1:9222"
$Ui   = "http://127.0.0.1:8766"

function Show-Error([string]$Message) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        $Message,
        "Jev Lab",
        "OK",
        "Error"
    ) | Out-Null
}

function Test-Url([string]$Url, [int]$Timeout = 2) {
    try {
        Invoke-WebRequest `
            -Uri $Url `
            -UseBasicParsing `
            -TimeoutSec $Timeout `
            | Out-Null

        return $true
    }
    catch {
        return $false
    }
}

# If Jev is already running, just open it.
if (Test-Url "$Ui/api/state") {
    Start-Process $Ui
    exit 0
}

if (-not (Test-Path $Repo)) {
    Show-Error "Jev repo not found:`n$Repo"
    exit 1
}

Set-Location $Repo

# Ultrafast should use the already-working direct CDP connection.
$env:BU_CDP_URL = $Cdp
$env:JEV_FOREGROUND = "1"

# Reuse an existing direct CDP connection, otherwise launch a dedicated Chrome.
if (-not (Test-Url "$Cdp/json/version")) {
    $ChromeCandidates = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )

    $Chrome = $ChromeCandidates |
        Where-Object { $_ -and (Test-Path $_) } |
        Select-Object -First 1

    if (-not $Chrome) {
        Show-Error "Google Chrome could not be found."
        exit 2
    }

    $Profile = Join-Path $env:LOCALAPPDATA "JevLab\ChromeProfile"
    New-Item -ItemType Directory -Force -Path $Profile | Out-Null

    Start-Process `
        -FilePath $Chrome `
        -ArgumentList @(
            "--remote-debugging-port=9222",
            "--user-data-dir=$Profile",
            "--no-first-run",
            "--no-default-browser-check",
            "about:blank"
        ) | Out-Null

    $CdpReady = $false
    for ($i = 0; $i -lt 60; $i++) {
        if (Test-Url "$Cdp/json/version" 1) {
            $CdpReady = $true
            break
        }

        Start-Sleep -Milliseconds 250
    }

    if (-not $CdpReady) {
        Show-Error "Jev Chrome started but CDP did not become available."
        exit 2
    }
}

# Pull a persisted user-level key into this process if one exists.
if (-not $env:TYPESAFE_API_KEY) {
    $userKey = [Environment]::GetEnvironmentVariable(
        "TYPESAFE_API_KEY",
        "User"
    )

    if ($userKey) {
        $env:TYPESAFE_API_KEY = $userKey
    }
}

# Otherwise ask for the Jev key without writing it to disk.
if (-not $env:TYPESAFE_API_KEY) {
    Write-Host ""
    Write-Host "TypeSafe/Jev API key is not configured." -ForegroundColor Yellow
    Write-Host "Paste it below. It will be kept only in this process." -ForegroundColor Yellow

    $secure = Read-Host "TYPESAFE_API_KEY" -AsSecureString

    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)

    try {
        $env:TYPESAFE_API_KEY =
            [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }

    if (-not $env:TYPESAFE_API_KEY) {
        Show-Error "No TypeSafe API key supplied."
        exit 3
    }
}

# Optional text helper.
# If a user-level key exists, inherit it.
if (-not $env:TEXT_MODEL_API_KEY) {
    $textKey = [Environment]::GetEnvironmentVariable(
        "TEXT_MODEL_API_KEY",
        "User"
    )

    if ($textKey) {
        $env:TEXT_MODEL_API_KEY = $textKey
    }
}

if (-not $env:TEXT_MODEL_API_KEY) {
    Write-Host ""
    Write-Host "No TEXT_MODEL_API_KEY found." -ForegroundColor DarkYellow
    Write-Host "Jev Lab will still start, but TYPE_TEXT actions will stop until a text-helper key is configured." -ForegroundColor DarkYellow
}

$UvCommand = Get-Command uv -ErrorAction SilentlyContinue
if ($UvCommand) {
    $Uv = $UvCommand.Source
}
else {
    $UvCandidates = @(
        "$env:USERPROFILE\.local\bin\uv.exe",
        (Get-ChildItem "$env:APPDATA\Python" -Filter uv.exe -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName)
    )
    $Uv = $UvCandidates |
        Where-Object { $_ -and (Test-Path $_) } |
        Select-Object -First 1
}

if (-not $Uv) {
    Show-Error "uv is not available on PATH."
    exit 4
}

# Launch Jev in its own visible terminal.
#
# Start-Process inherits the API keys and other environment variables
# from this launcher, without putting them in command-line arguments.
$Server = Start-Process `
    -FilePath "powershell.exe" `
    -ArgumentList @(
        "-NoExit",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        "Set-Location '$Repo'; & '$Uv' run jev"
    ) `
    -WorkingDirectory $Repo `
    -PassThru

Write-Host ""
Write-Host "Starting Jev Ultrafast..." -ForegroundColor Cyan

# Wait up to ~20 seconds for the local inspector.
$Ready = $false

for ($i = 0; $i -lt 80; $i++) {
    if ($Server.HasExited) {
        Show-Error "Jev exited before the UI became available."
        exit 5
    }

    if (Test-Url "$Ui/api/state" 1) {
        $Ready = $true
        break
    }

    Start-Sleep -Milliseconds 250
}

if (-not $Ready) {
    Show-Error @"
Jev started, but the inspector did not appear at:

$Ui

Check the Jev terminal for the error.
"@
    exit 6
}

Start-Process $Ui
