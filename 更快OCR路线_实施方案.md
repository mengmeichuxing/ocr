# 更快 OCR 路线实施方案

适用日期：2026-04-22

适用机器：

- 系统：Ubuntu 24.04 x86_64
- CPU：Intel Core i5-8300H，4 核 8 线程
- 内存：16 GiB
- GPU：NVIDIA GeForce GTX 1050 Mobile，2 GiB 显存

## 1. 背景

上一条路线是：

- `PaddleOCR-VL-1.5 + llama.cpp + GGUF`

这条路线已经在当前机器上跑通，但核心问题也已经很明确：

- 端到端太慢
- GPU 只能部分参与
- 实测从大约 `206.7` 秒降到大约 `199.2 ~ 201.0` 秒，提升只有 `3% ~ 4%`

所以这次换路线的目标不是继续榨 `VL`，而是改成更轻、更快、更贴近“OCR 本身”的方案。

## 2. 目标

这次新路线的目标是：

- 优先解决“文字提取速度”问题
- 尽量沿用现有 `PaddleOCR 3.5.0` 环境
- 优先使用当前机器最稳的 `CPU` 推理链路
- 保留结构化文档能力，但不再默认走大模型文档理解
- 每一步都要能测试、能回归、能写回文档

## 3. 非目标

这次不追求下面这些能力：

- 不追求 `PaddleOCR-VL-1.5` 那种大模型级文档理解
- 不追求复杂图文跨区域语义推理
- 不优先追求本机 GPU 深度加速
- 不把当前机器当成高吞吐生产机来设计

## 4. 新路线决策

这次采用两级路线：

### 4.1 主路线：`PP-OCRv5` 快速 OCR

适用场景：

- 图片文字提取
- PDF 转图片后的逐页 OCR
- 对速度敏感
- 不强依赖复杂版面理解

主路线命令入口：

- `paddleocr ocr`

这条路线的优先级最高，因为它最轻、最直接，也最符合“先把文字快点拿出来”的目标。

### 4.2 次路线：`PP-StructureV3` 轻量结构化解析

适用场景：

- 需要版面块信息
- 需要比纯 OCR 更好的文档结构输出
- 仍然希望比 `VL` 路线快很多

次路线命令入口：

- `paddleocr pp_structurev3`

这条路线不是默认首选，但会保留为“需要结构化时的升级档”。

### 4.3 保底路线：继续保留 `PaddleOCR-VL-1.5`

只有在下面情况才回退到 `VL`：

- 确实需要大模型级文档理解
- 普通 OCR / 结构化路线无法满足需求
- 速度不是第一优先级

## 5. 为什么这次不再把 GPU 当主线

当前机器上已经验证过：

- `GTX 1050 2GB` 可以让 `llama.cpp` 的文本层部分上 GPU
- 但视觉侧 `mmproj` 不能稳定上 GPU
- 真正拖慢总体耗时的阶段仍然大量在 CPU

所以这次的新路线不再围绕“如何让 GPU 多干一点”设计，而是围绕“如何减少根本不该跑的大模型链路”设计。

## 6. 验收标准

### 6.1 `PP-OCRv5` 主路线验收

至少要满足：

- 能对 `samples/paddleocr_vl_demo.png` 成功跑通
- 能生成稳定输出
- 要记录真实耗时
- 要形成一键可复现命令或脚本

### 6.2 `PP-StructureV3` 次路线验收

至少要满足：

- 能对同一张 demo 图成功跑通
- 能生成结构化输出
- 要记录真实耗时
- 要形成一键可复现命令或脚本

### 6.3 文档验收

至少要满足：

- 需求、边界、步骤、命令、测试、回归结果都要写清楚
- 文档能让后续操作不依赖临场记忆

## 7. 分步实施计划

### 第一步：建立 `PP-OCRv5` 基线

要做的事：

- 跑通 `paddleocr ocr`
- 找到当前机器最稳的参数组合
- 记录输出目录与耗时

