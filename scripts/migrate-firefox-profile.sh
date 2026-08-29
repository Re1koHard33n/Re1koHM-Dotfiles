#!/usr/bin/env bash
#
# Разовый переезд существующего профиля Firefox на детерминированное имя.
#
# Firefox генерирует имя каталога профиля случайно (fi5qa6bi.default), поэтому
# на каждой машине оно своё, и дотфайл с фиксированным путём разложить некуда.
# Скрипт переименовывает профиль в "default" — то имя, которое прописано в
# mozilla/.config/mozilla/firefox/profiles.ini.
#
# Нужен ТОЛЬКО на машинах, где Firefox уже запускался до раскладки дотфайлов.
# На чистой машине не нужен: Firefox прочитает наш profiles.ini и создаст
# каталог "default" сам.
#
# Порядок: сначала этот скрипт, потом раскладка (./install.sh mozilla
# или home-manager switch).
#
# Использование:
#   ./scripts/migrate-firefox-profile.sh           показать план, ничего не менять
#   ./scripts/migrate-firefox-profile.sh --apply   выполнить
#   ./scripts/migrate-firefox-profile.sh --apply --force   игнорировать lock профиля

set -euo pipefail

TARGET_NAME=default        # должно совпадать с Path= в profiles.ini
APPLY=0
FORCE=0

# ── вывод ────────────────────────────────────────────────────────────────────
# Всё диагностическое — в stderr, чтобы не мешалось при перенаправлении вывода.
info() { printf '  %s\n' "$*" >&2; }
warn() { printf 'внимание: %s\n' "$*" >&2; }
die()  { printf 'ошибка: %s\n' "$*" >&2; exit 1; }

# Обёртка для всех операций, меняющих файловую систему.
# Без --apply только печатает команду; %q экранирует так, что строку
# можно скопировать в терминал и выполнить руками.
run() {
    if (( APPLY )); then
        "$@"
    else
        printf '  [план] '; printf '%q ' "$@"; printf '\n'
    fi >&2
}

# ── аргументы ────────────────────────────────────────────────────────────────
while (( $# )); do
    case $1 in
        --apply) APPLY=1 ;;
        --force) FORCE=1 ;;
        -h | --help) sed -n '2,/^set -euo/p' -- "$0" | sed 's/^#\{0,1\} \{0,1\}//;$d' >&2; exit 0 ;;
        *) die "неизвестный аргумент: $1" ;;
    esac
    shift
done

# ── пути ─────────────────────────────────────────────────────────────────────
# XDG-раскладка. Firefox 154 использует её, если ~/.mozilla/firefox не существует.
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
cache_home=${XDG_CACHE_HOME:-$HOME/.cache}
base=$config_home/mozilla/firefox
cache_base=$cache_home/mozilla/firefox
ini=$base/profiles.ini
legacy=$HOME/.mozilla/firefox

# ── разбор profiles.ini ──────────────────────────────────────────────────────
# Возвращает Path= того профиля, у которого Default=1; если такого нет —
# Path= первого профиля в файле. Формат ini простой, внешние утилиты не нужны.
parse_default_profile() {
    local file=$1
    local line key value
    local in_profile=0 cur_path='' cur_default=0
    local default_path='' first_path=''

    # Сохранить накопленную секцию. Вызывается при переходе к следующей
    # секции и ещё раз после цикла — иначе последняя секция потеряется.
    _flush() {
        (( in_profile )) || return 0
        [[ -n $cur_path ]] || return 0
        [[ -n $first_path ]] || first_path=$cur_path
        if (( cur_default )) && [[ -z $default_path ]]; then
            default_path=$cur_path
        fi
        return 0
    }

    # `|| [[ -n $line ]]` — чтобы не потерять последнюю строку файла,
    # если она без завершающего перевода строки.
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}                      # на случай CRLF
        if [[ $line == \[*\] ]]; then
            _flush
            if [[ $line == \[Profile* ]]; then in_profile=1; else in_profile=0; fi
            cur_path=''
            cur_default=0
            continue
        fi
        (( in_profile )) || continue
        [[ $line == *=* ]] || continue
        key=${line%%=*}
        value=${line#*=}
        case $key in
            Path)    cur_path=$value ;;
            Default) [[ $value == 1 ]] && cur_default=1 || cur_default=0 ;;
        esac
    done < "$file"
    _flush

    printf '%s\n' "${default_path:-$first_path}"
}

