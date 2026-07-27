# 安装脚本使用说明

这份说明面向正在安装 Codex 或 Claude Code 中转配置的用户。请选择你的操作系统和要使用的工具，然后复制下载页提供的一条命令运行。

## 选择脚本

| 你的系统 | 使用 Codex | 使用 Claude Code |
| --- | --- | --- |
| Windows | `install-codex-relay-windows.ps1` | `install-claude-code-relay-windows.ps1` |
| macOS | `install-codex-relay-macos.sh` | `install-claude-code-relay-macos.sh` |
| Linux | `install-codex-relay-linux.sh` | `install-claude-code-relay-linux.sh` |

## 运行前准备

- 准备好你的 relay API key。脚本运行时会在终端里要求输入。
- 不要把 key 发给别人，也不要粘到网页聊天框里。
- 安装过程中可能会请求安装 Node.js、Codex CLI 或 Claude Code CLI，请按终端提示确认。
- 安装完成后，重启已经打开的 Codex、Claude Code 或 VS Code 插件窗口。

## 一条命令安装

请从下载页复制与你系统和工具匹配的命令。命令会下载并运行安装脚本；Node.js、CLI 安装、模型选择和配置写入都会由脚本自动完成。

如果下载页只提供脚本下载地址，可以按下面格式运行。把 `<脚本下载地址>` 替换成下载页给你的实际地址。

Windows PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Join-Path $env:TEMP 'relay-installer.ps1'; Invoke-RestMethod '<脚本下载地址>' -OutFile $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p"
```

macOS / Linux：

```bash
curl -fsSL "<脚本下载地址>" | bash
```

## 手动下载后运行

如果你已经把脚本文件下载到本机，先进入脚本所在目录，再运行对应命令。

Windows Codex：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-codex-relay-windows.ps1
```

Windows Claude Code：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-claude-code-relay-windows.ps1
```

macOS Codex：

```bash
bash ./install-codex-relay-macos.sh
```

macOS Claude Code：

```bash
bash ./install-claude-code-relay-macos.sh
```

Linux Codex：

```bash
bash ./install-codex-relay-linux.sh
```

Linux Claude Code：

```bash
bash ./install-claude-code-relay-linux.sh
```

## 安装后写入的位置

Codex 会写入：

```text
~/.codex/config.toml
```

Claude Code 会写入：

```text
~/.claude/settings.json
```

脚本会在修改前自动备份已有配置。

## 更新模型列表

安装完成后，选择与你的系统和工具匹配的更新脚本：

| 系统 | Codex | Claude Code |
| --- | --- | --- |
| Windows | `update-codex-relay-windows.ps1` | `update-claude-code-relay-windows.ps1` |
| macOS | `update-codex-relay-macos.sh` | `update-claude-code-relay-macos.sh` |
| Linux | `update-codex-relay-linux.sh` | `update-claude-code-relay-linux.sh` |

默认运行方式是 `refresh`，只更新模型列表，不改变当前默认模型。

Windows：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\update-codex-relay-windows.ps1 -Mode refresh
powershell -NoProfile -ExecutionPolicy Bypass -File .\update-claude-code-relay-windows.ps1 -Mode refresh
```

macOS：

```bash
bash ./update-codex-relay-macos.sh --mode refresh
bash ./update-claude-code-relay-macos.sh --mode refresh
```

Linux：

```bash
bash ./update-codex-relay-linux.sh --mode refresh
bash ./update-claude-code-relay-linux.sh --mode refresh
```

`list` 只显示模型，`switch` 才切换默认模型：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\update-codex-relay-windows.ps1 -Mode list
powershell -NoProfile -ExecutionPolicy Bypass -File .\update-codex-relay-windows.ps1 -Mode switch -Model "gpt-5.5"
```

```bash
bash ./update-codex-relay-linux.sh --mode list
bash ./update-codex-relay-linux.sh --mode switch --model "gpt-5.5"
```

### 不访问网络，直接提供模型列表

下面三种手动来源只能选一种。启用后脚本不会访问 `/v1/models`。

Windows：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\update-codex-relay-windows.ps1 -Models "gpt-5.5","gpt-5.6"
powershell -NoProfile -ExecutionPolicy Bypass -File .\update-claude-code-relay-windows.ps1 -ModelsFile "C:\path\to\models.json"
powershell -NoProfile -ExecutionPolicy Bypass -File .\update-codex-relay-windows.ps1 -Manual
```

