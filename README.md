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
| 模型更新脚本 Windows（Codex + Claude Code） | [update-relay-model-windows.ps1](update-relay-model-windows.ps1) |
| 模型更新脚本 Linux/macOS（Codex + Claude Code） | [update-relay-model-linux-macos.sh](update-relay-model-linux-macos.sh) |
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
- Codex 安装脚本会先引导安装 Git、Node.js/npm、Codex CLI；Windows 会继续尝试通过 Microsoft Store 安装 Codex Desktop，macOS 会通过 `codex app` 引导桌面端。
- Claude Code 安装脚本会先引导安装 Node.js/npm 和 Claude Code CLI，再写入 relay 配置。

## Codex 一键安装

如果你 fork 了这个项目，把下面的 URL 换成自己仓库里的 raw 文件地址。

Windows PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-RestMethod 'https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/install-codex-relay-windows.ps1' -OutFile ([IO.Path]::Combine([IO.Path]::GetTempPath(),'install-codex-relay-windows.ps1')); powershell -NoProfile -ExecutionPolicy Bypass -File ([IO.Path]::Combine([IO.Path]::GetTempPath(),'install-codex-relay-windows.ps1'))"
```

Linux/macOS：

```bash
curl -fsSL "https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/install-codex-relay-linux-macos.sh" -o "${TMPDIR:-/tmp}/install-codex-relay-linux-macos.sh"
bash "${TMPDIR:-/tmp}/install-codex-relay-linux-macos.sh"
```

Codex 脚本会提示输入 relay API key 和 default model。安装完成后，Codex CLI、Codex Desktop、VS Code Codex 插件会读取同一个 `~/.codex/config.toml`。

## Claude Code 一键安装

Windows PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-RestMethod 'https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/install-claude-code-relay-windows.ps1' -OutFile ([IO.Path]::Combine([IO.Path]::GetTempPath(),'install-claude-code-relay-windows.ps1')); powershell -NoProfile -ExecutionPolicy Bypass -File ([IO.Path]::Combine([IO.Path]::GetTempPath(),'install-claude-code-relay-windows.ps1'))"
```

Linux/macOS：

```bash
curl -fsSL "https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/install-claude-code-relay-linux-macos.sh" -o "${TMPDIR:-/tmp}/install-claude-code-relay-linux-macos.sh"
bash "${TMPDIR:-/tmp}/install-claude-code-relay-linux-macos.sh"
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

## 更新模型列表

中转平台后续可能加新模型。装好之后想拉最新模型列表、换默认模型，不需要重跑完整安装脚本，运行模型更新脚本就行。Codex 会更新默认 `model` 字段；Claude Code 会确保开启 `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1`，更新 `ANTHROPIC_MODEL`，并从网关模型列表里自动挑出 `sonnet` / `opus` / `haiku` 对应模型写入 `ANTHROPIC_DEFAULT_*_MODEL`。其他配置原样保留，并先写一份带时间戳的备份。

脚本会自动从已有配置里读出 base URL 和 API key，无需重新粘 key。Windows 日常直接用下面三条 PowerShell 7（`pwsh`）指令：Claude Code 一条、Codex 一条、两个一起更新一条。即使用 Windows PowerShell 5.1 的 `powershell` 启动，脚本也会自动转交给 `pwsh`，避免 5.1 解析较大的 Claude `settings.json` 时失败。

### PowerShell 一条指令更新

如果你 fork 了这个项目，把下面命令里的 raw URL 换成自己仓库地址。脚本每次都会重新请求最新模型列表，并把全部模型列出来给你编号选择默认模型。Claude Code 的插件/CLI 会同时打开网关模型发现；重启后如果客户端支持模型发现，就能从中转的 `/v1/models` 看到完整列表并切换。

只更新 Claude Code CLI / VS Code 插件：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -Command '$p = Join-Path $env:TEMP "update-relay-model-windows.ps1"; Invoke-RestMethod "https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/update-relay-model-windows.ps1" -OutFile $p; pwsh -NoProfile -ExecutionPolicy Bypass -File $p -Tool claude'
```

只更新 Codex CLI / Codex Desktop / VS Code 插件：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -Command '$p = Join-Path $env:TEMP "update-relay-model-windows.ps1"; Invoke-RestMethod "https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/update-relay-model-windows.ps1" -OutFile $p; pwsh -NoProfile -ExecutionPolicy Bypass -File $p -Tool codex'
```

Claude Code 和 Codex 一起更新：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -Command '$p = Join-Path $env:TEMP "update-relay-model-windows.ps1"; Invoke-RestMethod "https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/update-relay-model-windows.ps1" -OutFile $p; pwsh -NoProfile -ExecutionPolicy Bypass -File $p -Tool both'
```

Linux/macOS：

```bash
curl -fsSL "https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/update-relay-model-linux-macos.sh" -o "${TMPDIR:-/tmp}/update-relay-model-linux-macos.sh"
bash "${TMPDIR:-/tmp}/update-relay-model-linux-macos.sh"
```

### 常用参数

把 `/path/to/...` 或 `C:\path\to\...` 换成脚本在目标机器上的完整路径。绝大多数情况只需要第一条不带参数的命令，下面其它参数都是特殊场景才用。

Windows：

```powershell
$updater = "C:\path\to\update-relay-model-windows.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File $updater
pwsh -NoProfile -ExecutionPolicy Bypass -File $updater -Tool both
pwsh -NoProfile -ExecutionPolicy Bypass -File $updater -Tool codex
pwsh -NoProfile -ExecutionPolicy Bypass -File $updater -Tool claude
pwsh -NoProfile -ExecutionPolicy Bypass -File $updater -ListModels
pwsh -NoProfile -ExecutionPolicy Bypass -File $updater -DryRun
pwsh -NoProfile -ExecutionPolicy Bypass -File $updater -Model "gpt-5.5"
```

Linux/macOS：

```bash
updater="/path/to/update-relay-model-linux-macos.sh"
bash "$updater"
bash "$updater" --tool both
bash "$updater" --tool codex
bash "$updater" --tool claude
bash "$updater" --list-models
bash "$updater" --dry-run
bash "$updater" --model gpt-5.5
```

参数对照表：

| 参数（Windows / Linux·macOS） | 什么时候用 |
| --- | --- |
| 不带参数 | **日常用这条** |
| `-Tool both` / `--tool both` | 跳过"更新哪个"的提问，Codex 和 Claude Code 一起更 |
| `-Tool codex` / `--tool codex` | 只更 Codex，不动 Claude Code |
| `-Tool claude` / `--tool claude` | 只更 Claude Code，不动 Codex |
| `-ListModels` / `--list-models` | 只想看中转现在有哪些模型，不改任何配置 |
| `-DryRun` / `--dry-run` | 演练一遍，看脚本会怎么改，但不真写文件 |
| `-Model "gpt-5.5"` / `--model gpt-5.5` | 已经知道要换成哪个，跳过交互式选择 |
| `-NoModelPicker` / `--no-picker` | 完全跳过模型选择（配合 `-Model` 使用） |
| `-BaseUrl URL` / `--base-url URL` | 临时覆盖 base URL，不修改已保存的值 |
| `-ApiKey KEY` / `--api-key KEY` | 临时用另一个 key 调用，不修改已保存的值 |

### 注意

- Claude Code 更新脚本依赖本机的 Node.js（和原安装脚本一样，用来合并 `settings.json`）。Codex 更新优先使用 `python3` 替换 TOML 中的 model 行，没有 Python 时自动回落到 `awk` 实现。
- 更新完模型后请重开终端或重启 VS Code / Codex Desktop / Claude Code，让客户端重新读取配置。

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
