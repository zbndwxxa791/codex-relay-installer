# Codex 服务器部署与排障

这份说明用于在 Linux 服务器、云主机或 VS Code Remote SSH 远端环境中部署 Codex Relay Installer。它特别适合这些情况：服务器系统比较旧、网络不稳定、Node.js/npm/Codex CLI 缺失，或者终端命令经常出现“未识别”“找不到命令”“连接超时”等问题。

本安装器实际安装和配置的是 Codex CLI。安装包名是 `@openai/codex`，安装后命令是 `codex`。服务器上的 Codex CLI、VS Code Codex 远端插件和同一用户下的 Codex 配置共享：

```text
~/.codex/config.toml
```

默认中转地址是：

```text
https://litellm.blackwhitedeer.studio/v1
```

如果你习惯把它叫做 `openai-cli`，请注意：本安装器不会安装一个名为 `openai-cli` 的命令。

## 推荐流程

建议你按这个顺序处理：

1. 先确认系统、CPU 架构、Shell、网络和代理。
2. 再确认 Node.js、npm、curl、bash 是否可用。
3. 安装或修复 Codex CLI。
4. 运行安装脚本的 `--doctor`，不要一上来就直接安装。
5. `--doctor` 通过后再正式写入 `~/.codex/config.toml`。
6. 用 `--test` 或 `--benchmark` 验证中转是否真的可用。

这样做的好处是：报错会停在最靠近根因的位置，不会把网络问题、Node 问题、npm 问题和 Codex 配置问题混在一起。

## 1. 服务器基础检查

先运行：

```bash
cat /etc/os-release
uname -a
uname -m
echo "$SHELL"
command -v bash || true
command -v curl || true
command -v node || true
command -v npm || true
command -v codex || true
```

重点看：

- Linux 发行版和版本是否过老。
- CPU 是 `x86_64` / `amd64`，还是 `aarch64` / `arm64`。
- 当前是不是 `bash`。Linux/macOS 安装脚本需要用 `bash` 执行，不要用 `sh`。
- `curl` 是否存在。脚本下载、nvm 安装、接口测试都依赖它。
- `node`、`npm`、`codex` 是否在 `PATH` 里。

如果 `bash` 不存在，先安装 bash。Debian / Ubuntu 常见命令：

```bash
sudo apt-get update
sudo apt-get install -y bash curl ca-certificates
```

CentOS / RHEL / Rocky / AlmaLinux 常见命令：

```bash
sudo yum install -y bash curl ca-certificates
```

如果系统太旧，`apt-get` / `yum` 源也不可用，优先让服务器管理员修复系统源或换一台更新的服务器。不要在生产机上盲目手动替换 glibc、OpenSSL 这类系统组件。

## 2. 代理和网络检查

很多部署失败不是脚本问题，而是你的服务器访问不了这些地址：

- `raw.githubusercontent.com`
- `github.com`
- `registry.npmjs.org`
- 你的 relay base URL，例如 `https://litellm.blackwhitedeer.studio/v1`

先测试：

```bash
curl -I https://raw.githubusercontent.com
curl -I https://registry.npmjs.org
curl -I https://litellm.blackwhitedeer.studio/v1/models
```

如果服务器需要代理，只在当前终端临时设置：

```bash
export HTTP_PROXY="http://代理主机:端口"
export HTTPS_PROXY="http://代理主机:端口"
export ALL_PROXY="socks5h://代理主机:端口"
```

然后重新测试：

```bash
curl -I https://raw.githubusercontent.com
curl -I https://registry.npmjs.org
```

注意：`127.0.0.1:7890` 在服务器上代表服务器自己，不代表你本地电脑。如果代理开在你的电脑上，服务器不能直接使用 `http://127.0.0.1:7890`，除非你做了 SSH 端口转发或服务器上也运行了代理。

如果服务器完全不能访问 GitHub，可以在本地电脑下载脚本后上传到服务器：

```bash
scp "install-codex-relay-linux-macos.sh" user@server:/tmp/
ssh user@server
bash "/tmp/install-codex-relay-linux-macos.sh" --doctor
```

