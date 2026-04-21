# 记忆系统实战：以 Tom Moreno 的一天为例

以 7 人中文仿真 `zh-n7-day1` 中 Tom Moreno 的真实数据为例，说明各文件如何协作支撑角色的感知、记忆、反思、规划和对话。

---

## 文件总览

```
personas/Tom Moreno/bootstrap_memory/
├── scratch.json            ← 工作记忆：当前状态、日程、行动
├── spatial_memory.json     ← 空间记忆：去过的地方
└── associative_memory/
    ├── nodes.json          ← 长期记忆：所有事件/想法/对话（413条）
    ├── embeddings.json     ← 语义向量：每条记忆的数学表示（176条）
    └── kw_strength.json    ← 关键词计数：触发反思的依据
```

它们不是孤立的，而是在认知循环中协同工作：

```
感知 → nodes.json + embeddings.json（存新记忆）
         ↓
       kw_strength.json（关键词计数+1）
         ↓
       scratch.json（importance_trigger_curr 递减）
         ↓ 递减到 0
反思 → embeddings.json（语义检索相关记忆）
         ↓
       nodes.json（存新 thought，链接证据）
         ↓
规划 → scratch.json（更新 f_daily_schedule）
         ↓
对话 → nodes.json（存 chat 记录）
```

---

## 一、scratch.json — 工作记忆

Tom 的"大脑当前状态"，实时更新。

### 身份与性格

```json
{
  "name": "Tom Moreno",
  "innate": "粗鲁、好斗、精力充沛",
  "currently": "Tom Moreno 的周一从一场重要的会议开始。他与 Isabella 在 2月13日上午10点
                于 Hobbs Cafe 会面，讨论 Oak Hill College 项目..."
}
```

`innate` 是固定人设，`currently` 是 LLM 在仿真过程中不断更新的——它不是预设的，是角色"活"出来的。

### 日程计划（f_daily_schedule）

```json
[
  ["正在睡觉 (正在睡觉)", 420],
  ["起床并完成晨间例行活动 (正在起床)", 5],
  ["起床并完成晨间例行活动 (正在刷牙)", 5],
  ["起床并完成晨间例行活动 (正在准备早餐)", 10],
  ["起床并完成晨间例行活动 (正在吃早餐)", 10],
  ...
]
```

每项是 `[行动描述, 持续分钟数]`。这是 plan 模块通过 LLM 生成的——先生成粗粒度日程（小时级），再逐级分解到分钟级。

### 反思触发器

```json
{
  "importance_trigger_max": 150,
  "importance_trigger_curr": 80,
  "importance_ele_n": 29
}
```

- `importance_trigger_curr`：每感知一个事件，减去该事件的重要性分数
- 当减到 ≤ 0 时触发反思
- 当前值 80，说明已经消耗了 70 点（150-80），还需再积累 80 点重要性才会触发下一次反思
- `importance_ele_n = 29`：自上次反思以来感知了 29 个事件

### 当前行动

```json
{
  "act_description": "联系 Klaus，商讨项目预算细节 (正在与 Klaus 讨论项目预算细节)",
  "act_address": "the Ville:Hobbs Cafe:cafe:cafe customer seating"
}
```

Tom 当前在 Hobbs Cafe 的客座区，正在和 Klaus 讨论预算。

---

## 二、spatial_memory.json — 空间记忆

Tom 知道的地方——只有他去过或看到过的才会记住。

```json
{
  "the Ville": {
    "Moreno family's house": {
      "common room": [...],
      "Tom and Jane Moreno's bedroom": [...]
    },
    "The Willows Market and Pharmacy": {
      "store": [...]
    },
    "Hobbs Cafe": {
      "cafe": ["cafe customer seating", "behind the cafe counter"]
    },
    "Johnson Park": { "park": [...] },
    "Oak Hill College": { "library": [...] }
  }
}
```

