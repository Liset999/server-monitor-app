import sys
import os
import subprocess
import platform

# ================= 🔴 核心修改：在导入任何第三方库之前，先劫持 Popen =================
# 必须放在 import GPUtil 或 import wmi 之前，否则这些库会使用原版 Popen 导致闪烁

if platform.system() == "Windows":
    # 保存原版 Popen
    _original_popen = subprocess.Popen


    class SilentPopen(_original_popen):
        def __init__(self, *args, **kwargs):
            # 1. 强制添加“不创建窗口”标志位
            if 'creationflags' not in kwargs:
                kwargs['creationflags'] = 0x08000000 | subprocess.CREATE_NEW_PROCESS_GROUP

            # 2. 强制设置 STARTUPINFO (这是彻底解决闪烁的关键)
            if 'startupinfo' not in kwargs:
                si = subprocess.STARTUPINFO()
                si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
                si.wShowWindow = subprocess.SW_HIDE  # SW_HIDE = 0
                kwargs['startupinfo'] = si

            # 3. 强制重定向输入输出 (防止因找不到控制台而报错弹窗)
            if 'stdin' not in kwargs: kwargs['stdin'] = subprocess.DEVNULL
            if 'stdout' not in kwargs: kwargs['stdout'] = subprocess.PIPE
            if 'stderr' not in kwargs: kwargs['stderr'] = subprocess.PIPE

            super().__init__(*args, **kwargs)


    # ⛔ 覆盖系统 Popen，从此之后所有库（GPUtil, os.popen 等）都会被迫静默
    subprocess.Popen = SilentPopen
# =================================================================================

# 🔴 只有在劫持完成后，才开始导入其他库
import psutil
import socket
import threading
import random
import time
import json
import customtkinter as ctk
from PIL import Image, ImageDraw
import pystray
import winreg
import multiprocessing

# 尝试导入高级库
try:
    from flask import Flask, jsonify, request
    import GPUtil  # 👈 现在 GPUtil 导入时，会获取到我们需要静默的 Popen
    import wmi
    import pyautogui
except ImportError:
    print("❌ 缺少必要库...")
    sys.exit(1)

# --- 配置持久化处理 ---
CONFIG_FILE = "config.json"
pyautogui.FAILSAFE = False  # 🌟 SRE 建议：防止鼠标移到角落报错

# --- 📍 在 import 之后，MonitorUI 类之前，加入这个函数 ---
def resource_path(relative_path):
    """获取资源绝对路径（兼容 PyInstaller 打包后的临时路径）"""
    if hasattr(sys, '_MEIPASS'):
        return os.path.join(sys._MEIPASS, relative_path)
    return os.path.join(os.path.abspath("."), relative_path)


def get_local_ip():
    """获取本机在局域网中的真实 IP 地址"""
    try:
        # 利用 UDP 尝试连接公共 DNS（不实际发送数据），获取系统分配给对应网卡的 IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def udp_discovery_listener(ui_log_box):
    """还原原版的 UDP 自动发现协议"""
    UDP_PORT = 50001  # 🌟 严格还原原版的端口
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            # 允许端口复用
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(('0.0.0.0', UDP_PORT))
            ui_log_box.insert("end", f"\n[✔️] 局域网自动发现已启动 (UDP:{UDP_PORT})")

            while True:
                data, addr = sock.recvfrom(1024)
                msg = data.decode('utf-8', errors='ignore')

                # 🌟 严格还原原版的“接头暗号”
                # 注意：这里的 SECRET_CODE 是你代码里的全局变量
                if msg.startswith(f"FIND_SERVER:{SECRET_CODE}"):
                    ui_log_box.insert("end", f"\n[🔍] 匹配到设备 {addr[0]}，配对码正确，已响应！")
                    ui_log_box.see("end")
                    # 🌟 严格还原原版的响应内容
                    sock.sendto("HERE_I_AM".encode('utf-8'), addr)
    except Exception as e:
        ui_log_box.insert("end", f"\n[❌] 自动发现服务启动失败: {e}")



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
# 替换原代码中 106 行左右的 is_port_in_use 函数
def is_port_in_use(port):
    """检测本地指定 TCP 端口是否正在被占用"""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.5) # 防止网络层卡死
        return s.connect_ex(('127.0.0.1', port)) == 0

