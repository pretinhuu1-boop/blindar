# scripts/check-update.ps1
#
# Compara VERSION local com a versão no GitHub. Avisa se houver
# atualização. Cacheia resposta por 24h em .last-check.
#
# Uso:
#   .\check-update.ps1            # modo verboso (padrão)
#   .\check-update.ps1 -Quiet     # silencia se não houver update
#
# Desativar de vez:
#   $env:BLINDAR_SKIP_UPDATE_CHECK = "1"
#
# Configurar repo:
#   $env:BLINDAR_REPO = "owner/blindar"   # padrão abaixo

[CmdletBinding()]
param(
    [switch]$Quiet,
    [switch]$Force  # ignora cache
)

$ErrorActionPreference = 'Stop'

if ($env:BLINDAR_SKIP_UPDATE_CHECK -eq "1") {
    if (-not $Quiet) { Write-Host "blindar: update check desativado (BLINDAR_SKIP_UPDATE_CHECK=1)" }
    exit 0
}

$Repo = if ($env:BLINDAR_REPO) { $env:BLINDAR_REPO } else { "pretinhuu1-boop/blindar" }
$Branch = if ($env:BLINDAR_BRANCH) { $env:BLINDAR_BRANCH } else { "main" }

$SkillRoot = Split-Path -Parent $PSScriptRoot
$LocalVersionFile = Join-Path $SkillRoot "VERSION"
$CacheFile = Join-Path $SkillRoot ".last-check"

if (-not (Test-Path $LocalVersionFile)) {
    Write-Host "blindar: VERSION local nao encontrado em $LocalVersionFile" -ForegroundColor Yellow
    exit 1
}

$LocalVersion = (Get-Content $LocalVersionFile -Raw).Trim()

# Cache 24h
if (-not $Force -and (Test-Path $CacheFile)) {
    $cache = Get-Content $CacheFile -Raw | ConvertFrom-Json
    $age = (Get-Date) - [DateTime]::Parse($cache.checked_at)
    if ($age.TotalHours -lt 24) {
        if ($cache.remote_version -ne $LocalVersion) {
            Write-Host "blindar v$($cache.remote_version) disponivel (local: v$LocalVersion). Ver CHANGELOG.md" -ForegroundColor Yellow
        } elseif (-not $Quiet) {
            Write-Host "blindar v$LocalVersion (atualizado, ultima checagem ha $([int]$age.TotalHours)h)"
        }
        exit 0
    }
}

# Fetch remoto
$Url = "https://raw.githubusercontent.com/$Repo/$Branch/VERSION"
try {
    $RemoteVersion = (Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5).Content.Trim()
} catch {
    if (-not $Quiet) {
        Write-Host "blindar: nao foi possivel checar update ($($_.Exception.Message))" -ForegroundColor DarkGray
    }
    exit 0  # nao bloqueia
}

# Atualiza cache
@{
    checked_at = (Get-Date).ToString("o")
    local_version = $LocalVersion
    remote_version = $RemoteVersion
} | ConvertTo-Json | Out-File -FilePath $CacheFile -Encoding utf8

if ($RemoteVersion -ne $LocalVersion) {
    Write-Host ""
    Write-Host "  blindar v$RemoteVersion disponivel" -ForegroundColor Yellow
    Write-Host "  Voce esta em v$LocalVersion"
    Write-Host "  Atualizar: git -C `"$SkillRoot`" pull --ff-only"
    Write-Host "  CHANGELOG: https://github.com/$Repo/blob/$Branch/CHANGELOG.md"
    Write-Host ""
} elseif (-not $Quiet) {
    Write-Host "blindar v$LocalVersion (atualizado)"
}
