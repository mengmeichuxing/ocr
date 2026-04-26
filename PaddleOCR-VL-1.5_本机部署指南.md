# PaddleOCR-VL-1.5 本机部署指南

补充说明：

- 如果你的核心诉求已经从“文档大模型理解”切到“更快拿到 OCR 文字结果”，请优先看同目录下的新文档：
- `更快OCR路线_实施方案.md`

适用日期：2026-04-22

适用机器：

- 系统：Ubuntu 24.04 x86_64
- CPU：Intel Core i5-8300H，4 核 8 线程
- 内存：16 GiB
- GPU：NVIDIA GeForce GTX 1050 Mobile，2 GiB 显存

实测状态（2026-04-22）：

- 已完成 `GGUF + mmproj` 下载，实际文件大小与文档记录一致。
- 已完成 `llama.cpp` 编译，当前实测二进制可正常启动本地服务。
- 已完成 `PaddlePaddle CPU` 和 `paddleocr[doc-parser]` 安装。
- 已完成官方 demo 图端到端回归，成功生成 `json / md / docx / layout png / crop image` 输出。
- 当前账号没有 `sudo` 免密权限，因此系统依赖部分补充了“用户态自举”方案。
- 当前系统环境里存在 `ALL_PROXY=socks://127.0.0.1:7897/`，第一次调用 `paddleocr doc_parser` 时会触发 `httpx` 代理解析错误，运行本地回环请求前需要临时清掉代理变量。

## 1. 结论先说

这台机器最适合的方案不是走 NVIDIA GPU 推理，而是：

`PaddleOCR 客户端 + llama.cpp 本地服务 + PaddleOCR-VL-1.5 GGUF + CPU-only`

原因很直接：

- 你的 `GTX 1050` 属于 `Pascal`，CUDA Compute Capability 是 `6.1`，低于 PaddleOCR 文档里 PaddlePaddle/Transformers GPU 路线要求的 `CC >= 7.0`。
- 你的 NVIDIA 驱动显示 `CUDA Version 12.2`，而 PaddleOCR 文档里 `vLLM` 路线要求 `CUDA >= 12.6`。
- 你的独显只有 `2 GiB` 显存，实际还要被桌面占用，显存余量不适合跑这个 0.9B 文档 VLM。
- GGUF 版本总大小约 `1.82 GB`，更适合你这台机器走 CPU 本地离线方案。

一句话总结：

- 能本地跑。
- 适合少量文档、离线验证、个人使用。
- 不适合高并发、长 PDF 批处理、追求速度的生产部署。

## 2. 这套方案的工作方式

这套方案不是让 PaddleOCR 直接在本机 GPU 上跑完整 VLM，而是拆成两部分：

- `llama.cpp` 在本地以服务形式加载 `PaddleOCR-VL-1.5.gguf` 和 `mmproj`，只负责多模态大模型推理。
- `PaddleOCR` 客户端负责版面检测、流程编排、结果整理，并通过 HTTP 调用本地 `llama.cpp` 服务。

这样做的好处是：

- 避开你的 GPU 限制。
- 利用 GGUF 量化模型降低本地运行门槛。
- 保持和 PaddleOCR 官方 `doc_parser` 流程兼容。

## 3. 最终目录结构

建议统一放在当前目录 `~/桌面/ocr` 下：

```text
ocr/
├── PaddleOCR-VL-1.5_本机部署指南.md
├── llama.cpp/
├── models/
│   └── paddleocr-vl-1.5-gguf/
│       ├── PaddleOCR-VL-1.5.gguf
│       └── PaddleOCR-VL-1.5-mmproj.gguf
├── samples/
├── output/
└── .venv_paddleocr_vl/
```

## 4. 第一步：安装系统依赖

先进入工作目录：

```bash
cd "$HOME/桌面/ocr"
```

安装构建和 Python 依赖：

```bash
sudo apt update
sudo apt install -y \
  build-essential \
  cmake \
  curl \
  git \
  git-lfs \
  python3-pip \
  python3-venv
```

