#!/usr/bin/env bash
# AnyAIGC 一键安装配置工具 (macOS / Linux)
# 自动安装 Node.js + Codex / Claude Code，并写入 AnyAIGC 接口配置。
#
# 一行命令使用方式:
#   curl -fsSL https://docs.anyaigc.com/install.sh | bash
#
# 指定安装目标 (跳过菜单):
#   curl -fsSL https://docs.anyaigc.com/install.sh | bash -s both     # 同时安装 (默认)
#   curl -fsSL https://docs.anyaigc.com/install.sh | bash -s claude   # 仅 Claude Code
#   curl -fsSL https://docs.anyaigc.com/install.sh | bash -s codex    # 仅 Codex
#
# 非交互模式 (无终端时通过环境变量提供 Key):
#   OPENAI_API_KEY=sk-xxx ANTHROPIC_API_KEY=sk-xxx \
#     curl -fsSL https://docs.anyaigc.com/install.sh | bash -s both

set -u

# ---------------------------------------------------------------------------
# 可调参数
# ---------------------------------------------------------------------------
NODE_VERSION="22.11.0"                                          # 安装的 Node 版本 (LTS)
NPM_REGISTRY="https://registry.npmmirror.com"                   # npm 镜像 (国内加速)
NODE_MIRROR="https://registry.npmmirror.com/-/binary/node"      # Node 二进制镜像 (兜底下载)
BASE_URL="https://anyaigc.com"                                  # AnyAIGC 接口地址
SMALL_MODEL="claude-haiku-4-5-20251001"
CODEX_MODEL="gpt-5.5"

# macOS .pkg 安装包 (主源 + 镜像兜底)
NODE_PKG_URL="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}.pkg"
NODE_PKG_URL_FALLBACK="https://npmmirror.com/mirrors/node/v${NODE_VERSION}/node-v${NODE_VERSION}.pkg"

# 慢速检测阈值: 持续低于该速度超过指定秒数即切换下载源
SLOW_SPEED_THRESHOLD_KB=50   # KB/s
SLOW_SPEED_DURATION_SEC=15   # 秒

# ---------------------------------------------------------------------------
# 彩色输出
# ---------------------------------------------------------------------------
C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
C_BLUE=$'\033[34m'; C_MAGENTA=$'\033[35m'; C_CYAN=$'\033[36m'; C_RESET=$'\033[0m'
step()    { printf "%s%s%s\n" "$C_CYAN" "$1" "$C_RESET"; }
info()    { printf "%s[信息] %s%s\n" "$C_CYAN" "$1" "$C_RESET"; }
ok()      { printf "%s[成功] %s%s\n" "$C_GREEN" "$1" "$C_RESET"; }
warn()    { printf "%s%s%s\n" "$C_YELLOW" "$1" "$C_RESET"; }
err()     { printf "%s[错误] %s%s\n" "$C_RED" "$1" "$C_RESET" >&2; }

show_logo() {
  printf "\n"
  printf "%s   █████╗ ███╗   ██╗██╗   ██╗ █████╗ ██╗ ██████╗  ██████╗%s\n" "$C_CYAN" "$C_RESET"
  printf "%s  ██╔══██╗████╗  ██║╚██╗ ██╔╝██╔══██╗██║██╔════╝ ██╔════╝%s\n" "$C_CYAN" "$C_RESET"
  printf "%s  ███████║██╔██╗ ██║ ╚████╔╝ ███████║██║██║  ███╗██║     %s\n" "$C_BLUE" "$C_RESET"
  printf "%s  ██╔══██║██║╚██╗██║  ╚██╔╝  ██╔══██║██║██║   ██║██║     %s\n" "$C_BLUE" "$C_RESET"
  printf "%s  ██║  ██║██║ ╚████║   ██║   ██║  ██║██║╚██████╔╝╚██████╗%s\n" "$C_MAGENTA" "$C_RESET"
  printf "%s  ╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝╚═╝ ╚═════╝  ╚═════╝%s\n" "$C_MAGENTA" "$C_RESET"
  printf "\n%s              AnyAIGC 一键安装配置工具%s\n" "$C_MAGENTA" "$C_RESET"
  printf "%s  ====================================================%s\n\n" "$C_CYAN" "$C_RESET"
}

