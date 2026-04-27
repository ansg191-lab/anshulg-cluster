# shellcheck shell=bash
# .bash_profile - Executed for login shells
# Source .bashrc to ensure environment is loaded for login shells
if [ -f ~/.bashrc ]; then
  # shellcheck disable=SC1090
  . ~/.bashrc
fi
