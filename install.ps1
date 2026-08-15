# AnyAIGC 一键安装配置工具 (Windows / PowerShell 版)
# 自动安装 Node.js + Codex / Claude Code，并写入 AnyAIGC 接口配置。
#
# 一行命令使用方式 (PowerShell 或 CMD 均可):
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://www.anyaigc.ai/install.ps1 | iex"
#   回车后会弹出菜单，默认 (回车) = 同时安装 Claude Code + Codex
#
# 指定安装目标 (跳过菜单):
#   & ([scriptblock]::Create((irm https://www.anyaigc.ai/install.ps1))) both     # 同时安装 (默认)
#   & ([scriptblock]::Create((irm https://www.anyaigc.ai/install.ps1))) claude   # 仅 Claude Code
#   & ([scriptblock]::Create((irm https://www.anyaigc.ai/install.ps1))) codex    # 仅 Codex

param(
  [string]$Product = ""
)

$ErrorActionPreference = "Stop"

# 统一控制台为 UTF-8，避免中文与 Logo 在 GBK(936) 代码页下显示乱码
# (用户直接下载本脚本运行时的兜底；一行命令方式已在外层设过编码)
try {
  $OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8
  chcp 65001 > $null 2>&1
} catch {}

# ---------------------------------------------------------------------------
# 可调参数
# ---------------------------------------------------------------------------
$NodeVersion   = "22.11.0"                                   # 自动安装的 Node 版本 (LTS)
$NpmRegistry   = "https://registry.npmmirror.com"            # npm 镜像 (国内加速)
$NodeMirror    = "https://registry.npmmirror.com/-/binary/node"  # Node MSI 下载镜像 (winget 不可用时兜底)
$BaseUrl       = "https://anyaigc.ai"                        # AnyAIGC 接口地址
$SmallModel    = "claude-haiku-4-5-20251001"
$CodexModel    = "gpt-5.5"

# ---------------------------------------------------------------------------
# 彩色输出
# ---------------------------------------------------------------------------
function Write-Step($msg)  { Write-Host $msg -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "[成功] $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host $msg -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "[错误] $msg" -ForegroundColor Red }

function Show-Logo {
  Write-Host ""
  Write-Host "   █████╗ ███╗   ██╗██╗   ██╗ █████╗ ██╗ ██████╗  ██████╗" -ForegroundColor Cyan
  Write-Host "  ██╔══██╗████╗  ██║╚██╗ ██╔╝██╔══██╗██║██╔════╝ ██╔════╝" -ForegroundColor Cyan
  Write-Host "  ███████║██╔██╗ ██║ ╚████╔╝ ███████║██║██║  ███╗██║     " -ForegroundColor Blue
  Write-Host "  ██╔══██║██║╚██╗██║  ╚██╔╝  ██╔══██║██║██║   ██║██║     " -ForegroundColor Blue
  Write-Host "  ██║  ██║██║ ╚████║   ██║   ██║  ██║██║╚██████╔╝╚██████╗" -ForegroundColor Magenta
  Write-Host "  ╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚═╝  ╚═╝╚═╝ ╚═════╝  ╚═════╝" -ForegroundColor Magenta
  Write-Host ""
  Write-Host "              AnyAIGC 一键安装配置工具" -ForegroundColor Magenta
  Write-Host "  ====================================================" -ForegroundColor Cyan
  Write-Host ""
}

# 从注册表重新读取 PATH 灌入当前会话 (装完 Node 后当前终端才能立刻用 node/npm)
function Refresh-Path {
  $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $user    = [Environment]::GetEnvironmentVariable("Path", "User")
  $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ";"
}

# PowerShell 会优先解析 npm.ps1；该 wrapper 在 irm/iex 或 -Command 场景下
# 可能误解析外层命令。Windows 上显式使用 npm.cmd 更稳定。
function Get-NpmCommand {
  $cmd = Get-Command npm.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { return $cmd.Source }

  $node = Get-Command node -ErrorAction SilentlyContinue
  if ($node) {
    $npmCmd = Join-Path (Split-Path $node.Source -Parent) "npm.cmd"
    if (Test-Path -LiteralPath $npmCmd) { return $npmCmd }
  }

  throw "未找到 npm，请检查 Node.js 是否安装完整，或重新打开终端后再试"
}

# npm 的全局 prefix 如果指向不存在的用户目录，`npm list -g` 会直接 ENOENT。
# 这在从管理员窗口或异常用户环境运行时比较常见，先固定到当前用户的 APPDATA。
function Initialize-NpmEnvironment {
  $appData = $env:APPDATA
  if ([string]::IsNullOrWhiteSpace($appData)) {
    $appData = [Environment]::GetFolderPath("ApplicationData")
  }
  if ([string]::IsNullOrWhiteSpace($appData)) {
    throw "无法定位当前用户的 AppData\\Roaming 目录，请检查 Windows 用户环境变量 APPDATA"
  }

  $localAppData = $env:LOCALAPPDATA
  if ([string]::IsNullOrWhiteSpace($localAppData)) {
    $localAppData = [IO.Path]::GetTempPath()
  }

  $prefix = Join-Path $appData "npm"
  $cache = Join-Path $localAppData "npm-cache"

  New-Item -ItemType Directory -Path $prefix -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $prefix "node_modules") -Force | Out-Null
  New-Item -ItemType Directory -Path $cache -Force | Out-Null

  $env:npm_config_prefix = $prefix
  $env:npm_config_cache = $cache

  if (($env:Path -split ';') -notcontains $prefix) {
    $env:Path = "$prefix;$env:Path"
  }

  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $userPathParts = @($userPath -split ';' | Where-Object { $_ })
  if ($userPathParts -notcontains $prefix) {
    $newUserPath = (@($prefix) + $userPathParts) -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
  }
}

