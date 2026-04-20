# 计划：25 人中文版完整仿真

## 背景

用户想按照斯坦福 Generative Agents 论文完整跑一遍 25 人小镇仿真，使用中文。之前已完成 3 人中文版（Isabella、Klaus、Maria）并通过过夜验证。现在需要把 25 人版也中文化，然后跑 3000 步（到上午 8 点）。

**已有基础**：prompt 层的中文指令（对话、计划、身份修订）已全部就位，适用于所有仿真。只需翻译 25 人的人设数据。

---

## 步骤（可随时中断、恢复）

### 第 1 步：创建 25 人中文 base 仿真目录
- 复制 `base_the_ville_n25/` → `base_the_ville_zh_n25/`
- 不改目录结构，只改 `scratch.json` 内容
- **验证**：目录存在，25 个 persona 子目录完整

### 第 2 步：翻译 25 个角色的 scratch.json
每个角色需翻译 5 个字段：
| 字段 | 说明 | 示例 |
|---|---|---|
| `innate` | 天生特质 | "friendly, outgoing" → "友善、外向" |
| `learned` | 人物背景 | 整段翻译，人名地名保留英文 |
| `currently` | 当前状态 | 整段翻译，人名地名保留英文 |
| `lifestyle` | 作息习惯 | 整段翻译，时间格式保留英文 |
| `daily_plan_req` | 日常固定安排 | 整段翻译（12/25 人有此字段） |

**不翻译**：name、first_name、last_name、living_area、spatial_memory
**参数微调**（参照 3 人中文版）：importance_trigger_max 250→150，recency_decay 0.995→0.99

总量：约 4600 英文词 → 中文，可以用 LLM 批量翻译再人工校对。

- **验证**：抽查 3 个角色，确认中文内容正确、人名地名为英文

### 第 3 步：提交代码并同步到腾讯云
- `git add` 新的 base 仿真目录
- `git commit` + `git push`
- 腾讯云 `git pull`
- **验证**：腾讯云上 `ls` 确认 25 个 persona 目录存在

### 第 4 步：单元冒烟测试
- 在腾讯云跑 `demo_zh_chat.py` 确认 GLM API 正常
- **验证**：输出中文对话，无 1214 错误

### 第 5 步：启动 3000 步仿真
```bash
python3 automatic_execution.py \
  --origin base_the_ville_zh_n25 \
  --target zh-n25-day1 \
  --steps 3000 --ui None
```
预计 2-4 小时（25 人比 3 人慢，每步要调用更多 LLM）。
- **验证**：日志 `ok` 计数持续增长，无 1214 错误

### 第 6 步：检查结果
- 抽查 5 个角色的 `scratch.json`，确认 `currently` 等字段为中文
- 浏览器打开 demo URL 看对话
- 跑量化指标脚本检查失败率 < 10%
- **验证**：角色中文对话自然，日程涌现行为出现

---

## 关键文件

| 文件 | 作用 |
|---|---|
| `storage/base_the_ville_n25/personas/*/bootstrap_memory/scratch.json` | 翻译来源（25 个） |
| `storage/base_the_ville_zh_isabella_maria_klaus/personas/*/bootstrap_memory/scratch.json` | 翻译参考（3 个已完成） |
| `reverie/backend_server/automatic_execution.py` | 仿真启动脚本 |
| `scripts/smoke-test.sh` | 冒烟测试 |
| `docs/zh-verification.md` | 验证方法参考 |

## 风险

- **API 费用**：25 人 × 3000 步，LLM 调用量大约是 3 人版的 8 倍。建议先跑 500 步试水
- **速度**：25 人仿真明显更慢，角色互动多时可能降到 10-20 步/小时
- **翻译质量**：批量翻译可能有不一致，需人工校对关键角色

---

## 计划调整：改用 7 人精简版

### 原因

25 人版跑了 8 小时只推进 533 步（8 步/小时），GLM API 延迟 ~30 秒/次，25 人每步调用量太大。分析后确认 GLM 的合理承载量是 5-7 人。

### 7 人阵容（`base_the_ville_zh_n7`）

| 角色 | 身份 | 故事线 |
|---|---|---|
| Isabella Rodriguez | Hobbs Cafe 老板 | 筹备情人节派对，社交中心 |
| Klaus Mueller | 社会学学生 | 研究士绅化，和 Isabella 有会议 |
| Maria Lopez | 物理学生/主播 | 常去 Hobbs Cafe，活跃社交 |
| Sam Moore | 退役军官 | 竞选市长，和 Tom 有冲突 |
| Tom Moreno | 杂货店主 | 不喜欢 Sam，政治对立 |
| John Lin | 药剂师 | 好奇选举，家庭线 |
| Abigail Chen | 数字艺术家 | 和 Isabella 有合作项目 |

### 新步骤

| 步骤 | 内容 |
|---|---|
| 第 7 步 | 创建 `base_the_ville_zh_n7`（从 n25 精简） |
| 第 8 步 | 启动 3000 步仿真（预计 ~100 步/小时，30 小时完成） |
| 第 9 步 | 检查结果（对话、涌现行为） |
