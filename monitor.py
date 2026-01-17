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
import os


try:
    from flask import Flask, jsonify, request
    import GPUtil
    import cpuinfo
except ImportError as e:
    sys.exit(1)

app = Flask(__name__)

# --- 全局变量 ---
SECRET_CODE = str(random.randint(100000, 999999))
# 🔥 新增 gpu_temp 字段
CURRENT_STATS = {"cpu": 0, "ram": 0, "disk": 0, "gpu": 0, "gpu_temp": 0,"net_up": 0, "net_down": 0}
LAST_NET_IO = psutil.net_io_counters()
LAST_NET_TIME = time.time()
SYSTEM_SPECS = {}


def is_port_in_use(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(('127.0.0.1', port)) == 0


@app.before_request
def check_auth():
    if not request.endpoint: return
    if request.headers.get('X-Secret-Code') != SECRET_CODE:
        return jsonify({"error": "Auth Failed"}), 401


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
                if "Remote" not in name and "Virtual" not in name: return name
            if lines: return lines[0]
        except:
            pass
    return "集成显卡/未知设备"


def get_windows_marketing_name():
    if platform.system() != "Windows": return f"{platform.system()} {platform.release()}"
    try:
        cmd = "powershell \"Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption\""
        output = subprocess.check_output(cmd, shell=True).decode('gbk', errors='ignore')
        return output.strip().replace("Microsoft ", "")
    except:
        return "Windows Unknown"


def get_gpu_load_wmic():
    try:
        cmd = "wmic path Win32_PerfFormattedData_GPUPerformance_GPUEngine get UtilizationPercentage"
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True,
                                   startupinfo=startupinfo)
        output, error = process.communicate(timeout=2)
        if output:
            decoded_output = output.decode('utf-8', errors='ignore')
            values = [int(line) for line in decoded_output.split() if line.isdigit()]
            if values: return max(values)
    except:
        pass
    return 0


# --- 监控线程 ---
def monitor_loop():
    global CURRENT_STATS, LAST_NET_IO, LAST_NET_TIME  # 🔥 记得引用全局变量
    while True:
        try:
            # 1. 获取基础硬件信息
            cpu = psutil.cpu_percent(interval=1)  # 这里会阻塞1秒，刚好作为时间间隔
            ram = psutil.virtual_memory().percent
            disk = psutil.disk_usage('/').percent

            # 2. 获取显卡信息
            gpu = 0
            gpu_temp = 0
            try:
                gpus = GPUtil.getGPUs()
                if gpus:
                    gpu = gpus[0].load * 100
                    gpu_temp = gpus[0].temperature
            except:
                pass

            # 🔥🔥🔥 3. 核心新增：计算网速 🔥🔥🔥
            curr_net = psutil.net_io_counters()
            curr_time = time.time()

            # 计算时间差 (防止除以0)
            time_delta = curr_time - LAST_NET_TIME
            if time_delta == 0: time_delta = 1

            # 计算字节差 (现在 - 刚才 = 这一秒跑的流量)
            sent_bytes = curr_net.bytes_sent - LAST_NET_IO.bytes_sent
            recv_bytes = curr_net.bytes_recv - LAST_NET_IO.bytes_recv

            # 算出每秒字节数 (B/s)
            sent_speed = sent_bytes / time_delta
            recv_speed = recv_bytes / time_delta

            # 更新“刚才”的状态，为下一轮做准备
            LAST_NET_IO = curr_net
            LAST_NET_TIME = curr_time

            # 打印调试信息 (可选)
            # sys.stdout.write(f"\r🚀 Up: {sent_speed/1024:.1f} KB/s | Down: {recv_speed/1024:.1f} KB/s   ")
            # sys.stdout.flush()

            # 存入字典，发给手机
            CURRENT_STATS = {
                "cpu": cpu,
                "ram": ram,
                "disk": disk,
                "gpu": gpu,
                "gpu_temp": gpu_temp,
                "net_up": sent_speed,  # 上传速度 (B/s)
                "net_down": recv_speed  # 下载速度 (B/s)
            }
        except Exception as e:
            print(e)
            time.sleep(1)


# ... (init_specs, udp_listener, status路由保持不变) ...
# 为了节省篇幅，省略部分未修改代码，请保留你原有的 init_specs, udp_listener 和 路由部分
# 确保 CURRENT_STATS 包含了 gpu_temp 即可

def init_specs():
    global SYSTEM_SPECS
    print("\n⏳ 正在读取硬件配置...")
    try:
        try:
            cpu_name = cpuinfo.get_cpu_info()['brand_raw']
        except:
            cpu_name = platform.processor()
    except:
        cpu_name = "Unknown CPU"
    SYSTEM_SPECS = {
        "os": get_windows_marketing_name(),
        "cpu": cpu_name,
        "cores": f"{psutil.cpu_count(logical=False)}核",
        "ram": f"{round(psutil.virtual_memory().total / (1024 ** 3), 1)} GB",
        "gpu": get_gpu_name_safe()
    }
    print(f"✅ 硬件配置读取完毕: {SYSTEM_SPECS['os']}")


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


@app.route('/processes')
def processes():
    procs = []
    for p in psutil.process_iter(['pid', 'name', 'memory_percent']):
        try:
            if p.info['memory_percent'] > 0.1: procs.append(p.info)
        except:
            pass
    procs.sort(key=lambda x: x['memory_percent'], reverse=True)
    return jsonify(procs[:20])


@app.route('/kill', methods=['POST'])
def kill_process():
    try:
        psutil.Process(int(request.json.get('pid'))).terminate()
        return jsonify({"status": "success"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


# 🔥🔥🔥 新增：电源管理接口 🔥🔥🔥
@app.route('/power', methods=['POST'])
def power_action():
    try:
        action = request.json.get('action')
        print(f"\n⚠️ 收到电源指令: {action}")

        # 针对 Windows 系统的命令
        if platform.system() == "Windows":
            if action == 'shutdown':
                # /s=关机, /t 10=延迟10秒 (给你反悔机会)
                os.system("shutdown /s /t 10")
            elif action == 'restart':
                # /r=重启
                os.system("shutdown /r /t 5")
            elif action == 'lock':
                # 锁定屏幕
                os.system("rundll32.exe user32.dll,LockWorkStation")

        return jsonify({"status": "success", "message": f"执行 {action} 成功"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


if __name__ == '__main__':
    multiprocessing.freeze_support()
    try:
        if is_port_in_use(5000):
            print("\n❌ 端口 5000 被占用，请先杀掉旧进程")
            input("🔴 按回车键退出...")
            sys.exit(1)
        threading.Thread(target=udp_listener, daemon=True).start()
        threading.Thread(target=monitor_loop, daemon=True).start()
        init_specs()

        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
            s.close()
        except:
            local_ip = "127.0.0.1"

        print(f"\n🚀 服务启动 | IP: {local_ip} | 配对码: {SECRET_CODE}\n")
        app.run(host='0.0.0.0', port=5000, debug=False, use_reloader=False)
    except Exception as e:
        print("💥 错误:", e)
        input("🔴 按回车键退出...")