Tom 知道 11 个区域。**这棵树影响他的行动选择**——plan 模块问 LLM "Tom 应该去哪里"时，会把这棵树的可选地点列出来作为候选。Tom 不知道的地方他不会去。

---

## 三、nodes.json — 长期记忆

Tom 的全部记忆，413 条，分三种类型。

### event（事件，357 条）

角色感知到的事实：

```json
{
  "node_count": 413,
  "type": "event",
  "depth": 0,
  "created": "2023-02-13 11:41:40",
  "subject": "Tom Moreno",
  "predicate": "discuss",
  "object": "项目预算细节",
  "description": "Tom Moreno is 正在与 Klaus 讨论项目预算细节",
  "poignancy": 5,
  "keywords": ["Tom Moreno", "项目预算细节"],
  "embedding_key": "Tom Moreno is 正在与 Klaus 讨论项目预算细节",
  "filling": []
}
```

- `poignancy = 5`：LLM 给这个事件打的重要性分（1-10），中等偏高
- `keywords`：用于 kw_strength 计数和快速索引
- `embedding_key`：这段文字会被转成 2048 维向量存入 embeddings.json
- `filling = []`：事件没有证据链（它本身就是第一手事实）

### thought（想法，52 条）

反思产生的高层认知：

```json
{
  "node_count": 384,
  "type": "thought",
  "depth": 1,
  "description": "Tom Moreno was interested in Abigail Chen's ideas about integrating 
                  digital art and animation into the Oak Hill College project",
  "poignancy": 4,
  "filling": ["node_363"]
}
```

- `depth = 1`：这是从一手事件（depth=0）推导出来的想法
- **`filling = ["node_363"]`**：这条想法的"证据"是 node_363（和 Abigail 的对话）。这就是**证据链**——想法不是凭空产生的，可以追溯到原始事件

### chat（对话，4 条）

完整的对话记录：

```json
{
  "node_count": 363,
  "type": "chat",
  "subject": "Tom Moreno",
  "predicate": "chat with",
  "object": "Abigail Chen",
  "description": "talking to Abigail Chen and Isabella about the Oak Hill College project,
                  discussing the integration of digital art and animation elements...",
  "poignancy": 3,
  "filling": [
    ["Tom Moreno", "Abigail，你好！真高兴在这里见到你..."],
    ["Abigail Chen", "你好，Tom！是的，我正好是来参加 Oak Hill College 项目的..."],
    ["Tom Moreno", "是的，我们刚刚开始讨论可能的解决方案..."],
    ...14轮完整对话...
  ]
}
```

chat 节点的 `filling` 不是证据链，而是**完整对话原文**。

---

## 四、embeddings.json — 语义向量

每条记忆的 `embedding_key` 对应一个 2048 维向量（GLM embedding 模型）。

```json
{
  "Tom Moreno is 正在与 Klaus 讨论项目预算细节": [0.012, -0.034, 0.056, ...2048个浮点数],
  "Tom Moreno is 正在准备联系 Klaus 的材料": [-0.008, 0.021, 0.044, ...],
  "bed is idle": [0.001, -0.002, ...],
  ...176条...
}
```

### 检索时怎么用

当 Tom 在 Hobbs Cafe 遇到 Abigail，系统需要决定 Tom 应该想起什么。

1. 把当前情境 "Abigail Chen 走进 Hobbs Cafe" 转成一个 2048 维向量
2. 和 Tom 的 176 条向量逐一算**余弦相似度**
3. "之前和 Isabella 讨论过 Oak Hill College 项目" 这条的向量与当前情境语义最接近
4. Tom "想起"了这件事 → 于是对话时主动提到了项目

**检索公式**（三维加权）：

```
score = 时近性×0.5 + 相关性×3.0 + 重要性×2.0
```

相关性（embedding 余弦相似度）权重最高——语义匹配优先于时间和重要性。

---

## 五、kw_strength.json — 关键词频次

