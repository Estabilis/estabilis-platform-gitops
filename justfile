# Estabilis Platform GitOps — Development
# Justfile para setup e checks locais antes de commit/PR.
# A CI em .github/workflows/lint.yml aplica os mesmos hooks.

default:
    @just --list

# Setup one-time: instala pre-commit e ativa os git hooks no clone atual
install:
    @command -v pre-commit >/dev/null 2>&1 || pip install --user pre-commit
    pre-commit install
    @echo "pre-commit ativado. Hooks rodam automaticamente em cada commit."

# Roda o lint dos templates de ApplicationSet manualmente
lint:
    ./scripts/lint-applicationset-templates.sh

# Roda todos os pre-commit hooks sobre TODOS os arquivos do repo
# (útil antes de abrir PR para pegar drift histórico)
lint-all:
    pre-commit run --all-files
