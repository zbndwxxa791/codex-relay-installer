# Codex / Claude Code Relay Installer

这个仓库提供一组可公开分发的安装脚本和说明文档，用来把本机或服务器上的 AI 编程工具切换到 LiteLLM 中转服务。

当前支持两条配置路径：

- Codex CLI、Codex Desktop、VS Code Codex 插件：使用 OpenAI Responses API 兼容中转，配置写入 `~/.codex/config.toml`。
- Claude Code CLI、VS Code Claude Code 插件：使用 Anthropic Messages 兼容中转，配置写入 `~/.claude/settings.json`。

脚本内置默认 base URL，但不会包含你的 API key。运行时由用户在本机终端交互输入自己的 key。

## 文件速览

| 用途 | 文件 |
| --- | --- |
| Codex Windows 安装脚本 | [install-codex-relay-windows.ps1](install-codex-relay-windows.ps1) |
| Codex Linux/macOS 安装脚本 | [install-codex-relay-linux-macos.sh](install-codex-relay-linux-macos.sh) |
| Claude Code Windows 安装脚本 | [install-claude-code-relay-windows.ps1](install-claude-code-relay-windows.ps1) |
| Claude Code Linux/macOS 安装脚本 | [install-claude-code-relay-linux-macos.sh](install-claude-code-relay-linux-macos.sh) |
| Codex 手动配置 | [codex-manual-config.md](codex-manual-config.md) |
| Codex 服务器排障 | [codex-server-debug.md](codex-server-debug.md) |
| Claude Code 安装说明 | [claude-code-relay-installation.md](claude-code-relay-installation.md) |
| Claude Code 手动配置 | [claude-code-manual-config.md](claude-code-manual-config.md) |
| Claude Code 服务器排障 | [claude-code-server-debug.md](claude-code-server-debug.md) |
| 直接调用 API | [api-direct-calling-guide.md](api-direct-calling-guide.md) |

## 默认地址

Codex 使用 OpenAI Responses API 兼容地址，默认 base URL 带 `/v1`：

```text
https://litellm.blackwhitedeer.studio/v1
```

Claude Code 使用 Anthropic Messages 兼容地址，默认 base URL 不带 `/v1`：

```text
https://litellm.blackwhitedeer.studio
```

Claude Code 会自己请求：

```text
https://litellm.blackwhitedeer.studio/v1/models
https://litellm.blackwhitedeer.studio/v1/messages
```

## 前提

- 中转服务需要开放对应协议：Codex 用 OpenAI Responses API，Claude Code 用 Anthropic Messages。
- 用户需要有自己的 relay API key。
- 默认模型是 `gpt-5.5`，脚本会优先尝试从 `GET /v1/models` 拉取模型列表做模型选择。
- 如果目标机器没有 Node.js/npm，脚本会在需要安装 CLI 时引导补齐 Node.js LTS：Windows 使用 `winget` 安装 `OpenJS.NodeJS.LTS`，Linux/macOS 优先使用 `nvm` 安装 LTS。

## Codex 一键安装

如果你 fork 了这个项目，把下面的 URL 换成自己仓库里的 raw 文件地址。

Windows PowerShell：

```powershell
$url = "https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/install-codex-relay-windows.ps1"
$file = Join-Path $env:TEMP "install-codex-relay-windows.ps1"
Invoke-RestMethod $url -OutFile $file
powershell -NoProfile -ExecutionPolicy Bypass -File $file
```

Linux/macOS：

```bash
url="https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/install-codex-relay-linux-macos.sh"
tmp="${TMPDIR:-/tmp}/install-codex-relay-linux-macos.sh"
curl -fsSL "$url" -o "$tmp"
bash "$tmp"
```

Codex 脚本会提示输入 relay API key 和 default model。安装完成后，Codex CLI、Codex Desktop、VS Code Codex 插件会读取同一个 `~/.codex/config.toml`。

## Claude Code 一键安装

Windows PowerShell：

```powershell
$url = "https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/install-claude-code-relay-windows.ps1"
$file = Join-Path $env:TEMP "install-claude-code-relay-windows.ps1"
Invoke-RestMethod $url -OutFile $file
powershell -NoProfile -ExecutionPolicy Bypass -File $file
```

Linux/macOS：

```bash
url="https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/install-claude-code-relay-linux-macos.sh"
tmp="${TMPDIR:-/tmp}/install-claude-code-relay-linux-macos.sh"
curl -fsSL "$url" -o "$tmp"
bash "$tmp"
```

Claude Code 脚本会提示输入 relay API key 和默认模型。安装完成后，Claude Code CLI 和 VS Code Claude Code 插件会读取同一个 `~/.claude/settings.json`。

## Codex 会写入什么

脚本会先备份：

```text
~/.codex/config.toml.backup-YYYYMMDD-HHMMSS
```

然后写入或更新这些配置：

```toml
# BEGIN CODEX RELAY INSTALLER MANAGED BLOCK
model = "gpt-5.5"
model_provider = "custom-relay"
model_reasoning_effort = "xhigh"
# END CODEX RELAY INSTALLER MANAGED BLOCK

[windows]
sandbox = "elevated"

[projects."/path/to/current/project"]
trust_level = "trusted"

# BEGIN CODEX RELAY INSTALLER MANAGED BLOCK
[model_providers.custom-relay]
name = "custom-relay"
base_url = "https://litellm.blackwhitedeer.studio/v1"
wire_api = "responses"
experimental_bearer_token = "your-relay-api-key"
# END CODEX RELAY INSTALLER MANAGED BLOCK
```