# ── занят ли профиль работающим Firefox ──────────────────────────────────────
# Firefox зашивает PID владельца в симлинк lock: "127.0.0.2:+3641".
# Способ не зависит от имени процесса — а оно разное на разных дистрибутивах
# (на NixOS это ".firefox-wrapped", и ядро режет его до 15 символов,
# поэтому pgrep -x firefox не находит ничего, хотя браузер работает).
#
# Проверять НАЛИЧИЕ lock бессмысленно: файл остаётся и после нормального
# выхода. Значение имеет только то, жив ли зашитый в него процесс.
profile_is_locked() {
    local link pid
    # -L, а не -e: lock указывает на несуществующий "файл" 127.0.0.2:+PID,
    # поэтому -e (разыменовывает) вернёт false даже для работающего Firefox.
    [[ -L $1/lock ]] || return 1
    link=$(readlink -- "$1/lock") || return 1
    pid=${link##*+}                             # "127.0.0.2:+3641" -> "3641"
    [[ $pid == [0-9]* ]] || return 1
    kill -0 "$pid" 2>/dev/null                  # ничего не убивает, только проверяет
}

# ── проверки ─────────────────────────────────────────────────────────────────
printf 'Проверки:\n' >&2

[[ -d $base ]] || die "каталог профилей не найден: $base"

# Скрипт должен переживать повторный запуск. После успешного прогона
# profiles.ini унесён в .pre-dotfiles, и определять исходный профиль уже не по
# чему — но это не ошибка, а признак, что работа сделана.
if [[ ! -e $ini ]]; then
    if [[ -d $base/$TARGET_NAME ]]; then
        info "profiles.ini отсутствует, каталог '$TARGET_NAME' на месте — миграция уже выполнена"
        printf '\nОсталось разложить дотфайлы:\n' >&2
        printf '  ./install.sh mozilla                 (stow)\n' >&2
        printf '  home-manager switch --flake ...      (NixOS)\n' >&2
        exit 0
    fi
    die "не найден $ini — Firefox здесь ещё не запускался, миграция не нужна"
fi

# Если ~/.mozilla/firefox существует, Firefox уйдёт туда и XDG-путь
# проигнорирует. Тогда весь переезд бессмысленен: дотфайлы лягут в .config,
# а браузер будет читать из ~/.mozilla.
if [[ -e $legacy ]]; then
    die "существует $legacy — Firefox предпочтёт его XDG-пути. Удалите или перенесите его содержимое."
fi
info "ok: $legacy отсутствует, XDG-путь будет использован"

src_name=$(parse_default_profile "$ini")
[[ -n $src_name ]] || die "не удалось определить профиль по умолчанию в $ini"

if [[ $src_name == "$TARGET_NAME" ]]; then
    info "профиль уже называется '$TARGET_NAME' — переносить нечего"
    migrate=0
else
    migrate=1
fi

src=$base/$src_name
dst=$base/$TARGET_NAME

if (( migrate )); then
    [[ -d $src ]] || die "профиль '$src_name' указан в profiles.ini, но каталога нет: $src"
    # mv в СУЩЕСТВУЮЩИЙ каталог положил бы профиль внутрь него
    # ($dst/$src_name), а не переименовал. Поэтому проверяем заранее.
    [[ -e $dst ]] && die "целевой каталог уже существует: $dst (уберите его вручную)"
    info "ok: $src_name -> $TARGET_NAME"

    if profile_is_locked "$src"; then
        if (( FORCE )); then
            warn "профиль занят работающим Firefox, но указан --force"
        else
            die "Firefox запущен и держит профиль. Закройте браузер (или --force, если PID переиспользован после краха)."
        fi
    else
        info "ok: профиль не занят"
    fi

    # mv в пределах одной ФС — это rename(2), атомарная операция ядра:
    # каталог либо целиком на новом месте, либо целиком на старом.
    # На разных ФС mv деградирует до copy+unlink и атомарность теряется.
    if [[ $(stat -c %d -- "$src") != $(stat -c %d -- "$base") ]]; then
        warn "$src и $base на разных файловых системах — перенос не будет атомарным"
    else
        info "ok: одна файловая система, перенос атомарен"
    fi
fi

# ── план ─────────────────────────────────────────────────────────────────────
printf '\nДействия:\n' >&2

if (( migrate )); then
    run mv -- "$src" "$dst"

    # Кэш живёт отдельно от профиля и привязан к его имени. Не переносим,
    # а удаляем: это именно кэш, Firefox пересоберёт его сам, а старый
    # каталог иначе останется мусором навсегда.
    if [[ -d $cache_base/$src_name ]]; then
        run rm -rf -- "${cache_base:?}/${src_name:?}"
    fi

    # compatibility.ini содержит абсолютный путь к сборке Firefox
    # (LastPlatformDir=/nix/store/...). После переезда он всё равно неверен;
    # удаление заставляет Firefox пересчитать пути на первом запуске.
    if [[ -f $dst/compatibility.ini || -f $src/compatibility.ini ]]; then
        run rm -f -- "$dst/compatibility.ini"
    fi
fi

# profiles.ini заменит дотфайл. Home Manager откажется активироваться,
# если на месте будущего симлинка лежит обычный файл:
#   "Existing file '...' would be clobbered"
# Поэтому убираем его заранее, сохранив копию.
if [[ -f $ini && ! -L $ini ]]; then
    run mv -- "$ini" "$ini.pre-dotfiles"
elif [[ -L $ini ]]; then
    info "profiles.ini уже симлинк — оставляю как есть"
fi

# ── итог ─────────────────────────────────────────────────────────────────────
if (( APPLY )); then
    printf '\nГотово. Теперь разложите дотфайлы:\n' >&2
    printf '  ./install.sh mozilla                 (stow)\n' >&2
    printf '  home-manager switch --flake ...      (NixOS)\n' >&2
else
    printf '\nЭто был предпросмотр, ничего не изменено.\n' >&2
    printf 'Для выполнения запустите с --apply\n' >&2
fi
