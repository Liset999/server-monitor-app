# Server Monitor (SRE 练手项目)

这是一个基于 **Flutter** (移动端) 和 **Python Flask** (服务端) 开发的局域网服务器监控系统。
它可以实时监控 Windows 服务器的硬件状态，并支持查看详细的硬件配置信息。

## 📸 功能特性 (Features)

* **实时监控**：每秒刷新 CPU、内存、GPU、磁盘的使用率。
* **硬件详情**：自动识别 Windows 11/10 版本，精准获取 CPU 型号 (如 AMD Ryzen 9) 及核心数。
* **智能缓存**：配置信息支持本地缓存，减少网络请求，提升体验。
* **报警机制**：当 CPU 或 GPU 负载超过 80% 时，App 界面自动变红报警。
* **交互优化**：支持下拉刷新配置信息，底部弹窗自适应高度。

## 🛠️ 技术栈 (Tech Stack)

* **Backend**: Python 3, Flask, psutil, GPUtil, py-cpuinfo
* **Frontend**: Flutter, Dart, HTTP, Async/Await
* **Architecture**: RESTful API, C/S 架构

## 🚀 快速开始 (How to Run)

### 1. 启动服务端 (Server)

确保你安装了 Python 3.x。

```bash
# 1. 安装依赖
pip install -r requirements.txt

# 2. 启动探针
python monitor.py

### 2. 启动客户端 (App)
确保你安装了 Flutter SDK。

Bash
cd server_monitor
flutter pub get
flutter run
注意：请在 lib/main.dart 中修改 _baseUrl 为你的电脑局域网 IP。
Made with ❤️ by [Lanbo]