# ---------------------------------------------------------------------------
# 基础工具函数
# ---------------------------------------------------------------------------
is_tty_available() {
  [ -t 0 ] || [ -t 1 ] || [ -e /dev/tty ]
}

trim_whitespace() {
  local value="${1-}"
  value="${value%$'\r'}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

strip_cr() {
  local value="${1-}"
  printf '%s' "${value%$'\r'}"
}

trim_blank_lines() {
  awk '
    NF || found { if (!found) found=1; lines[++n] = $0 }
    END { while (n > 0 && lines[n] == "") n--; for (i = 1; i <= n; i++) print lines[i] }
  '
}

detect_shell_name() {
  local shell_name=""
  if [ -n "${SHELL:-}" ]; then
    shell_name="$(basename "$SHELL")"
  elif command -v ps >/dev/null 2>&1; then
    shell_name="$(ps -p "$$" -o comm= 2>/dev/null | awk '{print $1}')"
    shell_name="$(basename "${shell_name:-}")"
  fi
  [ -z "$shell_name" ] && shell_name="bash"
  printf '%s' "$shell_name"
}

detect_shell_rc() {
  local shell_name; shell_name="$(detect_shell_name)"
  case "$shell_name" in
    zsh)  printf '%s' "$HOME/.zshrc" ;;
    fish) printf '%s' "$HOME/.config/fish/config.fish" ;;
    *)
      if [ "$OS_TYPE" = "Darwin" ] && [ ! -f "$HOME/.bashrc" ]; then
        printf '%s' "$HOME/.bash_profile"
      else
        printf '%s' "$HOME/.bashrc"
      fi
      ;;
  esac
}

ensure_file_exists() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || : > "$file"
}

append_line_if_missing() {
  local file="$1" line="$2"
  ensure_file_exists "$file"
  grep -Fqx "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >> "$file"
}

add_path_entry() {
  local path_entry="$1"
  [ -n "$path_entry" ] || return 0
  [ -d "$path_entry" ] || return 0
  case ":$PATH:" in
    *":$path_entry:"*) ;;
    *) export PATH="$path_entry:$PATH"; hash -r 2>/dev/null || true ;;
  esac
}

resolve_npm_global_bin() {
  local npm_cmd="$1" npm_prefix=""
  npm_prefix="$("$npm_cmd" config get prefix 2>/dev/null || true)"
  npm_prefix="$(trim_whitespace "$npm_prefix")"
  [ -z "$npm_prefix" ] && return 1
  if [ -d "$npm_prefix/bin" ]; then printf '%s' "$npm_prefix/bin"; return 0; fi
  if [ -d "$npm_prefix" ]; then printf '%s' "$npm_prefix"; return 0; fi
  return 1
}

ensure_nvm_init_in_shell_rc() {
  local shell_name shell_rc
  shell_name="$(detect_shell_name)"; shell_rc="$(detect_shell_rc)"
  [ "$shell_name" = "fish" ] && return 0
  append_line_if_missing "$shell_rc" 'export NVM_DIR="$HOME/.nvm"'
  append_line_if_missing "$shell_rc" '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'
}

# 把 npm 全局 bin 目录加入当前会话 + 持久写入 shell 配置
persist_npm_path() {
  local npm_cmd="$1" npm_bin shell_rc shell_name
  npm_bin="$(resolve_npm_global_bin "$npm_cmd" || true)"
  [ -n "$npm_bin" ] || return 0
  add_path_entry "$npm_bin"
  shell_rc="$(detect_shell_rc)"; shell_name="$(detect_shell_name)"
  if [ "$shell_name" = "fish" ]; then
    append_line_if_missing "$shell_rc" "set -x PATH \"$npm_bin\" \$PATH"
  else
    append_line_if_missing "$shell_rc" "export PATH=\"$npm_bin:\$PATH\""
  fi
}

