# 中文化验证测试文档

记录 GLM + 中文化改造后的端到端验证方法,以及本次 2026-04-18 过夜仿真 `verify-zh-2day` 的实际结果。

目标读者:任何想复现或检验中文化效果的开发者。

---

## 已完成的改动

| 层次 | 改动内容 | 提交/文件 |
|---|---|---|
| 配置 | 模型 `glm-4-flash` → `glm-4-plus` | `openai_config.json`(gitignored) |
| 代码修复 | `GPT_structured_request` 修 1214 错误(`role: system → user`) | `gpt_structure.py:460` |
| Prompt 中文化 | 对话生成 + 人名地名锁英文 | `v3_ChatGPT/iterative_convo_v1.py` |
| Prompt 中文化 | 10 个 v2/v3 模板加中文指令 | `prompt_template/v2/*` / `v3_ChatGPT/*` |
| Prompt 中文化 | `revise_identity` 里 4 个 inline prompt | `plan.py:~516-540` |
| 前端模板 | persona_state、demo、home 三个页面 | `environment/frontend_server/templates/` |
| 中文人设 | 新 base 仿真,人名英文+描述中文 | `storage/base_the_ville_zh_isabella_maria_klaus/` |

---

## 一、单元测试(30 秒)

快速验证 GLM + 中文 prompt 管道能返回真中文内容,不走 fail_safe `"..."`。

```bash
ssh root@49.233.189.223 \
  'cd /opt/workspace/hehe/agentic_collab/reverie/backend_server && python3 demo_zh_chat.py 2>/dev/null'
```

**预期**:Isabella 和 Klaus 在 Hobbs Cafe 的 6 轮中文对话(内容每次不同,因 temperature > 0)。

**失败信号**:
- 输出是 `{"utterance": "..."}` → fail_safe 触发,说明 prompt/API 某环节返回格式不对
- 所有字段都是英文 → 中文指令未生效,检查 `iterative_convo_v1.py` 末尾是否有 `IMPORTANT: ... 简体中文 ...`
- 报 1214 错误 → `gpt_structure.py` 的 role 修复丢失

---

## 二、端到端验证:跑一个新仿真(~35 分钟)

```bash
ssh root@49.233.189.223
cd /opt/workspace/hehe/agentic_collab/reverie/backend_server
nohup python3 automatic_execution.py \
  --origin base_the_ville_zh_isabella_maria_klaus \
  --target test-zh-smoke \
  --steps 2500 \
  --ui None \
  > /tmp/test-zh-smoke.log 2>&1 &
```

2500 步覆盖到 Isabella 起床完成晨间例行(凌晨到约 6:56 AM)。

**跑完后的期望状态**(查 `scratch.json`):
- `currently`:以 "Status: ..." 开头,**整段中文**,人名地名英文
- `daily_req`:列表,每条中文,时间格式英文("7:00 am" 等)
- `f_daily_schedule`:列表,每项中文"正在 XXX"

**快速检查脚本**:

```python
import json, os, glob
STORAGE = "/opt/workspace/hehe/agentic_collab/environment/frontend_server/storage"
latest = max(glob.glob(f"{STORAGE}/test-zh-smoke-s-*"),
             key=lambda x: int(os.path.basename(x).split('-s-')[1].split('-')[0]))
for name in ["Isabella Rodriguez", "Maria Lopez", "Klaus Mueller"]:
    s = json.load(open(f"{latest}/personas/{name}/bootstrap_memory/scratch.json"))
    curr = s.get("currently", "")[:200]
    has_cn = any("\u4e00" <= c <= "\u9fff" for c in curr)
    print(f"{'🇨🇳' if has_cn else '🇺🇸'} {name}: {curr}")
```

三行都要是 🇨🇳。

---

## 三、浏览器查看现有仿真 `verify-zh-2day`(过夜跑的)

### 3.1 看最新状态(还在跑)

```
http://49.233.189.223:8000/demo/verify-zh-2day-s-24-4799-4999/4800/2/
```

URL 格式说明:`/demo/<sim_code>/<step>/<play_speed>/`
- 页面是仿真地图 + 侧边角色卡
- 点角色头像,看"当前对话"面板

### 3.2 三场高价值对话(demo URL,带气泡 + 播放控制)

| 场景 | URL | 内容 |
|---|---|---|
| Isabella ↔ Maria 规划全天(13 轮) | `http://49.233.189.223:8000/demo/verify-zh-2day-s-22-4399-4599/4477/2/` | 下午 1:30 碰头 / 2pm Klaus 一对一 / 7:30pm 图书馆 / 9pm 前结束 |
| Klaus ↔ Isabella 聊咖啡 + 研究(8 轮) | `http://49.233.189.223:8000/demo/verify-zh-2day-s-23-4599-4799/4725/2/` | 埃塞俄比亚耶加雪菲、柑橘花香、士绅化研究新数据 |
| Klaus ↔ Maria 再确认(4 轮) | `http://49.233.189.223:8000/demo/verify-zh-2day-s-24-4799-4999/4667/2/` | 下午 1:30 pm + 晚上 7:30 pm 两场会议 |