说明：

- 你的机器当前缺 `cmake`、`python3-pip`、`python3-venv`、`git-lfs`，这一步需要补齐。
- `git-lfs` 不是必须，但保留它以后下载 Hugging Face 大文件会更方便。

如果你当前账号没有 `sudo` 权限，可以走用户态自举方案。下面这组命令已经在这台机器上实测通过：

```bash
cd "$HOME/桌面/ocr"
mkdir -p .bootstrap

curl -L https://bootstrap.pypa.io/get-pip.py -o .bootstrap/get-pip.py
python3 .bootstrap/get-pip.py --user --break-system-packages

~/.local/bin/pip install --user --break-system-packages \
  virtualenv \
  cmake
```

这条分支的含义是：

- 用 `get-pip.py` 在用户目录安装 `pip`
- 用用户目录里的 `pip` 安装 `virtualenv` 和 `cmake`
- 不依赖 `sudo`，但要求 `build-essential`、`git`、`curl` 这类基础系统工具本机已经存在

实测补充：

- 这台机器已有 `build-essential`、`curl`、`git`
- 缺的是 `cmake`、`pip`、可用的 `venv`
- `git-lfs` 本次部署没有用到，不影响主流程

## 5. 第二步：准备目录

```bash
cd "$HOME/桌面/ocr"
mkdir -p models/paddleocr-vl-1.5-gguf
mkdir -p samples
mkdir -p output
```

## 6. 第三步：下载 GGUF 模型文件

这套模型需要两个文件：

- 主模型：`PaddleOCR-VL-1.5.gguf`
- 多模态投影：`PaddleOCR-VL-1.5-mmproj.gguf`

截至 2026-04-21，两个文件大小大约是：

- `PaddleOCR-VL-1.5.gguf`：`935,768,992` bytes
- `PaddleOCR-VL-1.5-mmproj.gguf`：`881,770,496` bytes

进入模型目录并下载：

```bash
cd "$HOME/桌面/ocr/models/paddleocr-vl-1.5-gguf"

curl -L -C - \
  -o PaddleOCR-VL-1.5.gguf \
  "https://huggingface.co/PaddlePaddle/PaddleOCR-VL-1.5-GGUF/resolve/main/PaddleOCR-VL-1.5.gguf"

curl -L -C - \
  -o PaddleOCR-VL-1.5-mmproj.gguf \
  "https://huggingface.co/PaddlePaddle/PaddleOCR-VL-1.5-GGUF/resolve/main/PaddleOCR-VL-1.5-mmproj.gguf"
```

说明：

- `-L` 表示跟随跳转。
- `-C -` 表示断点续传，下载中断后可以重新执行。
- 下载完后建议用 `ls -lh` 看一下两个文件是否都在。

检查文件：

```bash
ls -lh "$HOME/桌面/ocr/models/paddleocr-vl-1.5-gguf"
```

## 7. 第四步：编译 llama.cpp 的本地服务

回到工作目录并拉取源码：

```bash
cd "$HOME/桌面/ocr"
git clone https://github.com/ggml-org/llama.cpp.git
```

配置并编译 `llama-server`：

```bash
cd "$HOME/桌面/ocr"

cmake -S llama.cpp -B llama.cpp/build -DCMAKE_BUILD_TYPE=Release
cmake --build llama.cpp/build --config Release -j"$(nproc)" --target llama-server
```

编译完成后，服务二进制通常在：

```text
~/桌面/ocr/llama.cpp/build/bin/llama-server
```

检查一下是否成功：

```bash
ls -lh "$HOME/桌面/ocr/llama.cpp/build/bin/llama-server"
```

## 8. 第五步：创建 PaddleOCR Python 虚拟环境

优先使用系统 `venv`：

```bash
cd "$HOME/桌面/ocr"
python3 -m venv .venv_paddleocr_vl
source .venv_paddleocr_vl/bin/activate
```