# ---------------------------------------------------------------------------
# 确保 Node / npm 可用；没有则用正常方式安装 (winget 优先，官方 MSI 兜底)
# ---------------------------------------------------------------------------
function Ensure-Node {
  Write-Step "`n[检查] 检查 Node.js 环境..."

  if (Get-Command node -ErrorAction SilentlyContinue) {
    $v = (& node -v) 2>$null
    Write-Ok "已检测到 Node.js $v，跳过安装"
    Initialize-NpmEnvironment
    return
  }

  # 旧系统 (Win7/8/8.1) 不尝试自动安装：自动安装会失败，改为引导手动安装
  if (Test-OldWindows) {
    Show-OldSystemGuide
    throw "请先手动安装 Node.js 后再运行本工具"
  }

  Write-Warn "[提示] 未检测到 Node.js，开始自动安装..."
  Write-Warn "[重要] 安装过程可能弹出权限确认窗口，请点击【是】以继续。"

  # --- 方式一: winget (Windows 10 1709+/Windows 11 自带) ---
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Step "[安装] 使用 winget 安装 Node.js LTS ..."
    try {
      winget install -e --id OpenJS.NodeJS.LTS --silent `
        --accept-source-agreements --accept-package-agreements
    } catch { }
    Refresh-Path
    if (Get-Command node -ErrorAction SilentlyContinue) {
      Initialize-NpmEnvironment
      Write-Ok "Node.js 安装完成 $(& node -v)"
      return
    }
    Write-Warn "[提示] winget 安装未生效，改用官方安装包..."
  }

  # --- 方式二: 下载官方 MSI 安装包 ---
  $arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
  $file = "node-v$NodeVersion-$arch.msi"
  $url  = "$NodeMirror/v$NodeVersion/$file"
  $msi  = Join-Path $env:TEMP $file

  Write-Warn "[下载] $url"
  try {
    (New-Object System.Net.WebClient).DownloadFile($url, $msi)
  } catch {
    Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing
  }

  Write-Step "[安装] 正在安装 Node.js (请在弹出的窗口点击【是】)..."
  # /qb = 基本界面有进度条; MSI 会自动触发 UAC 提权
  Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qb /norestart" -Wait
  Remove-Item $msi -Force -ErrorAction SilentlyContinue
  Refresh-Path

  if (Get-Command node -ErrorAction SilentlyContinue) {
    Initialize-NpmEnvironment
    Write-Ok "Node.js 安装完成 $(& node -v)"
    return
  }
  throw "Node.js 自动安装未成功，请手动到 https://nodejs.org 下载安装后重新运行本工具"
}

# ---------------------------------------------------------------------------
# 全局安装指定 npm 包 (已安装则跳过)
# ---------------------------------------------------------------------------
function Ensure-NpmPackage($pkgName) {
  Write-Step "`n[检查] 检查 $pkgName 安装状态..."
  Initialize-NpmEnvironment
  $npm = Get-NpmCommand
  $listed = (& $npm list -g $pkgName --depth=0 2>$null | Out-String)
  if ($listed -match [regex]::Escape($pkgName)) {
    Write-Ok "$pkgName 已安装，跳过"
    return
  }
  Write-Step "[安装] 正在全局安装 $pkgName ..."
  & $npm install -g $pkgName --registry $NpmRegistry
  if ($LASTEXITCODE -ne 0) {
    throw "$pkgName 安装失败，可稍后手动执行: npm install -g $pkgName"
  } else {
    Write-Ok "$pkgName 安装完成"
  }
}

# ---------------------------------------------------------------------------
# JSON 读取 + 合并 (保留用户原有字段)
# ---------------------------------------------------------------------------
function Read-JsonFile($path) {
  if (Test-Path $path) {
    try {
      $raw = Get-Content $path -Raw -Encoding UTF8
      if ($raw.Trim()) { return ($raw | ConvertFrom-Json) }
    } catch { }
  }
  return ([pscustomobject]@{})
}

function Set-Prop($obj, $name, $value) {
  if ($obj.PSObject.Properties[$name]) { $obj.$name = $value }
  else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force }
  return $obj
}