重新运行 Codex 安装脚本会覆盖旧的 `custom-relay` provider 配置，不会堆叠重复 provider 表，也会保留无关的 Codex 配置。API key 会直接写入 `experimental_bearer_token`，不会写入环境变量、shell profile、`launchctl` 或 `environment.d`。

## Claude Code 会写入什么

脚本会先备份：

```text
~/.claude/settings.json.backup-YYYYMMDD-HHMMSS
```

然后在 `settings.json` 的 `env` 下写入或更新这些键：

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://litellm.blackwhitedeer.studio",
    "ANTHROPIC_AUTH_TOKEN": "your-relay-api-key",
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
    "ANTHROPIC_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "gpt-5.5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "gpt-5.5"
  }
}
```

脚本会保留 `settings.json` 里其他已有配置，例如主题、权限、MCP、插件设置等。注意 `ANTHROPIC_BASE_URL` 写中转根地址，不要手动加 `/v1`。

## 常用参数

把 `/path/to/...` 或 `C:\path\to\...` 换成脚本在目标机器上的完整路径。

Codex Linux/macOS：

```bash
installer="/path/to/install-codex-relay-linux-macos.sh"
bash "$installer" --dry-run
bash "$installer" --doctor
bash "$installer" --test
bash "$installer" --benchmark
bash "$installer" --list-models
bash "$installer" --restore
bash "$installer" --uninstall
bash "$installer" --base-url "https://litellm.blackwhitedeer.studio/v1" --model "gpt-5.5"
```

Codex Windows：

```powershell
$installer = "C:\path\to\install-codex-relay-windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Doctor
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -TestConnection
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Benchmark
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -ListModels
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Restore
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Uninstall
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -BaseUrl "https://litellm.blackwhitedeer.studio/v1" -Model "gpt-5.5"
```

Claude Code Linux/macOS：

```bash
installer="/path/to/install-claude-code-relay-linux-macos.sh"
bash "$installer" --dry-run
bash "$installer" --doctor
bash "$installer" --test
bash "$installer" --list-models
bash "$installer" --restore
bash "$installer" --uninstall
bash "$installer" --base-url "https://litellm.blackwhitedeer.studio" --model "gpt-5.5"
```

Claude Code Windows：

```powershell
$installer = "C:\path\to\install-claude-code-relay-windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Doctor
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -TestConnection
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -ListModels
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Restore
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Uninstall
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -BaseUrl "https://litellm.blackwhitedeer.studio" -Model "gpt-5.5"
```

## 诊断和连通性测试

Codex 诊断会检查 Codex CLI、配置文件、API key 配置、模型列表接口是否可达。连通性测试会发送最小 Responses API 请求。一次性测速和额度状态探测可以用 `--benchmark` / `-Benchmark`，它会测试模型列表、最小 Responses 请求耗时，并尝试读取 LiteLLM 的 spend/quota 元数据端点。

Claude Code 诊断会检查 Claude Code CLI、`settings.json`、模型列表接口和 Anthropic Messages 最小请求。`--test` / `-TestConnection` 会调用 `/v1/models` 和 `/v1/messages`。

跳过模型选择可以这样运行：

```powershell
$installer = "C:\path\to\install-codex-relay-windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -NoModelPicker -Model "gpt-5.5"
```

```bash
installer="/path/to/install-codex-relay-linux-macos.sh"
bash "$installer" --no-model-picker --model "gpt-5.5"
```

## 验证

Codex 安装后，重新打开终端或重启 VS Code/Codex Desktop：

```bash
codex --version
codex
```

Claude Code 安装后，重新打开终端或重启 VS Code Claude Code 插件：

```bash
claude --version
claude
```

如果使用 VS Code Remote SSH，配置必须写到远端服务器当前用户的 `~/.codex/config.toml` 或 `~/.claude/settings.json`，不是本地电脑的文件。

## 服务器和手动配置

- Codex 跑在服务器或 Remote SSH 里时，优先看 [codex-server-debug.md](codex-server-debug.md)。
- Claude Code 跑在服务器或 Remote SSH 里时，优先看 [claude-code-server-debug.md](claude-code-server-debug.md)。
- 不能运行脚本时，Codex 看 [codex-manual-config.md](codex-manual-config.md)，Claude Code 看 [claude-code-manual-config.md](claude-code-manual-config.md)。
- 只想验证 relay API 本身时，看 [api-direct-calling-guide.md](api-direct-calling-guide.md)。

## 回滚

恢复最近一次备份：

```powershell
$installer = "C:\path\to\install-codex-relay-windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Restore
```

```bash
installer="/path/to/install-codex-relay-linux-macos.sh"
bash "$installer" --restore
```

卸载脚本管理的 relay 配置：

```powershell
$installer = "C:\path\to\install-codex-relay-windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Uninstall
```

```bash
installer="/path/to/install-codex-relay-linux-macos.sh"
bash "$installer" --uninstall
```

Claude Code 的回滚和卸载使用同名参数，只需把脚本路径换成 `install-claude-code-relay-windows.ps1` 或 `install-claude-code-relay-linux-macos.sh`。
