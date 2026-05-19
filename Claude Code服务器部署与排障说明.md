# Claude Code 服务器部署与排障说明

这份说明用于服务器、远程开发机、VS Code Remote SSH、云主机和多系统环境。核心原则只有一个：

Claude Code 在哪里运行，就把 `~/.claude/settings.json` 写到哪里的当前用户目录。

如果你在本机 VS Code 里打开本地项目，配置写本机。如果你用 VS Code Remote SSH 连接 Linux 服务器，Claude Code 插件实际在远端运行，配置就必须写到远端服务器用户的 `~/.claude/settings.json`。

## 默认中转地址

```text
https://litellm.blackwhitedeer.studio
```

Claude Code 会请求：

```text
https://litellm.blackwhitedeer.studio/v1/models
https://litellm.blackwhitedeer.studio/v1/messages
```

## Linux 服务器

SSH 到服务器后运行：

```bash
installer="/path/to/install Claude Code for Linux&macOS.sh"
bash "$installer"
```

诊断：

```bash
bash "$installer" --doctor
bash "$installer" --test
```

检查配置：

```bash
ls -la ~/.claude
sed -n '1,160p' ~/.claude/settings.json
command -v claude || true
claude --version 2>/dev/null || true
```

如果服务器没有 Claude Code CLI：

```bash
npm install -g @anthropic-ai/claude-code
```

## Windows 服务器或远程 Windows 桌面

在目标 Windows 用户下运行：

```powershell
$installer = "C:\path\to\install Claude Code for Windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer
```

诊断：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Doctor
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -TestConnection
```

检查配置：

```powershell
$config = Join-Path $env:USERPROFILE ".claude\settings.json"
Test-Path $config
Get-Content $config
Get-Command claude -ErrorAction SilentlyContinue
claude --version
```

如果 PowerShell 的 `npm.ps1` 被执行策略拦截，使用：

```powershell
npm.cmd install -g @anthropic-ai/claude-code
```

## macOS 远程机器

```bash
installer="/path/to/install Claude Code for Linux&macOS.sh"
bash "$installer"
bash "$installer" --doctor
bash "$installer" --test
```

检查：

```bash
ls -la ~/.claude
cat ~/.claude/settings.json
command -v claude || true
claude --version 2>/dev/null || true
```

## VS Code Remote SSH

有一种常见情况是：你在本地 PowerShell 或本地终端配置好了 Claude Code，但 VS Code Remote SSH 里的 Claude Code 插件仍然报鉴权失败。

原因通常是插件运行在远端，读取远端用户的：

```text
~/.claude/settings.json
```

而不是本机的：

```text
C:\Users\<你>\.claude\settings.json
```

解决方式：

1. 用 VS Code Remote SSH 连接服务器。
2. 在 VS Code 的远端终端里运行 Linux/macOS 脚本。
3. 运行 `bash "$installer" --doctor`。
4. 完全关闭并重新打开 Claude Code 插件面板。

## 手动连通性排查

Linux/macOS：

```bash
base_url="https://litellm.blackwhitedeer.studio"
api_key="替换成你的 relay API key"
curl -sS "$base_url/v1/models" -H "Authorization: Bearer $api_key"
curl -sS "$base_url/v1/messages" \
  -H "Authorization: Bearer $api_key" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"gpt-5.5","max_tokens":16,"messages":[{"role":"user","content":"ping"}]}'
```

Windows PowerShell：

```powershell
$baseUrl = "https://litellm.blackwhitedeer.studio"
$apiKey = "替换成你的 relay API key"
Invoke-RestMethod "$baseUrl/v1/models" -Headers @{ Authorization = "Bearer $apiKey" }
```

如果 `/v1/models` 成功但 `/v1/messages` 失败，优先检查模型名和 key 权限。如果 `/v1/models` 也失败，优先检查 base URL、DNS、代理和 key。

## 错误对照

- `401`：key 不存在、错误、过期，或该 key 没有这个路由权限。
- `402`：余额、额度或计费限制。
- `403`：key 有效，但没有访问该模型或路由的权限。
- `404`：base URL 写错，尤其是误写成 `.../v1` 导致拼出 `.../v1/v1/messages`。
- `429`：限流。
- `5xx`：中转服务或上游模型服务异常。

## 回滚

Windows：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Restore
```

Linux/macOS：

```bash
bash "$installer" --restore
```

只移除本脚本管理的 Claude relay 环境变量：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Uninstall
```

```bash
bash "$installer" --uninstall
```