#连接开始
@app.before_request
def check_auth():
    # ✅ 关键修改：把 'show_ui_remote' 加入白名单
    # 这样新程序去唤醒旧程序时，才不会被 401 拦截
    if not request.endpoint or request.endpoint in ['static', 'show_ui_remote']:
        return

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
        # 🌟 针对 Windows，用 Popen 代替 os.system，配合顶部的“消音器”绝不弹窗
        if platform.system() == "Windows":
            if action == 'shutdown':
                subprocess.Popen(["shutdown", "/s", "/t", "10"])
            elif action == 'restart':
                subprocess.Popen(["shutdown", "/r", "/t", "5"])
            elif action == 'lock':
                subprocess.Popen(["rundll32.exe", "user32.dll,LockWorkStation"])
        return jsonify({"status": "success"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/show_ui')
def show_ui_remote():
    # 利用 tkinter 的 after 方法在主线程执行，防止线程冲突导致崩溃
    if 'ui' in globals() and ui:
        ui.after(0, ui.show_window)
    return "OK"

# --- 监控逻辑 ---
def get_gpu_load_windows():
    """获取 GPU 占用率（抗闪烁增强版）"""
    # 1. 尝试 GPUtil (NVIDIA)
    try:
        # 由于我们在头部已经劫持了 subprocess，GPUtil 这里应该已经静默了
        gpus = GPUtil.getGPUs()
        if gpus:
            return gpus[0].load * 100, gpus[0].temperature
    except:
        pass

    # 2. 尝试 typeperf (集成显卡/AMD)
    # 即使全局劫持了，我们这里也手动再加一层保险，因为这是循环调用的重灾区
    try:
        cmd = ['typeperf', r'\GPU Engine(*)\Utilization Percentage', '-sc', '1']

        # 手动构建 STARTUPINFO，确保万无一失
        si = subprocess.STARTUPINFO()
        si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        si.wShowWindow = subprocess.SW_HIDE

        # 注意：这里调用的是 _original_popen，避开递归，但手动传入了所有静默参数
        proc = _original_popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            stdin=subprocess.DEVNULL,  # 👈 关键：切断输入流
            text=True,
            creationflags=0x08000000,
            startupinfo=si
        )
        stdout, _ = proc.communicate(timeout=2)  # 设置超时防止卡死

        lines = stdout.strip().split('\n')
        if len(lines) > 1:
            data_row = lines[-1].split(',')
            loads = [float(val.replace('"', '')) for val in data_row[1:] if val.strip().replace('"', '')]
            return min(round(sum(loads), 1), 100.0), 0
    except Exception:
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



# --- UI 类 ---
class MonitorUI(ctk.CTk):
    # 🌟 修改 __init__，接收 ip 和 port
    def __init__(self, local_ip, current_port):
        super().__init__()
        self.title("Server Monitor 控制中心")
        self.geometry("400x580")  # 稍微拉长一点点窗口
        ctk.set_appearance_mode("dark")
        self.is_hidden = True

        # 1. 顶部标题
        ctk.CTkLabel(self, text="🖥️ 监控服务运行中", font=("微软雅黑", 20, "bold")).pack(pady=10)

        # 🌟 2. 颜值升级版：IP 与端口显示区
        # 使用深灰底色 + 圆角设计，字体改用更现代的系统默认无衬线字体
        self.ip_frame = ctk.CTkFrame(self, fg_color="#1e1e1e", corner_radius=10)
        self.ip_frame.pack(pady=10, padx=30, fill="x")

        # 增加一点留白和排版
        ctk.CTkLabel(self.ip_frame, text="SERVER ADDRESS", font=("Arial", 10, "bold"), text_color="#555555").pack(
            pady=(10, 0))

        # 使用科技感天蓝色 (#3498db) 代替刺眼的亮绿色
        ip_display = f"{local_ip}"
        ctk.CTkLabel(self.ip_frame, text=ip_display,
                     font=("Helvetica", 18, "bold"), text_color="#3498db").pack(pady=(2, 10))

        # 3. 日志框 (必须先创建，方便后续插入日志)
        self.log_box = ctk.CTkTextbox(self, height=100)

        # 下面的代码保持原样...
        self.frame = ctk.CTkFrame(self)
        self.frame.pack(pady=10, padx=30, fill="x")
        ctk.CTkLabel(self.frame, text="手机配对码", font=("微软雅黑", 12)).pack(pady=5)

        self.lbl_code = ctk.CTkLabel(self.frame, text="******", font=("Consolas", 32, "bold"), text_color="#1f93ff")
        self.lbl_code.pack(side="left", padx=20, pady=10, expand=True)

        self.btn_reveal = ctk.CTkButton(self.frame, text="👁️", width=30, fg_color="transparent",
                                        command=self.toggle_code_visibility)
        self.btn_reveal.pack(side="right", padx=10)

        self.info_lbl = ctk.CTkLabel(self, text="正在等待数据...", font=("微软雅黑", 14))
        self.info_lbl.pack(pady=10)

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

        # 日志框打包到底部
        self.log_box.pack(pady=10, padx=30, fill="both")

        threading.Thread(target=self.init_tray_permanently, daemon=True).start()
        self.refresh_ui()
        self.protocol("WM_DELETE_WINDOW", self.withdraw_window)

        try:
            self.iconbitmap(resource_path("favicon.ico"))
        except:
            pass

    # ... 保留类里的其他函数 (refresh_ui, change_code 等) ...

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
        # ✅ 修改：使用 resource_path 加载 icon.png
        icon_path = resource_path("icon.png")

        img = Image.open(icon_path) if os.path.exists(icon_path) else Image.new('RGB', (64, 64), color=(31, 147, 255))

        menu = (
            pystray.MenuItem('显示窗口', self.show_window, default=True),
            pystray.MenuItem('退出服务', self.quit_app)
        )
        self.tray = pystray.Icon("ServerMonitor", img, "Server Monitor", menu)
        self.tray.run()

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
def get_silent_specs():
    specs = {"os": "Unknown Windows", "cpu": "Unknown CPU", "gpu": "Unknown GPU"}

    # 1. 获取 Windows 精确产品名称 (如 Windows 11 Home)
    try:
        key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Windows NT\CurrentVersion")
        # ProductName 通常是最准确的描述
        specs["os"], _ = winreg.QueryValueEx(key, "ProductName")
        winreg.CloseKey(key)
    except:
        specs["os"] = platform.platform()

    # 2. 获取 CPU 完整型号
    try:
        key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"HARDWARE\DESCRIPTION\System\CentralProcessor\0")
        specs["cpu"], _ = winreg.QueryValueEx(key, "ProcessorNameString")
        winreg.CloseKey(key)
    except:
        specs["cpu"] = platform.processor()

    # 3. 🌟 获取显卡名称 (重点：同时兼容集显与独显)
    # Windows 所有的显示适配器都记录在这个 Class ID 路径下
    gpu_list = []
    gpu_reg_path = r"SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    try:
        main_key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, gpu_reg_path)
        # 遍历 0000, 0001, 0002 等子项，通常 0000 是集显，0001 是独显
        for i in range(10):
            try:
                sub_key_name = f"{i:04d}"  # 格式化为 0000, 0001...
                sub_key = winreg.OpenKey(main_key, sub_key_name)
                gpu_name, _ = winreg.QueryValueEx(sub_key, "DriverDesc")
                gpu_list.append(gpu_name)
                winreg.CloseKey(sub_key)
            except:
                break  # 找不到更多显卡了就退出
        winreg.CloseKey(main_key)
    except:
        pass

    # 如果有多个显卡，用斜杠连起来展示
    specs["gpu"] = " / ".join(gpu_list) if gpu_list else "通用显示适配器"

    return specs


