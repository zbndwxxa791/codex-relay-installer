# Codex / Claude Code Relay Installer

这个仓库提供可公开分发的一键安装脚本，用来把客户本机上的 AI 编程工具切到 LiteLLM 中转服务。

当前支持 3 个操作系统、2 个工具，共 6 个主安装脚本。所有主脚本都放在 `installers/` 下，仓库根目录的旧脚本只保留为兼容 wrapper。

## 默认协议和地址

Codex 使用 OpenAI Responses API 兼容协议，默认 base URL 带 `/v1`：

```text
https://litellm.blackwhitedeer.studio/v1
```

Claude Code 使用 Anthropic Messages 兼容协议，默认 base URL 不带 `/v1`：

```text
https://litellm.blackwhitedeer.studio
```

脚本不会内置客户 API key。客户运行脚本后，在终端里按提示输入自己的 relay API key 和默认模型。

## 文件速览

| 系统 | Codex | Claude Code |
| --- | --- | --- |
| Windows | `installers/install-codex-relay-windows.ps1` | `installers/install-claude-code-relay-windows.ps1` |
| macOS | `installers/install-codex-relay-macos.sh` | `installers/install-claude-code-relay-macos.sh` |
| Linux | `installers/install-codex-relay-linux.sh` | `installers/install-claude-code-relay-linux.sh` |

兼容入口：

| 旧入口 | 行为 |
| --- | --- |
| `install-codex-relay-windows.ps1` | 转发到 Windows Codex 主脚本 |
| `install-claude-code-relay-windows.ps1` | 转发到 Windows Claude Code 主脚本 |
| `install-codex-relay-linux-macos.sh` | 按 `uname` 转发到 macOS 或 Linux Codex 主脚本 |
| `install-claude-code-relay-linux-macos.sh` | 按 `uname` 转发到 macOS 或 Linux Claude Code 主脚本 |

模型更新脚本同样按操作系统和工具拆成 6 份，每份都可以单独下载运行：

| 系统 | Codex 模型更新 | Claude Code 模型更新 |
| --- | --- | --- |
| Windows | `installers/update-codex-relay-windows.ps1` | `installers/update-claude-code-relay-windows.ps1` |
| macOS | `installers/update-codex-relay-macos.sh` | `installers/update-claude-code-relay-macos.sh` |
| Linux | `installers/update-codex-relay-linux.sh` | `installers/update-claude-code-relay-linux.sh` |

## 安装方式

客户只需要复制对应的一条命令。命令会下载并运行本仓库的安装脚本；脚本内部会按需安装 Node.js、安装对应 CLI、拉取模型列表、提示输入 relay API key 和默认模型，并写好配置。

脚本默认直连官方地址，不写代理环境变量，也不使用第三方 GitHub 加速代理。如果官方安装命令失败，脚本会直接报错并提示用户检查网络或重试。

脚本内部会使用这些官方或系统原生方式：

- Windows Node.js：`winget install -e --id OpenJS.NodeJS.LTS`。
- macOS Node.js：nodejs.org 官方 LTS `.pkg` 和系统 `installer`。
- Linux Node.js：发行版包管理器或 NodeSource LTS 源。
- Codex CLI：Windows 用 `irm https://chatgpt.com/codex/install.ps1 | iex`，macOS/Linux 用 `curl -fsSL https://chatgpt.com/codex/install.sh | sh`。
- Claude Code CLI：Windows 用 `irm https://claude.ai/install.ps1 | iex`，macOS/Linux 用 `curl -fsSL https://claude.ai/install.sh | bash`。

### 网站一条命令

把下面命令里的 `https://your-domain.example` 换成你自己网站的真实域名。

Windows Codex：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Join-Path $env:TEMP 'install-codex-relay-windows.ps1'; Invoke-RestMethod 'https://your-domain.example/installers/install-codex-relay-windows.ps1' -OutFile $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p"
```

Windows Claude Code：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Join-Path $env:TEMP 'install-claude-code-relay-windows.ps1'; Invoke-RestMethod 'https://your-domain.example/installers/install-claude-code-relay-windows.ps1' -OutFile $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p"
```