如果你遇到 Ubuntu 24.04 常见的 `ensurepip is not available`，说明系统 `python3-venv` 没装好，这时直接改用用户态 `virtualenv`：

```bash
cd "$HOME/桌面/ocr"
virtualenv -p python3 .venv_paddleocr_vl
source .venv_paddleocr_vl/bin/activate
```

升级基础打包工具：

```bash
python -m pip install --upgrade pip setuptools wheel
```

安装 PaddlePaddle CPU 版和 PaddleOCR：

```bash
python -m pip install "paddlepaddle>=3.2.1" \
  -i https://www.paddlepaddle.org.cn/packages/stable/cpu/

python -m pip install -U "paddleocr[doc-parser]"
python -m pip install python-docx
```

说明：

- 这里明确走 `CPU` 版 PaddlePaddle，不要装 `paddlepaddle-gpu`。
- 第一次安装会花一点时间。
- 这台机器上实际安装到的版本是 `paddlepaddle 3.3.1`、`paddleocr 3.5.0`。
- 当前机器上还额外补装了 `python-docx 1.2.0`，否则 `save_all()` 在导出 `.docx` 时会报错。
- 如果以后重新打开终端，记得重新执行：

```bash
source "$HOME/桌面/ocr/.venv_paddleocr_vl/bin/activate"
```

## 9. 第六步：启动本地 llama.cpp 服务

新开一个终端，执行下面的命令启动服务：

```bash
cd "$HOME/桌面/ocr"

./llama.cpp/build/bin/llama-server \
  -m "$HOME/桌面/ocr/models/paddleocr-vl-1.5-gguf/PaddleOCR-VL-1.5.gguf" \
  --mmproj "$HOME/桌面/ocr/models/paddleocr-vl-1.5-gguf/PaddleOCR-VL-1.5-mmproj.gguf" \
  --host 127.0.0.1 \
  --port 8111 \
  -ngl 0 \
  -c 4096 \
  -t 8 \
  --temp 0
```

这些参数为什么这样配：

- `-ngl 0`：强制不往 GPU 丢层，避免 GTX 1050 2GB 显存带来问题。
- `-c 4096`：把上下文限制在更现实的范围，避免默认上下文过大导致内存压力。
- `-t 8`：对应你的 `8` 个逻辑线程。
- `--temp 0`：OCR 场景更适合稳定输出。

如果你后面发现内存压力大，优先把 `-c 4096` 改成 `-c 2048`。

## 10. 第七步：验证服务是否成功启动

服务启动后，在另一个终端检查健康状态：

```bash
curl http://127.0.0.1:8111/health
```

如果服务正常，应该返回健康检查结果。

还可以看一下服务暴露出来的模型信息：

```bash
curl http://127.0.0.1:8111/v1/models
```

这一步很有用：

- 如果后面 PaddleOCR 客户端报“模型名不匹配”，就把这里返回的模型 `id` 填给 `--vl_rec_api_model_name`。

## 11. 第八步：准备测试图片

先下载 PaddleOCR 官方 demo 图：

```bash
cd "$HOME/桌面/ocr"

curl -L -o samples/paddleocr_vl_demo.png \
  https://paddle-model-ecology.bj.bcebos.com/paddlex/imgs/demo_image/paddleocr_vl_demo.png
```

你也可以把自己的图片或 PDF 放到 `samples/` 目录里。

## 12. 第九步：第一次运行 OCR

再开一个终端，激活虚拟环境：

```bash
cd "$HOME/桌面/ocr"
source .venv_paddleocr_vl/bin/activate
```

执行最推荐的首次验证命令：

```bash
paddleocr doc_parser \
  --input "$HOME/桌面/ocr/samples/paddleocr_vl_demo.png" \
  --device cpu \
  --save_path "$HOME/桌面/ocr/output/demo" \
  --vl_rec_backend llama-cpp-server \
  --vl_rec_server_url http://127.0.0.1:8111/v1 \
  --vl_rec_max_concurrency 1
```

