# AnyAIGC One-Click Installer

English ｜ [简体中文](./README.md)

One command to automatically install and configure [Claude Code](https://www.anthropic.com/claude-code) and [Codex](https://openai.com/codex/), wiring in your [AnyAIGC](https://anyaigc.ai) endpoint config so everything works out of the box.

> Website: <https://anyaigc.ai>

## Features

- **One-click install**: automatically installs Node.js (LTS `v22.11.0`), Claude Code, and Codex
- **Auto configuration**: writes the AnyAIGC endpoint, models, and API key, and updates your editor (VS Code / Cursor) settings
- **Faster in China**: uses the [npmmirror](https://registry.npmmirror.com) mirror by default, with automatic fallback when downloads are slow
- **Cross-platform**: supports macOS, Linux, and Windows
- **Flexible**: install both tools at once, or just one of them
- **Interactive / non-interactive**: menu-driven prompts, or silent install via environment variables in headless environments (CI, cloud VMs)

## Quick Start

### macOS / Linux

```bash
# Shows a menu by default; press Enter to install both Claude Code + Codex
curl -fsSL https://www.anyaigc.ai/install.sh | bash
```

Choose a target (skip the menu):

```bash
curl -fsSL https://www.anyaigc.ai/install.sh | bash -s both     # install both (default)
curl -fsSL https://www.anyaigc.ai/install.sh | bash -s claude   # Claude Code only
curl -fsSL https://www.anyaigc.ai/install.sh | bash -s codex    # Codex only
```

Non-interactive mode (provide keys via environment variables when no terminal is available):

```bash
OPENAI_API_KEY=sk-xxx ANTHROPIC_API_KEY=sk-xxx \
  curl -fsSL https://www.anyaigc.ai/install.sh | bash -s both
```

### Windows (PowerShell / CMD)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://www.anyaigc.ai/install.ps1 | iex"
```

Choose a target (skip the menu):

```powershell
& ([scriptblock]::Create((irm https://www.anyaigc.ai/install.ps1))) both     # install both (default)
& ([scriptblock]::Create((irm https://www.anyaigc.ai/install.ps1))) claude   # Claude Code only
& ([scriptblock]::Create((irm https://www.anyaigc.ai/install.ps1))) codex    # Codex only
```

## Installation Flow

When the script runs, it goes through these steps in order:

1. Detect the OS and architecture, and prepare the install environment (clear proxies, probe permissions)
2. Install Node.js and npm (each OS prefers its native package manager / winget, falling back to a mirror binary or NVM on failure)
3. Globally install `@anthropic-ai/claude-code` and `@openai/codex` via npm
4. Prompt for API keys (both tools can share one key, or use separate keys to track usage individually)
5. Write the Claude / Codex config files and environment variables, and update editor settings

## Configuration

| Item | Value |
| --- | --- |
| Endpoint | `https://anyaigc.ai` |
| Claude fast model | `claude-haiku-4-5-20251001` |
| Codex model | `gpt-5.5` |
| npm mirror | `https://registry.npmmirror.com` |
| Node version | `22.11.0` (LTS) |

Config file locations:

- **Claude Code**: `~/.claude/config.json`, `~/.claude/settings.json`
- **Codex**: `~/.codex/config.toml`, `~/.codex/auth.json`
- Environment variables are written to the matching shell config file (`.bashrc` / `.zshrc` / `config.fish`, etc.); on Windows they go into the user environment variables

## Platform Support

| OS | Support |
| --- | --- |
| macOS | Catalina (10.15+), via `.pkg` install or NVM fallback |
| Linux | Ubuntu/Debian (apt), RHEL/CentOS/Fedora (dnf/yum), Arch (pacman), or NVM fallback |
| Windows | Windows 10 / 11, via winget or MSI install |

> Older systems (Win7/8, legacy macOS) will show a notice; install Node.js manually first, then run the script.

## FAQ

**Q: Do I need a VPN?**
Downloads use China mirrors by default, so a proxy is usually unnecessary. The script also switches to a fallback source automatically when downloads are slow.

**Q: Can I install just one tool?**
Yes. Pass `claude` or `codex` as an argument during installation.

**Q: Where do I get an API key?**
Register at the [AnyAIGC website](https://anyaigc.ai) to obtain one, in the format `sk-xxx`.

## About AnyAIGC

**AnyAIGC** is an AI model aggregation service for developers, offering a unified endpoint (`https://anyaigc.ai`) compatible with mainstream models like Anthropic Claude and OpenAI. With a single API key, you can use them directly in Claude Code, Codex, and other popular AI coding tools — no need to deal with networking, mirrors, or environment variables yourself.

- 🔗 Website: <https://anyaigc.ai>

## Links

- AnyAIGC website: <https://anyaigc.ai>
- Install scripts: <https://www.anyaigc.ai/install.sh> ｜ <https://www.anyaigc.ai/install.ps1>
