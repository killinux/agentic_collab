# Generative Agents: GLM 迁移文档

## 概述

将 [agentic_collab](https://github.com/crcresearch/agentic_collab)（基于论文 "Generative Agents: Interactive Simulacra of Human Behavior" 的模拟框架）从 OpenAI GPT-4o 迁移到智谱 GLM-4 系列模型，并部署在腾讯云上运行。

原项目依赖 OpenAI 的 Structured Outputs（`client.beta.chat.completions.parse()`），该功能是 OpenAI 专有的。迁移后使用 JSON mode + Pydantic 手动解析的方式替代，使代码兼容任何 OpenAI API 格式的 LLM 提供商。

## 改动文件清单

共修改/新增 5 个文件：

```
openai_config.example.json                              [新增] 配置模板
reverie/backend_server/utils.py                         [新增] 项目缺失的配置文件
reverie/backend_server/persona/prompt_template/gpt_structure.py  [修改] LLM 调用核心
environment/frontend_server/translator/views.py         [修改] 前端数据接口
environment/frontend_server/templates/home/main_script.html      [修改] 前端回放速度
```

---

## 一、LLM 后端迁移（GPT-4o → GLM-4）

### 1.1 改了什么

**文件**: `reverie/backend_server/persona/prompt_template/gpt_structure.py`

#### 1.1.1 新增 zhipu client 类型

`setup_client()` 函数原本只支持 `"azure"` 和 `"openai"` 两种 client 类型，新增 `"zhipu"`：

```python
elif type == "zhipu":
    client = OpenAI(
        api_key=config["key"],
        base_url=config.get("base-url", "https://open.bigmodel.cn/api/paas/v4"),
    )
```

原理：智谱 GLM 提供 OpenAI 兼容 API，使用 OpenAI SDK 的 `base_url` 参数即可指向智谱端点。不需要换 SDK。

#### 1.1.2 Structured Outputs 降级为 JSON mode

原代码使用 OpenAI 专有的 `client.beta.chat.completions.parse()`，传入 Pydantic 模型作为 `response_format`，OpenAI 会保证返回严格符合 schema 的 JSON。

GLM 不支持此功能，改为：

```python
# 之前（OpenAI 专有）
completion = client.beta.chat.completions.parse(
    model=..., response_format=PydanticModel, messages=[...]
)
return completion.choices[0].message.parsed

# 之后（兼容所有 OpenAI 格式的提供商）
schema = response_format.model_json_schema()
schema_instruction = f"\n\nYou MUST respond with a JSON object that conforms to this schema:\n{json.dumps(schema)}\nReturn ONLY valid JSON, no extra text."

completion = client.chat.completions.create(
    model=...,
    messages=[{"role": "user", "content": prompt + schema_instruction}],
    response_format={"type": "json_object"},
)
parsed = response_format.model_validate_json(completion.choices[0].message.content)
```

原理：
- `response_format={"type": "json_object"}` 是 GLM 支持的 JSON mode，保证返回合法 JSON
- 将 Pydantic 模型的 JSON Schema 注入到 prompt 中，引导模型输出正确结构
- 用 `model_validate_json()` 做客户端验证和解析

影响范围：项目中有 29 个 Pydantic 模型通过此路径调用，全部自动兼容，无需逐个修改。

涉及的两个函数：
- `ChatGPT_structured_request()` — ChatGPT 风格的结构化请求
- `GPT_structured_request()` — 带参数的结构化请求

#### 1.1.3 移除不兼容参数

`GPT_structured_request()` 中移除了 `frequency_penalty`、`presence_penalty`、`stop` 等 GLM 会忽略的参数，避免潜在兼容性问题。

### 1.2 新增 utils.py

**文件**: `reverie/backend_server/utils.py`

原项目要求用户手动创建此文件但未提供模板。新增的 `utils.py` 从 `openai_config.json` 读取配置，导出项目所需的全部变量：

| 变量 | 用途 |
|------|------|
| `openai_api_key` | LLM API 密钥 |
| `use_openai` | 是否使用 OpenAI 兼容 API |
| `api_model` | 模型名称 |
| `debug` | 调试开关 |
| `maze_assets_loc` | 地图素材路径 |
| `env_matrix` | 地图矩阵数据路径 |
| `fs_storage` | 模拟存储路径 |
| `fs_temp_storage` | 临时存储路径 |
| `collision_block_id` | 碰撞检测 block ID |
| `mqtt_*` | MQTT 配置（可选） |

所有路径使用 `Path(__file__).resolve()` 计算绝对路径，不依赖工作目录。

### 1.3 配置文件

**文件**: `openai_config.example.json`（模板，不含密钥）

实际运行需要在项目根目录创建 `openai_config.json`（已在 `.gitignore` 中）：

```json
{
  "client": "zhipu",
  "model": "glm-4-plus",
  "model-key": "YOUR_ZHIPU_API_KEY",
  "model-base-url": "https://open.bigmodel.cn/api/paas/v4",
  "model-costs": { "input": 0.0, "output": 0.0 },
  "embeddings-client": "zhipu",
  "embeddings": "embedding-3",
  "embeddings-key": "YOUR_ZHIPU_API_KEY",
  "embeddings-base-url": "https://open.bigmodel.cn/api/paas/v4",
  "embeddings-costs": { "input": 0.0, "output": 0.0 },
  "experiment-name": "glm-simulacra",
  "cost-upperbound": 100.0
}
```

支持的 client 类型：`"openai"` / `"azure"` / `"zhipu"`

支持的 GLM 模型：
- `glm-4-flash` — 免费，速度快，质量一般
- `glm-4-plus` — 收费，质量更好，推荐
- `glm-4` — 标准版

---

## 二、前端 Bug 修复

### 2.1 send_environment 不返回 movement 数据

**文件**: `environment/frontend_server/translator/views.py`

**问题**: 前端 JS 在 "update" 阶段 POST 到 `/send_environment/`，期望返回包含 `<step>` 字段的 movement 数据。但 fork 版本的 `send_environment` 只返回 `{"status": "success"}`，导致前端永远卡在 update 阶段，agent 不会移动。

**修复**: `send_environment` 在保存环境数据后，检查对应 step 的 movement 文件是否存在，如果存在则返回 movement 数据：

```python
movement_file = f"storage/{sim_code}/movement/{step}.json"
if os.path.exists(movement_file):
    with open(movement_file, 'r') as f:
        movement_data = json.load(f)
    movement_data["<step>"] = step
    return JsonResponse(movement_data)
```

### 2.2 get_movements GET 请求 500 错误

**问题**: `get_movements` 用 `json.loads(request.body)` 解析 GET 请求的 body，但浏览器发送的 GET 请求 body 为空，导致 JSON 解析错误。

**修复**: 先检查 `request.body` 是否非空再解析：

```python
if request.body:
    data = json.loads(request.body)
else:
    data = {}
```

### 2.3 replay 初始位置错误

**文件**: `environment/frontend_server/translator/views.py`

**问题**: `replay` view 使用 environment 目录中最大序号的文件来设置 agent 初始位置。对于 100 步的模拟，agent 从 step 100 的位置开始，但 movement 数据从 step 0 开始，导致位置错位。

**修复**: 使用 URL 中指定的 step 对应的 movement 文件来设置初始位置：

```python
movement_file = f'storage/{sim_code}/movement/{step}.json'
if os.path.exists(movement_file):
    with open(movement_file) as json_file:
        movement_data = json.load(json_file)
    for key, val in movement_data.get("persona", {}).items():
        persona_init_pos += [[key, val["movement"][0], val["movement"][1]]]
```

### 2.4 回放速度过快

**文件**: `environment/frontend_server/templates/home/main_script.html`

**问题**: `timer_max = 0`，`movement_speed = 32`，导致每帧执行一步、每步一帧完成移动，100 步瞬间播完。

**修复**:
- `timer_max = 60` — 每 60 帧（约 1 秒）查询一次新的 movement 数据
- `movement_speed = 4` — 每步需要 8 帧完成移动动画（32/4=8）

每步总耗时约 1.1 秒，100 步回放约 2 分钟。

---

## 三、部署架构

```
Mac (浏览器)
    │
    │ HTTP :8000
    ▼
腾讯云 VM (49.233.189.223)
    ├── Django 前端 (0.0.0.0:8000)
    │   └── environment/frontend_server/
    ├── Python 后端 (模拟引擎)
    │   └── reverie/backend_server/
    └── GLM API 调用
        └── https://open.bigmodel.cn/api/paas/v4
```

### 腾讯云配置

- 系统: Rocky Linux 9.4, 4 核 15G 内存
- Python: 3.9.19
- iptables 放行 TCP 8000
- 腾讯云安全组需放行 8000 端口
- Django `ALLOWED_HOSTS = ['*']`（在 `settings/local.py` 和 `settings/base.py`）

---

## 四、操作手册

### 4.1 启动前端（Django）

```bash
ssh root@49.233.189.223
cd /opt/workspace/hehe/agentic_collab/environment/frontend_server
nohup python3 manage.py runserver 0.0.0.0:8000 --noreload > /tmp/frontend.log 2>&1 &
```

### 4.2 运行模拟

```bash
ssh root@49.233.189.223
cd /opt/workspace/hehe/agentic_collab/reverie/backend_server

# 3 人场景，100 步（约 5 分钟）
python3 automatic_execution.py \
  --origin base_the_ville_isabella_maria_klaus \
  --target my-test-run \
  --steps 100 \
  --ui None

# 25 人场景，500 步
python3 automatic_execution.py \
  --origin base_the_ville_n25 \
  --target my-25agent-run \
  --steps 500 \
  --ui None

# 后台运行
nohup python3 automatic_execution.py \
  --origin base_the_ville_isabella_maria_klaus \
  --target my-long-run \
  --steps 8640 \
  --ui None > /tmp/backend.log 2>&1 &
```

参数说明：
- `--origin`: 基础场景名称（在 `storage/` 目录下）
- `--target`: 新模拟的名称
- `--steps`: 步数（1 步 = 模拟中 10 秒，8640 步 = 24 小时）
- `--ui None`: headless 模式，不需要浏览器

### 4.3 回放模拟

浏览器访问：
```
http://49.233.189.223:8000/replay/<sim_code>/<start_step>/
```

例如：
```
http://49.233.189.223:8000/replay/my-test-run-s-0-0-100/0/
```

操作：
- **Play / Pause** — 控制回放
- **方向键** — 移动视角
- **Z 键** — 放大
- **X 键** — 缩小

### 4.4 查看 Agent 状态

浏览器访问：
```
http://49.233.189.223:8000/replay_persona_state/<sim_code>/<step>/<Persona_Name>/
```

例如：
```
http://49.233.189.223:8000/replay_persona_state/my-test-run-s-0-0-100/0/Isabella_Rodriguez/
```

### 4.5 切换模型

编辑腾讯云上的配置文件：

```bash
ssh root@49.233.189.223
vi /opt/workspace/hehe/agentic_collab/openai_config.json
```

修改 `"model"` 字段：
- `"glm-4-flash"` — 快速/免费
- `"glm-4-plus"` — 高质量/收费
- `"glm-4"` — 标准

修改后直接运行新的模拟即可，不需要重启 Django。

### 4.6 可用的基础场景

| 场景名 | Agent 数 | 说明 |
|--------|----------|------|
| `base_the_ville_isabella_maria_klaus` | 3 | 经典 3 人场景 |
| `base_the_ville_n25` | 25 | 完整 25 人小镇 |
| `base_the_ville_smol_elections_5_voters` | 5 | 选举场景 |
| `base_hide_and_seek` | - | 捉迷藏场景 |
| `base_search_and_rescue` | - | 搜救场景 |

---

## 五、数据目录结构

每次模拟的数据保存在：
```
environment/frontend_server/storage/<sim_name>/
├── personas/
│   └── <Agent Name>/
│       └── bootstrap_memory/
│           ├── scratch.json              # 当前状态、日计划、正在做的事
│           ├── spatial_memory.json       # 空间记忆（知道哪些地方）
│           └── associative_memory/
│               ├── nodes.json            # 所有记忆节点（事件/对话/想法）
│               ├── embeddings.json       # 记忆的向量嵌入（用于检索）
│               └── kw_strength.json      # 关键词关联强度
├── movement/
│   ├── 0.json ... N.json                # 每步的位置、动作、表情、对话
└── environment/
    ├── 0.json ... N.json                # 每步的环境状态（所有 agent 坐标）
```

### movement JSON 格式示例

```json
{
  "persona": {
    "Isabella Rodriguez": {
      "movement": [73, 14],
      "pronunciatio": "💤",
      "description": "sleeping@the Ville:Isabella Rodriguez's apartment:main room:bed",
      "chat": null
    }
  },
  "meta": {
    "curr_time": "February 13, 2023, 00:16:40"
  }
}
```

---

## 六、已知限制

1. **JSON mode 不如 Structured Outputs 稳定** — GLM 偶尔可能返回不符合 schema 的 JSON，代码有重试机制（默认 3-5 次）
2. **Embedding 维度不同** — GLM embedding-3 输出 2048 维，OpenAI text-embedding-3-small 输出 1536 维。两者不能混用于同一个模拟的记忆检索
3. **Django 版本老旧** — 项目使用 Django 2.2（已 EOL），不影响功能但有安全风险
4. **单线程模拟** — 后端模拟是单线程的，多个 agent 串行处理，25 人场景会较慢