## 3. 修复 Node.js 和 npm

先看版本：

```bash
node -v
npm -v
```

Node.js 官方文档建议使用当前受支持的 Node.js 版本运行 npm，并可用 `node -v`、`npm -v` 验证。对于服务器部署，建议优先使用 Node.js LTS。

### 推荐方式：nvm

如果服务器系统较旧，优先用 nvm 装当前 LTS，而不是依赖系统源里的旧 Node.js：

```bash
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm install --lts
nvm use --lts
node -v
npm -v
```

如果提示 `nvm: command not found`，通常是当前 shell 没加载 nvm。退出服务器重新登录，或手动执行：

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
```

### 系统源方式

如果你不想用 nvm，可以用 NodeSource 或服务器发行版的软件源安装 Node.js LTS。旧系统的软件源经常只有很老的 Node.js，这种情况下装出来能看到 `node`，但 npm 安装现代 CLI 时仍可能失败。

如果遇到类似下面的问题：

- `node: command not found`
- `npm: command not found`
- `npm ERR! notsup Unsupported engine`
- `GLIBC_2.xx not found`
- `node: /lib64/libc.so.6: version ... not found`

先不要继续跑安装脚本。优先升级 Node.js LTS；如果是 glibc 太旧，通常说明这台服务器系统年代太久，建议换更新系统、使用容器，或让运维提供更现代的运行环境。

## 4. 安装或修复 Codex CLI

确认 npm 可用后安装：

```bash
npm i -g @openai/codex
```

安装后验证：

```bash
command -v codex
codex --version
codex
```

如果 `npm i -g @openai/codex` 成功，但 `codex` 仍然提示命令不存在，通常是 npm 全局 bin 目录没有进 `PATH`。检查：

```bash
npm bin -g 2>/dev/null || npm config get prefix
npm config get prefix
echo "$PATH"
```

常见修复方式：

```bash
export PATH="$(npm config get prefix)/bin:$PATH"
command -v codex
```

如果你用 nvm，重新加载 nvm 后再查：

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
command -v node
command -v npm
command -v codex
```

确认命令可用后，可以把对应的 `export NVM_DIR=...` 和加载语句写进 `~/.bashrc`。如果是临时服务器或一次性部署，只在当前终端设置也可以。

## 5. 下载并运行安装脚本

能访问 GitHub 时：

```bash
url="https://raw.githubusercontent.com/zbndwxxa791/codex-relay-installer/main/install-codex-relay-linux-macos.sh"
tmp="${TMPDIR:-/tmp}/install-codex-relay-linux-macos.sh"
curl -fsSL "$url" -o "$tmp"
bash "$tmp" --doctor
```

文档示例统一给脚本路径加引号，避免路径里有空格或特殊字符时出错。

先跑诊断：

```bash
bash "$tmp" --doctor
```

诊断能看到 Codex、配置文件、模型接口状态后，再正式安装：

```bash
bash "$tmp"
```

如果服务器已经自己安装好 Codex CLI，不想让脚本检查或询问安装 Codex：

```bash
bash "$tmp" --skip-codex-check
```

如果模型列表拉取不稳定，可以跳过模型选择，直接指定模型：

```bash
bash "$tmp" --no-model-picker --model "gpt-5.5"
```

## 6. 验证中转连接

安装完成后，重新打开终端或重新登录服务器，然后运行：

```bash
codex --version
codex
```

也可以用脚本测试：

```bash
bash "$tmp" --test --base-url "https://litellm.blackwhitedeer.studio/v1"
bash "$tmp" --benchmark
```

`--test` 会发送最小 `POST /v1/responses` 请求。`--benchmark` 会测试：

- `GET /v1/models`
- `POST /v1/responses`
- LiteLLM spend/quota 元数据端点

普通用户 key 没权限访问 spend/quota 元数据端点时，不一定代表中转不可用；关键看 `/models` 和 `/responses` 是否成功。

## 7. VS Code Remote SSH 插件读不到 key

