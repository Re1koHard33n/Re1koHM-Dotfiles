if [[ $- == *i* ]]; then
    fastfetch

    alias gs="git status"
    alias ga="git add"
    alias gc="git commit"
    alias gp="git push"
    alias dc="docker-compose"
    alias dcu="docker-compose up -d"
    alias ll="ls -lah"
    alias ..="cd .."

    export FZF_ALT_C_OPTS="--preview 'edir {}'"
fi

if [[ -o login ]]; then
    autoload -U colors && colors

    HOSTNAME_STR=$(hostname)
    UPTIME_STR=$(uptime | awk '{print $3}' | sed 's/,$//')
    LOAD_STR=$(uptime | grep -oP 'load average: \K[0-9.]+')
    MEM_STR=$(free | awk 'NR==2{printf "%.0f%%", $3/$2*100}')
    DISK_STR=$(df / | awk 'NR==2{print $5}')

    print -P "\n%F{#81A1C1}▸ $HOSTNAME_STR %f↑ $UPTIME_STR ⚡ $LOAD_STR 🧠 $MEM_STR 💾 $DISK_STR\n"
fi


function mkcd() {
    mkdir -p "$1" && cd "$1"
}

function extract() {
    if [ -f "$1" ]; then
        case "$1" in
            *.tar.gz|*.tgz) tar -xzf "$1" ;;
            *.tar.bz2)      tar -xjf "$1" ;;
            *.zip)          unzip "$1"    ;;
            *.rar)          unrar x "$1"  ;;
            *.7z)           7z x "$1"     ;;
            *)              echo "Unsupported archive type" ;;
        esac
    else
        echo "File not found"
    fi
}

bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char
