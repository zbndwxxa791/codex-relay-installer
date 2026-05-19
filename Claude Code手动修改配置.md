# Claude Code 手动修改配置

如果不运行脚本，也可以手动配置 Claude Code CLI 和 VS Code Claude Code 插件。两者共享：

```text
~/.claude/settings.json
```

## 配置文件位置

Windows：

```text
C:\Users\<你的用户名>\.claude\settings.json
```

Linux：

```text
/home/<你的用户名>/.claude/settings.json
```

macOS：

```text
/Users/<你的用户名>/.claude/settings.json
```

## 推荐配置

把下面内容合并到 `settings.json`。如果文件里已经有 `env`，只添加或替换这些键，不要删除其他配置。

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

注意：这里的 `ANTHROPIC_BASE_URL` 写中转根地址：

```text
https://litellm.blackwhitedeer.studio
```

不要写成：

```text
https://litellm.blackwhitedeer.studio/v1
```

Claude Code 会自己拼出 `/v1/models` 和 `/v1/messages`。

## Windows 手动创建

```powershell
$dir = Join-Path $env:USERPROFILE ".claude"
$config = Join-Path $dir "settings.json"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
notepad $config
```

保存后重启 VS Code 和 Claude Code。

## Linux 手动创建

```bash
mkdir -p ~/.claude
nano ~/.claude/settings.json
```

保存后重新打开终端里的 `claude`。

## macOS 手动创建

```bash
mkdir -p ~/.claude
nano ~/.claude/settings.json
```

保存后重新打开终端里的 `claude`；如果 VS Code 已打开，也要重启 VS Code。

## 连通性测试

Windows PowerShell：

```powershell
$baseUrl = "https://litellm.blackwhitedeer.studio"
$apiKey = "替换成你的 relay API key"
Invoke-RestMethod "$baseUrl/v1/models" -Headers @{ Authorization = "Bearer $apiKey" }
```

Linux/macOS：

```bash
base_url="https://litellm.blackwhitedeer.studio"
api_key="替换成你的 relay API key"
curl -sS "$base_url/v1/models" -H "Authorization: Bearer $api_key"
```

Anthropic Messages 最小测试请求：

```bash
curl -sS "$base_url/v1/messages" \
  -H "Authorization: Bearer $api_key" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"gpt-5.5","max_tokens":16,"messages":[{"role":"user","content":"ping"}]}'
```

正常情况下，返回体应包含：

```json
{
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text"
    }
  ]
}
```

## 常见错误

- `401 Invalid bearer token`：key 错误、过期，或这个 key 没有该路由权限。
- `404 Not Found`：base URL 写错，常见原因是把 `/v1` 写进了 `ANTHROPIC_BASE_URL` 后又被 Claude Code 拼了一次。
- VS Code 插件仍然走旧配置：完全退出 VS Code 后重新打开。
- Remote SSH 不生效：配置写到了本地电脑，实际应该写到远端服务器用户的 `~/.claude/settings.json`。
