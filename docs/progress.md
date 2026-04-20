# agentic_collab 中文化 + GLM 修复进展

最后更新:2026-04-20

## 一句话现状

3 人中文版已完成并验证。25 人中文版（`base_the_ville_zh_n25`）人设翻译完成，已同步到腾讯云，待跑 3000 步仿真。

## 已完成

| 改动 | 文件 / 位置 | 提交 |
|---|---|---|
| 模型 glm-4-flash → glm-4-plus | `openai_config.json`(gitignored,两端手动同步) | — |
| 1214 错误修复(role system→user) | `reverie/backend_server/persona/prompt_template/gpt_structure.py:460` | `0bb953f8` |
| 对话 prompt 中文 + 人名锁英文 | `v3_ChatGPT/iterative_convo_v1.py` | `283a1137` |
| 10 个 v2/v3 prompt 加中文指令 | `persona/prompt_template/v2/*`、`v3_ChatGPT/*` | `4ff3d4e2` |
| `revise_identity` 里 4 个 inline prompt 加中文指令 | `cognitive_modules/plan.py` | `8cc1a0cc` |
| 3 个前端模板翻译(persona_state / demo / home) | `environment/frontend_server/templates/` | `b0170a42` |
| 中文人设 base 仿真(人名英文、描述中文) | `storage/base_the_ville_zh_isabella_maria_klaus/` | `ec678ee1` |
| `demo_zh_chat.py` 单元测试脚本 | `reverie/backend_server/demo_zh_chat.py` | `41210490` / `f993693c` |
| 验证测试文档 | `docs/zh-verification.md` | `893bceea` |

## 过夜跑的仿真

`verify-zh-2day`,跑了 10.5 小时,step 4936 @ sim 时间 13:42 PM 被手动 kill(推进速度太慢,边际产出递减)。

**量化结果**
- 1289 ok / 52 err / **0 个真 1214 错误** / 失败率 4%
- 产出 3 场独立真实中文对话,拼出一致的多人日程表(核心的 emergent behavior 验证)

**3 场对话的观看 URL**(播放 2× 速)
```
http://49.233.189.223:8000/demo/verify-zh-2day-s-22-4399-4599/4477/2/  # Isabella ↔ Maria,13 轮
http://49.233.189.223:8000/demo/verify-zh-2day-s-23-4599-4799/4725/2/  # Isabella ↔ Klaus,8 轮(咖啡 + 士绅化)
http://49.233.189.223:8000/demo/verify-zh-2day-s-24-4799-4999/4667/2/  # Klaus ↔ Maria,4 轮
```

**persona_state 全中文验证**
```
http://49.233.189.223:8000/replay_persona_state/verify-zh-2day-s-24-4799-4999/4800/Isabella_Rodriguez/
http://49.233.189.223:8000/replay_persona_state/verify-zh-2day-s-24-4799-4999/4800/Klaus_Mueller/
http://49.233.189.223:8000/replay_persona_state/verify-zh-2day-s-24-4799-4999/4800/Maria_Lopez/
```

## 当前运行状态(腾讯云 49.233.189.223)

仍在跑:
- Django frontend(PID 1021213,端口 8000)— 浏览器查看 URL 靠它
- tencent_agent.py(PID 1299772)— aws-remote 任务通道

没有在跑的:
- 所有 sim 进程已清理
- 所有 monitor 进程已清理

## 25 人中文版进展

详细计划见 `docs/plan-zh-n25.md`。

| 步骤 | 内容 | 状态 |
|---|---|---|
| 第 1 步 | 创建 `base_the_ville_zh_n25` 目录 | ✓ 完成 |
| 第 2 步 | 翻译 25 个角色 scratch.json | ✓ 完成（`4f65f053`） |
| 第 3 步 | 提交 + 推送 + 腾讯云同步 | ✓ 完成 |
| 第 4 步 | 冒烟测试（demo_zh_chat.py） | 待执行 |
| 第 5 步 | 启动 3000 步仿真 | 待执行 |
| 第 6 步 | 检查结果 | 待执行 |

## 已解决的悬而未决

- `smoke-test.sh` 已提交到 `scripts/smoke-test.sh`（`6656d86a`）

## 相关文件索引

- 本文件:`docs/progress.md`
- 25 人计划:`docs/plan-zh-n25.md`
- 测试方法文档:`docs/zh-verification.md`
- 冒烟测试脚本:`scripts/smoke-test.sh`
- 单元测试脚本:`reverie/backend_server/demo_zh_chat.py`
- 25 人中文 base 仿真:`environment/frontend_server/storage/base_the_ville_zh_n25/`
- 翻译脚本:`scripts/translate_n25.py`

## 回来了怎么快速回到状态

```bash
# 看进度和计划
cat docs/progress.md
cat docs/plan-zh-n25.md

# 单元烟测(30 秒)
ssh root@49.233.189.223 'cd /opt/workspace/hehe/agentic_collab/reverie/backend_server && python3 demo_zh_chat.py 2>/dev/null | head -20'

# 完整冒烟测试(~5 分钟)
ssh root@49.233.189.223 'cd /opt/workspace/hehe/agentic_collab && bash scripts/smoke-test.sh'
```