有一种常见情况是：直接 SSH 到 Linux 服务器后，终端里的 `codex` 能用；但 VS Code 通过 Remote SSH 连接同一台服务器时，VS Code Codex 插件仍然提示没有 key、无法鉴权或连接失败。

这通常不是 Codex CLI 本身坏了，而是 VS Code 远端扩展宿主和你手动登录的交互式 shell 不是同一个环境。你在 `~/.bashrc`、`~/.profile`、临时 `export` 或某个终端窗口里设置的环境变量，VS Code 远端插件不一定会继承。

推荐的解决方式是：不要只把 relay key 放在环境变量里，而是写入远端服务器当前用户的 `~/.codex/config.toml`：

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

先在 VS Code 的 Remote SSH 窗口里打开集成终端，确认这个终端确实连到服务器，而不是本机：

```bash
hostname
whoami
echo "$HOME"
pwd -P
command -v codex || true
codex --version 2>/dev/null || true
ls -la ~/.codex
sed -n '1,120p' ~/.codex/config.toml 2>/dev/null
```

重点看三件事：

- VS Code Remote SSH 使用的服务器用户，是否和你手动 SSH 登录时的用户一致。
- `~/.codex/config.toml` 是否在远端服务器用户的 HOME 下，而不是写到了本地电脑。
- provider 里是否真的有 `experimental_bearer_token`，并且 `model_provider = "custom-relay"` 位于文件最前面的顶层区域。

如果你之前只在普通 SSH 终端里设置过环境变量，例如：

```bash
export OPENAI_API_KEY="..."
export HTTP_PROXY="..."
export HTTPS_PROXY="..."
```

那么 VS Code Codex 插件不一定能读到。请优先改成运行安装脚本或手动写 `~/.codex/config.toml`：

```bash
bash "/tmp/install-codex-relay-linux-macos.sh" --no-model-picker --model "gpt-5.5"
```

写完后，不要只重载终端。建议在本机 VS Code 里执行：

1. 打开 Command Palette。
2. 运行 `Remote-SSH: Kill VS Code Server on Host...`。
3. 重新连接该服务器。
4. 再打开 VS Code Codex 插件测试。

如果只是执行 `Developer: Reload Window`，有时远端扩展宿主仍可能保留旧状态；杀掉远端 VS Code Server 后重连更彻底。

如果插件仍然失败，但远端终端里的 `codex` 成功，请继续收集下面的信息：

```bash
whoami
echo "$HOME"
cat ~/.codex/config.toml
env | grep -i proxy || true
curl -I https://litellm.blackwhitedeer.studio/v1/models 2>&1 | head -30
codex --version
```

同时在 VS Code 里查看：

- `Output` 面板里是否有 Codex 相关输出。
- `Developer: Toggle Developer Tools` 里的 Console 是否有鉴权、网络、证书或代理错误。
- Remote SSH 连接的目标主机名和用户是否与上面命令输出一致。

如果服务器访问外网必须走代理，代理也必须存在于服务器侧。你本地电脑的 `127.0.0.1:7890` 对远端 VS Code 插件没有意义；Remote SSH 插件运行在服务器上，它看到的 `127.0.0.1` 是服务器自己。

## 8. 常见报错对照

### `bash: command not found`

服务器没有 bash，或者当前环境 PATH 异常。先安装 bash，或用绝对路径：

```bash
/bin/bash "/tmp/install-codex-relay-linux-macos.sh" --doctor
```

### `sh: 1: Syntax error` 或 `set: Illegal option -o pipefail`

你用了 `sh` 执行脚本。改用 `bash`：

```bash
bash "/tmp/install-codex-relay-linux-macos.sh"
```

### `curl: command not found`

先安装 curl：

```bash
sudo apt-get update && sudo apt-get install -y curl ca-certificates
```

或：

```bash
sudo yum install -y curl ca-certificates
```

### `curl: (6) Could not resolve host`

DNS 或网络不可用。先检查：

```bash
cat /etc/resolv.conf
curl -I https://github.com
```

如果服务器必须走代理，先设置 `HTTP_PROXY` / `HTTPS_PROXY`。