macOS / Linux：

```bash
bash ./update-codex-relay-linux.sh --models "gpt-5.5,gpt-5.6"
bash ./update-claude-code-relay-linux.sh --models-file "/path/to/models.json"
bash ./update-codex-relay-linux.sh --manual
```

### 六类脚本逐一导入清单或交互输入

Windows：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\update-codex-relay-windows.ps1 -ModelsFile "C:\path\models.txt"
powershell -NoProfile -ExecutionPolicy Bypass -File .\update-codex-relay-windows.ps1 -Manual
powershell -NoProfile -ExecutionPolicy Bypass -File .\update-claude-code-relay-windows.ps1 -ModelsFile "C:\path\models.txt"
powershell -NoProfile -ExecutionPolicy Bypass -File .\update-claude-code-relay-windows.ps1 -Manual
```

macOS：

```bash
bash ./update-codex-relay-macos.sh --models-file "/path/models.txt"
bash ./update-codex-relay-macos.sh --manual
bash ./update-claude-code-relay-macos.sh --models-file "/path/models.txt"
bash ./update-claude-code-relay-macos.sh --manual
```

Linux：

```bash
bash ./update-codex-relay-linux.sh --models-file "/path/models.txt"
bash ./update-codex-relay-linux.sh --manual
bash ./update-claude-code-relay-linux.sh --models-file "/path/models.txt"
bash ./update-claude-code-relay-linux.sh --manual
```
文本清单示例：

```text
# 每行一个模型 ID
gpt-5.5
gpt-5.6
```

JSON 清单示例：

```json
{
  "data": [
    {
      "id": "gpt-5.5",
      "display_name": "GPT-5.5",
      "owned_by": "relay",
      "context_window": 128000
    },
    {
      "id": "gpt-5.6"
    }
  ]
}
```

JSON 还可以是字符串数组、对象数组或使用 `models` 数组。重复 ID 会去重，最终列表按 ID 排序。空清单、非法 ID 或多个手动来源同时出现时，脚本会停止且不写配置。

## 手动配置前先看

如果一键脚本不能运行，也可以手动配置。手动配置前请确认：

- 已经安装好要使用的工具：Codex 或 Claude Code。
- 准备好 relay API key。
- 把下面配置里的 `替换成你的 relay API key` 换成自己的 key。
- 如果服务商给了不同模型名，把 `gpt-5.5` 换成服务商提供的模型名。
- 如果配置文件已经存在，建议先复制一份备份，再把下面内容粘进去。

## Windows Codex 手动配置

配置文件位置：

```text
C:\Users\<你的用户名>\.codex\config.toml
```

打开或创建配置文件：

```powershell
$dir = Join-Path $env:USERPROFILE ".codex"
$config = Join-Path $dir "config.toml"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Item $config "$config.backup-manual" -ErrorAction SilentlyContinue
notepad $config
```

把下面内容粘到 `config.toml`。如果文件里已经有旧内容，最无障碍的做法是先保存备份，然后用下面内容整体替换。

```toml
model = "gpt-5.5"
model_provider = "custom-relay"
model_reasoning_effort = "xhigh"

[windows]
sandbox = "elevated"

