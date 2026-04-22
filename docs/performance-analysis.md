# 性能瓶颈分析与优化方向

基于 zh-n7-day1 仿真（7 人中文版，GLM-4-plus）的实测数据。

---

## 实测数据

### 速度随角色密度变化

| 阶段 | 步数范围 | 模拟时间 | 速度 | 原因 |
|---|---|---|---|---|
| 睡觉期 | 0-2500 | 0:00-6:56 | ~3000 步/小时 | 大部分角色 idle，每步几乎不调 LLM |
| 起床期 | 2500-3200 | 6:56-8:53 | ~500 步/小时 | 角色陆续起床，逐个生成日程 |
| 分散活动 | 3200-3700 | 8:53-10:16 | ~200 步/小时 | 7 人分散在不同地点，各自行动 |
| 聚集期 | 3700-4200 | 10:16-11:40 | **~8 步/小时** | 4 人聚集在 Hobbs Cafe |

**速度下降 375 倍**（3000 → 8 步/小时），完全由角色聚集导致。

### 单步 LLM 调用量分析

| 场景 | 每步调用次数 | 每步耗时（GLM ~3-5s/次） |
|---|---|---|
| 7 人全部睡觉 | 0-1 次 | <5 秒 |
| 7 人分散活动 | ~10 次 | ~40 秒 |
| 4 人同地点 | ~25 次 | **~5-10 分钟** |
| 假设 7 人同地点 | ~50 次 | **~15-20 分钟** |

---

## 瓶颈 1：O(n²) 的社交判断

### 问题

每一步，对同一地点的每对角色都要调用 `generate_decide_to_talk`（是否交谈）和 `generate_decide_to_react`（是否反应）。

```
同地点 n 人 → n×(n-1)/2 对 → 每对 1-2 次 LLM 调用

4 人: 6 对 × 2 = 12 次
7 人: 21 对 × 2 = 42 次
25 人: 300 对 × 2 = 600 次（这就是 25 人版完全不可用的原因）
```

### 代码位置

`reverie/backend_server/persona/cognitive_modules/perceive.py` 中感知到其他角色后，在 `converse.py` 里对每对角色调用判断。

### 可能的优化方向

1. **空间过滤**：只对距离 ≤ 2 格的角色对做社交判断，而不是同一 arena 的所有人
2. **冷却机制**：两个角色刚聊完（最近 N 步内），跳过 decide_to_talk
3. **批量判断**：把多对角色的判断合并成一次 LLM 调用（"以下 6 对角色，哪些应该交谈？"）
4. **概率跳过**：同地点人数 > 3 时，每步只随机检查 3 对，而不是全部

**预估收益**：4 人聚集场景从 12 次调用降到 3-4 次，速度提升 3-4 倍。

---

## 瓶颈 2：每步逐角色串行处理

### 问题

主循环对每个角色**串行**执行完整认知循环：

```python
# reverie.py 主循环（伪代码）
for step in range(total_steps):
    for persona in all_personas:          # 串行遍历
        perceive(persona, maze)           # 调 LLM
        retrieved = retrieve(persona)     # 调 embedding API
        plan(persona, retrieved)          # 调 LLM
        reflect(persona)                  # 可能调 LLM
        execute(persona, maze)            # 本地计算
        converse(persona, ...)            # 调 LLM
```

7 个角色串行处理，即使每个角色的 LLM 调用之间没有依赖。

### 可能的优化方向

1. **角色级并行**：用 `asyncio` 或线程池并行处理不同角色（同一步内角色间有空间依赖，但感知和规划可以并行）
2. **LLM 调用并行**：同一角色的 `generate_poig_score` 和 `generate_action_event_triple` 可以并行发起
3. **批量 API 调用**：GLM 支持批量请求，把多个角色的 prompt 合并成一次 batch 调用

**预估收益**：理论上 7 人可以并行到接近 1 人的速度（7 倍），实际受限于 API 并发限制，预计 3-4 倍。

---

## 瓶颈 3：GLM API 延迟

