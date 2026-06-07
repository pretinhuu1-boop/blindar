# scripts/release.ps1
#
# Uso do DONO do repo. Faz bump de versao, atualiza CHANGELOG, taggeia,
# pusha e (se gh CLI disponivel) cria release no GitHub.
#
# Uso:
#   .\release.ps1 -Bump patch         # 0.2.0 -> 0.2.1
#   .\release.ps1 -Bump minor         # 0.2.0 -> 0.3.0
#   .\release.ps1 -Bump major         # 0.2.0 -> 1.0.0
#   .\release.ps1 -Version 0.5.0      # set explicito

[CmdletBinding()]
param(
    [ValidateSet("patch","minor","major")]
    [string]$Bump = "patch",
    [string]$Version,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$SkillRoot = Split-Path -Parent $PSScriptRoot
$VersionFile = Join-Path $SkillRoot "VERSION"
$ChangelogFile = Join-Path $SkillRoot "CHANGELOG.md"

if (-not (Test-Path (Join-Path $SkillRoot ".git"))) {
    Write-Host "Erro: $SkillRoot nao e repo git. Rode 'git init' primeiro." -ForegroundColor Red
    exit 1
}

# Estado limpo
$status = git -C $SkillRoot status --porcelain
if ($status) {
    Write-Host "Erro: working tree sujo. Commita ou esconde mudancas antes de release." -ForegroundColor Red
    Write-Host $status
    exit 1
}

$Current = (Get-Content $VersionFile -Raw).Trim()
Write-Host "Versao atual: $Current"

if (-not $Version) {
    $parts = $Current -split '\.'
    $maj = [int]$parts[0]; $min = [int]$parts[1]; $pat = [int]$parts[2]
    switch ($Bump) {
        "patch" { $pat++ }
        "minor" { $min++; $pat = 0 }
        "major" { $maj++; $min = 0; $pat = 0 }
    }
    $Version = "$maj.$min.$pat"
}

Write-Host "Nova versao: $Version" -ForegroundColor Green

if ($DryRun) {
    Write-Host "(dry-run, nada feito)"
    exit 0
}

# Bump VERSION
$Version | Out-File -FilePath $VersionFile -Encoding utf8 -NoNewline
Write-Host "Atualizado VERSION."

# Lembrete CHANGELOG (nao edita automatico — exige humano)
Write-Host ""
Write-Host "Edite CHANGELOG.md adicionando entrada para v$Version e salve." -ForegroundColor Yellow
Write-Host "Pressione ENTER quando terminar (ou Ctrl+C pra abortar)."
[void](Read-Host)

# Commit + tag
git -C $SkillRoot add VERSION CHANGELOG.md
git -C $SkillRoot commit -m "release: v$Version"
git -C $SkillRoot tag "v$Version"

Write-Host "Commit + tag v$Version criados localmente."
Write-Host "Pra publicar:"
Write-Host "  git -C `"$SkillRoot`" push origin main --tags"

# GitHub release opcional
$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) {
    Write-Host ""
    $resp = Read-Host "Criar GitHub release agora? (y/N)"
    if ($resp -eq "y") {
        git -C $SkillRoot push origin main --tags
        gh release create "v$Version" --title "v$Version" --notes-file (Join-Path $SkillRoot "CHANGELOG.md") --repo $env:BLINDAR_REPO
        Write-Host "Release publicado." -ForegroundColor Green
    }
}
