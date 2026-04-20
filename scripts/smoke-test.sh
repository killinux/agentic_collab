#!/usr/bin/env bash
# 日常冒烟测试：改代码后快速验证核心功能没坏
# 用法：在腾讯云上执行  bash scripts/smoke-test.sh
set -euo pipefail

REPO=/opt/workspace/hehe/agentic_collab
BACKEND=$REPO/reverie/backend_server
FRONTEND_URL=http://localhost:8000
SIM_NAME="smoke-$(date +%Y%m%d-%H%M%S)"

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

pass() { echo -e "  ${GREEN}✓${RESET} $1"; }
fail() { echo -e "  ${RED}✗${RESET} $1"; EXIT_CODE=1; }

EXIT_CODE=0

echo -e "\n${BOLD}[1/4] 单元测试：demo_zh_chat.py${RESET}"
if cd "$BACKEND" && python3 demo_zh_chat.py 2>/dev/null | grep -q "总轮数"; then
    pass "中文对话生成正常"
else
    fail "demo_zh_chat.py 失败"
fi

echo -e "\n${BOLD}[2/4] 短仿真：100 步${RESET}"
cd "$BACKEND"
LOG="/tmp/${SIM_NAME}.log"
python3 automatic_execution.py \
    --origin base_the_ville_zh_isabella_maria_klaus \
    --target "$SIM_NAME" \
    --steps 100 \
    --ui None \
    > "$LOG" 2>&1 || true

ok=$(grep -c "^Response: ChatCompletion" "$LOG" 2>/dev/null || echo 0)
err=$(grep -c "^Error:" "$LOG" 2>/dev/null || echo 0)
e1214=$(grep -cE "code.{0,5}: .{0,3}1214" "$LOG" 2>/dev/null || echo 0)

if [ "$e1214" -eq 0 ] && [ "$ok" -gt 0 ]; then
    pass "100 步完成 (ok=$ok, err=$err, 1214=$e1214)"
else
    fail "100 步异常 (ok=$ok, err=$err, 1214=$e1214)"
fi

echo -e "\n${BOLD}[3/4] 前端可达性${RESET}"
if curl -s --max-time 5 "$FRONTEND_URL" | grep -qi "ville"; then
    pass "Django 前端正常 ($FRONTEND_URL)"
else
    fail "Django 前端不可达"
fi

echo -e "\n${BOLD}[4/4] 最近日志错误分布${RESET}"
if [ -f "$LOG" ]; then
    total=$((ok + err))
    if [ "$total" -gt 0 ]; then
        rate=$(python3 -c "print(f'{${err}/${total}*100:.1f}%')")
        echo "  成功: $ok  失败: $err  失败率: $rate  真1214: $e1214"
        if [ "$err" -gt 0 ]; then
            echo "  最近错误样本:"
            grep "^Error:" "$LOG" 2>/dev/null | tail -3 | sed 's/^/    /'
        fi
    fi
else
    echo "  (无日志)"
fi

echo ""
if [ "$EXIT_CODE" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}全部通过${RESET}"
else
    echo -e "${RED}${BOLD}有失败项，请检查${RESET}"
fi
exit $EXIT_CODE
