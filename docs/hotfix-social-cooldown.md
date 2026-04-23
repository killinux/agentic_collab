# 止血方案：社交判断冷却机制

## 问题

7 人仿真跑了 54 小时，模拟时间才到下午 1:03。最近 24 小时只推进 40 步（~1.7 步/小时），原因是 4 个角色聚集在 Hobbs Cafe，每步需要 O(n²) 次 LLM 调用判断"要不要交谈"。

**核心数据**：

| 时间段 | 步速 | 聚集情况 |
|---|---|---|
| 0-3000 步（睡觉期） | 3000 步/小时 | 无聚集 |
| 3000-3700 步（分散活动） | 200 步/小时 | 7 人分散 |
| 3700-4700 步（Hobbs Cafe 午餐） | **1.7 步/小时** | 4 人同地 |

**速度下降 1700 倍**，完全因为一个问题：刚聊完的角色对，下一步又要调 LLM 判断要不要再聊。

---

## 止血方案：社交冷却

### 原理

两个角色刚聊完，短时间内不需要再判断要不要交谈——直接跳过 `decide_to_talk`。

### 改动位置

`reverie/backend_server/persona/cognitive_modules/perceive.py`

在调用 `generate_decide_to_talk` 之前加入冷却检查。

### 代码改动

```python
# ============================================================
# 方案 A：最小改动（约 15 行）
# 在 perceive.py 中，找到调用 decide_to_talk 的位置
# ============================================================

# 在文件顶部添加全局冷却字典
_chat_cooldown = {}  # key: frozenset({name_a, name_b}), value: last_chat_step
COOLDOWN_STEPS = 50  # 冷却 50 步（约 8 分钟模拟时间）

# 在调用 generate_decide_to_talk 之前插入：
def should_check_talk(persona_name, target_name, curr_step):
    pair = frozenset({persona_name, target_name})
    last = _chat_cooldown.get(pair, -999)
    if curr_step - last < COOLDOWN_STEPS:
        return False  # 冷却中，跳过 LLM 调用
    return True

# 对话结束后记录冷却：
def record_chat_done(persona_name, target_name, curr_step):
    pair = frozenset({persona_name, target_name})
    _chat_cooldown[pair] = curr_step
```

### 预期效果

| 场景 | 改动前 | 改动后 |
|---|---|---|
| 4 人聚集，刚聊完 | 每步 12 次 decide_to_talk | 每步 0-2 次 |
| 4 人聚集，冷却结束 | 每步 12 次 | 每步 6 次（只检查没聊过的对） |
| 速度（4 人聚集） | 1.7 步/小时 | **预计 15-30 步/小时** |

### 风险评估

- **极低风险**：不影响对话质量，只是减少重复判断
- **不会漏掉对话**：冷却 50 步后会重新检查
- **可调参数**：COOLDOWN_STEPS 可以调大（更快）或调小（更敏感）

---

## 补充方案：idle 事件缓存

### 问题

`"bed is idle"`、`"desk is idle"` 等事件每次都调 LLM 打重要性分，结果永远是 1。

### 改动位置

`reverie/backend_server/persona/cognitive_modules/perceive.py` 中调用 `generate_poig_score` 的位置。

### 代码改动

```python
# 在 generate_poig_score 调用之前：
def get_poignancy_fast(persona, event_type, description):
    desc_lower = description.lower()
    # idle 事件永远是 1 分，不需要调 LLM
    if "idle" in desc_lower or "is idle" in desc_lower:
        return 1
    # 正在睡觉也是低分
    if "sleeping" in desc_lower or "正在睡觉" in desc_lower:
        return 1
    # 其他情况正常调 LLM
    return generate_poig_score(persona, event_type, description)
```

### 预期效果

减少 30-40% 的 poignancy LLM 调用。全局提速 ~20%。

---

## 实施步骤

### 步骤 1：定位代码

```bash
# 找到 decide_to_talk 的调用位置
grep -n "decide_to_talk\|generate_decide_to_talk" \
  reverie/backend_server/persona/cognitive_modules/*.py

# 找到 poig_score 的调用位置
grep -n "generate_poig_score\|poig_score" \
  reverie/backend_server/persona/cognitive_modules/perceive.py
```

### 步骤 2：实施社交冷却

1. 在 perceive.py 顶部添加冷却字典和常量
2. 在 `generate_decide_to_talk` 调用前插入冷却检查
3. 在对话结束的位置（converse.py）记录冷却

### 步骤 3：实施 idle 缓存

1. 在 perceive.py 中包装 `generate_poig_score` 调用

### 步骤 4：测试

```bash
# 单元测试
cd reverie/backend_server
python3 demo_zh_chat.py 2>/dev/null

# 短仿真验证（100 步）
python3 automatic_execution.py \
  --origin base_the_ville_zh_n7 \
  --target test-cooldown \
  --steps 100 --ui None

# 对比：看日志中 decide_to_talk 的调用次数
grep -c "generate_decide_to_talk" /tmp/test-cooldown.log
```

### 步骤 5：从当前 checkpoint 继续

优化代码后，从最近的 checkpoint 继续跑：

```bash
python3 automatic_execution.py \
  --origin zh-n7-day1-ext-s-7-4400-4600 \
  --target zh-n7-day1-v2 \
  --steps 6000 --ui None
```

---

## 不做什么

本次止血**只做冷却和缓存**，不做：
- asyncio 并行（改动大，风险高）
- 分层模型（需要验证小模型质量）
- 批量社交判断（需要改 prompt 格式）
- 本地 embedding（需要安装依赖）

这些放到后续优化迭代中。

---

## 成功标准

| 指标 | 当前 | 目标 |
|---|---|---|
| 4 人聚集速度 | 1.7 步/小时 | ≥15 步/小时 |
| 全局 LLM 调用/步 | ~25 次 | ≤10 次 |
| 对话质量 | 14 轮自然对话 | 不退化 |
| 改动量 | — | ≤30 行 |