# ---------------------------------------------------------------------------
# 下载: 带进度条，持续慢速则返回 1 (供切换下载源)
#   $5 allow_slow=1 时不因慢速中断 (用于最后一个源)
# ---------------------------------------------------------------------------
download_with_progress() {
  local url="$1" dest="$2" slow_kb="$3" slow_sec="$4" allow_slow="${5:-0}"
  rm -f "$dest"
  if command -v curl >/dev/null 2>&1; then
    local speed_limit=$(( slow_kb * 1024 ))
    if [ "$allow_slow" = "1" ]; then
      curl -fL --progress-bar --connect-timeout 15 -o "$dest" "$url" && return 0
    else
      curl -fL --progress-bar --speed-limit "$speed_limit" --speed-time "$slow_sec" \
        --connect-timeout 15 -o "$dest" "$url" && return 0
    fi
    rm -f "$dest"; return 1
  elif command -v wget >/dev/null 2>&1; then
    wget --timeout=15 --tries=1 -O "$dest" "$url" 2>&1 && return 0
    rm -f "$dest"; return 1
  else
    err "未找到 curl 或 wget"; return 1
  fi
}

# 依次尝试多个下载源
download_file() {
  local dest="$1"; shift
  local urls=("$@") total=${#urls[@]} i=0
  for url in "${urls[@]}"; do
    [ "$i" -gt 0 ] && info "切换到备用下载源..."
    info "正在下载: $url"
    local allow_slow=0
    [ "$i" -eq $((total - 1)) ] && allow_slow=1
    if download_with_progress "$url" "$dest" "$SLOW_SPEED_THRESHOLD_KB" "$SLOW_SPEED_DURATION_SEC" "$allow_slow"; then
      ok "下载完成: $(basename "$dest")"; return 0
    fi
    err "下载失败或速度过慢: $url"; i=$((i + 1))
  done
  err "所有下载源均失败，请检查网络后重试。"; return 1
}

# ---------------------------------------------------------------------------
# 旧 macOS 检测 (低于 10.15 Catalina)
# ---------------------------------------------------------------------------
is_old_macos() {
  [ "$OS_TYPE" = "Darwin" ] || return 1
  local ver major minor
  ver="$(sw_vers -productVersion 2>/dev/null)"
  [ -z "$ver" ] && return 1
  major="$(echo "$ver" | cut -d. -f1)"; minor="$(echo "$ver" | cut -d. -f2)"
  if [ "$major" -lt 10 ] || { [ "$major" -eq 10 ] && [ "${minor:-0}" -lt 15 ]; }; then
    return 0
  fi
  return 1
}

show_old_system_guide() {
  printf "\n"
  warn "[提示] 检测到 macOS $(sw_vers -productVersion 2>/dev/null)，本工具的【自动安装】功能不支持此系统。"
  warn ""
  warn "  你可以手动安装后再使用本工具的配置功能:"
  warn "    1) 前往 https://nodejs.org 下载并安装 Node.js"
  warn "    2) 安装完成后，重新运行本命令即可自动完成配置"
  warn ""
  warn "  请注意: 过旧的 macOS 可能无法运行新版 Node.js 与 Claude Code,"
  warn "          建议升级到 macOS 10.15 (Catalina) 或更高版本。"
  printf "\n"
}

# ---------------------------------------------------------------------------
# 系统 / 权限检测
# ---------------------------------------------------------------------------
OS_TYPE="$(uname -s)"

run_sudo() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif [ -n "$SUDO_CMD" ]; then "$SUDO_CMD" "$@"
  else "$@"; fi
}

detect_sudo() {
  SUDO_CMD=""
  if [ "$(id -u)" -eq 0 ]; then
    SUDO_CMD=""
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    SUDO_CMD="sudo"
  elif command -v sudo >/dev/null 2>&1; then
    info "安装 Node.js 可能需要管理员权限，接下来可能提示输入密码"
    sudo -v 2>/dev/null && SUDO_CMD="sudo"
  fi
}