如果你的环境里配置了代理，尤其是像下面这样的变量：

```bash
ALL_PROXY=socks://127.0.0.1:7897/
```

那么第一次运行前，建议直接用下面这组更稳的命令。这个版本已经在当前机器上实测，可以避开 `httpx` 对 `socks://` 代理 URL 的解析报错：

```bash
cd "$HOME/桌面/ocr"
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
export NO_PROXY=127.0.0.1,localhost
export no_proxy=127.0.0.1,localhost

source .venv_paddleocr_vl/bin/activate

paddleocr doc_parser \
  --input "$HOME/桌面/ocr/samples/paddleocr_vl_demo.png" \
  --device cpu \
  --save_path "$HOME/桌面/ocr/output/demo" \
  --vl_rec_backend llama-cpp-server \
  --vl_rec_server_url http://127.0.0.1:8111/v1 \
  --vl_rec_api_model_name PaddleOCR-VL-1.5.gguf \
  --vl_rec_max_concurrency 1
```

说明：

- `--device cpu`：客户端本身也走 CPU。
- `--vl_rec_backend llama-cpp-server`：告诉 PaddleOCR，大模型能力来自本地 `llama.cpp` 服务。
- `--vl_rec_server_url`：指定本地服务地址。
- `--vl_rec_api_model_name PaddleOCR-VL-1.5.gguf`：当前机器上 `/v1/models` 返回的模型 `id` 就是这个值，显式传入更稳。
- `--vl_rec_max_concurrency 1`：你的机器内存和 CPU 比较紧，先用单并发最稳。
- 第一次运行时，PaddleOCR 还会下载自己的版面检测等辅助模型，比如 `PP-DocLayoutV3`，所以首跑会更慢。
- 当前机器的成功复跑实测里，官方 demo 图处理耗时约 `206,716 ms`，也就是约 `3 分 27 秒`。
- 首跑如果叠加辅助模型下载、字体下载和排障，整体耗时会更长。

如果图片是扫描件、方向容易错，可以第二次再加这些参数试：

```bash
--use_doc_orientation_classify True
--use_doc_unwarping True
```

但是在你这台机器上，这两个功能会进一步增加耗时，首次验证先不要开。

## 13. 第十步：查看输出结果

默认会在下面这个目录生成输出：

```text
~/桌面/ocr/output/demo
```

你可以先看：

- 终端里的结构化输出
- `output/demo` 里的保存结果

当前机器上的成功回归，实际生成了这些文件：

- `paddleocr_vl_demo_res.json`
- `paddleocr_vl_demo.md`
- `paddleocr_vl_demo.docx`
- `paddleocr_vl_demo_layout_det_res.png`
- `imgs/img_in_image_box_777_201_1502_685.jpg`

如果你要处理自己的文件，把 `--input` 换成你的路径即可，比如：

```bash
paddleocr doc_parser \
  --input "$HOME/桌面/ocr/samples/your_file.pdf" \
  --device cpu \
  --save_path "$HOME/桌面/ocr/output/your_file" \
  --vl_rec_backend llama-cpp-server \
  --vl_rec_server_url http://127.0.0.1:8111/v1 \
  --vl_rec_max_concurrency 1
```

## 14. 日常使用时的最简流程

以后常用时，基本只需要两个终端。

终端 1：启动本地 VLM 服务

```bash
cd "$HOME/桌面/ocr"
./llama.cpp/build/bin/llama-server \
  -m "$HOME/桌面/ocr/models/paddleocr-vl-1.5-gguf/PaddleOCR-VL-1.5.gguf" \
  --mmproj "$HOME/桌面/ocr/models/paddleocr-vl-1.5-gguf/PaddleOCR-VL-1.5-mmproj.gguf" \
  --host 127.0.0.1 \
  --port 8111 \
  -ngl 0 \
  -c 4096 \
  -t 8 \
  --temp 0
```

终端 2：调用 PaddleOCR

