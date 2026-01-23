import psutil
import platform
import socket
import threading
import sys
import random
import subprocess
import time
import json
import os
import customtkinter as ctk
from PIL import Image, ImageDraw
import pystray
import winreg

# 尝试导入高级库
try:
    from flask import Flask, jsonify, request
    import GPUtil
    import cpuinfo
    import wmi
    import pyautogui  # 🌟 补上了鼠标控制库
except ImportError:
    print(
        "❌ 缺少必要库，请执行: pip install flask gputil py-cpuinfo wmi pypiwin32 pyautogui pillow customtkinter pystray -i https://pypi.tuna.tsinghua.edu.cn/simple")
    sys.exit(1)

# --- 配置持久化处理 ---
CONFIG_FILE = "config.json"
pyautogui.FAILSAFE = False  # 🌟 SRE 建议：防止鼠标移到角落报错

#自启动
def manage_autostart(enable=True):
    key_path = r"Software\Microsoft\Windows\CurrentVersion\Run"
    app_name = "ServerMonitorProbe"
    exe_path = os.path.abspath(sys.argv[0])
    try:
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, key_path, 0, winreg.KEY_ALL_ACCESS)
        if enable:
            winreg.SetValueEx(key, app_name, 0, winreg.REG_SZ, exe_path)
        else:
            try:
                winreg.DeleteValue(key, app_name)
            except FileNotFoundError:
                pass
        winreg.CloseKey(key)
        return True
    except:
        return False

#检测当前程序是否已设置为随 Windows 系统启动而自动运行
def check_autostart_status():
    key_path = r"Software\Microsoft\Windows\CurrentVersion\Run"
    try:
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, key_path, 0, winreg.KEY_READ)
        winreg.QueryValueEx(key, "ServerMonitorProbe")
        winreg.CloseKey(key)
        return True
    except:
        return False

#读取配对码，若不存在则生成一个随机的
def load_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                return json.load(f).get("secret_code")
        except:
            pass
    return str(random.randint(100000, 999999))

#自定义配对码
def save_config(code):
    with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
        json.dump({"secret_code": str(code)}, f)


# --- 初始化 ---
SECRET_CODE = load_config()
w_info = wmi.WMI()
app = Flask(__name__)
CURRENT_STATS = {"cpu": 0, "ram": 0, "disk": 0, "gpu": 0, "gpu_temp": 0, "net_up": 0, "net_down": 0}
LAST_NET_IO = psutil.net_io_counters()
LAST_NET_TIME = time.time()
SYSTEM_SPECS = {}