# 在 init_specs 里调用它
# --- 启动逻辑 ---
def init_specs():
    global SYSTEM_SPECS
    import winreg

    # 1. 处理器：直接读注册表，不闪黑框
    try:
        k = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"HARDWARE\DESCRIPTION\System\CentralProcessor\0")
        cpu_name, _ = winreg.QueryValueEx(k, "ProcessorNameString")
        winreg.CloseKey(k)
        cpu_name = cpu_name.strip()
    except:
        cpu_name = platform.processor()

    # 2. 操作系统：强制纠正 Win11 显示 Bug
    os_display_name = platform.platform()
    if platform.system() == "Windows":
        try:
            k = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Windows NT\CurrentVersion")
            product_name, _ = winreg.QueryValueEx(k, "ProductName")
            build_num, _ = winreg.QueryValueEx(k, "CurrentBuild")
            display_version, _ = winreg.QueryValueEx(k, "DisplayVersion")
            winreg.CloseKey(k)
            # 如果内核版本号 >= 22000，强制修正名字为 Windows 11
            if int(build_num) >= 22000:
                product_name = product_name.replace("Windows 10", "Windows 11")
            os_display_name = f"{product_name} {display_version}"
        except:
            pass

    # 3. 显卡：多显卡全量枚举逻辑（解决集显被省略的问题）
    gpu_list = []
    # Windows 所有的显示设备都藏在这个 Class ID 路径下
    gpu_reg_path = r"SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    try:
        main_key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, gpu_reg_path)
        # 循环尝试 0000 到 0007，抓取所有的显卡驱动描述
        for i in range(8):
            try:
                sub_key = winreg.OpenKey(main_key, f"{i:04d}")
                name, _ = winreg.QueryValueEx(sub_key, "DriverDesc")
                # 排除掉远程桌面或虚拟显卡等干扰项
                if "Remote" not in name and "Virtual" not in name:
                    if name not in gpu_list:  # 防止重复抓取
                        gpu_list.append(name)
                winreg.CloseKey(sub_key)
            except:
                break
        winreg.CloseKey(main_key)
    except:
        pass

    final_gpu = " / ".join(gpu_list) if gpu_list else "通用显示适配器"

    # 封装最终数据
    SYSTEM_SPECS = {
        "os": os_display_name,
        "cpu": cpu_name,
        "ram": f"{round(psutil.virtual_memory().total / (1024 ** 3), 1)} GB",
        "gpu": final_gpu
    }