```bash
cd "$HOME/桌面/ocr"
source .venv_paddleocr_vl/bin/activate

paddleocr doc_parser \
  --input "$HOME/桌面/ocr/samples/xxx.png" \
  --device cpu \
  --save_path "$HOME/桌面/ocr/output/xxx" \
  --vl_rec_backend llama-cpp-server \
  --vl_rec_server_url http://127.0.0.1:8111/v1 \
  --vl_rec_max_concurrency 1
```

## 15. 这台机器上的调优建议

### 15.1 稳定优先

先用下面这组参数：

- `-ngl 0`
- `-c 4096`
- `-t 8`
- `--vl_rec_max_concurrency 1`

### 15.2 如果出现内存吃紧或速度太慢

按下面顺序调：

1. 把 `-c 4096` 改成 `-c 2048`
2. 把 `-t 8` 改成 `-t 6` 或 `-t 4`
3. 继续保持 `--vl_rec_max_concurrency 1`
4. 首次先不要开 `--use_doc_orientation_classify True`
5. 首次先不要开 `--use_doc_unwarping True`

### 15.3 处理长 PDF 的建议

这台机器不适合直接拿大 PDF 做高强度批量跑，建议：

- 先抽几页测试效果
- 一次只跑一个文件
- 尽量不要同时开很多大应用
- 如果 PDF 很长，分段处理更稳

### 15.4 如果想尽量利用 GTX 1050

这条路不是官方推荐主路径，但我已经在当前机器上做过实测，结论是：

- `GTX 1050 2GB` 可以被 `llama.cpp` 的 CUDA 后端识别到
- 纯文本主模型可以基本完整 offload 到 GPU
- 但 `mmproj` 再上 GPU 会直接爆显存
- 因此最稳的组合是：`文本模型上 GPU + mmproj 留在 CPU`

当前机器上可复现的 CUDA 编译命令：

```bash
cd "$HOME/桌面/ocr"

cmake -S llama.cpp -B llama.cpp/build-cuda \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_CUDA=ON \
  -DGGML_NATIVE=OFF \
  -DCMAKE_CUDA_ARCHITECTURES=61

cmake --build llama.cpp/build-cuda --config Release \
  -j"$(nproc)" --target llama-server
```

当前机器上实测可启动的命令：

```bash
cd "$HOME/桌面/ocr"

./llama.cpp/build-cuda/bin/llama-server \
  -m "$HOME/桌面/ocr/models/paddleocr-vl-1.5-gguf/PaddleOCR-VL-1.5.gguf" \
  --mmproj "$HOME/桌面/ocr/models/paddleocr-vl-1.5-gguf/PaddleOCR-VL-1.5-mmproj.gguf" \
  --no-mmproj-offload \
  --host 127.0.0.1 \
  --port 8114 \
  -ngl 999 \
  -c 2048 \
  -t 8 \
  --temp 0 \
  --no-warmup
```

如果你不想每次手敲整段命令，现在可以直接用仓库里的脚本：

```bash
cd "$HOME/桌面/ocr"
./scripts/start_llama_server_gpu_hybrid.sh
```

这个脚本已经把下面几件事固定好了：

- 自动清理本机回环请求会踩坑的代理变量
- 默认监听 `127.0.0.1:8114`
- 默认使用 `-ngl 999`
- 默认强制 `mmproj` 留在 CPU
- 默认使用 `-c 2048`

如果你想直接跑一次 GPU 路线回归，也可以新开一个终端执行：

```bash
cd "$HOME/桌面/ocr"
./scripts/run_paddleocr_vl_demo_gpu.sh
```

默认输入是：

- `samples/paddleocr_vl_demo.png`

默认输出目录是：

- `output/demo_gpu_script`

如果要换自己的文件，也可以这样传参：

```bash
cd "$HOME/桌面/ocr"
./scripts/run_paddleocr_vl_demo_gpu.sh \
  "$HOME/桌面/ocr/samples/your_file.pdf" \
  "$HOME/桌面/ocr/output/your_file_gpu"
```