### 问题

GLM-4-plus 单次调用延迟约 3-5 秒（包括网络往返），这是硬限制。

实测数据：
- 简单调用（poignancy 评分）：~3 秒
- 复杂调用（日程生成、对话）：~5-8 秒
- 失败重试：额外 3-5 秒/次

### 可能的优化方向

1. **换更快的模型**：GPT-4o-mini 延迟约 0.5-1 秒，比 GLM 快 3-5 倍
2. **分层模型策略**：简单任务（poignancy 评分、pronunciatio）用小模型（GLM-4-flash 或 GPT-3.5），复杂任务（对话、反思）用大模型
3. **本地小模型**：poignancy 评分等简单打分任务可以用本地 7B 模型替代，零延迟
4. **缓存常见调用**：`"bed is idle"` 的 poignancy 永远是 1，不需要每次都调 LLM

**预估收益**：换 GPT-4o-mini 可以整体提速 3-5 倍；分层策略可以再提 2 倍。

---

## 瓶颈 4：Embedding 生成

### 问题

每条新记忆都要调一次 embedding API。虽然单次比 LLM 调用快（~1 秒），但累积量大。

实测：Tom Moreno 到 4200 步时已有 176 条 embedding（4.7MB）。

### 可能的优化方向

1. **批量 embedding**：攒 10 条文本一次性调用，而不是逐条
2. **本地 embedding 模型**：用 sentence-transformers 等本地模型，零网络延迟
3. **跳过低价值 embedding**：`"bed is idle"` 等重复出现的低分事件，复用已有向量

**预估收益**：本地 embedding 可以把 embedding 相关耗时从 ~30% 降到 ~5%。

---

## 瓶颈 5：Retry 浪费

### 问题

GLM 有时返回格式不对的响应，系统重试最多 5 次。

实测：2084 次 Attempt 中有 9 次 Attempt 3+，说明 ~0.4% 的调用需要额外 2-4 次重试。

虽然比例不高，但每次重试都是 3-5 秒的等待。

### 可能的优化方向

1. **更强的 prompt 格式约束**：在 prompt 中加更明确的 JSON schema 示例
2. **GLM 的 JSON mode**：如果 GLM 支持 structured output，强制 JSON 输出
3. **本地解析修复**：对格式略有偏差的响应做本地修复，而不是直接重试

---

## 综合优化路线图

### 短期（改动小，收益明显）

| 优化 | 改动量 | 预估提速 |
|---|---|---|
| 社交判断冷却机制（刚聊完的跳过） | ~20 行 | 2-3 倍（聚集场景） |
| 缓存常见 poignancy（idle 事件） | ~10 行 | 10-20%（全局） |
| 批量 embedding 调用 | ~30 行 | 15-20%（全局） |

### 中期（需要一定重构）

| 优化 | 改动量 | 预估提速 |
|---|---|---|
| 角色级 asyncio 并行 | ~100 行 | 3-4 倍 |
| 分层模型（简单任务用小模型） | ~50 行 | 2-3 倍 |
| 批量社交判断（一次 LLM 判断多对） | ~50 行 | 2-3 倍（聚集场景） |

### 长期（架构级改动）

| 优化 | 改动量 | 预估提速 |
|---|---|---|
| 本地 embedding 模型 | ~200 行 | 消除 embedding 延迟 |
| 本地小模型做评分 | ~300 行 | 消除评分延迟 |
| 全异步架构重写 | ~1000 行 | 接近理论上限 |

### 理论上限

如果所有优化都做了：
- 7 人聚集场景：从 8 步/小时 → 估计 200-400 步/小时
- 7 人分散场景：从 200 步/小时 → 估计 1000-2000 步/小时
- 25 人完整仿真一天（8640 步）：从不可行 → 估计 8-15 小时

---

## AI 作为瓶颈：核心矛盾

### 问题本质

Generative Agents 的架构设计假设 LLM 调用是"廉价"的——论文用的是 GPT-3.5 时代的 API，延迟 ~0.3 秒，成本低。但在实际部署中（尤其是用 GLM-4-plus），每次调用 3-5 秒，这个假设不再成立。