macOS Codex：

```bash
curl -fsSL "https://your-domain.example/installers/install-codex-relay-macos.sh" | bash
```

macOS Claude Code：

```bash
curl -fsSL "https://your-domain.example/installers/install-claude-code-relay-macos.sh" | bash
```

Linux Codex：

```bash
curl -fsSL "https://your-domain.example/installers/install-codex-relay-linux.sh" | bash
```

Linux Claude Code：

```bash
curl -fsSL "https://your-domain.example/installers/install-claude-code-relay-linux.sh" | bash
```

### GitHub raw 一条命令

如果你先直接用 GitHub 分发，可以使用当前仓库 raw URL。

Windows Codex：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Join-Path $env:TEMP 'install-codex-relay-windows.ps1'; Invoke-RestMethod 'https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/installers/install-codex-relay-windows.ps1' -OutFile $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p"
```

Windows Claude Code：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Join-Path $env:TEMP 'install-claude-code-relay-windows.ps1'; Invoke-RestMethod 'https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/installers/install-claude-code-relay-windows.ps1' -OutFile $p; powershell -NoProfile -ExecutionPolicy Bypass -File $p"
```

macOS Codex：

```bash
curl -fsSL "https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/installers/install-codex-relay-macos.sh" | bash
```

macOS Claude Code：

```bash
curl -fsSL "https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/installers/install-claude-code-relay-macos.sh" | bash
```

Linux Codex：

```bash
curl -fsSL "https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/installers/install-codex-relay-linux.sh" | bash
```

Linux Claude Code：

```bash
curl -fsSL "https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/installers/install-claude-code-relay-linux.sh" | bash
```

## 脚本会写入什么

Codex 脚本会备份并更新：

```text
~/.codex/config.toml
```

核心配置如下：

```toml
model = "gpt-5.5"
model_provider = "custom-relay"
model_reasoning_effort = "xhigh"

[model_providers.custom-relay]
name = "custom-relay"
base_url = "https://litellm.blackwhitedeer.studio/v1"
wire_api = "responses"
experimental_bearer_token = "your-relay-api-key"
```

Claude Code 脚本会备份并更新：

```text
~/.claude/settings.json
```

核心配置如下：

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

## 常用参数

Windows 示例：

```powershell
$installer = "C:\path\to\installers\install-codex-relay-windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Doctor
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -TestConnection
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -ListModels
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Restore
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Uninstall
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -BaseUrl "https://litellm.blackwhitedeer.studio/v1" -Model "gpt-5.5"
```

macOS/Linux 示例：

```bash
installer="/path/to/installers/install-codex-relay-linux.sh"
bash "$installer" --dry-run
bash "$installer" --doctor
bash "$installer" --test
bash "$installer" --list-models
bash "$installer" --restore
bash "$installer" --uninstall
bash "$installer" --base-url "https://litellm.blackwhitedeer.studio/v1" --model "gpt-5.5"
```

Claude Code 参数同名，只需要把脚本路径换成对应 Claude Code 脚本。Codex 额外支持 `-Benchmark` / `--benchmark`。

## 更新模型列表

安装完成后请选择与你的操作系统、工具对应的更新脚本。默认 `refresh` 会刷新模型列表，但不会改变当前默认模型；`switch` 才会切换默认模型。

Windows Codex：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\installers\update-codex-relay-windows.ps1" -Mode refresh
```

Windows Claude Code：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\installers\update-claude-code-relay-windows.ps1" -Mode refresh
```

macOS：

```bash
bash "/path/to/installers/update-codex-relay-macos.sh" --mode refresh
bash "/path/to/installers/update-claude-code-relay-macos.sh" --mode refresh
```

Linux：

```bash
bash "/path/to/installers/update-codex-relay-linux.sh" --mode refresh
bash "/path/to/installers/update-claude-code-relay-linux.sh" --mode refresh
```