# ---------------------------------------------------------------------------
# 1. 安装 Node.js
# ---------------------------------------------------------------------------
NODE_INSTALLED_VIA_NVM=0
ensure_node() {
  step $'\n[检查] 检查 Node.js 环境...'
  if command -v node >/dev/null 2>&1; then
    ok "已检测到 Node.js $(node -v)，跳过安装"
    return
  fi

  # 旧版 macOS 不尝试自动安装：改为引导手动安装
  if is_old_macos; then
    show_old_system_guide
    exit 1
  fi

  info "未检测到 Node.js，开始安装 (v${NODE_VERSION})..."

  case "$OS_TYPE" in
    Darwin)
      if [ -z "$SUDO_CMD" ] && [ "$(id -u)" -ne 0 ]; then
        err "macOS 安装 Node.js 需要管理员权限，请使用具备 sudo 权限的账户重试。"
        exit 1
      fi
      info "检测到 macOS 架构: $(uname -m)"
      local node_pkg="/tmp/node-setup.pkg"
      download_file "$node_pkg" "$NODE_PKG_URL" "$NODE_PKG_URL_FALLBACK" || exit 1
      info "正在安装 Node.js..."
      run_sudo installer -pkg "$node_pkg" -target /
      rm -f "$node_pkg"
      ;;
    Linux)
      if [ -n "$SUDO_CMD" ] || [ "$(id -u)" -eq 0 ]; then
        if command -v apt-get >/dev/null 2>&1; then
          info "通过 NodeSource 安装 Node.js (Ubuntu/Debian)..."
          curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION%%.*}.x" | run_sudo bash -
          run_sudo apt-get install -y nodejs
        elif command -v dnf >/dev/null 2>&1; then
          curl -fsSL "https://rpm.nodesource.com/setup_${NODE_VERSION%%.*}.x" | run_sudo bash -
          run_sudo dnf install -y nodejs
        elif command -v yum >/dev/null 2>&1; then
          curl -fsSL "https://rpm.nodesource.com/setup_${NODE_VERSION%%.*}.x" | run_sudo bash -
          run_sudo yum install -y nodejs
        elif command -v pacman >/dev/null 2>&1; then
          run_sudo pacman -Sy --noconfirm nodejs npm
        else
          warn "[提示] 无法通过系统包管理器安装，改用 nvm..."
        fi
      fi

      # 包管理器没装上 (或无 sudo) → nvm 兜底，免 root
      if ! command -v node >/dev/null 2>&1; then
        info "通过 nvm 安装 Node.js (无需 sudo)..."
        export NVM_DIR="$HOME/.nvm"
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        nvm install "${NODE_VERSION%%.*}"
        nvm use "${NODE_VERSION%%.*}"
        NODE_INSTALLED_VIA_NVM=1
      fi
      ;;
    *)
      err "不支持的系统: $OS_TYPE"; exit 1 ;;
  esac

  # 刷新 PATH，让当前会话立即可用
  add_path_entry "/usr/local/bin"
  local latest_node_bin
  latest_node_bin="$(ls -1d "$HOME/.nvm/versions/node/"*/bin 2>/dev/null | tail -n 1 || true)"
  add_path_entry "$(trim_whitespace "$latest_node_bin")"
  [ "$NODE_INSTALLED_VIA_NVM" -eq 1 ] && ensure_nvm_init_in_shell_rc

  if command -v node >/dev/null 2>&1; then
    ok "Node.js 安装完成 $(node -v)"
  else
    err "安装后仍找不到 Node.js，请重新打开终端后再试。"
    exit 1
  fi

  if ! command -v npm >/dev/null 2>&1; then
    err "未找到 npm，请检查 Node.js 安装。"
    exit 1
  fi
  ok "node $(node -v)  /  npm $(npm -v)"
}

