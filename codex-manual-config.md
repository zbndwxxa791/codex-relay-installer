# Codex 手动配置指南

这份说明用于无法运行安装脚本，或者不想让脚本自动改配置时，手动把 Codex CLI、Codex Desktop 和 VS Code Codex 插件切到自己的 Responses API 兼容中转服务。

## 适用前提

- 中转服务必须兼容 OpenAI Responses API。
- 默认中转地址是 `https://litellm.blackwhitedeer.studio/v1`，如果你的服务地址不同，请替换成自己的 base URL。
- 你需要有自己的 relay API key。
- Codex CLI、Codex Desktop、VS Code Codex 插件读取同一个用户级配置文件：`~/.codex/config.toml`。

## 1. 找到配置文件

Windows PowerShell:

```powershell
$config = Join-Path $env:USERPROFILE ".codex\config.toml"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $config)
notepad $config
```

Linux / macOS:

```bash
mkdir -p ~/.codex
nano ~/.codex/config.toml
```

如果文件不存在，可以新建。改之前建议先备份一份。

Windows PowerShell:

```powershell
$config = Join-Path $env:USERPROFILE ".codex\config.toml"
Copy-Item $config "$config.backup-manual" -ErrorAction SilentlyContinue
```

Linux / macOS:

```bash
cp ~/.codex/config.toml ~/.codex/config.toml.backup-manual 2>/dev/null || true
```

## 2. 写入顶层默认模型

把下面三行放在 `config.toml` 最前面，必须放在任何 `[xxx]` 表之前。

```toml
model = "gpt-5.5"
model_provider = "custom-relay"
model_reasoning_effort = "xhigh"
```

如果文件里已经有旧的 `model`、`model_provider` 或 `model_reasoning_effort`，请只保留一组顶层配置，避免同一个字段重复。

## 3. 写入中转 provider

把下面这一段放在文件后面，并替换 `experimental_bearer_token` 的值。

```toml
[model_providers.custom-relay]
name = "custom-relay"
base_url = "https://litellm.blackwhitedeer.studio/v1"
wire_api = "responses"
experimental_bearer_token = "替换成你的 relay API key"
```

如果你的中转地址不是默认地址，只改 `base_url`：

```toml
base_url = "https://your-relay.example.com/v1"
```

不要改成 `env_key` 或 `env_key_instructions`。当前安装脚本采用的是直接写入 `experimental_bearer_token` 的方式。

## 4. Windows 沙箱配置

Windows 用户建议确保文件里有下面这一段：

```toml
[windows]
sandbox = "elevated"
```

如果已经存在 `[windows]`，只在该表下面保留一行 `sandbox = "elevated"`。不要把 `sandbox = "elevated"` 放到 `[model_providers.custom-relay]` 或 `[projects...]` 下面。

## 5. 可选：信任当前项目

如果 Codex 要在某个项目目录里工作，可以把该目录加入 trusted project。

Windows 示例：

```toml
[projects."C:\\Users\\你的用户名\\Desktop\\你的项目"]
trust_level = "trusted"
```

Linux / macOS 示例：

```toml
[projects."/Users/your-name/your-project"]
trust_level = "trusted"
```

这一步不是连接中转的必要条件，只是减少 Codex 在指定项目里的权限确认。

## 6. 完整示例

最小可用配置如下：

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

如果你还有其他 Codex 配置，可以保留；只要注意顶层 `model` / `model_provider` / `model_reasoning_effort` 必须位于第一个 `[xxx]` 表之前。

## 7. 验证连接

先测试模型列表接口。

Windows PowerShell:

```powershell
$baseUrl = "https://litellm.blackwhitedeer.studio/v1"
$apiKey = "替换成你的 relay API key"
Invoke-RestMethod "$baseUrl/models" -Headers @{ Authorization = "Bearer $apiKey" }
```

Linux / macOS:

```bash
base_url="https://litellm.blackwhitedeer.studio/v1"
api_key="替换成你的 relay API key"
curl -sS "$base_url/models" -H "Authorization: Bearer $api_key"
```

再打开一个新的终端，确认 Codex 能启动：

```bash
codex --version
codex
```

如果 VS Code Codex 插件或 Codex Desktop 已经打开，请完全退出后重新启动，让它们重新读取 `~/.codex/config.toml`。

## 常见错误

- `model_provider` 写在 `[model_providers.custom-relay]` 后面：这会让它落到 provider 表里，而不是顶层配置。请把三行默认模型配置移动到文件最前面。
- provider 表重复：只保留一个 `[model_providers.custom-relay]`。
- `wire_api` 不是 `responses`：Responses 兼容中转应写 `wire_api = "responses"`。
- base URL 多写了一层路径：默认应类似 `https://xxx/v1`，模型接口最终会是 `https://xxx/v1/models`。
- API key 写错或额度不足：通常会在 `/models` 或 `/responses` 请求中表现为 401、402、403 或 429。
- 改完后旧窗口仍然不生效：重开终端、重启 VS Code Codex 插件或 Codex Desktop。

## 回滚

如果手动修改后想恢复，直接用备份覆盖回来。

Windows PowerShell:

```powershell
$config = Join-Path $env:USERPROFILE ".codex\config.toml"
Copy-Item "$config.backup-manual" $config -Force
```

Linux / macOS:

```bash
cp ~/.codex/config.toml.backup-manual ~/.codex/config.toml
```
