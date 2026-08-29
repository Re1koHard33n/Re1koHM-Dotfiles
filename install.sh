#!/usr/bin/env bash
#
# Раскладка дотфайлов через GNU Stow на не-NixOS машинах.
# На NixOS то же самое делает hm-module.nix через home.file (recursive = true).
#
# Использование:
#   ./install.sh                     показать список пакетов
#   ./install.sh mozilla fish        разложить пакеты
#   ./install.sh -n mozilla          то же, но только показать, что будет сделано
#   ./install.sh -D mozilla          убрать разложенное
#
# Любые другие флаги stow пробрасываются как есть.

set -euo pipefail

# --no-folding — САМОЕ ВАЖНОЕ здесь, ради этого скрипт и существует.
#
# По умолчанию stow сворачивает дерево: если целевого каталога ещё нет, он
# создаёт ОДИН симлинк на весь каталог пакета. Для mozilla это означает
#     ~/.mozilla -> <репозиторий>/mozilla/.mozilla
# и Firefox начинает писать logins.db, key4.db, cookies.sqlite и places.sqlite
# прямо в рабочую копию git. Репозиторий публичный — это утечка паролей.
#
# С --no-folding stow создаёт настоящие каталоги и симлинчит только файлы,
# так что Firefox пишет своё состояние рядом с симлинками, а не в репозиторий.
# Опция отсутствует в выводе `stow --help` версии 2.4.1, но работает.
STOW_FLAGS=(--no-folding --target="$HOME")

die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

# Каталог репозитория. Не $PWD: скрипт должен работать при вызове откуда угодно.
# BASH_SOURCE[0], а не $0 — $0 содержит не то при `source ./install.sh`.
# readlink -f разыменовывает симлинки, если сам скрипт куда-то слинкован.
repo_dir=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
cd -- "$repo_dir"

# Пакет — любой каталог верхнего уровня, кроме служебных.
list_packages() {
    local d
    for d in */; do
        d=${d%/}
        case $d in
            .git | scripts) continue ;;
        esac
        printf '%s\n' "$d"
    done
}

if (( $# == 0 )); then
    printf 'Доступные пакеты:\n' >&2
    list_packages | sed 's/^/  /' >&2
    printf '\nПример: %s mozilla fish\n' "${BASH_SOURCE[0]}" >&2
    exit 0
fi

# Проверка здесь, а не выше: список пакетов должен показываться и на машине
# без stow (например, на NixOS, где раскладкой занимается Home Manager).
command -v stow >/dev/null || die "GNU Stow не установлен"

# exec, а не обычный вызов: процесс скрипта заменяется на stow, поэтому
# код возврата и сигналы (Ctrl-C) проходят напрямую, без посредника.
exec stow "${STOW_FLAGS[@]}" "$@"