# ---------------------------------------------------------------------------
# 2. 全局安装 npm 包 (已装则跳过；按权限选择是否 sudo)
# ---------------------------------------------------------------------------
ensure_npm_package() {
  local pkg="$1" cmd_name="$2"
  step $'\n[检查] 检查 '"$pkg"' 安装状态...'
  if command -v "$cmd_name" >/dev/null 2>&1; then
    ok "$cmd_name 已安装，跳过 ($("$cmd_name" --version 2>/dev/null || echo unknown))"
    persist_npm_path "$(command -v npm)"
    return
  fi

  step "[安装] 正在全局安装 $pkg ..."
  local npm_cmd; npm_cmd="$(command -v npm)"
  if [ "$(id -u)" -eq 0 ]; then
    "$npm_cmd" install -g "$pkg" --registry "$NPM_REGISTRY" --quiet
  elif "$npm_cmd" install -g "$pkg" --registry "$NPM_REGISTRY" --quiet 2>/dev/null; then
    : # 普通权限成功
  elif [ -n "$SUDO_CMD" ]; then
    warn "[提示] 普通权限安装失败，尝试 sudo..."
    "$SUDO_CMD" "$npm_cmd" install -g "$pkg" --registry "$NPM_REGISTRY" --quiet
  else
    err "$pkg 安装失败，可手动执行: npm install -g $pkg"
    return 1
  fi

  persist_npm_path "$npm_cmd"
  if command -v "$cmd_name" >/dev/null 2>&1; then
    ok "$pkg 安装完成"
  else
    err "$cmd_name 不在 PATH 中，请重新打开终端后再试。"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# JSON 合并: 用 node 做对象级深合并，保留用户原有字段
# ---------------------------------------------------------------------------
merge_json() {
  local path="$1" patch="$2"
  mkdir -p "$(dirname "$path")"
  node -e '
    const fs = require("fs");
    const [path, patch] = [process.argv[1], process.argv[2]];
    let cur = {};
    try { cur = JSON.parse(fs.readFileSync(path, "utf8")); } catch (e) {}
    const p = JSON.parse(patch);
    const deepMerge = (a, b) => {
      for (const k of Object.keys(b)) {
        if (b[k] && typeof b[k] === "object" && !Array.isArray(b[k])) {
          a[k] = deepMerge(a[k] && typeof a[k] === "object" ? a[k] : {}, b[k]);
        } else { a[k] = b[k]; }
      }
      return a;
    };
    fs.writeFileSync(path, JSON.stringify(deepMerge(cur, p), null, 2), "utf8");
  ' "$path" "$patch"
}

# ---------------------------------------------------------------------------
# 读取 API Key
#   $1 = 显示名称  $2 = 非交互模式下读取的环境变量名
# ---------------------------------------------------------------------------
read_api_key() {
  local label="$1" env_var="$2" key=""
  if is_tty_available; then
    while [ -z "$key" ]; do
      printf "请输入你的 %s API Key (sk-xxx): " "$label" > /dev/tty
      read -r key < /dev/tty || true
      key="$(trim_whitespace "$key")"
      case "$key" in
        sk-*) ;;
        "")   err "API Key 不能为空" ;;
        *)    err "API Key 格式不正确，应以 sk- 开头"; key="" ;;
      esac
    done
  else
    key="$(trim_whitespace "$(eval "echo \"\${$env_var:-}\"")")"
    if [ -z "$key" ]; then
      err "非交互模式下 API Key 不能为空 (请设置环境变量 $env_var)"
      return 1
    fi
  fi
  printf '%s' "$key"
}

# 读取一个 API Key (自定义提示语，不绑定具体产品)；仅交互模式使用
read_api_key_prompt() {
  local prompt="$1" key=""
  while [ -z "$key" ]; do
    printf "%s" "$prompt" > /dev/tty
    read -r key < /dev/tty || true
    key="$(trim_whitespace "$key")"
    case "$key" in
      sk-*) ;;
      "")   err "API Key 不能为空" ;;
      *)    err "API Key 格式不正确，应以 sk- 开头"; key="" ;;
    esac
  done
  printf '%s' "$key"
}

# 询问 Y/n，默认 Y (回车=是)；返回 0=是 1=否
ask_yes_default() {
  local prompt="$1" ans=""
  printf "%s" "$prompt" > /dev/tty
  read -r ans < /dev/tty || true
  case "$(trim_whitespace "$ans")" in
    [nN]|[nN][oO]) return 1 ;;
    *) return 0 ;;
  esac
}

