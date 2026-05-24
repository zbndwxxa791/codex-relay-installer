# Codex Relay Installer

一键把 Codex CLI、Codex Desktop 和 VS Code Codex 插件切到你自己的 OpenAI
Responses API 兼容中转服务。

这个项目适合公开分发给用户运行。脚本内置默认 base URL，但不会包含你的 API key；用户在本机终端交互粘贴自己的 key。

## 前提

- 中转服务必须支持 OpenAI Responses API。
- base URL 默认使用 `https://litellm.blackwhitedeer.studio/v1`，也可以用参数覆盖。
- 用户需要有自己的 API key。
- Codex CLI、Codex Desktop、VS Code Codex 插件共享 `~/.codex/config.toml`。脚本写好这个文件后，三个入口会读取同一套 provider 配置。
- 如果用户主机没有 Node.js/npm，脚本在需要安装 Codex CLI 时会先尝试补齐 Node.js LTS：Windows 使用 `winget` 安装 `OpenJS.NodeJS.LTS`，Linux/macOS 使用 `nvm` 安装 LTS。若这些工具不可用，脚本会给出明确的手动安装提示。

## 一键运行

把下面的 `RAW_URL` 替换成你发布后的真实 raw 文件地址。

### Windows PowerShell

```powershell
$url = "https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/install%20for%20Windows.ps1"
$file = Join-Path $env:TEMP "install-codex-relay-windows.ps1"
Invoke-RestMethod $url -OutFile $file
powershell -NoProfile -ExecutionPolicy Bypass -File $file
```

### Linux / macOS

```bash
url="https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/install%20for%20Linux%26macOS.sh"
tmp="${TMPDIR:-/tmp}/install-codex-relay-linux-macos.sh"
curl -fsSL "$url" -o "$tmp"
bash "$tmp"
```

运行时脚本会提示用户输入：

- relay API key
- default model，脚本会优先尝试从 `GET /v1/models` 拉取模型列表，让用户选择；失败时再手动输入

如果本机还没有 Codex CLI，脚本会询问是否执行 `npm i -g @openai/codex`。当 npm 不存在时，脚本会先引导安装 Node.js LTS，而不是直接报错退出。

## 会写入什么

脚本会备份：

```text
~/.codex/config.toml.backup-YYYYMMDD-HHMMSS
```

然后写入一个受控配置块：

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

Rerunning the installer overwrites the old `custom-relay` provider config instead of stacking duplicate provider tables, while keeping unrelated Codex settings. Windows sandbox will be normalized into `[windows]` as `sandbox = "elevated"`. If it was accidentally appended at the end of the file and landed under another TOML table, rerunning the installer moves it back to the right table.

API key 会直接写入 `~/.codex/config.toml` 的 `experimental_bearer_token` 字段。

脚本不会写入用户环境变量、shell profile、`launchctl` 或 `environment.d`。改完后建议重启 VS Code 和 Codex Desktop，让它们重新读取 `config.toml`。

## 常用参数

Replace `/path/to/...` or `C:\path\to\...` with the full path where the script is saved on that machine.

Linux/macOS:

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

Windows:

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

## 诊断和连通性测试

诊断模式不会安装配置，只检查当前环境：

```powershell
$installer = "C:\path\to\install-codex-relay-windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Doctor
```

```bash
installer="/path/to/install-codex-relay-linux-macos.sh"
bash "$installer" --doctor
```

它会检查 Codex CLI、配置文件、API key 配置、模型列表接口是否可达。

连通性测试会发送最小 Responses API 请求。一次性测速和额度状态探测可以用 `--benchmark` / `-Benchmark`，它会测试模型列表、最小 Responses 请求耗时，并尝试读取 LiteLLM 的 spend/quota 元数据端点；普通用户 key 无权读取元数据时会给出提示，但不代表请求额度不可用。

```powershell
$installer = "C:\path\to\install-codex-relay-windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -TestConnection -BaseUrl "https://litellm.blackwhitedeer.studio/v1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Benchmark
```

```bash
installer="/path/to/install-codex-relay-linux-macos.sh"
bash "$installer" --test --base-url "https://litellm.blackwhitedeer.studio/v1"
bash "$installer" --benchmark
```

模型选择器会调用 `GET /v1/models`，让用户从中转实际返回的模型列表中选择默认模型。也可以跳过模型选择：

```powershell
$installer = "C:\path\to\install-codex-relay-windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -NoModelPicker -Model "gpt-5.5"
```

```bash
installer="/path/to/install-codex-relay-linux-macos.sh"
bash "$installer" --no-model-picker --model "gpt-5.5"
```

## 验证

安装后打开一个新终端：

```bash
codex --version
codex
```

VS Code Codex 插件和 Codex Desktop 如果已经打开，需要完全退出后重新启动。

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

卸载中转配置：

```powershell
$installer = "C:\path\to\install-codex-relay-windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Uninstall
```

```bash
installer="/path/to/install-codex-relay-linux-macos.sh"
bash "$installer" --uninstall
```