核心矛盾是：**多人交互是仿真最有价值的部分，但恰恰是 LLM 调用最密集的部分。**

```
仿真价值 ∝ 角色交互数量
LLM 调用 ∝ 角色交互数量²
实际速度 ∝ 1 / LLM 调用数量

→ 仿真越有价值，跑得越慢
```

### 实测数据佐证（zh-n7-day1-ext，28 小时运行）

| 阶段 | 角色密度 | LLM 调用/步 | 速度 | 对话产出 |
|---|---|---|---|---|
| 0:00-8:20（睡觉→起床） | 0-2 人活跃 | 0-3 次 | 3000 步/h | 0 场 |
| 8:20-10:16（分散活动） | 7 人分散 | ~10 次 | 200 步/h | 0 场 |
| 10:16-12:35（Hobbs Cafe 聚集） | 4 人同地 | ~25 次 | 8 步/h | **6 场** |

所有有价值的内容（6 场对话、涌现行为）都发生在最慢的阶段。

### 这不只是 GLM 的问题

换成 GPT-4o-mini（延迟 ~0.5 秒）能快 5 倍，但 O(n²) 的架构问题仍然存在：
- 7 人聚集：从 8 步/h → ~40 步/h（仍然很慢）
- 25 人聚集：从不可行 → 仍然不可行

**必须同时解决架构问题和延迟问题。**

---

## 工程优化方案（附代码示例）

### 优化 1：社交冷却机制（最优先）

最近 N 步内聊过的角色对，跳过 `decide_to_talk`。

```python
# cognitive_modules/converse.py 或 perceive.py 中添加
# 在调用 generate_decide_to_talk 之前：

CHAT_COOLDOWN_STEPS = 30  # 5 分钟冷却

if last_chat_step.get((persona_a, persona_b), -999) > current_step - CHAT_COOLDOWN_STEPS:
    return False  # 跳过，不调 LLM
```

改动：~20 行。4 人聚集场景从 12 次调用降到 3-4 次。

### 优化 2：静态 poignancy 缓存

```python
# gpt_structure.py 或 perceive.py 中添加

STATIC_POIGNANCY = {}

def get_poignancy_cached(description):
    # idle 事件永远是 1 分
    if "idle" in description.lower():
        return 1
    # 检查缓存
    if description in STATIC_POIGNANCY:
        return STATIC_POIGNANCY[description]
    # 调 LLM
    score = generate_poig_score(description)
    STATIC_POIGNANCY[description] = score
    return score
```

改动：~10 行。减少 30-40% 的 poignancy LLM 调用。

### 优化 3：批量社交判断

把多对角色的判断合成一次 LLM 调用：

```python
# 当前：6 对 = 6 次 LLM 调用
for pair in all_pairs:
    should_talk = generate_decide_to_talk(pair)  # 每次 3-5 秒

# 优化后：6 对 = 1 次 LLM 调用
prompt = """以下角色都在 Hobbs Cafe，请判断哪些对应该交谈。
返回 JSON 数组，1=应该交谈，0=不需要。

1. Isabella Rodriguez ↔ Tom Moreno
2. Isabella Rodriguez ↔ Klaus Mueller
3. Isabella Rodriguez ↔ Abigail Chen
4. Tom Moreno ↔ Klaus Mueller
5. Tom Moreno ↔ Abigail Chen
6. Klaus Mueller ↔ Abigail Chen

返回格式：{"decisions": [1, 0, 1, 0, 0, 0]}"""
```

改动：~50 行。6 次调用 → 1 次，聚集场景提速 4-5 倍。

### 优化 4：asyncio 角色并行

```python
# reverie.py 主循环改造

import asyncio

async def process_persona_async(persona, maze):
    perceived = await perceive_async(persona, maze)
    retrieved = await retrieve_async(persona, perceived)
    await plan_async(persona, retrieved)
    if reflection_trigger(persona):
        await reflect_async(persona)
    execute(persona, maze)  # 本地计算，不需要 async

# 每步并行处理所有角色
async def run_step(personas, maze):
    await asyncio.gather(*[
        process_persona_async(p, maze) for p in personas
    ])
```