# ---------------------------------------------------------------------------
# 配置 Claude Code
# ---------------------------------------------------------------------------
configure_claude() {
  ensure_npm_package "@anthropic-ai/claude-code" "claude" || return 1

  local key="${1:-}"
  if [ -z "$key" ]; then
    key="$(read_api_key "Claude" "ANTHROPIC_API_KEY")" || return 1
  fi

  merge_json "$HOME/.claude/config.json" '{"primaryApiKey":"1"}'
  merge_json "$HOME/.claude/settings.json" \
    "{\"env\":{\"ANTHROPIC_AUTH_TOKEN\":\"$key\",\"ANTHROPIC_BASE_URL\":\"$BASE_URL\",\"ANTHROPIC_SMALL_FAST_MODEL\":\"$SMALL_MODEL\"}}"
  ok "配置文件已写入 $HOME/.claude"

  local rc; rc="$(detect_shell_rc)"
  append_line_if_missing "$rc" "export ANTHROPIC_AUTH_TOKEN=\"$key\""
  append_line_if_missing "$rc" "export ANTHROPIC_BASE_URL=\"$BASE_URL\""
  append_line_if_missing "$rc" "export ANTHROPIC_SMALL_FAST_MODEL=\"$SMALL_MODEL\""
  ok "环境变量已写入 $rc"
}

# ---------------------------------------------------------------------------
# 配置 Codex (保留用户已有的其它 TOML 配置段)
# ---------------------------------------------------------------------------
configure_codex() {
  ensure_npm_package "@openai/codex" "codex" || return 1

  local key="${1:-}"
  if [ -z "$key" ]; then
    key="$(read_api_key "OpenAI" "OPENAI_API_KEY")" || return 1
  fi

  local codex_dir="$HOME/.codex"
  mkdir -p "$codex_dir"
  local config_file="$codex_dir/config.toml"

  local toml_block
  toml_block="model_provider = \"codex\"
model = \"$CODEX_MODEL\"
model_reasoning_effort = \"high\"
disable_response_storage = true

[model_providers.codex]
name = \"codex\"
base_url = \"$BASE_URL/v1\"
wire_api = \"responses\"
requires_openai_auth = true"

  if [ -f "$config_file" ]; then
    # 移除旧的 codex 段与关键字段，保留用户其它配置
    local remaining="" in_codex=0 line
    while IFS= read -r line || [ -n "$line" ]; do
      line="$(strip_cr "$line")"
      if [[ "$line" =~ ^[[:space:]]*\[model_providers\.codex\][[:space:]]*$ ]]; then in_codex=1; continue; fi
      if [ "$in_codex" -eq 1 ] && [[ "$line" =~ ^[[:space:]]*\[[^]]+\][[:space:]]*$ ]]; then in_codex=0; fi
      [ "$in_codex" -eq 1 ] && continue
      [[ "$line" =~ ^[[:space:]]*model_provider[[:space:]]*= ]] && continue
      [[ "$line" =~ ^[[:space:]]*model[[:space:]]*=[[:space:]]*\"gpt- ]] && continue
      [[ "$line" =~ ^[[:space:]]*model_reasoning_effort[[:space:]]*= ]] && continue
      [[ "$line" =~ ^[[:space:]]*disable_response_storage[[:space:]]*= ]] && continue
      remaining="${remaining}${line}
"
    done < "$config_file"
    remaining="$(printf '%s' "$remaining" | trim_blank_lines)"
    if [ -n "$remaining" ]; then
      printf '%s\n\n%s\n' "$toml_block" "$remaining" > "$config_file"
    else
      printf '%s\n' "$toml_block" > "$config_file"
    fi
  else
    printf '%s\n' "$toml_block" > "$config_file"
  fi

  merge_json "$codex_dir/auth.json" "{\"OPENAI_API_KEY\":\"$key\"}"
  ok "配置文件已写入 $codex_dir"

  # 编辑器配置 (存在才更新)
  if [ "$OS_TYPE" = "Darwin" ]; then
    update_editor "$HOME/Library/Application Support/Code/User/settings.json" "VS Code"
    update_editor "$HOME/Library/Application Support/Cursor/User/settings.json" "Cursor"
  else
    update_editor "$HOME/.config/Code/User/settings.json" "VS Code"
    update_editor "$HOME/.config/Cursor/User/settings.json" "Cursor"
  fi
}

update_editor() {
  local path="$1" name="$2"
  [ -f "$path" ] || return
  merge_json "$path" \
    "{\"chatgpt.apiBase\":\"$BASE_URL/v1\",\"chatgpt.config\":{\"preferred_auth_method\":\"apikey\",\"model\":\"$CODEX_MODEL\",\"model_reasoning_effort\":\"high\",\"wire_api\":\"responses\"}}"
  ok "$name 配置已更新"
}

# ---------------------------------------------------------------------------
# 完成提示
# ---------------------------------------------------------------------------
show_done() {
  local rc; rc="$(detect_shell_rc)"
  printf "\n%s%s%s\n" "$C_YELLOW" "============================================================" "$C_RESET"
  printf "%s  安装配置完成，开启你的 AI 编程之旅%s\n" "$C_YELLOW" "$C_RESET"
  printf "%s%s%s\n\n" "$C_YELLOW" "============================================================" "$C_RESET"
  warn "请重新打开终端，或运行: source $rc"
  printf "然后运行:\n"
  case "$INSTALL_TARGET" in
    both)   printf "  %sclaude%s   或   %scodex%s\n\n" "$C_GREEN" "$C_RESET" "$C_GREEN" "$C_RESET" ;;
    claude) printf "  %sclaude%s\n\n" "$C_GREEN" "$C_RESET" ;;
    codex)  printf "  %scodex%s\n\n" "$C_GREEN" "$C_RESET" ;;
  esac
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
INSTALL_TARGET=""