### `curl: (7) Failed to connect` 或一直超时

通常是服务器出站网络被拦、代理没开、代理地址写错，或 relay base URL 不通。先分别测试 GitHub、npm registry 和 relay：

```bash
curl -I https://raw.githubusercontent.com
curl -I https://registry.npmjs.org
curl -I https://litellm.blackwhitedeer.studio/v1/models
```

### `node: command not found`

Node.js 没安装，按上面的 nvm 方式安装 Node.js LTS。

### `npm: command not found`

npm 没安装，或者 Node.js 安装不完整。重新安装 Node.js LTS 后再查：

```bash
node -v
npm -v
```

### `npm ERR! notsup Unsupported engine`

Node.js 版本太旧。用 nvm 安装 LTS：

```bash
nvm install --lts
nvm use --lts
```

### `npm ERR! network` / `ETIMEDOUT` / `ECONNRESET`

npm 访问 registry 失败。先检查：

```bash
npm config get registry
curl -I https://registry.npmjs.org
```

如果需要代理：

```bash
npm config set proxy "$HTTP_PROXY"
npm config set https-proxy "$HTTPS_PROXY"
```

如果只是当前终端临时使用，也可以不写 npm config，只设置环境变量后重试。

### `codex: command not found`

Codex CLI 没装，或者 npm 全局 bin 目录不在 `PATH`。先执行：

```bash
npm i -g @openai/codex
command -v codex
```

如果仍找不到：

```bash
export PATH="$(npm config get prefix)/bin:$PATH"
command -v codex
```

### `Unknown option`

参数写错了。查看帮助：

```bash
bash "/tmp/install-codex-relay-linux-macos.sh" --help
```

### `Permission denied`

不要直接执行脚本文件，使用 bash 调用即可：

```bash
bash "/tmp/install-codex-relay-linux-macos.sh"
```

如果你必须直接执行：

```bash
chmod +x "/tmp/install-codex-relay-linux-macos.sh"
"/tmp/install-codex-relay-linux-macos.sh"
```

### `No such file or directory`

常见原因是路径写错，或者文件名里的空格、`&` 没有加引号。先确认文件存在：

```bash
ls -l /tmp
```

然后用完整路径加引号执行：

```bash
bash "/tmp/install-codex-relay-linux-macos.sh" --doctor
```

### HTTP 401 / 403

API key 错误、过期，或者没有权限访问对应 relay。重新确认 key，再跑：

```bash
bash "$tmp" --test
```

### HTTP 402 / 429

通常是余额、额度、并发或限速问题。不是脚本语法问题，需要检查 relay 后台的额度和限流配置。

### HTTP 404

base URL 可能写错。脚本会拼接 `/models` 和 `/responses`，所以 base URL 通常应类似：

```text
https://你的中转域名/v1
```

不要写成已经带 `/models` 或 `/responses` 的完整接口地址。

## 9. 最小手动兜底

如果服务器怎么都跑不了脚本，但你已经有 Codex CLI，可以手动写配置：

```bash
mkdir -p ~/.codex
nano ~/.codex/config.toml
```

写入：

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

然后验证：

```bash
codex --version
codex
```

## 10. 遇到问题时提供诊断信息

如果你仍然无法部署，请把下面命令的输出发给维护者或服务提供方。不要只发一句“跑不通”，否则很难判断是系统、网络、Node/npm、Codex CLI、代理，还是 relay 配置的问题。

```bash
cat /etc/os-release
uname -m
echo "$SHELL"
command -v bash || true
command -v curl || true
command -v node || true
command -v npm || true
command -v codex || true
node -v 2>/dev/null || true
npm -v 2>/dev/null || true
codex --version 2>/dev/null || true
env | grep -i proxy || true
curl -I https://raw.githubusercontent.com 2>&1 | head -20
curl -I https://registry.npmjs.org 2>&1 | head -20
bash "/tmp/install-codex-relay-linux-macos.sh" --doctor 2>&1 | tail -80
```

如果脚本不在 `/tmp/install-codex-relay-linux-macos.sh`，把最后一行路径换成实际保存位置。
