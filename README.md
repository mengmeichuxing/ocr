# OCR Project (PaddleOCR-VL + llama.cpp)

基于 PaddleOCR-VL 和 llama.cpp 的 OCR 识别工具。

## 依赖下载

以下目录已从 git 中排除，需手动下载：

### 1. PaddleOCR-VL 模型

从 HuggingFace 下载 GGUF 格式模型文件：

```bash
# 创建模型目录
mkdir -p models/paddleocr-vl-1.5-gguf
cd models/paddleocr-vl-1.5-gguf

# 下载模型 (约 1.7G)
wget https://huggingface.co/ggml-org/PaddleOCR-VL-1.5-gguf/resolve/main/PaddleOCR-VL-1.5.gguf
wget https://huggingface.co/ggml-org/PaddleOCR-VL-1.5-gguf/resolve/main/PaddleOCR-VL-1.5-mmproj.gguf
```

### 2. llama.cpp

```bash
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
make -j
```
