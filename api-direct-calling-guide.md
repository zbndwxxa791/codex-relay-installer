# API 直接调用教程

这个教程演示如何绕过 Codex / Claude Code 安装脚本，直接用 OpenAI Python SDK 请求 LiteLLM 中转 API。

默认中转地址：

```text
https://litellm.blackwhitedeer.studio/v1
```

默认模型：

```text
gpt-5.5
```

## 1. 安装 Python 依赖

```bash
python -m pip install --upgrade openai
```

如果教程要公开发给别人，建议不要把真实 key 写进代码文件。可以先把 key 放到环境变量里：

PowerShell:

```powershell
$env:LITELLM_API_KEY = "你的 LiteLLM key"
```

Linux / macOS:

```bash
export LITELLM_API_KEY="你的 LiteLLM key"
```

## 2. Chat Completions API 示例

把 `你的 LiteLLM key` 替换成自己的中转 key，然后保存为 `test_chat_completions.py` 运行。

```python
from openai import OpenAI

client = OpenAI(
    api_key="你的 LiteLLM key",
    base_url="https://litellm.blackwhitedeer.studio/v1",
)

resp = client.chat.completions.create(
    model="gpt-5.5",
    messages=[
        {"role": "user", "content": "Reply exactly: OK"}
    ],
)

print(resp.choices[0].message.content)
```

运行：

```bash
python test_chat_completions.py
```

正常情况下会输出：

```text
OK
```

## 3. Responses API JSON 示例

把 `你的 LiteLLM key` 替换成自己的中转 key，然后保存为 `test_responses_json.py` 运行。

```python
from openai import OpenAI

client = OpenAI(
    api_key="你的 LiteLLM key",
    base_url="https://litellm.blackwhitedeer.studio/v1",
)

resp = client.responses.create(
    model="gpt-5.5",
    input='Return JSON only: {"ok": true}',
    text={
        "format": {
            "type": "json_object"
        }
    },
)

print(resp.output_text)
```

运行：

```bash
python test_responses_json.py
```

正常情况下会输出类似：

```json
{"ok": true}
```

## 4. Responses API 普通文本示例

如果不需要 JSON，只要普通文本，可以直接使用 `input` 和 `output_text`。

```python
from openai import OpenAI

client = OpenAI(
    api_key="你的 LiteLLM key",
    base_url="https://litellm.blackwhitedeer.studio/v1",
)

resp = client.responses.create(
    model="gpt-5.5",
    input="用一句话介绍什么是 LiteLLM 中转 API。",
)

print(resp.output_text)
```

## 5. Responses API JSON Schema 示例

如果下游程序需要稳定字段，推荐使用 `json_schema`，比只要求模型返回 JSON 更严格。

```python
from openai import OpenAI

client = OpenAI(
    api_key="你的 LiteLLM key",
    base_url="https://litellm.blackwhitedeer.studio/v1",
)

resp = client.responses.create(
    model="gpt-5.5",
    input="生成一个 API 连通性检查结果：名称是 relay，状态是 true。",
    text={
        "format": {
            "type": "json_schema",
            "name": "check_result",
            "strict": True,
            "schema": {
                "type": "object",
                "properties": {
                    "name": {"type": "string"},
                    "ok": {"type": "boolean"}
                },
                "required": ["name", "ok"],
                "additionalProperties": False
            }
        }
    },
)

print(resp.output_text)
```

正常情况下会输出类似：

```json
{"name":"relay","ok":true}
```

## 6. Responses API 流式输出示例

长文本生成时可以开启 `stream=True`，边生成边接收事件。

```python
from openai import OpenAI

client = OpenAI(
    api_key="你的 LiteLLM key",
    base_url="https://litellm.blackwhitedeer.studio/v1",
)

stream = client.responses.create(
    model="gpt-5.5",
    input="写一段 100 字以内的中转 API 使用说明。",
    stream=True,
)

for event in stream:
    print(event)
```

## 7. 不用 SDK 的 curl 示例

如果只是想快速测试接口，也可以不用 Python SDK，直接发 HTTP 请求。

Windows PowerShell 建议使用 `curl.exe`，避免和 PowerShell 自带别名混淆。

### Chat Completions

```powershell
curl.exe https://litellm.blackwhitedeer.studio/v1/chat/completions `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer 你的 LiteLLM key" `
  -d '{"model":"gpt-5.5","messages":[{"role":"user","content":"Reply exactly: OK"}]}'
```

Linux / macOS:

```bash
curl https://litellm.blackwhitedeer.studio/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer 你的 LiteLLM key" \
  -d '{"model":"gpt-5.5","messages":[{"role":"user","content":"Reply exactly: OK"}]}'
```

### Responses

```powershell
curl.exe https://litellm.blackwhitedeer.studio/v1/responses `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer 你的 LiteLLM key" `
  -d '{"model":"gpt-5.5","input":"Return JSON only: {\"ok\": true}","text":{"format":{"type":"json_object"}}}'
```

Linux / macOS:

```bash
curl https://litellm.blackwhitedeer.studio/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer 你的 LiteLLM key" \
  -d '{"model":"gpt-5.5","input":"Return JSON only: {\"ok\": true}","text":{"format":{"type":"json_object"}}}'
```

## 常见问题

如果提示 `ModuleNotFoundError: No module named 'openai'`，先执行：

```bash
python -m pip install --upgrade openai
```

如果提示认证失败，检查 `api_key` 是否已经替换成自己的 LiteLLM key。

如果提示模型不存在，检查中转服务后台是否已经配置并开放 `gpt-5.5` 这个模型名。
