# Claude Code Relay 安装指南

这套脚本用于把 Claude Code CLI 和 VS Code Claude Code 插件切换到支持 Anthropic Messages 协议的中转服务。两者共享同一个用户级配置文件：

```text
~/.claude/settings.json
```

默认中转地址为：

```text
https://litellm.blackwhitedeer.studio
```

脚本会让 Claude Code 请求：

```text
https://litellm.blackwhitedeer.studio/v1/models
https://litellm.blackwhitedeer.studio/v1/messages
```

不要把默认地址手动写成 `.../v1`，脚本会自动规范化，避免出现 `.../v1/v1/messages`。

## 前提

- 中转服务必须支持 Anthropic Messages 协议。
- 用户需要自己的中转 API key。
- Claude Code CLI 和 VS Code Claude Code 插件会读取同一个 `~/.claude/settings.json`。
- 改完配置后，需要重启 VS Code 的 Claude Code 插件窗口；如果 CLI 会话已经打开，也需要重新打开。

## Windows PowerShell

把脚本下载或保存到本机后运行：

```powershell
$installer = "C:\path\to\installers\install-claude-code-relay-windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer
```

常用参数：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Doctor
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -TestConnection
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -ListModels
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Restore
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Uninstall
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -BaseUrl "https://litellm.blackwhitedeer.studio" -Model "gpt-5.5"
```

如果需要手动安装 Claude Code CLI，优先使用官方 Windows 命令：

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://claude.ai/install.ps1 | iex"
```

## Linux

```bash
installer="/path/to/installers/install-claude-code-relay-linux.sh"
bash "$installer"
```

常用参数：

```bash
bash "$installer" --dry-run
bash "$installer" --doctor
bash "$installer" --test
bash "$installer" --list-models
bash "$installer" --restore
bash "$installer" --uninstall
bash "$installer" --base-url "https://litellm.blackwhitedeer.studio" --model "gpt-5.5"
```

如果还没有 Claude Code CLI，优先使用官方命令：

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

## macOS

macOS 使用独立脚本：

```bash
installer="/path/to/installers/install-claude-code-relay-macos.sh"
bash "$installer"
```

如果还没有 Claude Code CLI，优先使用官方命令：

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

## 脚本会写入什么

脚本会先备份：

```text
~/.claude/settings.json.backup-YYYYMMDD-HHMMSS
```

然后在 `settings.json` 的 `env` 下写入或覆盖这些键：

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

脚本会保留 `settings.json` 里其他已有配置，例如主题、权限、MCP、插件设置等。

## 验证

运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Doctor
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -TestConnection
```

或：

```bash
bash "$installer" --doctor
bash "$installer" --test
```

`TestConnection` 会调用 `/v1/models` 和 `/v1/messages`，并确认返回体是 Anthropic Messages 格式。

## VS Code Claude Code 插件

VS Code Claude Code 插件读取的是同一个 `~/.claude/settings.json`。脚本运行成功后：

1. 关闭 VS Code 里已有的 Claude Code 面板。
2. 最稳妥的方式是完全退出 VS Code 后重新打开。
3. 重新打开 Claude Code 插件。

如果是在 VS Code Remote SSH 中使用插件，配置必须写在远端服务器用户的 `~/.claude/settings.json`，不是本地电脑的文件。
