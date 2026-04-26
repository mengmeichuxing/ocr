#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${ROOT_DIR}/.venv_paddleocr_vl"
PADDLEOCR_BIN="${VENV_DIR}/bin/paddleocr"

INPUT_PATH="${1:-${ROOT_DIR}/samples/paddleocr_vl_demo.png}"
OUTPUT_DIR="${2:-${ROOT_DIR}/output/ppstructurev3_lite_fast}"
CPU_THREADS="${CPU_THREADS:-8}"

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
export PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True

source "${VENV_DIR}/bin/activate"

exec paddleocr pp_structurev3 \
  -i "${INPUT_PATH}" \
  --save_path "${OUTPUT_DIR}" \
  --use_doc_orientation_classify False \
  --use_doc_unwarping False \
  --use_textline_orientation False \
  --use_seal_recognition False \
  --use_table_recognition False \
  --use_formula_recognition False \
  --use_chart_recognition False \
  --use_region_detection False \
  --format_block_content False \
  --text_detection_model_name PP-OCRv5_mobile_det \
  --text_recognition_model_name PP-OCRv5_mobile_rec \
  --device cpu \
  --engine paddle_dynamic \
  --cpu_threads "${CPU_THREADS}"
