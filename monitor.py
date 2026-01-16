import psutil
import platform
import sys
import cpuinfo  # <--- 新增：专门读 CPU 型号的库
from flask import Flask, jsonify
import GPUtil

app = Flask(__name__)


# --- 获取精准的 Windows 版本 ---
def get_os_info():
    try:
        ver_str = platform.version()
        parts = ver_str.split('.')
        build_number = int(parts[-1])

        system_name = "Windows 10"
        if build_number >= 22000:
            system_name = "Windows 11"

        edition = platform.win32_edition()
        if edition == 'Core':
            edition = 'Home'
        elif edition == 'Professional':
            edition = 'Pro'

        return f"{system_name} {edition}"
    except:
        return f"{platform.system()} {platform.release()}"


# --- 1. 动态接口 ---
@app.route('/status')
def status():
    cpu = psutil.cpu_percent(interval=1)
    ram = psutil.virtual_memory().percent
    disk = psutil.disk_usage('/').percent
    gpus = GPUtil.getGPUs()
    gpu = gpus[0].load * 100 if gpus else 0
    return jsonify({"cpu": cpu, "ram": ram, "disk": disk, "gpu": gpu})


# --- 2. 静态接口 (配置信息) ---
@app.route('/specs')
def specs():
    os_name = get_os_info()

    # --- 修改重点：获取真实的 CPU 名字 ---
    try:
        info = cpuinfo.get_cpu_info()
        # brand_raw 就是你要的 "AMD Ryzen 9 7945HX"
        cpu_name = info['brand_raw']
    except:
        cpu_name = platform.processor()  # 如果获取失败，才用老的

    cpu_cores = psutil.cpu_count(logical=False)
    cpu_threads = psutil.cpu_count(logical=True)
    ram_total = round(psutil.virtual_memory().total / (1024 ** 3), 1)

    gpus = GPUtil.getGPUs()
    gpu_name = gpus[0].name if gpus else "无独立显卡"

    return jsonify({
        "os": os_name,
        "cpu": cpu_name,  # 现在这里是真名了
        "cores": f"{cpu_cores}核 {cpu_threads}线程",
        "ram": f"{ram_total} GB",
        "gpu": gpu_name
    })


if __name__ == '__main__':
    print("🚀 监控探针已启动 (显示真实CPU名称)...")
    app.run(host='0.0.0.0', port=5000)