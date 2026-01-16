import psutil
from flask import Flask, jsonify

app = Flask(__name__)


@app.route('/status')
def status():
    # 1. 获取 CPU (1秒平均值)
    cpu = psutil.cpu_percent(interval=1)
    # 2. 获取内存百分比
    ram = psutil.virtual_memory().percent

    print(f"当前状态 -> CPU: {cpu}% | 内存: {ram}%")

    return jsonify({
        "cpu": cpu,
        "ram": ram
    })


if __name__ == '__main__':
    print("🚀 监控服务已启动！正在监听 5000 端口...")
    app.run(host='0.0.0.0', port=5000)