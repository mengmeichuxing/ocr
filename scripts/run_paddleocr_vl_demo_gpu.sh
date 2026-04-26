#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${ROOT_DIR}/.venv_paddleocr_vl"
PADDLEOCR_BIN="${VENV_DIR}/bin/paddleocr"

INPUT_PATH="${1:-${ROOT_DIR}/samples/paddleocr_vl_demo.png}"
OUTPUT_DIR="${2:-${ROOT_DIR}/output/demo_gpu_script}"
SERVER_URL="${SERVER_URL:-http://127.0.0.1:8114/v1}"
MODEL_NAME="${MODEL_NAME:-PaddleOCR-VL-1.5.gguf}"

if [[ ! -x "${PADDLEOCR_BIN}" ]]; then
  echo "Missing paddleocr executable: ${PADDLEOCR_BIN}" >&2
  exit 1
fi

if [[ ! -e "${INPUT_PATH}" ]]; then
  echo "Missing input file: ${INPUT_PATH}" >&2
  exit 1
fi

unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
export NO_PROXY=127.0.0.1,localhost
export no_proxy=127.0.0.1,localhost

source "${VENV_DIR}/bin/activate"

exec paddleocr doc_parser \
  --input "${INPUT_PATH}" \
  --device cpu \
  --save_path "${OUTPUT_DIR}" \
  --vl_rec_backend llama-cpp-server \
  --vl_rec_server_url "${SERVER_URL}" \
  --vl_rec_api_model_name "${MODEL_NAME}" \
  --vl_rec_max_concurrency 1