**涌现行为**:三场双人对话独立发生,却拼出了完全一致的日程表 —— 这是 Stanford Generative Agents 论文的核心验证点,中文版复现成功。

### 3.3 persona_state 全中文验证

```
http://49.233.189.223:8000/replay_persona_state/verify-zh-2day-s-24-4799-4999/4800/Isabella_Rodriguez/
http://49.233.189.223:8000/replay_persona_state/verify-zh-2day-s-24-4799-4999/4800/Klaus_Mueller/
http://49.233.189.223:8000/replay_persona_state/verify-zh-2day-s-24-4799-4999/4800/Maria_Lopez/
```

(注意:persona 名字里空格换下划线)

页面上应该全中文的区块:
- **基本信息**(标签中文,字段值:first_name/last_name 是英文名、age 是数字)
- **感知参数**(纯数值)
- **人格与生活方式**:天生特质、习得特质、**当前状态**、生活习惯 → 全中文句子
- **当前行动状态**:日常目标(列表中文)、今日日程(列表中文)、行动描述(中文进行时)
- **记忆 → 对话历史**:中文摘要 + 中文原文
- **内心想法**:中文反思

**仅这些 可能 英文**(已知、非阻塞):
- `act_address`:地图内部键名,"the Ville:Hobbs Cafe:cafe:cafe customer seating" 这种 —— 必须保留
- 偶尔的 `sleeping` 等基础状态 —— bootstrap 初始占位,次日 revise_identity 后会被新内容覆盖

---

## 四、量化指标(验收红线)

抽样最近 1000 条 LLM 响应,统计:

```bash
ssh root@49.233.189.223 'bash -s' <<'EOF'
LOG=/tmp/verify_zh_2day.log   # 换成你自己的 sim 日志
ok=$(grep -c "^Response: ChatCompletion" $LOG)
err=$(grep -c "^Error:" $LOG)
e1214=$(grep -cE "code.{0,5}: .{0,3}1214" $LOG)
echo "ok: $ok, err: $err, 真 1214: $e1214"
echo "失败率: $(python3 -c "print(f'{$err/($ok+$err)*100:.1f}%')")"
EOF
```

**红线**:
| 指标 | 可接受 | 要警惕 |
|---|---|---|
| 真 1214 错误 | 0 | ≥ 5 |
| 总失败率 | < 10% | > 20% |
| ok 计数 | 稳步增长 | 30 分钟不变(卡死) |
| 步数推进 | 有增长 | 60 分钟不变(卡死) |

本次过夜(10.5 小时)实测:1289 ok / 52 err / 0 真 1214 / 4% 失败率。

---

## 五、故障排查

| 症状 | 可能原因 | 排查 |
|---|---|---|
| 对话全是 `"..."` | iterative_convo fail_safe 被触发 | 看 `/tmp/<log>` 里 `<generate_convo>` 段,若 LLM 返回 schema 定义而非内容 → glm-4-plus 没配好;若报 1214 → role 修复丢失 |
| `currently` 字段英文 | `plan.py:revise_identity` 的 Chinese 指令丢了 | 检查 `cognitive_modules/plan.py` 约 516 行附近是否有中文指令 |
| demo URL 报 500 FileNotFoundError | sim 还没压缩到 `compressed_storage/` | 跑 `python3 reverie/compress_sim_storage.py` 然后手动 `c.compress('<sim_code>')` |
| replay URL 能看地图但点角色没对话 | 仿真阶段该角色确实没在聊天 | 先切到 `/demo/` 路由,它能显示当前对话面板;否则查 `movement/<step>.json` 里该 persona 的 `chat` 字段 |
| 前端 404 | Django runserver 挂了 | `pgrep -af "manage.py runserver"` 检查进程 |
| 仿真卡在某步不动 | 某个 LLM 调用无限 retry | 查 log tail 看最后的 `Attempt N` 循环,必要时 kill + 从最近 checkpoint 重启 |

---

## 六、相关文件索引

- 改动汇总:`docs/glm-migration.md`(上一轮 GLM 迁移)+ 本文件
- 值班记录:`/opt/workspace/hehe/aws-remote/nightshift_log.txt`(过夜实录)
- Demo 文档:`/opt/workspace/hehe/aws-remote/morning_demo.md`
- 单元测试脚本:`reverie/backend_server/demo_zh_chat.py`
- 中文 base 仿真:`environment/frontend_server/storage/base_the_ville_zh_isabella_maria_klaus/`