改动：~100 行（需要把 LLM 调用改成 async）。7 人并行理论 7 倍，实际受 API 并发限制约 3-4 倍。

### 优化 5：分层模型策略

```python
# gpt_structure.py 中添加模型路由

TASK_MODEL_MAP = {
    "poignancy":        "glm-4-flash",     # 简单评分，用快模型
    "pronunciatio":     "glm-4-flash",     # 表情符号，用快模型
    "decide_to_talk":   "glm-4-flash",     # 是/否判断，用快模型
    "action_event":     "glm-4-flash",     # SPO 三元组，用快模型
    "conversation":     "glm-4-plus",      # 对话生成，用大模型
    "daily_plan":       "glm-4-plus",      # 日程规划，用大模型
    "reflection":       "glm-4-plus",      # 反思洞察，用大模型
}

def get_model_for_task(task_type):
    return TASK_MODEL_MAP.get(task_type, "glm-4-plus")
```

改动：~50 行。简单任务延迟从 3-5 秒降到 0.5-1 秒，整体提速 2-3 倍。

### 优化 6：本地 embedding

```python
# gpt_structure.py 中替换 get_embedding

from sentence_transformers import SentenceTransformer

_local_model = None

def get_embedding(text):
    global _local_model
    if _local_model is None:
        _local_model = SentenceTransformer(
            'paraphrase-multilingual-MiniLM-L12-v2'
        )
    text = text.replace("\n", " ")
    if not text:
        text = "this is blank"
    return _local_model.encode(text).tolist()
    # 本地计算 ~10ms，无网络延迟
```

改动：~20 行（+安装依赖）。消除全部 embedding 网络延迟。需要 GPU 或性能较好的 CPU。

---

## 综合收益估算

| 优化组合 | 4 人聚集 | 7 人分散 | 改动量 |
|---|---|---|---|
| 当前基线 | 8 步/h | 200 步/h | — |
| +冷却+缓存 | 25 步/h | 260 步/h | 30 行 |
| +批量社交 | 50 步/h | 260 步/h | +50 行 |
| +asyncio 并行 | 150 步/h | 800 步/h | +100 行 |
| +分层模型 | 400 步/h | 1500 步/h | +50 行 |
| +本地 embedding | 500 步/h | 2000 步/h | +20 行 |
| **全部优化** | **500 步/h** | **2000 步/h** | **~250 行** |

全部优化后，当前 28 小时跑 4500 步的工作量可以在 **~3 小时**内完成。25 人完整一天（8640 步）预计 **15-20 小时**可行。

---

## 推荐实施顺序

| 优先级 | 优化 | 改动 | 收益 | 风险 |
|---|---|---|---|---|
| **P0** | 社交冷却机制 | 20 行 | 聚集场景 3 倍 | 极低 |
| **P0** | 静态 poignancy 缓存 | 10 行 | 全局 20% | 极低 |
| **P1** | 批量社交判断 | 50 行 | 聚集场景 5 倍 | 低（需测试 prompt） |
| **P1** | 分层模型 | 50 行 | 全局 2-3 倍 | 低（需验证小模型质量） |
| **P2** | asyncio 并行 | 100 行 | 全局 3-4 倍 | 中（需重构主循环） |
| **P3** | 本地 embedding | 20 行 | 消除 embedding 延迟 | 低（需安装依赖+验证精度） |

---

## 当前决策

**本轮不优化**，原因：
1. 7 人版已产出 6 场对话、完整涌现行为链路，验证了系统能力
2. 优化需要测试确保不破坏认知行为的正确性
3. 先积累仿真经验，确认哪些优化最有价值

**下次迭代优先做 P0**（冷却+缓存，共 30 行），可以立即将聚集场景速度从 8 步/h 提升到 ~25 步/h。
