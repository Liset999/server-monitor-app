# 🖥️ Server Monitor (Cross-Platform)

一个现代化的、跨平台的服务器性能监控应用。服务端使用 **Python (Flask + Psutil)** 采集数据，客户端使用 **Flutter** 构建，支持实时波形图、进程管理及远程电源控制。
实现手机控制电脑进程

------

## 📖 使用方法 (Usage)

1. **PC 端**：在 [Releases](https://www.google.com/search?q=https://github.com/你的用户名/你的仓库名/releases) 下载并运行 `monitor.exe`。
2. **手机端**：下载并安装 `ServerMonitor.apk`。
3. **连接**：电脑端打开后会显示 **配对码**，在手机端输入配对码即可连接。
4. **注意**：电脑端打开后可以最小化，但**不可以关闭**，否则连接会断开。请勿同时打开两个及以上的 EXE。

------

## ✨ 核心功能 (Features)

- 📊 **实时仪表盘**：毫秒级监控 CPU、内存、磁盘使用率。
- 📈 **动态波形图**：支持查看 CPU、内存、网络流量的 60 秒实时波动趋势。
- ⚡ **网速监控**：双通道显示上传/下载速率，支持 KB/s 和 MB/s 智能单位切换。
- 🎮 **进程管理**：实时查看服务器进程，支持远程**强制结束 (Kill)** 异常进程。
- 🔌 **远程控制**：支持一键远程 🔒锁定、🔄重启、🛑关机 (带确认弹窗)。
- 🎨 **多主题切换**：内置深海蓝、赛博紫、黑客绿、梦幻极光等 5 款。

------

## ⚠️ 重要说明 (Important Notes)

- **网络环境**：手机与电脑**必须连接同一个 WiFi**，或由手机开启热点供电脑连接。若连接失败，请尝试手动输入电脑 IP 地址。
- **防火墙**：若在公网环境下使用，请确保防火墙已放行相关端口（默认 5000）。
- **GPU 监测**：温度及负载监测主要通过 **NVIDIA** 接口获取。集成显卡或 AMD 显卡用户可能会出现度数为 0 的情况。
- **安全性**：设置配对码是为了防止在公网环境下他人未经授权连接并控制你的进程。

------

## 🛠️ 技术栈 (Tech Stack)

### Client (Flutter)

- `fl_chart`: 复杂数据可视化（动态折线图）。
- `shared_preferences`: 本地连接配置存储。
- `http`: 异步网络请求处理。
- `flutter_launcher_icons`: 自动化图标配置。

### Server (Python)

- `Flask`: 提供轻量级 API 接口。
- `psutil`: 跨平台系统硬件信息采集。
- `GPUtil`: 专门用于 NVIDIA GPU 状态读取。

------

## 🚀 开发者快速开始 (For Developers)

### 1. 服务端部署

Bash

```
# 进入服务端目录
cd server
# 安装依赖
pip install -r requirements.txt
# 启动监控探针
python monitor.py
```

### 2. 客户端开发

Bash

```
# 进入 App 目录
cd server_monitor
# 获取 Flutter 依赖
flutter pub get
# 运行调试
flutter run
```

------

## 👨‍💻 作者 (Author)

**Lanbo**

- 🎓 专注于系统监控与自动化运维工具开发
