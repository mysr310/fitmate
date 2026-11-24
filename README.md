# 健身管家（fitmate）

手机端 AI 健身管理应用：**AI 生成一周训练计划 · 拍照识别食物卡路里 · 体重管理 · 微信一键备份到电脑**。

📖 完整使用说明见 [docs/使用手册.md](docs/使用手册.md)。

数据全部保存在手机本地（SQLite），不注册、不上传；换手机或手机故障时，通过备份文件即可完整恢复。

## 功能

| 模块 | 说明 |
| --- | --- |
| 今日 | 热量环（摄入/预算）、三大营养素进度、今日训练卡片、体重快捷记录 |
| 饮食 | 拍照 / 相册 / 文字描述 → AI 估算热量与蛋白质/脂肪/碳水 → 确认入账；常吃食物库自动沉淀；按 Mifflin-St Jeor 公式计算每日预算 |
| 训练 | AI 结合身体档案 + 近 7 天摄入热量 + 体重趋势生成周计划；逐组打卡执行；历史记录；多计划保存切换 |
| 体重 | 记录与折线趋势图、目标体重进度 |
| 备份 | 一键备份全部数据为 `.fitbak`（zip 包，**不含 API Key**）；经微信「文件传输助手」发送到电脑；恢复时手机微信里点开文件「用其他应用打开」即可；另有局域网网页直传备用通道 |

## AI 接口

支持任何 **OpenAI 兼容** 的服务，App 内预置快速填充：

- DeepSeek：`https://api.deepseek.com`（Key 在 platform.deepseek.com）
- 智谱 GLM：`https://open.bigmodel.cn/api/paas/v4`（Key 在 bigmodel.cn）
- OpenAI 或任意中转站

两个模型槽位可分别指定（可混搭）：**拍照识别食物**用视觉模型（如 glm-4.6v / DeepSeek 视觉模型），**生成训练计划**用文本模型（如 deepseek-chat / glm-4.6）。API Key 只存在手机 App 内，不进代码仓库。

## 构建 APK

推送代码到 GitHub 后，`Build APK` 工作流自动执行 analyze + test + build，在 Actions 运行页下载 `fitmate-apk`；也可以本地执行：

```bash
flutter build apk --release
```

## 本地开发

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # drift 代码生成
flutter analyze
flutter test
flutter run -d chrome                                      # Web 冒烟测试
```

## 技术栈

Flutter · Riverpod · Drift(SQLite) · dio · fl_chart · image_picker · share_plus · file_picker · shelf（局域网传输） · qr_flutter · archive（备份打包）

## 目录速览

```
lib/
  ai/          AI 客户端、提示词、容错 JSON 解析、服务
  core/        主题与工具（日期/枚举/格式化）
  data/db/     Drift 表与应用数据库
  services/    热量预算、备份恢复、局域网传输、照片存储
  ui/          今日 / 饮食 / 训练 / 体重 / 我的 五个模块页面
test/          解析容错、热量计算、备份恢复往返的单元测试
.github/workflows/build.yml   CI 自动出 APK
```
