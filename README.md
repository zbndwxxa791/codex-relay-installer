# Codex Relay Installer

一键把 Codex CLI、Codex Desktop 和 VS Code Codex 插件切到你自己的 OpenAI
Responses API 兼容中转服务。

这个项目适合公开分发给用户运行。脚本内置默认 base URL，但不会包含你的 API key；用户在本机终端交互粘贴自己的 key。

## 前提

- 中转服务必须支持 OpenAI Responses API。
- base URL 默认使用 `https://litellm.blackwhitedeer.studio/v1`，也可以用参数覆盖。
- 用户需要有自己的 API key。
- Codex CLI、Codex Desktop、VS Code Codex 插件共享 `~/.codex/config.toml`。脚本写好这个文件后，三个入口会读取同一套 provider 配置。

## 一键运行

把下面的 `RAW_URL` 替换成你发布后的真实 raw 文件地址。

### Windows PowerShell

```powershell
$url = "https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/install%20for%20Windows.ps1"
$file = Join-Path $env:TEMP "install for Windows.ps1"
Invoke-RestMethod $url -OutFile $file
powershell -NoProfile -ExecutionPolicy Bypass -File $file
```

### Linux / macOS

```bash
url="https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/install%20for%20Linux%26macOS.sh"
tmp="${TMPDIR:-/tmp}/install for Linux&macOS.sh"
curl -fsSL "$url" -o "$tmp"
bash "$tmp"
```

运行时脚本会提示用户输入：

- relay API key
- default model，脚本会优先尝试从 `GET /v1/models` 拉取模型列表，让用户选择；失败时再手动输入

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
# END CODEX RELAY INSTALLER MANAGED BLOCK

[windows]
sandbox = "elevated"

# BEGIN CODEX RELAY INSTALLER MANAGED BLOCK
[model_providers.custom-relay]
name = "custom-relay"
base_url = "https://litellm.blackwhitedeer.studio/v1"
wire_api = "responses"
env_key = "CODEX_RELAY_API_KEY"
env_key_instructions = "Set CODEX_RELAY_API_KEY in your user environment."
# END CODEX RELAY INSTALLER MANAGED BLOCK
```

Rerunning the installer overwrites the old `custom-relay` provider config instead of stacking duplicate provider tables, while keeping unrelated Codex settings. Windows sandbox will be normalized into `[windows]` as `sandbox = "elevated"`. If it was accidentally appended at the end of the file and landed under another TOML table, rerunning the installer moves it back to the right table.

API key 默认写入当前用户的环境变量 `CODEX_RELAY_API_KEY`，不会写进 `config.toml`。

Windows 会写入用户环境变量。Linux/macOS 会写入当前 shell profile；macOS 还会尝试 `launchctl setenv`，Linux 会额外写入 `~/.config/environment.d/codex-relay.conf`。改完后建议重启终端、VS Code 和 Codex Desktop。

## 常用参数

Linux/macOS:

```bash
installer="$HOME/Desktop/中转api安装脚本/install for Linux&macOS.sh"
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
$installer = "C:\Users\wjj20\Desktop\中转api安装脚本\install for Windows.ps1"
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
$installer = "C:\Users\wjj20\Desktop\中转api安装脚本\install for Windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Doctor
```

```bash
installer="$HOME/Desktop/中转api安装脚本/install for Linux&macOS.sh"
bash "$installer" --doctor
```

它会检查 Codex CLI、配置文件、API key 环境变量、模型列表接口是否可达。

连通性测试会发送最小 Responses API 请求。一次性测速和额度状态探测可以用 `--benchmark` / `-Benchmark`，它会测试模型列表、最小 Responses 请求耗时，并尝试读取 LiteLLM 的 spend/quota 元数据端点；普通用户 key 无权读取元数据时会给出提示，但不代表请求额度不可用。

```powershell
$installer = "C:\Users\wjj20\Desktop\中转api安装脚本\install for Windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -TestConnection -BaseUrl "https://litellm.blackwhitedeer.studio/v1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Benchmark
```

```bash
installer="$HOME/Desktop/中转api安装脚本/install for Linux&macOS.sh"
bash "$installer" --test --base-url "https://litellm.blackwhitedeer.studio/v1"
bash "$installer" --benchmark
```

模型选择器会调用 `GET /v1/models`，让用户从中转实际返回的模型列表中选择默认模型。也可以跳过模型选择：

```powershell
$installer = "C:\Users\wjj20\Desktop\中转api安装脚本\install for Windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -NoModelPicker -Model "gpt-5.5"
```

```bash
installer="$HOME/Desktop/中转api安装脚本/install for Linux&macOS.sh"
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
$installer = "C:\Users\wjj20\Desktop\中转api安装脚本\install for Windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Restore
```

```bash
installer="$HOME/Desktop/中转api安装脚本/install for Linux&macOS.sh"
bash "$installer" --restore
```

卸载中转配置并清理脚本写入的环境变量配置：

```powershell
$installer = "C:\Users\wjj20\Desktop\中转api安装脚本\install for Windows.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Uninstall
```

```bash
installer="$HOME/Desktop/中转api安装脚本/install for Linux&macOS.sh"
bash "$installer" --uninstall
```
