# AnyAIGC 一键安装配置工具

一条命令，自动为你安装并配置 [Claude Code](https://www.anthropic.com/claude-code) 与 [Codex](https://openai.com/codex/)，并写入 [AnyAIGC](https://anyaigc.com) 接口配置，开箱即用。

> 官网：<https://anyaigc.com> ｜ 文档与脚本：<https://docs.anyaigc.com>

## 功能特性

- **一键安装**：自动安装 Node.js（LTS `v22.11.0`）、Claude Code、Codex
- **自动配置**：写入 AnyAIGC 接口地址、模型与 API Key，并更新编辑器（VS Code / Cursor）配置
- **国内加速**：默认使用 [npmmirror](https://registry.npmmirror.com) 镜像，下载慢时自动切换兜底源
- **跨平台**：支持 macOS、Linux、Windows
- **灵活选择**：可同时安装两个工具，或仅安装其中之一
- **交互 / 非交互**：支持菜单交互，也支持通过环境变量在无终端环境（CI、云主机）中静默安装

## 快速开始

### macOS / Linux

```bash
# 默认弹出菜单，回车即同时安装 Claude Code + Codex
curl -fsSL https://docs.anyaigc.com/install.sh | bash
```

指定安装目标（跳过菜单）：

```bash
curl -fsSL https://docs.anyaigc.com/install.sh | bash -s both     # 同时安装（默认）
curl -fsSL https://docs.anyaigc.com/install.sh | bash -s claude   # 仅 Claude Code
curl -fsSL https://docs.anyaigc.com/install.sh | bash -s codex    # 仅 Codex
```

非交互模式（无终端时通过环境变量提供 Key）：

```bash
OPENAI_API_KEY=sk-xxx ANTHROPIC_API_KEY=sk-xxx \
  curl -fsSL https://docs.anyaigc.com/install.sh | bash -s both
```

### Windows（PowerShell / CMD 均可）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://docs.anyaigc.com/install.ps1 | iex"
```

指定安装目标（跳过菜单）：

```powershell
& ([scriptblock]::Create((irm https://docs.anyaigc.com/install.ps1))) both     # 同时安装（默认）
& ([scriptblock]::Create((irm https://docs.anyaigc.com/install.ps1))) claude   # 仅 Claude Code
& ([scriptblock]::Create((irm https://docs.anyaigc.com/install.ps1))) codex    # 仅 Codex
```

## 安装流程

脚本运行后会依次完成：

1. 检测系统与架构，准备安装环境（清理代理、探测权限）
2. 安装 Node.js 与 npm（各系统优先使用原生包管理器 / winget，失败时回退到镜像二进制或 NVM）
3. 通过 npm 全局安装 `@anthropic-ai/claude-code` 与 `@openai/codex`
4. 提示输入 API Key（可两个工具共用一个，也可分开填写以便分别统计用量）
5. 写入 Claude / Codex 配置文件与环境变量，并更新编辑器配置

## 配置说明

| 项目 | 值 |
| --- | --- |
| 接口地址 | `https://anyaigc.com` |
| Claude 快速模型 | `claude-haiku-4-5-20251001` |
| Codex 模型 | `gpt-5.5` |
| npm 镜像 | `https://registry.npmmirror.com` |
| Node 版本 | `22.11.0`（LTS） |

配置文件写入位置：

- **Claude Code**：`~/.claude/config.json`、`~/.claude/settings.json`
- **Codex**：`~/.codex/config.toml`、`~/.codex/auth.json`
- 环境变量会写入对应的 shell 配置文件（`.bashrc` / `.zshrc` / `config.fish` 等），Windows 写入用户环境变量

## 系统支持

| 系统 | 支持情况 |
| --- | --- |
| macOS | Catalina (10.15+)，使用 `.pkg` 安装或 NVM 回退 |
| Linux | Ubuntu/Debian (apt)、RHEL/CentOS/Fedora (dnf/yum)、Arch (pacman)，或 NVM 回退 |
| Windows | Windows 10 / 11，使用 winget 或 MSI 安装 |

> 更早的系统（Win7/8、旧版 macOS）会给出提示，建议手动安装 Node.js 后再运行脚本。

## 常见问题

**Q：需要科学上网吗？**
默认使用国内镜像下载，通常无需代理。脚本还会在下载缓慢时自动切换兜底源。

**Q：可以只装其中一个工具吗？**
可以，安装时通过参数 `claude` 或 `codex` 指定即可。

**Q：从哪里获取 API Key？**
在 [AnyAIGC 官网](https://anyaigc.com) 注册并获取，格式为 `sk-xxx`。

## 关于 AnyAIGC

**AnyAIGC** 是面向国内开发者的 AI 模型聚合服务，通过统一的接口地址（`https://anyaigc.com`）兼容 Anthropic Claude 与 OpenAI 等主流模型。你只需要一个 API Key，就能在 Claude Code、Codex 等主流 AI 编程工具中直接使用，无需自行处理网络、镜像与环境变量等繁琐配置。

- 🔗 官网：<https://anyaigc.com>
- 📘 文档：<https://docs.anyaigc.com>

## 相关链接

- AnyAIGC 官网：<https://anyaigc.com>
- 文档中心：<https://docs.anyaigc.com>
- 安装脚本：<https://docs.anyaigc.com/install.sh> ｜ <https://docs.anyaigc.com/install.ps1>
