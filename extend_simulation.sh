#!/bin/bash
#
# extend_simulation.sh - 在已完成的模拟基础上继续跑更多步数
#
# 用法:
#   ./extend_simulation.sh <origin> <target> <steps>
#
# 示例:
#   # 等 glm-25agent-test-s-0-0-100 跑完后，接着跑 200 步
#   ./extend_simulation.sh glm-25agent-test-s-0-0-100 glm-25agent-extend 200
#
#   # 后台运行
#   nohup ./extend_simulation.sh glm-25agent-test-s-0-0-100 glm-25agent-extend 200 > /tmp/extend.log 2>&1 &
#
# 说明:
#   - 如果 origin 对应的模拟还在跑，脚本会等待它完成后再启动
#   - agent 的记忆、位置、状态全部从 origin 继承
#   - 新的模拟数据保存在 storage/<target>-s-*/ 目录下

set -e

ORIGIN="${1:?用法: $0 <origin> <target> <steps>}"
TARGET="${2:?用法: $0 <origin> <target> <steps>}"
STEPS="${3:?用法: $0 <origin> <target> <steps>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="${SCRIPT_DIR}/reverie/backend_server"
STORAGE_DIR="${SCRIPT_DIR}/environment/frontend_server/storage"

echo "[$(date)] extend_simulation: origin=${ORIGIN}, target=${TARGET}, steps=${STEPS}"

# Check if origin directory exists or if a simulation producing it is still running
if [ ! -d "${STORAGE_DIR}/${ORIGIN}" ]; then
    echo "[$(date)] Origin '${ORIGIN}' not found in storage. Checking if a simulation is producing it..."
fi

# Wait for any running simulation that targets this origin
while ps aux | grep "automatic_execution" | grep -v grep | grep -q "${ORIGIN%%-s-*}"; do
    CURRENT_STEPS=$(ls "${STORAGE_DIR}/${ORIGIN}/movement/" 2>/dev/null | wc -l)
    echo "[$(date)] Waiting for previous simulation to complete... (${CURRENT_STEPS} steps so far)"
    sleep 60
done

# Verify origin exists
if [ ! -d "${STORAGE_DIR}/${ORIGIN}" ]; then
    echo "[$(date)] ERROR: Origin '${ORIGIN}' not found in ${STORAGE_DIR}/"
    echo "Available simulations:"
    ls "${STORAGE_DIR}/" | grep -v "^base_"
    exit 1
fi

ORIGIN_STEPS=$(ls "${STORAGE_DIR}/${ORIGIN}/movement/" 2>/dev/null | wc -l)
echo "[$(date)] Origin '${ORIGIN}' has ${ORIGIN_STEPS} steps. Starting extension with ${STEPS} more steps..."

cd "${BACKEND_DIR}"
python3 automatic_execution.py \
    --origin "${ORIGIN}" \
    --target "${TARGET}" \
    --steps "${STEPS}" \
    --ui None

echo "[$(date)] Extension completed. New simulation: ${TARGET}"
echo "[$(date)] Replay URL: http://<your-ip>:8000/replay/${TARGET}-s-0-0-${STEPS}/0/"
