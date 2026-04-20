# 记忆系统架构

基于斯坦福 Generative Agents 论文的记忆实现，代码位于 `reverie/backend_server/persona/`。

---

## 总体架构

```
感知(perceive) → 新事件存入联想记忆，打分，生成嵌入
     ↓
检索(retrieve) → 三维加权找出最相关的 30 条记忆
     ↓
规划(plan)     → 基于检索结果制定/调整日程
     ↓
反思(reflect)  → 重要性累积触发，产生高层想法
     ↓
执行(execute)  → 角色移动、互动
     ↓
对话(converse) → 基于记忆和当前情境生成对话
```

---

## 三层记忆结构

### 1. 联想记忆（长期记忆）

**文件**：`memory_structures/associative_memory.py`

每条记忆是一个 ConceptNode，包含：

| 字段 | 说明 |
|---|---|
| node_id | 唯一标识，如 "node_1" |
| type | event（事件）/ thought（想法）/ chat（对话） |
| depth | 事件/对话=0，想法=1+（基于证据链深度） |
| created | 创建时间 |
| last_accessed | 最后被检索的时间 |
| subject / predicate / object | 三元组，如 "Isabella - 正在准备 - 情人节派对" |
| description | 完整文字描述 |
| embedding_key | 用于生成嵌入向量的文本 |
| poignancy | 重要性分数（LLM 打 1-10 分） |
| keywords | 关键词集合，用于快速索引 |
| filling | 证据链——想法类记忆链接到产生它的原始记忆 |

**存储结构**：
```python
self.seq_event          # 按时间排序的事件列表
self.seq_thought        # 按时间排序的想法列表
self.seq_chat           # 按时间排序的对话列表
self.kw_to_event        # 关键词 → 事件索引
self.kw_to_thought      # 关键词 → 想法索引
self.kw_strength_event  # 关键词出现次数（触发反思用）
self.embeddings         # embedding_key → 1536 维向量
```

### 2. 工作记忆（短期记忆）

**文件**：`memory_structures/scratch.py`

角色的当前状态：

| 类别 | 字段 |
|---|---|
| 身份 | name, age, innate, learned, currently, lifestyle |
| 感知参数 | vision_r=4（视野半径）, att_bandwidth=3（注意力带宽）, retention=5（不重复感知窗口） |
| 反思控制 | importance_trigger_max=150, importance_trigger_curr（递减计数器） |
| 检索权重 | recency_w=1, relevance_w=1, importance_w=1, recency_decay=0.99 |
| 日程 | daily_req, f_daily_schedule, f_daily_schedule_hourly_org |
| 当前行动 | act_address, act_description, act_duration, act_event |
| 对话状态 | chatting_with, chat, chatting_end_time |

### 3. 空间记忆

**文件**：`memory_structures/spatial_memory.py`

层级树结构：
```
世界（the Ville）
  └─ 区域（Hobbs Cafe）
       └─ 房间（cafe）
            └─ 物品（counter, table, coffee machine）
```

角色只记住自己去过/看到过的地方，随感知逐步扩展。

---

## 核心算法

### 记忆检索（retrieve.py）

对每条记忆打三个分，加权求和后取 top-30：

| 维度 | 计算方法 | 全局权重 | 含义 |
|---|---|---|---|
| 时近性 Recency | `decay_rate ^ 位置序号` | ×0.5 | 越新的记忆分越高 |
| 相关性 Relevance | 余弦相似度 `cos_sim(记忆向量, 查询向量)` | **×3** | 语义最相关的优先 |
| 重要性 Importance | 节点的 poignancy 分数 | ×2 | 重要事件优先 |

**公式**：
```
score = recency_w × recency × 0.5
      + relevance_w × relevance × 3.0
      + importance_w × importance × 2.0
```

三个分量各自归一化到 [0, 1] 后加权。相关性权重最高，语义匹配是第一优先级。

### 感知（perceive.py）

```
1. 获取视野内的 tile（vision_r=4 格）
2. 更新空间记忆树
3. 对视野内事件按距离排序，取最近 att_bandwidth=3 个
4. 对每个新事件（不在最近 retention=5 条内）：
   a. 生成嵌入向量（调 embedding API）
   b. LLM 打重要性分（1-10）
   c. 存入联想记忆
   d. 重要性计数器 -= poignancy
```

### 反思（reflect.py）

**触发条件**：`importance_trigger_curr <= 0`（重要性累积到阈值）

