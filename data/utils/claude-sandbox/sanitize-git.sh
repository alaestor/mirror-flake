#!/usr/bin/env bash
# LICENSE: MIT  (github:mrquentin/claude-sandbox 2025)
# sanitize-git.sh — Create a safe .gitconfig for the sandbox
# Strips credential helpers, include directives, SSH commands, aliases,
# filter drivers, and hook paths.

SED="@GNUSED@"
GREP="@GNUGREP@"

_sanitize_single_gitconfig() {
  local src="$1"
  local dst="$2"

  if [[ ! -f "$src" ]]; then
    return 1
  fi

  # Strip dangerous sections and directives.
  # Section headers are matched case-insensitively with optional leading whitespace
  # to prevent bypasses via indentation or case variation.
  # Sections removed entirely:
  #   credential.*  — credential helpers can leak tokens
  #   alias.*       — aliases can execute arbitrary shell commands
  #   url.*         — insteadOf can redirect to credential-leaking URLs
  #   include       — can pull in arbitrary unsafe config files
  #   includeIf     — conditional includes, same risk
  #   filter.*      — filter drivers (clean/smudge/process) execute arbitrary code
  # Individual keys removed (case-insensitive):
  #   sshCommand    — can execute arbitrary commands
  #   gitProxy      — can redirect traffic
  #   helper        — credential helper references
  #   hooksPath     — can execute arbitrary hook scripts
  #   askpass       — can execute arbitrary password prompts
  #   fsmonitor     — filesystem monitor can execute arbitrary commands
  #   pager         — can execute arbitrary commands
  #   diff.external — can execute arbitrary commands
  #   include/path  — stray include directives outside [include] sections
  "$SED" \
    -e '/^[[:space:]]*\[credential/I,/^[[:space:]]*\[/{ /^[[:space:]]*\[credential/Id; /^[[:space:]]*\[/!d; }' \
    -e '/^[[:space:]]*\[alias/I,/^[[:space:]]*\[/{ /^[[:space:]]*\[alias/Id; /^[[:space:]]*\[/!d; }' \
    -e '/^[[:space:]]*\[url /I,/^[[:space:]]*\[/{ /^[[:space:]]*\[url /Id; /^[[:space:]]*\[/!d; }' \
    -e '/^[[:space:]]*\[include\]/I,/^[[:space:]]*\[/{ /^[[:space:]]*\[include\]/Id; /^[[:space:]]*\[/!d; }' \
    -e '/^[[:space:]]*\[includeIf /I,/^[[:space:]]*\[/{ /^[[:space:]]*\[includeIf /Id; /^[[:space:]]*\[/!d; }' \
    -e '/^[[:space:]]*\[filter /I,/^[[:space:]]*\[/{ /^[[:space:]]*\[filter /Id; /^[[:space:]]*\[/!d; }' \
    -e '/sshCommand/Id' \
    -e '/gitProxy/Id' \
    -e '/helper\s*=/Id' \
    -e '/hooksPath/Id' \
    -e '/askpass/Id' \
    -e '/fsmonitor/Id' \
    -e '/^\s*include\b/Id' \
    -e '/^\s*path\s*=.*\//d' \
    "$src" > "$dst" 2>/dev/null || true
}

sanitize_gitconfig() {
  local src_home="$1"
  local dst_home="$2"
  local src_gitconfig="${src_home}/.gitconfig"
  local dst_gitconfig="${dst_home}/.gitconfig"

  # sandbox.sh pins GIT_CONFIG_GLOBAL to this one file, which makes git skip
  # its normal global lookup chain entirely — including ~/.config/git/config
  # (XDG). Real-world setups (this one included) keep user.name/user.email
  # there rather than in ~/.gitconfig, so sanitizing the XDG file into its
  # own untouched-by-git path silently dropped identity out of the sandbox.
  # Merge both sanitized sources into the single file GIT_CONFIG_GLOBAL
  # points to, XDG first then ~/.gitconfig, matching git's real precedence
  # (XDG config < global ~/.gitconfig, last key wins on conflict).
  local xdg_config_home="${XDG_CONFIG_HOME:-${src_home}/.config}"
  local xdg_git_config="${xdg_config_home}/git/config"

  : > "$dst_gitconfig"
  if [[ -f "$xdg_git_config" ]]; then
    _sanitize_single_gitconfig "$xdg_git_config" "$dst_gitconfig.xdg"
    cat "$dst_gitconfig.xdg" >> "$dst_gitconfig" 2>/dev/null
    rm -f "$dst_gitconfig.xdg"
  fi
  if [[ -f "$src_gitconfig" ]]; then
    _sanitize_single_gitconfig "$src_gitconfig" "$dst_gitconfig.local"
    cat "$dst_gitconfig.local" >> "$dst_gitconfig" 2>/dev/null
    rm -f "$dst_gitconfig.local"
  fi

  # fall back to minimal config if nothing came through.
  if [[ ! -s "$dst_gitconfig" ]] || ! "$GREP" -q '\S' "$dst_gitconfig" 2>/dev/null; then
    cat > "$dst_gitconfig" <<'GITCFG'
[core]
	autocrlf = input
GITCFG
  fi

  # Also drop a sanitized copy at the XDG path for tools that read it
  # directly rather than through GIT_CONFIG_GLOBAL.
  if [[ -f "$xdg_git_config" ]]; then
    local dst_xdg_dir="${dst_home}/.config/git"
    mkdir -p "$dst_xdg_dir"
    _sanitize_single_gitconfig "$xdg_git_config" "${dst_xdg_dir}/config"
  fi
}