if __name__ == "__main__":
    # 1. 必须放在第一行，防止进程炸弹
    multiprocessing.freeze_support()

    # 2. ✅ 单例模式检查：如果程序已在运行，就唤醒它并退出自己
    import urllib.request
    import urllib.error

    try:
        # 尝试连接唤醒接口 (设置 1 秒超时，防止太快失败)
        resp = urllib.request.urlopen("http://127.0.0.1:5000/show_ui", timeout=1)
        if resp.getcode() == 200:
            # print("唤醒成功，正在退出...") # 调试用
            sys.exit(0)
    except urllib.error.HTTPError as e:
        # 如果返回 401/403/500，说明服务其实在运行，只是报错了，也应该退出
        # 但因为我们上面修了 check_auth，正常情况应该是 200
        sys.exit(0)
    except Exception as e:
        # 只有连接不上（ConnectionRefused）才说明没运行
        pass

    init_specs()

    # 3. 端口处理
    CURRENT_PORT = 5000
    if is_port_in_use(CURRENT_PORT):
        CURRENT_PORT = 5001

    LOCAL_IP = get_local_ip()

    # 4. 启动 UI
    ui = MonitorUI(LOCAL_IP, CURRENT_PORT)

    if CURRENT_PORT == 5001:
        ui.log_box.insert("end", "\n[⚠️] 5000端口被占用，自动切换至 5001 端口！")
    else:
        ui.log_box.insert("end", f"\n[✔️] 服务就绪，端口: {CURRENT_PORT}")

    # 5. 启动线程
    threading.Thread(target=monitor_loop, daemon=True).start()

    threading.Thread(
        target=lambda: app.run(host='0.0.0.0', port=CURRENT_PORT, debug=False, use_reloader=False),
        daemon=True
    ).start()

    threading.Thread(
        target=udp_discovery_listener,
        args=(ui.log_box,),
        daemon=True
    ).start()

    ui.mainloop()