[model_providers.custom-relay]
name = "custom-relay"
base_url = "https://litellm.blackwhitedeer.studio/v1"
wire_api = "responses"
experimental_bearer_token = "替换成你的 relay API key"
```

保存后关闭 Codex、VS Code Codex 插件或 Codex Desktop，再重新打开。

## macOS Codex 手动配置

配置文件位置：

```text
/Users/<你的用户名>/.codex/config.toml
```

打开或创建配置文件：

```bash
mkdir -p ~/.codex
cp ~/.codex/config.toml ~/.codex/config.toml.backup-manual 2>/dev/null || true
nano ~/.codex/config.toml
```

把下面内容粘到 `config.toml`。如果文件里已经有旧内容，最无障碍的做法是先保存备份，然后用下面内容整体替换。

```toml
model = "gpt-5.5"
model_provider = "custom-relay"
model_reasoning_effort = "xhigh"

[model_providers.custom-relay]
name = "custom-relay"
base_url = "https://litellm.blackwhitedeer.studio/v1"
wire_api = "responses"
experimental_bearer_token = "替换成你的 relay API key"
```

保存后关闭 Codex 或 VS Code Codex 插件，再重新打开。

## Linux Codex 手动配置

配置文件位置：

```text
/home/<你的用户名>/.codex/config.toml
```

打开或创建配置文件：

```bash
mkdir -p ~/.codex
cp ~/.codex/config.toml ~/.codex/config.toml.backup-manual 2>/dev/null || true
nano ~/.codex/config.toml
```

把下面内容粘到 `config.toml`。如果文件里已经有旧内容，最无障碍的做法是先保存备份，然后用下面内容整体替换。

```toml
model = "gpt-5.5"
model_provider = "custom-relay"
model_reasoning_effort = "xhigh"

[model_providers.custom-relay]
name = "custom-relay"
base_url = "https://litellm.blackwhitedeer.studio/v1"
wire_api = "responses"
experimental_bearer_token = "替换成你的 relay API key"
```

保存后关闭 Codex 或 VS Code Codex 插件，再重新打开。

## Windows Claude Code 手动配置

配置文件位置：

```text
C:\Users\<你的用户名>\.claude\settings.json
```

打开或创建配置文件：

```powershell
$dir = Join-Path $env:USERPROFILE ".claude"
$config = Join-Path $dir "settings.json"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Item $config "$config.backup-manual" -ErrorAction SilentlyContinue
notepad $config
```

把下面内容粘到 `settings.json`。如果文件里已经有旧内容，最无障碍的做法是先保存备份，然后用下面内容整体替换。

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://litellm.blackwhitedeer.studio",
    "ANTHROPIC_AUTH_TOKEN": "替换成你的 relay API key",
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
    "ANTHROPIC_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "gpt-5.5"
  }
}
```

保存后关闭 Claude Code、VS Code Claude Code 插件，再重新打开。

## macOS Claude Code 手动配置

配置文件位置：

```text
/Users/<你的用户名>/.claude/settings.json
```

打开或创建配置文件：

```bash
mkdir -p ~/.claude
cp ~/.claude/settings.json ~/.claude/settings.json.backup-manual 2>/dev/null || true
nano ~/.claude/settings.json
```

把下面内容粘到 `settings.json`。如果文件里已经有旧内容，最无障碍的做法是先保存备份，然后用下面内容整体替换。

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://litellm.blackwhitedeer.studio",
    "ANTHROPIC_AUTH_TOKEN": "替换成你的 relay API key",
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
    "ANTHROPIC_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "gpt-5.5"
  }
}
```

保存后关闭 Claude Code 或 VS Code Claude Code 插件，再重新打开。

## Linux Claude Code 手动配置

配置文件位置：

```text
/home/<你的用户名>/.claude/settings.json
```

打开或创建配置文件：

```bash
mkdir -p ~/.claude
cp ~/.claude/settings.json ~/.claude/settings.json.backup-manual 2>/dev/null || true
nano ~/.claude/settings.json
```

把下面内容粘到 `settings.json`。如果文件里已经有旧内容，最无障碍的做法是先保存备份，然后用下面内容整体替换。

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://litellm.blackwhitedeer.studio",
    "ANTHROPIC_AUTH_TOKEN": "替换成你的 relay API key",
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
    "ANTHROPIC_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "gpt-5.5"
  }
}
```