测试要求：

- 单张 demo 图成功
- 输出可复查
- 失败原因要写入文档

### 第二步：尝试当前机器可用的 CPU 加速项

要做的事：

- 测试 `cpu_threads`
- 测试是否能安全使用 `MKLDNN`
- 评估是否值得尝试 `enable_hpi`

测试要求：

- 任何加速选项都必须先通过正确性回归
- 如果出现运行时错误，不能硬上，必须回退并记文档

### 第三步：补 `PP-StructureV3` 轻量结构化路线

要做的事：

- 跑通 `paddleocr pp_structurev3`
- 默认关闭不必要模块，优先速度
- 记录输出类型、耗时和适用边界

测试要求：

- 同一张 demo 图成功
- 输出目录可复查
- 与主路线的差异要写清楚

### 第四步：脚本化与回归

要做的事：

- 把主路线和次路线都固化成脚本
- 做最终回归
- 回写最终版部署文档

## 8. 当前已确认的已知风险

截至 2026-04-22，本机已经确认这些风险需要重点关注：

- `Python 3.12 + paddlepaddle 3.3.1 + 某些 CPU 加速组合` 可能存在兼容性问题
- 首次运行新模型时会触发模型下载，不能把“下载时间”误当成纯推理时间
- 某些 CLI 参数组合虽然理论上更快，但一旦影响稳定性就不能作为默认值

## 9. 当前阶段记录

### 9.1 已确认的方向

- 主路线定为 `PP-OCRv5`
- 次路线定为 `PP-StructureV3`
- `VL` 保留为兜底，不再作为默认日常路线

### 9.1.1 当前已经实测出的主路线默认配置

当前机器上，已经通过实际回归验证、可以作为默认主路线的配置是：

- 命令：`paddleocr ocr`
- 检测模型：`PP-OCRv5_mobile_det`
- 识别模型：`PP-OCRv5_mobile_rec`
- 引擎：`paddle_dynamic`
- 设备：`cpu`
- 线程：`8`
- 关闭项目：
  - `use_doc_orientation_classify=False`
  - `use_doc_unwarping=False`
  - `use_textline_orientation=False`

已经固化好的脚本：

- `scripts/run_ppocrv5_mobile_fast.sh`

### 9.2 本轮先关注的问题

先回答 3 个最关键的问题：

1. `PP-OCRv5` 在当前机器上到底能不能稳跑
2. 它相比 `VL` 实际能快多少
3. `PP-StructureV3` 是否能在“结构化能力”和“速度”之间取得更合理平衡

### 9.3 已踩到的第一个坑

在本轮首次尝试 `PP-OCRv5 + enable_mkldnn=True` 时，当前环境已经触发运行时错误：

- `NotImplementedError: ConvertPirAttribute2RuntimeAttribute not support [pir::ArrayAttribute<pir::DoubleAttribute>]`

这说明：

- `MKLDNN` 不能直接作为当前机器默认配置
- 后续需要先验证“稳态配置”再谈加速配置

### 9.4 2026-04-22 本机实测结论

#### 9.4.1 `PP-OCRv5_server + paddle_static`

结果：

- 不可用

现象：

- 直接触发运行时错误

错误关键词：

- `NotImplementedError`
- `ConvertPirAttribute2RuntimeAttribute`

结论：

- 当前环境下不作为默认路线

#### 9.4.2 `PP-OCRv5_server + paddle_dynamic`

结果：

- 理论上可跑
- 但不适合当前机器

现象：

- 检测阶段能过
- 识别阶段耗时过长
- 实测运行数分钟后仍未完成，最终中断

结论：

- 对这台机器来说太重
- 不符合“快路线”目标

#### 9.4.3 `PP-OCRv5_mobile + paddle_dynamic`

结果：

- 已成功跑通

首次完整跑通：

- 约 `479.59` 秒

说明：

