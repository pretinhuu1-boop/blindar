# Checklist pós-download

Use logo após clonar/baixar o `blindar`. Tudo aqui é validação local — não
mexe em projetos reais.

## 1. Instalação correta

- [ ] Skill está em uma das pastas que o Claude Code procura:
  - Windows: `%USERPROFILE%\.claude\skills\blindar\`
  - Linux/macOS: `~/.claude/skills/blindar/`
- [ ] `SKILL.md` existe na raiz do skill (arquivo, não pasta)
- [ ] Pastas `pipeline/`, `agents/`, `templates/`, `scripts/` existem
- [ ] `VERSION` contém uma string semver válida (ex: `0.2.0`)

## 2. Versão atual

- [ ] Rodar `scripts/check-update.ps1` (Windows) e ler o output
- [ ] Confirmar que a versão local bate com a do GitHub
- [ ] Se houver versão nova, ler `CHANGELOG.md` antes de atualizar

## 3. Reconhecimento pelo Claude Code

- [ ] Abrir Claude Code em qualquer pasta
- [ ] Digitar `/skills` (ou perguntar "quais skills você tem?")
- [ ] Confirmar que `blindar` aparece na listagem
- [ ] A descrição mostrada bate com a do frontmatter de `SKILL.md`

## 4. Teste seco (sem rodar em projeto real)

- [ ] Criar uma pasta vazia descartável: `mkdir test-blindar && cd test-blindar`
- [ ] `git init` (skill exige projeto Git)
- [ ] Digitar `blindar` no Claude Code
- [ ] Confirmar que o skill **detecta corretamente** que não há suite/CI e
      reporta isso ao invés de tentar rodar (esse é o comportamento certo —
      ver "Quando NÃO rodar" em `SKILL.md`)

## 5. Primeiro uso em projeto real

Antes de invocar `blindar` num projeto que importa:

- [ ] `git status` está limpo (sem mudanças não-commitadas)
- [ ] Branch atual é mergível (geralmente `main` ou feature branch viva)
- [ ] Suite de testes atual está **verde** (`pytest` / `npm test` passa)
- [ ] CI está configurada e rodando (GitHub Actions, GitLab CI, etc.)
- [ ] Você tem permissão de merge nos PRs do repo
- [ ] Você está OK com o skill criar `sec.html` na raiz do projeto
- [ ] Você revisou os defaults em `SKILL.md` (round size ≤80 LOC,
      adversarial a cada 10 rounds, etc.)

## 6. Customização (opcional)

- [ ] Se você for forkar pra customizar: adicione seu fork como remote
- [ ] Se quiser desabilitar o auto-check: setar env var
      `BLINDAR_SKIP_UPDATE_CHECK=1`
- [ ] Se quiser ajustar defaults: edite a tabela "Defaults (não negocia)" do
      `SKILL.md` — mas saiba que defaults agressivos foram pagos em
      PR-vermelho-mergeado

## 7. Riscos aceitos

- [ ] Você entendeu o **launcher** (4 perguntas + menu de 19 módulos, ≤30s)
      na primeira execução em projeto novo (v0.8+)
- [ ] Você escolheu o **modo** de execução: **AUTO** (vai até o fim sem
      pausar), **SUPERVISIONADO** (pausa entre rounds), **ESCOLHIDOS**
      (roda só módulos selecionados)
- [ ] Em modo AUTO, ele **não pede mais confirmação** depois do launcher
      — roda até termination sozinho
- [ ] Você entendeu que ele **faz commits e abre PRs reais** no projeto
- [ ] Você entendeu que ele **espera CI verde** antes de mergear (não bypassa
      com `--no-verify`)
- [ ] Você sabe que pode interromper com `Ctrl+C` a qualquer momento — o
      último commit fica intacto
- [ ] Você sabe que `blindar --reset` apaga `.blindar/` e roda launcher de novo
- [ ] Se você escolheu `rigor = COMPLIANCE`, escolheu também um `target_framework`
      válido (`iso27001` / `nist-csf` / `cis` / `asvs-l1` / `asvs-l2` / `asvs-l3` /
      `pci-dss` / `soc2` / `lgpd`)

---

Checklist concluído? Rode `blindar` num projeto que precisa de hardening e
abra `sec.html` no browser pra acompanhar.
