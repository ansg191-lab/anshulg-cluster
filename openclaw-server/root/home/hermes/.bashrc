# shellcheck shell=bash
# Enable 256 colors
export TERM=xterm-256color
export COLORTERM=truecolor

# Add local bin to PATH
export PATH="/home/hermes/.local/bin:/home/hermes/.local/bin:$PATH"

# Color support for common tools
export CLICOLOR=1
export LS_COLORS='di=34:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43'

# Aliases
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias ll='ls -lah'

# # D-Bus session for systemd access
# XDG_RUNTIME_DIR="/run/user/$(id -u)"
# export XDG_RUNTIME_DIR
# if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
#   export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
# fi

# Homebrew
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"

# # Node Compile Cache
# export NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache
# export OPENCLAW_NO_RESPAWN=1
