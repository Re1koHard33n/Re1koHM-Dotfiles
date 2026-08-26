if status is-interactive
    fastfetch

    abbr -a gs  "git status"
    abbr -a ga  "git add"
    abbr -a gc  "git commit"
    abbr -a gp  "git push"
    abbr -a dc  "docker-compose"
    abbr -a dcu "docker-compose up -d"
    abbr -a ll  "ls -lah"
    abbr -a ..  "cd .."

    set -g fzf_preview_dir_cmd edir
end

if status is-login
    set_color '#81A1C1'; printf "\n▸ %s " (hostname); set_color normal
    printf "↑ %s " (uptime | awk '{print $3}' | sed 's/,$//')
    printf "⚡ %s " (uptime | grep -oP 'load average: \K[0-9.]+')
    printf "🧠 %s " (free | awk 'NR==2{printf "%.0f%%", $3/$2*100}')
    printf "💾 %s\n\n" (df / | awk 'NR==2{print $5}')
end


function mkcd
    mkdir -p $argv[1]; and cd $argv[1]
end

function extract
    if test -f $argv[1]
      switch $argv[1]
        case "*.tar.gz" "*.tgz"
          tar -xzf $argv[1]
        case '*.tar.bz2'
          tar -xjf $argv[1]
        case "*.zip"
          unzip $argv[1]
        case "*.rar"
          unrar x $argv[1]
        case "*.7z"
          7z x $argv[1]
        case '*'
          echo "Unsupported archive type"
      end
    else
      echo "File not found"
    end
end