这个组合的实际含义是：

- `-ngl 999`：让 `llama.cpp` 尽可能多地往 GPU 放层
- 最终实测结果是文本主模型 `19/19 layers` 都进了 GPU
- `--no-mmproj-offload`：强制视觉投影继续留在 CPU，否则 2GB 显存不够
- `-c 2048`：给显存留更多余量，比 `4096` 更稳

当前机器上的实测现象：

- 启动后 `nvidia-smi` 大约看到 `1.5 GiB / 2 GiB` 显存占用
- VLM 生成阶段明显变快，单 token 解码时间大幅下降
- 但端到端总耗时只从大约 `206.7` 秒降到 `199.2` 秒，改善有限

为什么收益不大：

- 真正拖时间的不只是文本生成
- 视觉编码和 `mmproj` 仍然留在 CPU
- `doc_parser` 自身还有版面检测、结果整理、保存输出这些开销

所以这一条 GPU 路线的现实结论是：

- 能用上 GPU
- 但提升不大
- 值得尝试
- 不值得对这台 `2GB` 机器抱太高预期

## 16. 常见报错与解决方法

### 16.1 `cmake: command not found`

说明系统没装 `cmake`，执行：

```bash
sudo apt update
sudo apt install -y cmake
```

### 16.2 `No module named pip`

说明系统没装 `python3-pip` 或者虚拟环境没建好，执行：

```bash
sudo apt update
sudo apt install -y python3-pip python3-venv
```

然后删除旧环境并重建：

```bash
cd "$HOME/桌面/ocr"
rm -rf .venv_paddleocr_vl
python3 -m venv .venv_paddleocr_vl
source .venv_paddleocr_vl/bin/activate
python -m pip install --upgrade pip setuptools wheel
```

### 16.3 llama.cpp 服务启动了，但 PaddleOCR 调不通

先检查服务：

```bash
curl http://127.0.0.1:8111/health
curl http://127.0.0.1:8111/v1/models
```

再确认客户端参数：

- `--vl_rec_backend llama-cpp-server`
- `--vl_rec_server_url http://127.0.0.1:8111/v1`

如果依然提示模型名相关错误，就增加：

```bash
--vl_rec_api_model_name <把 /v1/models 返回的 id 填进来>
```

### 16.4 `ValueError: Unknown scheme for proxy URL URL('socks://127.0.0.1:7897/')`

这是当前机器实测碰到过的真实报错。根因不是 `llama.cpp` 服务没起来，而是：

- `paddleocr` 内部通过 OpenAI 兼容客户端访问 `http://127.0.0.1:8111/v1`
- 运行环境里存在 `ALL_PROXY=socks://127.0.0.1:7897/`
- `httpx` 对这个 `socks://` 写法直接报错，导致请求还没发出去就失败了

