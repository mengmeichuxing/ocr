#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_BIN="${ROOT_DIR}/llama.cpp/build-cuda/bin/llama-server"
MODEL_PATH="${ROOT_DIR}/models/paddleocr-vl-1.5-gguf/PaddleOCR-VL-1.5.gguf"
MMPROJ_PATH="${ROOT_DIR}/models/paddleocr-vl-1.5-gguf/PaddleOCR-VL-1.5-mmproj.gguf"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8114}"
THREADS="${THREADS:-8}"
CTX_SIZE="${CTX_SIZE:-2048}"
GPU_LAYERS="${GPU_LAYERS:-999}"

for required_path in "${SERVER_BIN}" "${MODEL_PATH}" "${MMPROJ_PATH}"; do
  if [[ ! -e "${required_path}" ]]; then
    echo "Missing required path: ${required_path}" >&2
    exit 1
  fi
done

unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
export NO_PROXY=127.0.0.1,localhost
export no_proxy=127.0.0.1,localhost

exec "${SERVER_BIN}" \
  -m "${MODEL_PATH}" \
  --mmproj "${MMPROJ_PATH}" \
  --no-mmproj-offload \
  --host "${HOST}" \
  --port "${PORT}" \
  -ngl "${GPU_LAYERS}" \
  -c "${CTX_SIZE}" \
  -t "${THREADS}" \
  --temp 0 \
  --no-warmup
