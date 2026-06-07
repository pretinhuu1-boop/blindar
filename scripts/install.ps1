# scripts/install.ps1
#
# Instala (ou atualiza) o skill blindar em ~/.claude/skills/blindar.
#
# Uso remoto:
#   iwr -useb https://raw.githubusercontent.com/<owner>/blindar/main/scripts/install.ps1 | iex
#
# Uso local (depois de clonar):
#   .\install.ps1

[CmdletBinding()]
param(
    [string]$Repo = $(if ($env:BLINDAR_REPO) { $env:BLINDAR_REPO } else { "pretinhuu1-boop/blindar" }),
    [string]$Branch = $(if ($env:BLINDAR_BRANCH) { $env:BLINDAR_BRANCH } else { "main" })
)

$ErrorActionPreference = 'Stop'

$Target = Join-Path $env:USERPROFILE ".claude\skills\blindar"
$ParentDir = Split-Path -Parent $Target

if (-not (Test-Path $ParentDir)) {
    New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null
}

if (Test-Path $Target) {
    Write-Host "blindar ja instalado em $Target" -ForegroundColor Yellow
    $isGit = Test-Path (Join-Path $Target ".git")
    if ($isGit) {
        Write-Host "Atualizando via git pull..."
        git -C $Target fetch --quiet
        git -C $Target pull --ff-only
        Write-Host "OK." -ForegroundColor Green
    } else {
        Write-Host "Instalacao existente nao e repo git. Para atualizar, remova manualmente:"
        Write-Host "  Remove-Item -Recurse -Force `"$Target`""
        Write-Host "Depois rode este script de novo."
        exit 1
    }
    exit 0
}

# Tenta git clone primeiro
$gitOk = $false
try {
    $null = Get-Command git -ErrorAction Stop
    Write-Host "Clonando $Repo -> $Target..."
    git clone --branch $Branch --depth 1 "https://github.com/$Repo.git" $Target
    $gitOk = $true
} catch {
    Write-Host "git nao disponivel ou clone falhou: $($_.Exception.Message)" -ForegroundColor Yellow
}

if (-not $gitOk) {
    Write-Host "Caindo pra download tarball (sem auto-update via git pull)..."
    $TarballUrl = "https://github.com/$Repo/archive/refs/heads/$Branch.tar.gz"
    $TempFile = Join-Path $env:TEMP "blindar-$Branch.tar.gz"
    Invoke-WebRequest -Uri $TarballUrl -OutFile $TempFile -UseBasicParsing
    # Requer tar (Win10+ tem nativo)
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    tar -xzf $TempFile -C $Target --strip-components=1
    Remove-Item $TempFile
}

Write-Host ""
Write-Host "blindar instalado em $Target" -ForegroundColor Green
Write-Host ""
Write-Host "Proximo passo: leia CHECKLIST.md"
Write-Host "  notepad `"$Target\CHECKLIST.md`""
Write-Host ""