最直接的处理方式是在运行前临时清掉代理变量：

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
export NO_PROXY=127.0.0.1,localhost
export no_proxy=127.0.0.1,localhost
```

然后重新执行 `paddleocr doc_parser`。

### 16.5 运行中被系统杀掉，或者明显卡死

通常是内存压力太大。优先这样改：

```bash
-c 2048
```

并保持：

```bash
--vl_rec_max_concurrency 1
```

同时关掉浏览器大标签页、IDE、视频软件这类吃内存的程序。

### 16.6 CUDA 版 `llama.cpp` 启动时 `mmproj` 爆显存

这是当前机器在 GPU 路线下实测碰到的真实问题。典型现象是：

- 文本模型已经成功 offload 到 GPU
- 日志里能看到 `offloaded 19/19 layers to GPU`
- 但接着在加载 `mmproj` 时出现 `cudaMalloc failed: out of memory`

当前机器上的直接解决方法是：

```bash
--no-mmproj-offload
```

并把上下文适当收紧，例如：

```bash
-c 2048
```

### 16.7 `ModuleNotFoundError: No module named 'docx'`

这是当前机器在第一次成功推理后又遇到的真实报错。现象是：

- `paddleocr` 已经完成识别
- `res.json`、`md`、版面图等文件已经开始生成
- 但在 `save_all()` 导出 `.docx` 时失败

处理方式很直接：

```bash
cd "$HOME/桌面/ocr"
source .venv_paddleocr_vl/bin/activate
python -m pip install python-docx
```

装完后重新执行 `paddleocr doc_parser` 即可。

### 16.8 想让 GTX 1050 参与推理

不建议在这台机器上折腾这条路。原因是：

- 显卡算力等级不满足官方 GPU 路线要求
- 显存只有 `2 GiB`
- 即使勉强尝试，稳定性和收益都不理想

最稳的做法仍然是 `CPU-only + GGUF + llama.cpp`。

## 17. 预期体验

这套方案的定位是：

- 可以跑
- 可以离线
- 适合验证
- 不快

在 `i5-8300H + 16 GiB RAM` 这种机器上，单页文档的体验大概率会落在“可用但别着急”的级别。当前机器对官方 demo 图的成功回归实测约 `206.7` 秒；切到“文本层上 GPU、mmproj 留在 CPU”的混合方案后，实测约 `199.2` 秒。也就是说，能快一点，但不会出现数量级变化。具体速度会受到这些因素影响：

- 图片分辨率
- 页面复杂度
- 是否含表格、公式、印章
- 是否开启文档纠偏和去扭曲
- 当前后台程序占用

这里没有写死固定秒数，因为不同文档差异会很大；但至少可以明确，这不是“打开就秒出结果”的部署方案。

补一条 2026-04-22 的脚本化回归记录：

- 启动脚本：`scripts/start_llama_server_gpu_hybrid.sh`
- 回归脚本：`scripts/run_paddleocr_vl_demo_gpu.sh`
- 默认输入：`samples/paddleocr_vl_demo.png`
- 默认输出：`output/demo_gpu_script`
- 本次端到端实测：约 `201.0` 秒
- 产物已经成功生成：`.json`、`.md`、`.docx`、版面可视化图、裁切图片

## 18. 实测版本记录

截至 2026-04-22，这台机器上已经实际落地的关键版本是：

- `llama.cpp`：`82d3f4d`
- `cmake`：`4.3.1`（用户目录安装）
- `virtualenv`：`21.2.4`（用户目录安装）
- `paddlepaddle`：`3.3.1`
- `paddleocr`：`3.5.0`
- GPU 混合模式辅助脚本：
  - `scripts/start_llama_server_gpu_hybrid.sh`
  - `scripts/run_paddleocr_vl_demo_gpu.sh`

## 19. 如果你只想要更快的 OCR

如果你的目标只是“识别文字”，不是复杂文档理解，那这台机器上更合适的是：

- `PP-OCRv5`
- `PP-StructureV3`

它们通常会比 `PaddleOCR-VL-1.5` 这类文档大模型轻很多、快很多。

## 20. 参考来源

- PaddleOCR 官方文档：<https://www.paddleocr.ai/main/en/version3.x/pipeline_usage/PaddleOCR-VL.html>
- PaddleOCR-VL-1.5 模型卡：<https://huggingface.co/PaddlePaddle/PaddleOCR-VL-1.5>
- PaddleOCR-VL-1.5 GGUF 模型卡：<https://huggingface.co/PaddlePaddle/PaddleOCR-VL-1.5-GGUF>
- llama.cpp server 文档：<https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md>
- NVIDIA CUDA Legacy GPU 列表：<https://developer.nvidia.com/cuda/gpus/legacy>

## 21. 一句话版本

对这台机器来说，最稳妥的落地路径就是：

1. 装依赖
2. 下载 `GGUF + mmproj`
3. 编译 `llama-server`
4. 建 `PaddleOCR` 虚拟环境
5. 用 `llama.cpp` 本地服务承载 VLM
6. 用 `paddleocr doc_parser` 走 `llama-cpp-server` 后端

这就是当前最适合你的本地部署方案。