- 这个数字包含首次下载：
  - `PP-OCRv5_mobile_det_safetensors`
  - `PP-OCRv5_mobile_rec_safetensors`
  - `simfang.ttf`

缓存后二跑：

- 约 `158.55` 秒
- 脚本化回归约 `168.90` 秒

当前机器上的稳态体验可以理解为：

- 大约 `158 ~ 169` 秒

相对 `VL` 路线的对比：

- `PaddleOCR-VL-1.5` CPU 稳态回归约 `206.7` 秒
- `PP-OCRv5_mobile + paddle_dynamic` 稳态回归约 `158.55` 秒
- 当前机器上约快 `48.15` 秒
- 提升大约 `23%`

输出类型：

- `paddleocr_vl_demo_res.json`
- `paddleocr_vl_demo_ocr_res_img.png`

与 `VL` 路线的能力差异：

- 更快
- 更轻
- 更适合拿纯文本
- 但不会直接给你 `md / docx / layout markdown` 这种文档理解结果

当前结论：

- 这条路线已经足够作为新的日常默认路线
- 当你只是想“快点把字拿出来”时，优先走这一条

#### 9.4.4 `PP-StructureV3 lite + paddle_dynamic`

测试配置：

- `use_seal_recognition=False`
- `use_table_recognition=False`
- `use_formula_recognition=False`
- `use_chart_recognition=False`
- `use_region_detection=False`
- `format_block_content=False`
- `text_detection_model_name=PP-OCRv5_mobile_det`
- `text_recognition_model_name=PP-OCRv5_mobile_rec`

结果：

- 已成功跑通

首次完整跑通：

- 端到端约 `181.45` 秒

说明：

- 这个数字包含首次下载 `PP-DocLayout_plus-L_safetensors`

纯处理阶段日志：

- `Processed item 0 in 157763.866 ms`

缓存脚本回归：

- 端到端约 `159.47` 秒
- 纯处理阶段约 `150970.691 ms`

输出能力：

- 能返回版面块信息
- 能区分 `doc_title / paragraph_title / text / image / figure_title` 等块
- 比纯 `ocr` 更接近文档结构化
- 已成功生成：
  - `.json`
  - `.md`
  - `.docx`
  - `.tex`
  - 版面检测图
  - 阅读顺序图
  - 总体 OCR 可视化图
  - 预处理图
  - 裁切图片

与纯 `PP-OCRv5` 主路线的关系：

- 比纯 OCR 稍慢
- 但比 `VL` 路线轻
- 当你想保留一定文档结构，又不想上大模型时，这条线更合适

和当前 demo 的实测对比：

- `PP-OCRv5_mobile + paddle_dynamic` 脚本回归约 `168.90` 秒
- `PP-StructureV3 lite + paddle_dynamic` 脚本回归约 `159.47` 秒
- 在这张 demo 图上，两者几乎处于同一量级
- `PP-StructureV3 lite` 反而在输出丰富度上明显更强

已固化好的脚本：

- `scripts/run_ppstructurev3_lite_fast.sh`

### 9.4.5 当前综合判断

如果你只想快速拿纯文本：

- 优先用 `scripts/run_ppocrv5_mobile_fast.sh`

如果你希望保留文档结构输出，而且不想回到 `VL` 大模型：

- 更推荐直接用 `scripts/run_ppstructurev3_lite_fast.sh`

在当前这台机器和当前 demo 上，`PP-StructureV3 lite` 的速度并没有比纯 `PP-OCRv5` 明显更差，但输出更完整，所以它很可能会成为新的日常默认路线。

## 10. 参考来源

- PaddleOCR OCR pipeline：<https://www.paddleocr.ai/main/en/version3.x/pipeline_usage/OCR.html>
- PaddleOCR PP-StructureV3 pipeline：<https://www.paddleocr.ai/main/en/version3.x/pipeline_usage/PP-StructureV3.html>
- PaddleOCR high performance inference：<https://www.paddleocr.ai/main/en/version3.x/deployment/high_performance_inference.html>
