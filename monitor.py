import psutil
import platform
import socket
import threading
import sys
import random
import subprocess
import time
import json
import traceback
import multiprocessing

# --- 强力依赖检测 ---
try:
    from flask import Flask, jsonify, request
    import GPUtil
    import cpuinfo
except ImportError as e:
    sys.exit(1)

app = Flask(__name__)

# --- 全局变量 ---
SECRET_CODE = str(random.randint(100000, 999999))
CURRENT_STATS = {"cpu": 0, "ram": 0, "disk": 0, "gpu": 0}
SYSTEM_SPECS = {}


def is_port_in_use(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(('127.0.0.1', port)) == 0


@app.before_request
def check_auth():
    if not request.endpoint: return
    if request.headers.get('X-Secret-Code') != SECRET_CODE:
        return jsonify({"error": "Auth Failed"}), 401


# --- 显卡名称获取 ---
def get_gpu_name_safe():
    try:
        gpus = GPUtil.getGPUs()
        if gpus: return gpus[0].name
    except:
        pass

    if platform.system() == "Windows":
        try:
            cmd = "powershell \"Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name\""
            output = subprocess.check_output(cmd, shell=True).decode('gbk', errors='ignore')
            lines = [line.strip() for line in output.split('\n') if line.strip()]
            for name in lines:
                if "Remote" not in name and "Virtual" not in name:
                    return name
            if lines: return lines[0]
        except:
            pass
    return "集成显卡/未知设备"


# --- 系统版本名称 ---
def get_windows_marketing_name():
    if platform.system() != "Windows":
        return f"{platform.system()} {platform.release()}"
    try:
        cmd = "powershell \"Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption\""
        output = subprocess.check_output(cmd, shell=True).decode('gbk', errors='ignore')
        return output.strip().replace("Microsoft ", "")
    except:
        return "Windows Unknown"


# --- 🔥 新增：强行读取核显占用率 (WMI) ---
def get_integrated_gpu_load():
    try:
        # 使用 PowerShell 查询 WMI 性能数据 (语言无关，中英文通吃)
        # 获取所有 GPU 引擎的利用率，然后取最大值 (Measure-Object -Maximum)
        cmd = "powershell \"Get-CimInstance Win32_PerfFormattedData_GPUPerformance_GPUEngine | Measure-Object -Property UtilizationPercentage -Maximum | Select-Object -ExpandProperty Maximum\""

        # 隐藏窗口执行，防止闪黑框
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW

        output = subprocess.check_output(cmd, startupinfo=startupinfo, shell=True).decode().strip()
        if output:
            return float(output)
    except:
        pass
    return 0


# --- 监控线程 (修改版) ---
def monitor_loop():
    global CURRENT_STATS
    while True:
        try:
            # 1. CPU & 内存
            cpu = psutil.cpu_percent(interval=1)
            ram = psutil.virtual_memory().percent
            disk = psutil.disk_usage('/').percent

            # 2. GPU 获取策略
            gpu = 0
            # 策略A: 先试 GPUtil (NVIDIA 独显)
            try:
                gpus = GPUtil.getGPUs()
                if gpus:
                    gpu = gpus[0].load * 100
            except:
                pass

            # 策略B: 如果没读到 (是0)，说明可能是核显，启动 WMI 暴力读取
            if gpu == 0 and platform.system() == "Windows":
                gpu = get_integrated_gpu_load()

            CURRENT_STATS = {"cpu": cpu, "ram": ram, "disk": disk, "gpu": gpu}
        except:
            time.sleep(1)


def init_specs():
    global SYSTEM_SPECS
    print("⏳ 正在读取硬件配置...")

    os_name = get_windows_marketing_name()
    try:
        try:
            cpu_name = cpuinfo.get_cpu_info()['brand_raw']
        except:
            cpu_name = platform.processor()
    except:
        cpu_name = "Unknown CPU"

    SYSTEM_SPECS = {
        "os": os_name,
        "cpu": cpu_name,
        "cores": f"{psutil.cpu_count(logical=False)}核",
        "ram": f"{round(psutil.virtual_memory().total / (1024 ** 3), 1)} GB",
        "gpu": get_gpu_name_safe()
    }
    print(f"✅ 硬件配置读取完毕: {os_name}")


def udp_listener():
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(('0.0.0.0', 50001))
        while True:
            data, addr = sock.recvfrom(1024)
            if data.decode('utf-8', errors='ignore').startswith(f"FIND_SERVER:{SECRET_CODE}"):
                sock.sendto("HERE_I_AM".encode('utf-8'), addr)
    except:
        pass


@app.route('/status')
def status(): return jsonify(CURRENT_STATS)


@app.route('/specs')
def specs(): return jsonify(SYSTEM_SPECS)


# --- 主程序 ---
if __name__ == '__main__':
    multiprocessing.freeze_support()  # 防死循环

    try:
        if is_port_in_use(5000):
            print("\n❌ 启动失败！端口 5000 被占用")
            print("请用 taskkill /F /IM monitor.exe /T 杀掉旧进程")
            input("🔴 按回车键退出...")
            sys.exit(1)

        t1 = threading.Thread(target=udp_listener, daemon=True)
        t1.start()
        t2 = threading.Thread(target=monitor_loop, daemon=True)
        t2.start()

        init_specs()

        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
            s.close()
        except:
            local_ip = "127.0.0.1"

        print("\n" + "=" * 50)
        print(f"   🚀 服务已启动 | IP: {local_ip}")
        print(f"   🔑 配对码: 【 {SECRET_CODE} 】")
        print("=" * 50 + "\n")

        app.run(host='0.0.0.0', port=5000, debug=False, use_reloader=False)

    except Exception as e:
        print("💥 错误:", e)
        input("🔴 按回车键退出...")