```
1. 从最近的高重要性记忆中，让 LLM 生成 3 个焦点问题
   例："最近发生的事里，什么最值得思考？"

2. 对每个焦点问题，用三维检索找出最相关的 30 条记忆

3. 让 LLM 基于这些记忆生成洞察（insight）
   例："也许可以在情人节派对上邀请 Klaus 讨论社区话题"

4. 每条洞察存为 thought 节点：
   - 生成嵌入向量
   - 打重要性分
   - 链接证据（filling 字段指向原始记忆）
   - depth = 1 + max(证据节点的 depth)

5. 重置计数器：importance_trigger_curr = 150
```

### 重要性衰减

```python
poignancy × (1 - decay_rate) ^ 经过的秒数
```

随时间指数衰减，老记忆的重要性逐渐降低。

---

## 嵌入向量（embeddings.json）

**文件**：`persona/prompt_template/gpt_structure.py` 中的 `get_embedding()`

### 生成时机

`embeddings.json` 不是预先生成的，而是仿真运行过程中**逐条生成、逐条追加**：

- **感知时**：角色看到新事件（如"bed is idle"），为事件描述生成向量
- **反思时**：角色产生新想法，为想法文本生成向量
- **检索时**：为查询的焦点问题生成向量，用于和已有记忆做余弦相似度比较

### 生成过程

```python
# gpt_structure.py
def get_embedding(text):
    text = text.replace("\n", " ")
    response = embeddings_client.embeddings.create(
        input=[text],
        model="text-embedding-3-small"  # 或智谱的 embedding 模型
    )
    return response.data[0].embedding  # 向量（维度取决于模型）
```

调一次 embedding API，返回一个浮点数组（OpenAI 模型 1536 维，智谱 GLM 模型 2048 维）。

### 缓存机制

生成后存入内存字典，避免重复调用 API：

```python
# perceive.py 中
if desc in persona.a_mem.embeddings:
    event_embedding = persona.a_mem.embeddings[desc]  # 命中缓存
else:
    event_embedding = get_embedding(desc)              # 调 API
```

### 持久化

每次 checkpoint（每 200 步），整个 embeddings 字典序列化写入磁盘：

```json
// embeddings.json 示例
{
  "bed is idle": [0.012, -0.034, 0.056, ...],
  "Sam Moore is idle": [-0.008, 0.021, 0.044, ...],
  "Klaus is writing a research paper": [0.031, -0.015, ...]
}
```

每个 key 是记忆原文，value 是对应的向量数组。

### 起始与增长

- 初始 `embeddings.json` 为空 `{}`
- 随仿真推进逐步累积：角色每感知/思考/对话一次就多一条
- 实测 25 人仿真跑 500 步后，最活跃角色（Sam Moore，最早起床）有 51 条，约 1.4MB；其他角色 7-30 条不等

### 余弦相似度

检索时用嵌入向量计算语义相似度：

```python
cos_sim(a, b) = dot(a, b) / (norm(a) × norm(b))
# 返回 [-1, 1]，通常 [0, 1]
# 1.0 = 语义完全一致，0.0 = 完全无关
```

---

## 涌现行为的产生机制

1. 每个角色**独立**运行感知→检索→规划→反思→执行循环
2. 角色之间**唯一的信息交换**是：
   - 在同一物理空间时互相感知
   - 对话时交换信息
3. 通过记忆检索和反思，角色能：
   - 记住之前的对话内容
   - 联系不同时间的事件产生洞察
   - 基于洞察调整自己的日程
4. 当多个角色各自独立做出一致的决策时，**涌现行为**就产生了

**例子**：Isabella 告诉 Klaus "下午 1 点在 Hobbs Cafe 见面"，又告诉 Maria 同样的事。Klaus 和 Maria 各自将这条信息存入记忆，在规划日程时检索到它，于是三人都在下午 1 点出现在 Hobbs Cafe——尽管没有任何中央调度系统。

---

## 文件索引

| 文件路径 | 功能 |
|---|---|
| `persona/memory_structures/associative_memory.py` | 长期记忆存储与索引 |
| `persona/memory_structures/scratch.py` | 工作记忆 / 当前状态 |
| `persona/memory_structures/spatial_memory.py` | 空间记忆树 |
| `persona/cognitive_modules/perceive.py` | 感知 → 记忆存储 |
| `persona/cognitive_modules/retrieve.py` | 三维加权检索 |
| `persona/cognitive_modules/reflect.py` | 反思 → 洞察生成 |
| `persona/cognitive_modules/plan.py` | 基于记忆的日程规划 |
| `persona/cognitive_modules/converse.py` | 基于记忆的对话生成 |
| `persona/prompt_template/gpt_structure.py` | LLM 调用 + embedding 生成 |
