param(
    [string]$SourceDir = "..\\CyberDeck\\tests\\snapshots",
    [string]$TargetDir = "test\\contracts",
    [switch]$Check
)

$ErrorActionPreference = "Stop"

$requiredFiles = @(
    "protocol_snapshot.json",
    "stream_offer_snapshot.json"
)

if (-not (Test-Path $SourceDir)) {
    Write-Host "Source snapshot directory is missing: $SourceDir"
    exit 0
}

if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir | Out-Null
}

$hadMismatch = $false

foreach ($name in $requiredFiles) {
    $src = Join-Path $SourceDir $name
    $dst = Join-Path $TargetDir $name
    if (-not (Test-Path $src)) {
        Write-Host "Missing source snapshot: $src"
        $hadMismatch = $true
        continue
    }

    if ($Check) {
        if (-not (Test-Path $dst)) {
            Write-Host "Missing local snapshot: $dst"
            $hadMismatch = $true
            continue
        }
        $srcHash = (Get-FileHash $src -Algorithm SHA256).Hash
        $dstHash = (Get-FileHash $dst -Algorithm SHA256).Hash
        if ($srcHash -ne $dstHash) {
            Write-Host "Snapshot mismatch: $name"
            $hadMismatch = $true
        }
        continue
    }

    Copy-Item $src $dst -Force
    Write-Host "Updated $name"
}

if ($Check -and $hadMismatch) {
    Write-Host "Contract snapshots are out of sync."
    exit 1
}

if ($Check) {
    Write-Host "Contract snapshots are in sync."
}