保存后关闭 Claude Code 或 VS Code Claude Code 插件，再重新打开。

## 不运行更新脚本时手动更新模型列表

下面方法用于脚本无法运行时。修改前先关闭 Codex、Claude Code 和对应 VS Code 插件窗口，并备份已有文件。

不要把真实 API key 发给别人，也不要把包含 key 的配置文件提交到 Git。

### 配置路径

| 系统 | Codex catalog | Claude Code 兼容缓存 |
| --- | --- | --- |
| Windows | `C:\Users\<你的用户名>\.codex\cc-switch-model-catalog.json` | `C:\Users\<你的用户名>\.claude\cache\gateway-models.json` |
| macOS | `/Users/<你的用户名>/.codex/cc-switch-model-catalog.json` | `/Users/<你的用户名>/.claude/cache/gateway-models.json` |
| Linux | `/home/<你的用户名>/.codex/cc-switch-model-catalog.json` | `/home/<你的用户名>/.claude/cache/gateway-models.json` |

Windows 备份：

```powershell
$codexDir = Join-Path $env:USERPROFILE ".codex"
$claudeDir = Join-Path $env:USERPROFILE ".claude"
Copy-Item (Join-Path $codexDir "config.toml") (Join-Path $codexDir "config.toml.backup-manual") -ErrorAction SilentlyContinue
Copy-Item (Join-Path $codexDir "cc-switch-model-catalog.json") (Join-Path $codexDir "cc-switch-model-catalog.json.backup-manual") -ErrorAction SilentlyContinue
Copy-Item (Join-Path $claudeDir "settings.json") (Join-Path $claudeDir "settings.json.backup-manual") -ErrorAction SilentlyContinue
Copy-Item (Join-Path $claudeDir "cache\gateway-models.json") (Join-Path $claudeDir "cache\gateway-models.json.backup-manual") -ErrorAction SilentlyContinue
```

macOS 备份：

```bash
cp ~/.codex/config.toml ~/.codex/config.toml.backup-manual 2>/dev/null || true
cp ~/.codex/cc-switch-model-catalog.json ~/.codex/cc-switch-model-catalog.json.backup-manual 2>/dev/null || true
cp ~/.claude/settings.json ~/.claude/settings.json.backup-manual 2>/dev/null || true
cp ~/.claude/cache/gateway-models.json ~/.claude/cache/gateway-models.json.backup-manual 2>/dev/null || true
```

Linux 使用相同命令：

```bash
cp ~/.codex/config.toml ~/.codex/config.toml.backup-manual 2>/dev/null || true
cp ~/.codex/cc-switch-model-catalog.json ~/.codex/cc-switch-model-catalog.json.backup-manual 2>/dev/null || true
cp ~/.claude/settings.json ~/.claude/settings.json.backup-manual 2>/dev/null || true
cp ~/.claude/cache/gateway-models.json ~/.claude/cache/gateway-models.json.backup-manual 2>/dev/null || true
```

### 查看 `/v1/models` 返回值

Windows PowerShell：

```powershell
$headers = @{ Authorization = "Bearer 替换成你的 relay API key" }
Invoke-RestMethod -Uri "https://litellm.blackwhitedeer.studio/v1/models" -Headers $headers -Method Get
```

macOS / Linux：

```bash
curl -sS "https://litellm.blackwhitedeer.studio/v1/models" \
  -H "Authorization: Bearer 替换成你的 relay API key"
```

如果你的服务商要求 `x-api-key`，把请求头改成 `x-api-key: 替换成你的 relay API key`。不要把带 key 的命令保存到公开脚本或 shell 历史。

### 手工更新 Codex catalog

在 `~/.codex/config.toml` 顶层加入下面一行。不要放进 `[model_providers.*]` 小节：

```toml
model_catalog_json = "cc-switch-model-catalog.json"
```

创建 `~/.codex/cc-switch-model-catalog.json`，下面是一份可以直接使用的完整单模型示例。增加模型时复制整个模型对象，再修改 `slug`、`display_name`、`description` 和上下文窗口。