#检测本地（127.0.0.1）的指定 TCP 端口是否正在被占用
def is_port_in_use(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(('127.0.0.1', port)) == 0

#连接开始
@app.before_request
def check_auth():
    if not request.endpoint or request.endpoint == 'static': return
    if request.headers.get('X-Secret-Code') != SECRET_CODE:
        return jsonify({"error": "Auth Failed"}), 401


# --- 🌟 补全：触控板路由 ---
@app.route('/mouse', methods=['POST'])
def mouse_control():
    data = request.json
    action = data.get('action')
    try:
        if action == 'move':
            pyautogui.moveRel(data.get('dx', 0) * 1.5, data.get('dy', 0) * 1.5)
        elif action == 'click':
            pyautogui.click()
        elif action == 'right_click':
            pyautogui.rightClick()
        elif action == 'scroll':
            pyautogui.scroll(int(data.get('dy', 0) * 10))
        return jsonify({"status": "success"})
    except:
        return jsonify({"status": "error"}), 500

#提供接口返回数据
@app.route('/status')
def status(): return jsonify(CURRENT_STATS)

#以JSON 格式返回服务器或主机的系统规格信息（如 CPU、内存、操作系统等）
@app.route('/specs')
def specs(): return jsonify(SYSTEM_SPECS)

#任务管理器
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

#kill进程
@app.route('/kill', methods=['POST'])
def kill_process():
    try:
        psutil.Process(int(request.json.get('pid'))).terminate()
        return jsonify({"status": "success"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

#远程操控（锁屏，重启，关机）
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

# --- 监控逻辑 ---
def get_gpu_load_windows():
    # 1. 尝试 NVIDIA 独显 (GPUtil)
    try:
        gpus = GPUtil.getGPUs()
        if gpus: return gpus[0].load * 100, gpus[0].temperature
    except:
        pass
    try:
        cmd = "typeperf \"\\GPU Engine(*)\\Utilization Percentage\" -sc 1"
        for gpu_ctrl in w_info.Win32_VideoController():
            name = gpu_ctrl.Name.lower()
            if any(x in name for x in ["intel", "amd", "graphics"]):
                gpu_val = 0.5  # 注意：这里是变量赋值，不是 return
                gpu_temp = 0  # 也是变量赋值
                break  # 🌟 关键：用 break 跳出循环，而不是 return 结束函数
    except:
        pass
    return 0, 0

# --- 核心监控线程 ---
def monitor_loop():
    global CURRENT_STATS, LAST_NET_IO, LAST_NET_TIME
    while True:
        try:
            # 💡 改进 1: CPU 平滑处理（取 3 次采样平均值，防止数值虚高跳变）
            cpu_samples = []
            for _ in range(3):
                cpu_samples.append(psutil.cpu_percent(interval=0.2))
            avg_cpu = sum(cpu_samples) / len(cpu_samples)

            ram = psutil.virtual_memory().percent
            disk = psutil.disk_usage('C:' if platform.system() == "Windows" else '/').percent

            # 💡 改进 2: 修复了原代码中的 return Bug，改为变量赋值
            gpu_val, temp_val = get_gpu_load_windows()

            # 3. 计算网速
            curr_net = psutil.net_io_counters()
            curr_time = time.time()
            time_delta = curr_time - LAST_NET_TIME if curr_time - LAST_NET_TIME > 0 else 1

            sent_speed = (curr_net.bytes_sent - LAST_NET_IO.bytes_sent) / time_delta
            recv_speed = (curr_net.bytes_recv - LAST_NET_IO.bytes_recv) / time_delta

            LAST_NET_IO = curr_net
            LAST_NET_TIME = curr_time

            # 更新全局状态
            CURRENT_STATS = {
                "cpu": round(avg_cpu, 1),
                "ram": ram,
                "disk": disk,
                "gpu": round(gpu_val, 1),
                "gpu_temp": temp_val,
                "net_up": round(sent_speed, 1),
                "net_down": round(recv_speed, 1)
            }
            time.sleep(0.1)  # 维持大约 1Hz 的更新频率
        except Exception as e:
            time.sleep(2)

def get_gpu_name_realtime():
    """启动时精准获取显卡名称"""
    # 1. 先试独显
    try:
        import GPUtil
        gpus = GPUtil.getGPUs()
        if gpus: return gpus[0].name
    except:
        pass

    # 2. 再试 WMI (针对集显)
    try:
        for gpu_ctrl in w_info.Win32_VideoController():
            name = gpu_ctrl.Name
            if "Remote" not in name and "Virtual" not in name:
                return name
    except:
        pass
    return "通用显示适配器/集成显卡"

# --- 启动逻辑 ---
def init_specs():
    global SYSTEM_SPECS
    try:
        cpu_name = cpuinfo.get_cpu_info()['brand_raw']
    except:
        cpu_name = platform.processor()
    os_name = platform.platform()
    if platform.system() == "Windows":
        try:
            # 尝试获取更友好的 Windows 名称
            import wmi
            w = wmi.WMI()
            os_name = w.Win32_OperatingSystem()[0].Caption
        except:
            pass
    SYSTEM_SPECS = {
        "os": os_name,
        "cpu": cpu_name,
        "ram": f"{round(psutil.virtual_memory().total / (1024 ** 3), 1)} GB",
        "gpu": get_gpu_name_realtime()
    }




# --- UI 类 ---
class MonitorUI(ctk.CTk):
    def __init__(self):
        super().__init__()
        self.title("Server Monitor 控制中心")
        self.geometry("400x550")
        ctk.set_appearance_mode("dark")
        self.is_hidden = True

        # 1. 🌟 调整顺序：先创建日志框，防止其他函数调用时报错
        self.log_box = ctk.CTkTextbox(self, height=100)

        # 2. UI 组件布局
        ctk.CTkLabel(self, text="🖥️ 监控服务运行中", font=("微软雅黑", 20, "bold")).pack(pady=20)

        self.frame = ctk.CTkFrame(self)
        self.frame.pack(pady=10, padx=30, fill="x")
        ctk.CTkLabel(self.frame, text="手机配对码", font=("微软雅黑", 12)).pack(pady=5)

        self.lbl_code = ctk.CTkLabel(self.frame, text="******", font=("Consolas", 32, "bold"), text_color="#1f93ff")
        self.lbl_code.pack(side="left", padx=20, pady=10, expand=True)

        self.btn_reveal = ctk.CTkButton(self.frame, text="👁️", width=30, fg_color="transparent",
                                        command=self.toggle_code_visibility)
        self.btn_reveal.pack(side="right", padx=10)

        self.info_lbl = ctk.CTkLabel(self, text="正在等待数据...", font=("微软雅黑", 14))
        self.info_lbl.pack(pady=20)

        self.edit_frame = ctk.CTkFrame(self)
        self.edit_frame.pack(pady=10, padx=30, fill="x")
        self.code_entry = ctk.CTkEntry(self.edit_frame, placeholder_text="输入新配对码")
        self.code_entry.pack(side="left", padx=10, pady=10, expand=True, fill="x")
        self.save_btn = ctk.CTkButton(self.edit_frame, text="保存", width=60, command=self.change_code)
        self.save_btn.pack(side="right", padx=10)

        self.sw_frame = ctk.CTkFrame(self)
        self.sw_frame.pack(pady=10, padx=30, fill="x")
        self.auto_switch = ctk.CTkSwitch(self.sw_frame, text="开机自启", command=self.toggle_autostart_logic)
        self.auto_switch.pack(pady=10)
        if check_autostart_status(): self.auto_switch.select()

        # 最后放日志框
        self.log_box.pack(pady=10, padx=30, fill="both")

        # 启动即创建托盘图标，确保位置不动
        threading.Thread(target=self.init_tray_permanently, daemon=True).start()
        self.refresh_ui()
        self.protocol("WM_DELETE_WINDOW", self.withdraw_window)

    def refresh_ui(self):
        self.info_lbl.configure(text=f"CPU: {CURRENT_STATS['cpu']}% | GPU: {CURRENT_STATS['gpu']}%")
        self.after(1000, self.refresh_ui)

    def toggle_code_visibility(self):
        if self.is_hidden:
            self.lbl_code.configure(text=SECRET_CODE)
            self.btn_reveal.configure(text="🔒")
            self.is_hidden = False
        else:
            self.lbl_code.configure(text="******")
            self.btn_reveal.configure(text="👁️")
            self.is_hidden = True

    def change_code(self):
        new_code = self.code_entry.get().strip()
        if len(new_code) >= 4:
            global SECRET_CODE
            SECRET_CODE = new_code
            save_config(SECRET_CODE)
            if not self.is_hidden: self.lbl_code.configure(text=SECRET_CODE)
            self.log_box.insert("end", f"\n[{time.strftime('%H:%M:%S')}] 配对码已更新")
            self.code_entry.delete(0, 'end')

    def toggle_autostart_logic(self):
        is_on = self.auto_switch.get()
        if manage_autostart(enable=(is_on == 1)):
            self.log_box.insert("end", f"\n[OK] 自启状态: {'开' if is_on else '关'}")
        self.log_box.see("end")

    def init_tray_permanently(self):
        """创建一个永远不消失的托盘图标"""
        icon_path = "icon.png"
        img = Image.open(icon_path) if os.path.exists(icon_path) else Image.new('RGB', (64, 64), color=(31, 147, 255))

        # 定义固定菜单
        menu = (
            pystray.MenuItem('显示窗口', self.show_window, default=True),
            pystray.MenuItem('退出服务', self.quit_app)
        )
        self.tray = pystray.Icon("ServerMonitor", img, "Server Monitor", menu)
        self.tray.run()  # 这里的 run 会一直运行，直到程序退出

    def withdraw_window(self):
        """点击 [X] 仅仅隐藏窗口"""
        self.withdraw()


    def show_window(self, icon=None, item=None):
        """仅仅显示窗口，绝对不去动托盘图标"""
        self.deiconify()
        self.state('normal')
        self.focus_force()

    def quit_app(self):
        if self.tray: self.tray.stop()
        os._exit(0)


# --- 启动 ---
def init_specs():
    global SYSTEM_SPECS
    try:
        cpu_name = cpuinfo.get_cpu_info()['brand_raw']
    except:
        cpu_name = platform.processor()
    os_name = platform.platform()
    if platform.system() == "Windows":
        try:
            # 尝试获取更友好的 Windows 名称
            import wmi
            w = wmi.WMI()
            os_name = w.Win32_OperatingSystem()[0].Caption
        except:
            pass
    SYSTEM_SPECS = {
        "os": os_name,
        "cpu": cpu_name,
        "ram": f"{round(psutil.virtual_memory().total / (1024 ** 3), 1)} GB",
        "gpu": get_gpu_name_realtime()
    }



if __name__ == "__main__":
    init_specs()
    threading.Thread(target=monitor_loop, daemon=True).start()
    threading.Thread(target=lambda: app.run(host='0.0.0.0', port=5000, debug=False, use_reloader=False),
                     daemon=True).start()
    MonitorUI().mainloop()