main() {
  show_logo

  INSTALL_TARGET="${1:-}"

  # 无参数 → 弹菜单 (默认第 1 项 = 同时安装)
  if [ -z "$INSTALL_TARGET" ]; then
    if is_tty_available; then
      printf "%s  请选择要安装配置的工具:%s\n" "$C_CYAN" "$C_RESET"
      printf "    1) 同时安装 Claude Code + Codex  (推荐, 默认)\n"
      printf "    2) 仅 Claude Code\n"
      printf "    3) 仅 Codex\n\n"
      while [ -z "$INSTALL_TARGET" ]; do
        printf "请输入序号 [1/2/3] (回车默认 1): " > /dev/tty
        local sel; read -r sel < /dev/tty || true
        case "$(trim_whitespace "$sel")" in
          ""|1) INSTALL_TARGET="both" ;;    # 回车 = 默认同时安装
          2)    INSTALL_TARGET="claude" ;;
          3)    INSTALL_TARGET="codex" ;;
          *)    err "无效输入 '$sel'，请输入 1、2 或 3 (或直接回车选默认)" ;;
        esac
      done
    else
      INSTALL_TARGET="both"   # 非交互默认装两个
    fi
  fi

  # 规范化别名
  case "$INSTALL_TARGET" in
    claude*) INSTALL_TARGET="claude" ;;
    codex*)  INSTALL_TARGET="codex" ;;
    all|both|"") INSTALL_TARGET="both" ;;
  esac

  # 下载前清理代理 (云主机 / AutoDL 等环境)
  unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY 2>/dev/null || true

  detect_sudo
  ensure_node          # 环境只准备一次

  case "$INSTALL_TARGET" in
    both)
      # 同时安装: 先输一次 Key，再询问是否两边复用
      if is_tty_available; then
        local shared_key reuse_codex_key=""
        shared_key="$(read_api_key_prompt "请输入你的 API Key (sk-xxx): ")"
        printf "\n"
        if ask_yes_default "Claude 和 Codex 使用同一个 Key 吗? (同一个直接回车 / 想分开统计用量输入 n) [Y/n]: "; then
          ok "两边均使用该 Key"
          configure_claude "$shared_key"
          configure_codex "$shared_key"
        else
          reuse_codex_key="$(read_api_key_prompt "请输入 Codex 专用的 API Key (sk-xxx): ")"
          configure_claude "$shared_key"
          configure_codex "$reuse_codex_key"
        fi
      else
        # 非交互: 各自从环境变量读取 (ANTHROPIC_API_KEY / OPENAI_API_KEY)
        configure_claude
        configure_codex
      fi
      ;;
    claude) configure_claude ;;
    codex)  configure_codex ;;
  esac

  show_done
}

main "${1:-}"