```json
{
  "models": [
    {
      "slug": "gpt-5.5",
      "display_name": "GPT-5.5",
      "description": "Custom relay model",
      "default_reasoning_level": "medium",
      "supported_reasoning_levels": [
        { "effort": "low", "description": "Fast responses with lighter reasoning" },
        { "effort": "medium", "description": "Balanced reasoning" },
        { "effort": "high", "description": "Greater reasoning depth" },
        { "effort": "xhigh", "description": "Extra high reasoning depth" }
      ],
      "shell_type": "shell_command",
      "visibility": "list",
      "supported_in_api": true,
      "priority": 0,
      "additional_speed_tiers": [],
      "service_tiers": [],
      "availability_nux": null,
      "upgrade": null,
      "base_instructions": "You are Codex, a coding agent.",
      "model_messages": null,
      "include_skills_usage_instructions": true,
      "supports_reasoning_summaries": true,
      "default_reasoning_summary": "auto",
      "support_verbosity": true,
      "default_verbosity": "medium",
      "apply_patch_tool_type": "freeform",
      "web_search_tool_type": "text_and_image",
      "truncation_policy": { "mode": "tokens", "limit": 10000 },
      "supports_parallel_tool_calls": true,
      "supports_image_detail_original": true,
      "context_window": 128000,
      "max_context_window": 128000,
      "effective_context_window_percent": 95,
      "experimental_supported_tools": [],
      "input_modalities": ["text", "image"],
      "supports_search_tool": true,
      "use_responses_lite": false
    }
  ]
}
```

只更新列表时不要修改 `config.toml` 里的 `model = "..."`。需要切换默认模型时，再把 `model` 改成 catalog 中对应的 `slug`。

### 手工更新 Claude Code 模型发现和兼容缓存

确认 `~/.claude/settings.json` 的 `env` 中包含下面字段。已有其他设置时应合并，不要直接删除：

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://litellm.blackwhitedeer.studio",
    "ANTHROPIC_AUTH_TOKEN": "替换成你的 relay API key",
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
    "ANTHROPIC_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "gpt-5.5"
  }
}
```

创建目录 `~/.claude/cache`，再创建 `gateway-models.json`：

```json
{
  "baseUrl": "https://litellm.blackwhitedeer.studio",
  "fetchedAt": 0,
  "models": [
    {
      "id": "gpt-5.5",
      "display_name": "GPT-5.5",
      "owned_by": "relay",
      "context_window": 128000
    }
  ]
}
```

Claude Code 新版会在启动时根据 `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1` 主动读取网关 `/v1/models`；`gateway-models.json` 是为旧流程和排障保留的兼容缓存。

完成后完全退出并重新打开 Codex、Claude Code、Codex Desktop 或对应 VS Code 插件窗口。Codex catalog 和 Claude Code 网关模型发现都在启动时加载。

## 手动配置后的检查

Codex：

```bash
codex --version
codex
```

Claude Code：

```bash
claude --version
claude
```

如果是在 Windows PowerShell 里检查，也可以直接运行同样的两条命令。

## 常用检查和恢复

Windows 参数：

```text
-Doctor
-TestConnection
-ListModels
-Restore
-Uninstall
```

macOS / Linux 参数：

```text
--doctor
--test
--list-models
--restore
--uninstall
```

常见用法示例：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-codex-relay-windows.ps1 -Doctor
```

```bash
bash ./install-codex-relay-linux.sh --doctor
```

## 常见问题

- 如果提示没有权限，请确认你在自己的电脑账户下运行终端。
- 如果提示网络连接失败，请检查是否能访问下载页和中转服务。
- 如果提示 key 无效，请重新复制你的 relay API key。
- 如果 VS Code 插件仍然不可用，请完全退出 VS Code 后重新打开。
- 如果是在 Remote SSH 服务器上使用，请在远端终端运行脚本，而不是本地电脑终端。