function Write-JsonFile($path, $obj) {
  $dir = Split-Path $path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $obj | ConvertTo-Json -Depth 20 | Set-Content -Path $path -Encoding UTF8
}

# ---------------------------------------------------------------------------
# 读取 API Key
# ---------------------------------------------------------------------------
# 读取一个 API Key (自定义提示语，循环直到格式正确)
function Read-ApiKeyPrompt($prompt) {
  while ($true) {
    $key = (Read-Host $prompt).Trim()
    if (-not $key) { Write-Err "API Key 不能为空"; continue }
    if (-not $key.StartsWith("sk-")) { Write-Err "API Key 格式不正确，应以 sk- 开头"; continue }
    return $key
  }
}

# 询问 Y/n，默认 Y (回车=是)；返回 $true=是 $false=否
function Ask-YesDefault($prompt) {
  $ans = (Read-Host $prompt).Trim().ToLower()
  if ($ans -eq "n" -or $ans -eq "no") { return $false }
  return $true
}

# ---------------------------------------------------------------------------
# 配置 Claude Code
# ---------------------------------------------------------------------------
function Configure-Claude($presetKey) {
  Ensure-NpmPackage "@anthropic-ai/claude-code"

  Write-Warn "[提示] 粘贴方式: 鼠标右键 或 Shift+Insert"
  $key = if ($presetKey) { $presetKey } else { Read-ApiKeyPrompt "请输入你的 Claude API Key (sk-xxx)" }
  if (-not $key) { return }

  $claudeDir   = Join-Path $env:USERPROFILE ".claude"
  $configPath  = Join-Path $claudeDir "config.json"
  $settingsPath= Join-Path $claudeDir "settings.json"

  # config.json: { primaryApiKey: "1" }
  $config = Read-JsonFile $configPath
  $config = Set-Prop $config "primaryApiKey" "1"
  Write-JsonFile $configPath $config

  # settings.json: { env: { ... } }
  $settings = Read-JsonFile $settingsPath
  $envObj = if ($settings.PSObject.Properties["env"]) { $settings.env } else { [pscustomobject]@{} }
  $envObj = Set-Prop $envObj "ANTHROPIC_AUTH_TOKEN" $key
  $envObj = Set-Prop $envObj "ANTHROPIC_BASE_URL" $BaseUrl
  $envObj = Set-Prop $envObj "ANTHROPIC_SMALL_FAST_MODEL" $SmallModel
  $settings = Set-Prop $settings "env" $envObj
  Write-JsonFile $settingsPath $settings
  Write-Ok "配置文件已写入 $claudeDir"

  # 系统用户环境变量 (新开终端生效)
  [Environment]::SetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", $key, "User")
  [Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", $BaseUrl, "User")
  [Environment]::SetEnvironmentVariable("ANTHROPIC_SMALL_FAST_MODEL", $SmallModel, "User")
  Write-Ok "用户环境变量已设置"
}

# ---------------------------------------------------------------------------
# 配置 Codex
# ---------------------------------------------------------------------------
function Configure-Codex($presetKey) {
  Ensure-NpmPackage "@openai/codex"

  Write-Warn "[提示] 粘贴方式: 鼠标右键 或 Shift+Insert"
  $key = if ($presetKey) { $presetKey } else { Read-ApiKeyPrompt "请输入你的 OpenAI API Key (sk-xxx)" }
  if (-not $key) { return }

  $codexDir  = Join-Path $env:USERPROFILE ".codex"
  $tomlPath  = Join-Path $codexDir "config.toml"
  $authPath  = Join-Path $codexDir "auth.json"
  if (-not (Test-Path $codexDir)) { New-Item -ItemType Directory -Path $codexDir -Force | Out-Null }

  # config.toml: 写入 AnyAIGC 规范配置块
  $toml = @"
model_provider = "codex"
model = "$CodexModel"
model_reasoning_effort = "high"
disable_response_storage = true

[model_providers.codex]
name = "codex"
base_url = "$BaseUrl/v1"
wire_api = "responses"
requires_openai_auth = true
"@
  Set-Content -Path $tomlPath -Value $toml -Encoding UTF8

  # auth.json: { OPENAI_API_KEY: "sk-xxx" }
  $auth = Read-JsonFile $authPath
  $auth = Set-Prop $auth "OPENAI_API_KEY" $key
  Write-JsonFile $authPath $auth
  Write-Ok "配置文件已写入 $codexDir"

  # 写入 VS Code / Cursor 配置 (若存在)
  Update-EditorConfig (Join-Path $env:APPDATA "Code\User\settings.json")   "VS Code"
  Update-EditorConfig (Join-Path $env:APPDATA "Cursor\User\settings.json") "Cursor"
}

# 更新编辑器 settings.json 中的 chatgpt.* 字段
function Update-EditorConfig($path, $name) {
  if (-not (Test-Path $path)) { return }
  $s = Read-JsonFile $path
  $s = Set-Prop $s "chatgpt.apiBase" "$BaseUrl/v1"
  $cfg = [pscustomobject]@{
    preferred_auth_method  = "apikey"
    model                  = $CodexModel
    model_reasoning_effort = "high"
    wire_api               = "responses"
  }
  $s = Set-Prop $s "chatgpt.config" $cfg
  Write-JsonFile $path $s
  Write-Ok "$name 配置已更新"
}

# ---------------------------------------------------------------------------
# 完成提示
# ---------------------------------------------------------------------------
function Show-Done($target) {
  Write-Host ""
  Write-Host ("=" * 60) -ForegroundColor Yellow
  Write-Host "  安装配置完成，开启你的 AI 编程之旅" -ForegroundColor Yellow
  Write-Host ("=" * 60) -ForegroundColor Yellow
  Write-Host ""
  Write-Warn "请【重新打开终端】使环境变量生效，然后运行:"
  switch ($target) {
    "both"   { Write-Host "    claude   或   codex" -ForegroundColor Green }
    "claude" { Write-Host "    claude" -ForegroundColor Green }
    "codex"  { Write-Host "    codex" -ForegroundColor Green }
  }
  Write-Host ""
}

# ---------------------------------------------------------------------------
# 判断是否为旧系统 (Windows 10 以下：Win7/8/8.1)
# ---------------------------------------------------------------------------
function Test-OldWindows {
  return ([Environment]::OSVersion.Version.Major -lt 10)
}

function Get-WindowsName {
  $v = [Environment]::OSVersion.Version
  switch ("$($v.Major).$($v.Minor)") {
    "6.1" { "Windows 7" }
    "6.2" { "Windows 8" }
    "6.3" { "Windows 8.1" }
    default { "当前系统 (版本 $($v.Major).$($v.Minor))" }
  }
}

# 旧系统上没有 Node 时：给出友好的手动安装引导 (不尝试自动安装)
function Show-OldSystemGuide {
  $name = Get-WindowsName
  Write-Host ""
  Write-Warn "[提示] 检测到 $name，本工具的【自动安装】功能不支持此系统。"
  Write-Warn ""
  Write-Warn "  你可以手动安装后再使用本工具的配置功能:"
  Write-Warn "    1) 前往 https://nodejs.org 下载并安装 Node.js"
  Write-Warn "    2) 安装完成后，重新运行本命令即可自动完成配置"
  Write-Warn ""
  Write-Warn "  请注意: Windows 7 可能无法运行新版 Node.js (v22) 与 Claude Code,"
  Write-Warn "          它们已停止支持 Windows 10 以下的系统。"
  Write-Warn "          如遇无法运行，建议升级到 Windows 10 / 11。"
  Write-Host ""
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
function Main {
  Show-Logo

  $choice = $Product.ToLower()
  if (-not $choice -and $args.Count -gt 0) { $choice = "$($args[0])".ToLower() }

  if (-not $choice) {
    Write-Host "  请选择要安装配置的工具:" -ForegroundColor Cyan
    Write-Host "    1) 同时安装 Claude Code + Codex  (推荐, 默认)"
    Write-Host "    2) 仅 Claude Code"
    Write-Host "    3) 仅 Codex"
    Write-Host ""
    while (-not $choice) {
      $sel = (Read-Host "请输入序号 [1/2/3] (回车默认 1)").Trim()
      switch ($sel) {
        ""  { $choice = "both" }     # 回车 = 默认同时安装
        "1" { $choice = "both" }
        "2" { $choice = "claude" }
        "3" { $choice = "codex" }
        default { Write-Err "无效输入 '$sel'，请输入 1、2 或 3 (或直接回车选默认)" }
      }
    }
  }

  # 规范化别名
  switch -Wildcard ($choice) {
    "claude*" { $choice = "claude" }
    "codex*"  { $choice = "codex" }
    "all"     { $choice = "both" }
    "both"    { $choice = "both" }
    default   { $choice = "both" }
  }

  try {
    Ensure-Node    # 环境只准备一次
    switch ($choice) {
      "both" {
        # 同时安装: 先输一次 Key，再询问是否两边复用
        $sharedKey = Read-ApiKeyPrompt "请输入你的 API Key (sk-xxx)"
        Write-Host ""
        if (Ask-YesDefault "Claude 和 Codex 使用同一个 Key 吗? (同一个直接回车 / 想分开统计用量输入 n) [Y/n]") {
          Write-Ok "两边均使用该 Key"
          Configure-Claude $sharedKey
          Configure-Codex  $sharedKey
        } else {
          $codexKey = Read-ApiKeyPrompt "请输入 Codex 专用的 API Key (sk-xxx)"
          Configure-Claude $sharedKey
          Configure-Codex  $codexKey
        }
      }
      "claude" { Configure-Claude }
      "codex"  { Configure-Codex }
    }
    Show-Done $choice
  } catch {
    Write-Err $_.Exception.Message
    exit 1
  }
}

Main