```json
{
  "kw_strength_event": {
    "tom moreno": 63,
    "cafe customer seating": 25,
    "john lin": 21,
    "abigail chen": 19,
    "isabella rodriguez": 19,
    "grocery store counter": 9
  },
  "kw_strength_thought": {
    "tom moreno": 51,
    "have": 9,
    "work": 8,
    "prepare": 7,
    "meet": 7
  }
}
```

### 反思触发时怎么用

每当一个 event 的关键词在 `kw_strength_event` 中的计数超过阈值（默认 4），这个主题被标记为"值得关注"。

Tom 和 "isabella rodriguez" 相关的事件有 19 次，和 "abigail chen" 相关的有 19 次——这些高频主题会被优先选为反思的焦点问题。

### 反思流程中的数据流

```
kw_strength 发现 "Oak Hill College" 频繁出现
    ↓
importance_trigger_curr 减到 ≤ 0
    ↓ 触发反思
LLM 生成焦点问题："Oak Hill College 项目最重要的进展是什么？"
    ↓
用 embeddings.json 做语义检索，找到最相关的 30 条记忆
    ↓
LLM 基于这些记忆生成洞察（thought）：
  "Tom Moreno 对 Abigail Chen 将数字艺术融入项目的想法很感兴趣"
    ↓
新 thought 存入 nodes.json，filling 指向证据 node_363
    ↓
重置 importance_trigger_curr = 150，等待下一轮
```

---

## 六、完整示例：一场对话的全链路

以 **Tom ↔ Abigail 在 Hobbs Cafe 的 14 轮对话**为例，展示所有文件如何协作。

### 第 1 阶段：碰面前

**spatial_memory.json**：Tom 知道 Hobbs Cafe 的位置
**scratch.json**：Tom 的日程里有 "上午 10 点在 Hobbs Cafe 与 Isabella 会面"
**plan 模块**：读取 scratch.json 的日程，驱动 Tom 走向 Hobbs Cafe

### 第 2 阶段：感知 Abigail

Tom 到达 Hobbs Cafe，视野内出现 Abigail Chen。

**perceive 模块**：
1. 扫描 `spatial_memory.json` 中 vision_r=4 格内的 tile
2. 检测到事件 "Abigail Chen 在 cafe customer seating"
3. 调 embedding API 生成向量 → 存入 `embeddings.json`
4. 调 LLM 打重要性分 → poignancy=4
5. 创建 event 节点 → 存入 `nodes.json`
6. 更新 `kw_strength.json`：`"abigail chen": 18 → 19`
7. 更新 `scratch.json`：`importance_trigger_curr -= 4`

### 第 3 阶段：决定是否交谈

**retrieve 模块**：
1. 用 "Abigail Chen 在 Hobbs Cafe" 作为查询
2. 从 `embeddings.json` 中找语义最相关的记忆
3. 找到："之前 Isabella 提到过 Abigail 参与 Oak Hill College 项目"
4. 把检索结果传给 `generate_decide_to_talk`
5. LLM 判断：是，应该和 Abigail 聊聊项目

### 第 4 阶段：对话

**converse 模块**：
1. 从 `scratch.json` 读取 Tom 的身份和当前状态
2. 从 `nodes.json` 检索与 Abigail 相关的记忆作为上下文
3. LLM 生成第一句话："Abigail，你好！真高兴在这里见到你。我正在和 Isabella 讨论 Oak Hill College 项目，你也是来参加这个项目的吗？"
4. 对话持续 14 轮，讨论了数字艺术、预算、设备采购
5. 约定"明天下午 3 点在 Hobbs Cafe 再开会"

### 第 5 阶段：对话存储

对话结束后：
1. 完整 14 轮对话存入 `nodes.json` 作为 chat 类型节点（node_363）
2. 对话摘要的向量存入 `embeddings.json`
3. `kw_strength.json` 中 "abigail chen" 计数再 +1
4. `scratch.json` 的 `importance_trigger_curr` 再次递减