查看和切换模型：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\installers\update-codex-relay-windows.ps1" -Mode list
powershell -NoProfile -ExecutionPolicy Bypass -File ".\installers\update-codex-relay-windows.ps1" -Mode switch -Model "gpt-5.5"
```

```bash
bash ./installers/update-codex-relay-linux.sh --mode list
bash ./installers/update-codex-relay-linux.sh --mode switch --model "gpt-5.5"
```

无法或不想访问 `/v1/models` 时，可以显式提供模型列表。使用这些参数后脚本不会发起网络请求：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\installers\update-codex-relay-windows.ps1" -Models "gpt-5.5","gpt-5.6"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\installers\update-claude-code-relay-windows.ps1" -ModelsFile "C:\path\to\models.json"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\installers\update-codex-relay-windows.ps1" -Manual
```

```bash
bash ./installers/update-codex-relay-linux.sh --models "gpt-5.5,gpt-5.6"
bash ./installers/update-claude-code-relay-linux.sh --models-file "/path/to/models.json"
bash ./installers/update-codex-relay-linux.sh --manual
```

### 六类脚本逐一导入清单或交互输入

Windows：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\installers\update-codex-relay-windows.ps1" -ModelsFile "C:\path\models.txt"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\installers\update-codex-relay-windows.ps1" -Manual
powershell -NoProfile -ExecutionPolicy Bypass -File ".\installers\update-claude-code-relay-windows.ps1" -ModelsFile "C:\path\models.txt"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\installers\update-claude-code-relay-windows.ps1" -Manual
```

macOS：

```bash
bash ./installers/update-codex-relay-macos.sh --models-file "/path/models.txt"
bash ./installers/update-codex-relay-macos.sh --manual
bash ./installers/update-claude-code-relay-macos.sh --models-file "/path/models.txt"
bash ./installers/update-claude-code-relay-macos.sh --manual
```

Linux：

```bash
bash ./installers/update-codex-relay-linux.sh --models-file "/path/models.txt"
bash ./installers/update-codex-relay-linux.sh --manual
bash ./installers/update-claude-code-relay-linux.sh --models-file "/path/models.txt"
bash ./installers/update-claude-code-relay-linux.sh --manual
```
文本清单每行一个模型 ID，空行和以 `#` 开头的行会被忽略。JSON 可使用字符串数组、对象数组、OpenAI `data` 格式或 `models` 格式；对象支持 `id`、`display_name`、`owned_by`、`context_window`。

Codex 会更新 `~/.codex/cc-switch-model-catalog.json`，并在 `config.toml` 写入 `model_catalog_json = "cc-switch-model-catalog.json"`。Claude Code 会开启 `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1`，并维护 `~/.claude/cache/gateway-models.json` 兼容缓存。详细手工更新步骤和完整配置见 `installers/README.md`。

## 验证

Codex 安装后重开终端或重启 VS Code/Codex Desktop：

```bash
codex --version
codex
```

Claude Code 安装后重开终端或重启 VS Code Claude Code 插件：

```bash
claude --version
claude
```

如果使用 VS Code Remote SSH，配置必须写到远端服务器当前用户的 `~/.codex/config.toml` 或 `~/.claude/settings.json`，不是本地电脑的文件。

## 排障和手动配置

- Codex 跑在服务器或 Remote SSH 里时，看 `codex-server-debug.md`。
- Claude Code 跑在服务器或 Remote SSH 里时，看 `claude-code-server-debug.md`。
- 不能运行脚本时，Codex 看 `codex-manual-config.md`，Claude Code 看 `claude-code-manual-config.md`。
- 只想验证 relay API 本身时，看 `api-direct-calling-guide.md`。

## 回滚

恢复最近一次备份：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\installers\install-codex-relay-windows.ps1" -Restore
```

```bash
bash "/path/to/installers/install-codex-relay-linux.sh" --restore
```

卸载脚本管理的 relay 配置：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\installers\install-codex-relay-windows.ps1" -Uninstall
```

```bash
bash "/path/to/installers/install-codex-relay-linux.sh" --uninstall
```