### 第 6 阶段：反思

如果 `importance_trigger_curr` 减到 ≤ 0：

1. 从 `kw_strength.json` 看到 "abigail chen"、"oak hill college" 频繁出现
2. 用 `embeddings.json` 检索相关记忆
3. LLM 生成想法：

   > "Tom Moreno 对 Abigail Chen 将数字艺术和动画融入 Oak Hill College 项目的想法很感兴趣"

4. 这条 thought 存入 `nodes.json`（node_384），`filling` 指向 node_363（对话证据）
5. 重置 `scratch.json` 的触发器：`importance_trigger_curr = 150`

### 第 7 阶段：影响未来行为

下次 Tom 做日程规划时：
1. plan 模块用 "明天的安排" 检索 `embeddings.json`
2. node_383（计划记忆）被检索到："明天下午 3 点在 Hobbs Cafe 与 Isabella 和 Abigail 讨论预算"
3. 这条记忆被写入新的 `scratch.json` 日程

**整个链路**：感知 → 记忆 → 检索 → 对话 → 存储 → 反思 → 影响未来规划。没有中央调度，每个角色独立运行这个循环，涌现行为就是这样产生的。

---

## 七、核心概念

### 涌现行为（Emergent Behavior）

没有任何代码告诉 Tom "你应该和 Abigail 讨论数字艺术"。这个行为是从以下独立决策中自然产生的：
- Isabella 独立决定筹办 Oak Hill College 项目
- Tom 独立规划了去 Hobbs Cafe 和 Isabella 开会
- Abigail 独立决定去 Hobbs Cafe 和 Isabella 讨论项目
- 三人碰巧在同一地点相遇 → 对话自然发生

本次仿真中的具体例子：Tom 和 Abigail 在对话中约定了"明天下午 3 点在 Hobbs Cafe 再开会"——这个约定会被双方各自存入记忆，影响各自明天的日程规划。

### 重要性评分（Poignancy）

每个 event/thought/chat 都有一个 1-10 的重要性分（由 LLM 打分）。

本次仿真中的实际分布：
- `poignancy=1`：bed is idle（家具状态，无关紧要）
- `poignancy=3`：Tom Moreno is 正在准备联系 Klaus 的材料（日常行为）
- `poignancy=5`：Tom Moreno is 正在与 Klaus 讨论项目预算细节（重要工作）
- `poignancy=6`：和 Abigail 的完整对话记录（高价值社交事件）

重要性分有两个用途：
1. 检索时作为排序权重（重要的记忆更容易被"想起来"）
2. 累积递减 `importance_trigger_curr`（重要事件多了就触发反思）

### 证据链（Filling / Evidence）

thought 类型的记忆有 `filling` 字段，指向产生这个想法的原始记忆：

```
node_384 (thought): "Tom 对 Abigail 的数字艺术想法感兴趣"
  └─ filling → node_363 (chat): Tom ↔ Abigail 的 14 轮对话
```

这让系统能追溯"为什么角色会这样想"——想法不是凭空产生的，每条都有证据。

### 注意力带宽（Attention Bandwidth）

`scratch.json` 中 `att_bandwidth=3`：每一步最多感知 3 个事件。如果周围有 10 个事件，只取最近的 3 个。这模拟了人类注意力的有限性。

### 记忆保留窗口（Retention）

`scratch.json` 中 `retention=5`：最近 5 步内已经感知过的事件不会重复存储。避免同一个事件（如"bed is idle"）被反复记忆。

---

## 八、核心代码文件

### 认知模块（大脑）

位于 `reverie/backend_server/persona/cognitive_modules/`

| 文件 | 功能 | 读写哪些数据文件 |
|---|---|---|
| `perceive.py` | 感知环境，存储新事件 | 写 nodes.json、embeddings.json、kw_strength.json；写 scratch.json（递减触发器） |
| `retrieve.py` | 三维加权检索记忆 | 读 nodes.json、embeddings.json |
| `plan.py` | 生成/调整日程，更新身份 | 读 nodes.json；写 scratch.json（daily_schedule、currently） |
| `reflect.py` | 从事件中提炼想法 | 读 kw_strength.json、embeddings.json；写 nodes.json（新 thought） |
| `execute.py` | 寻路和行动执行 | 读 scratch.json、spatial_memory.json |
| `converse.py` | 多轮对话生成 | 读 nodes.json、scratch.json；写 nodes.json（新 chat） |

### 记忆结构（存储层）

位于 `reverie/backend_server/persona/memory_structures/`

| 文件 | 对应数据文件 | 功能 |
|---|---|---|
| `associative_memory.py` | nodes.json, embeddings.json, kw_strength.json | 长期记忆的增删查，向量缓存，关键词索引 |
| `scratch.py` | scratch.json | 工作记忆的读写，日程索引，行动状态管理 |
| `spatial_memory.py` | spatial_memory.json | 层级地点树的查询和扩展 |

### LLM 调用层

位于 `reverie/backend_server/persona/prompt_template/`

| 文件 | 功能 |
|---|---|
| `gpt_structure.py` | 封装 LLM API 调用（ChatGPT/GLM）、embedding 生成、结构化输出解析 |
| `v2/*.py` | 第二代 prompt 模板（日程生成、地点选择等） |
| `v3_ChatGPT/*.py` | 第三代 prompt 模板（对话生成、事件反应等） |

关键函数：
- `ChatGPT_safe_generate_structured_response()`：带重试的结构化 LLM 调用
- `get_embedding()`：文本转向量（结果缓存到 embeddings.json）
- `generate_poig_score()`：让 LLM 给事件打重要性分

### 仿真主循环

| 文件 | 功能 |
|---|---|
| `reverie/backend_server/reverie.py` | 主循环：每步对每个角色执行 perceive→retrieve→plan→reflect→execute→converse |
| `reverie/backend_server/automatic_execution.py` | 自动模式：headless 运行 + 定时 checkpoint |

### 前端展示

| 文件 | 功能 |
|---|---|
| `environment/frontend_server/templates/demo/` | 回放页面（地图 + 对话面板 + Z/X 缩放） |
| `environment/frontend_server/templates/home/` | 实时查看页面（simulator_home） |
| `environment/frontend_server/translator/views.py` | Django 视图：读取 compressed_storage 数据给前端 |
| `reverie/compress_sim_storage.py` | 压缩存储：把 movement/*.json 合并，供 demo 页面使用 |

---

## 文件关系图

```
scratch.json (工作记忆)
  │
  ├─ 读 ← plan 模块生成日程
  ├─ 读 ← execute 模块驱动行动
  ├─ 写 → importance_trigger_curr 递减（perceive 每次更新）
  └─ 写 → currently 更新（revise_identity 每天更新）

spatial_memory.json (空间记忆)
  │
  ├─ 读 ← plan 模块（可选目的地列表）
  ├─ 读 ← perceive 模块（视野范围计算）
  └─ 写 → perceive 模块（发现新地点时扩展）

nodes.json (长期记忆)
  │
  ├─ 写 ← perceive（新 event）
  ├─ 写 ← reflect（新 thought，带 filling 证据链）
  ├─ 写 ← converse（新 chat，带完整对话）
  ├─ 读 → retrieve（被检索为上下文）
  └─ 读 → plan/converse（作为 LLM prompt 的记忆输入）

embeddings.json (语义向量)
  │
  ├─ 写 ← perceive/reflect/converse（每条新记忆生成向量）
  └─ 读 → retrieve（余弦相似度检索）

kw_strength.json (关键词频次)
  │
  ├─ 写 ← perceive（每个 event 的关键词 +1）
  ├─ 写 ← reflect（每个 thought 的关键词 +1）
  └─ 读 → reflect（判断哪些主题值得反思）
```
