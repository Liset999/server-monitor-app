import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/physics.dart';

class TouchpadPage extends StatefulWidget {
  final String serverUrl;
  final String secretCode;

  const TouchpadPage({
    super.key,
    required this.serverUrl,
    required this.secretCode,
  });

  @override
  State<TouchpadPage> createState() => _TouchpadPageState();
}

class _TouchpadPageState extends State<TouchpadPage>
    with SingleTickerProviderStateMixin {
  final http.Client _client = http.Client();

  double sensitivity = 5.0;
  bool isLandscape = true;
  bool isScrollReversed = false;
  bool isVibrationEnabled = false;

  // 状态变量
  int _lastFingerUpTime = 0;
  bool _isDragActive = false;
  bool _isScrolling = false;
  // 在状态类顶部与其他 bool 变量放在一起
  bool isDrawingMode = false; // 🔥 新增：数位板模式开关

  // 🔥 三指手势专用变量
  double _threeFingerDx = 0; // 累计横向移动距离
  double _threeFingerDy = 0; // 累计纵向移动距离
  bool _hasTriggeredGesture = false; // 本次触摸是否已经触发过手势(防止一次滑动触发十次)
  Offset? _startFocalPoint; // 记录手指按下的位置
  double _totalMoveDistance = 0.0; // 记录总共移动了多少像素

  late AnimationController _scrollController;
  double _lastAnimationValue = 0;

  @override
  void initState() {
    super.initState();
    _setOrientation(true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scrollController = AnimationController.unbounded(vsync: this);
    _scrollController.addListener(() {
      // 计算这一帧和上一帧之间的距离差
      double delta = _scrollController.value - _lastAnimationValue;
      _lastAnimationValue = _scrollController.value;

      // 缩放滚轮速度 (除以15是比较舒服的阻尼)
      double scrollDy = delta / 15;
      if (isScrollReversed) scrollDy = -scrollDy;

      // 如果还在移动，就持续发送滚动指令
      if (scrollDy.abs() > 0.1) {
        _sendAction('scroll', dy: scrollDy);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _client.close();
    super.dispose();
  }

  void _setOrientation(bool landscape) {
    setState(() {
      isLandscape = landscape;
    });
    if (landscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  void _triggerVibration({bool heavy = false}) {
    if (isVibrationEnabled) {
      if (heavy) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    }
  }

  // 发送绝对坐标 (0.0 ~ 1.0 之间)
  Future<void> _sendAbsoluteMove(Offset localPos, Size size) async {
    // 计算当前手指在触控板上的百分比位置
    double xPct = (localPos.dx / size.width).clamp(0.0, 1.0);
    double yPct = (localPos.dy / size.height).clamp(0.0, 1.0);

    try {
      final url = Uri.parse('${widget.serverUrl}/mouse');
      _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Secret-Code': widget.secretCode,
        },
        body: jsonEncode({
          'action': 'absolute_move', // 🔥 新的动作指令
          'x': xPct,
          'y': yPct,
        }),
      );
    } catch (e) {/* ignore */}
  }

  Future<void> _sendAction(String action,
      {double dx = 0, double dy = 0}) async {
    try {
      final url = Uri.parse('${widget.serverUrl}/mouse');
      _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Secret-Code': widget.secretCode,
        },
        body: jsonEncode({
          'action': action,
          'dx': dx,
          'dy': dy,
          'sensitivity': sensitivity,
        }),
      );
    } catch (e) {/* ignore */}
  }

  // 🔥 新增：发送键盘输入的文本
  Future<void> _sendText(String text) async {
    if (text.isEmpty) return;
    try {
      // 这里我们请求一个新的路由 /keyboard
      final url = Uri.parse('${widget.serverUrl}/keyboard');
      _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Secret-Code': widget.secretCode,
        },
        body: jsonEncode({'text': text}),
      );
    } catch (e) {/* ignore */}
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text("触控板设置",
                  style: TextStyle(color: Colors.white, fontSize: 18)),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. 灵敏度
                      Row(
                        children: [
                          const Icon(Icons.speed,
                              color: Colors.blueAccent, size: 20),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 40,
                            child: Text(
                              sensitivity.toStringAsFixed(1),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: sensitivity,
                              min: 1.0,
                              max: 20.0,
                              divisions: 19,
                              activeColor: Colors.blueAccent,
                              inactiveColor: Colors.white10,
                              onChanged: (v) {
                                setStateDialog(() => sensitivity = v);
                                setState(() => sensitivity = v);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // 2. 横竖屏
                      _buildSwitchRow(
                        icon: isLandscape
                            ? Icons.crop_landscape
                            : Icons.crop_portrait,
                        label: isLandscape ? "横屏模式" : "竖屏模式",
                        value: isLandscape,
                        activeColor: Colors.orangeAccent,
                        onChanged: (val) {
                          setStateDialog(() => isLandscape = val);
                          _setOrientation(val);
                        },
                      ),
                      const SizedBox(height: 10),

                      // 3. 滚动反转
                      _buildSwitchRow(
                        icon: Icons.swap_vert,
                        label: isScrollReversed ? "滚动方向：反转" : "滚动方向：标准",
                        value: isScrollReversed,
                        activeColor: Colors.pinkAccent,
                        onChanged: (val) {
                          setStateDialog(() => isScrollReversed = val);
                          setState(() => isScrollReversed = val);
                        },
                      ),
                      const SizedBox(height: 10),

                      // 4. 震动开关
                      _buildSwitchRow(
                        icon: isVibrationEnabled
                            ? Icons.vibration
                            : Icons.smartphone,
                        label: isVibrationEnabled ? "按键震动：开启" : "按键震动：关闭",
                        value: isVibrationEnabled,
                        activeColor: Colors.greenAccent,
                        onChanged: (val) {
                          setStateDialog(() => isVibrationEnabled = val);
                          setState(() => isVibrationEnabled = val);
                        },
                      ),

                      // 5. 数位板模式 (绝对坐标)
                      _buildSwitchRow(
                        icon: isDrawingMode ? Icons.draw : Icons.mouse,
                        label: isDrawingMode
                            ? "模式：专业数位板 (绝对坐标)"
                            : "模式：普通触控板 (相对坐标)",
                        value: isDrawingMode,
                        activeColor: Colors.deepPurpleAccent,
                        onChanged: (val) {
                          setStateDialog(() => isDrawingMode = val);
                          setState(() => isDrawingMode = val);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("完成"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSwitchRow(
      {required IconData icon,
      required String label,
      required bool value,
      required Color activeColor,
      required Function(bool) onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: activeColor, size: 20),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(color: Colors.white70)),
            ],
          ),
          Switch(
            value: value,
            activeColor: activeColor,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: LayoutBuilder(// 👈 新增 LayoutBuilder
                    builder: (context, constraints) {
                  // 👈 constraints 包含了触控板的精确宽高
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,

                    // 🔥 1. 手指按下：重置所有状态
                    onScaleStart: (details) {
                      // 🔥 新增：手指一按到屏幕，立刻停止之前的惯性滚动
                      if (_scrollController.isAnimating) {
                        _scrollController.stop();
                      }

                      // 重置三指手势数据
                      _threeFingerDx = 0;
                      _threeFingerDy = 0;
                      _hasTriggeredGesture = false;
                      _totalMoveDistance = 0.0; // 👈 重置移动距离

                      // 👇 记录单指开始的位置
                      if (details.pointerCount == 1) {
                        _startFocalPoint = details.focalPoint;
                      }

                      // 单指逻辑 (双击拖拽)
                      if (details.pointerCount == 1) {
                        final now = DateTime.now().millisecondsSinceEpoch;
                        if (now - _lastFingerUpTime < 250) {
                          _isDragActive = true;
                          _triggerVibration(heavy: true);
                          setState(() {});
                          _sendAction('left_down');
                        }
                      }
                      // 双指逻辑
                      else if (details.pointerCount == 2) {
                        _isScrolling = true;
                      }
                    },

                    // 🔥 2. 手指移动：核心手势识别
                    onScaleUpdate: (details) {
                      _totalMoveDistance += details.focalPointDelta.distance;

                      // 👉 单指：移动鼠标
                      if (details.pointerCount == 1) {
                        // 🔥 如果是数位板模式，发送绝对位置
                        if (isDrawingMode) {
                          _sendAbsoluteMove(
                              details.localFocalPoint, constraints.biggest);
                          // 如果处于拖拽/绘画状态，同时也代表正在按下左键作画
                          if (_isDragActive) {
                            // 可选：在这里加上发送左键按下的逻辑，配合画笔力度
                          }
                        }
                        // 👉 否则，就是原来的普通触控板模式
                        else {
                          _sendAction('move',
                              dx: details.focalPointDelta.dx,
                              dy: details.focalPointDelta.dy);
                        }
                      }
                      // ✌️ 双指：滚动
                      else if (details.pointerCount == 2) {
                        if (details.focalPointDelta.dy != 0) {
                          double scrollDy = details.focalPointDelta.dy / 2;
                          if (isScrollReversed) scrollDy = -scrollDy;
                          _sendAction('scroll', dy: scrollDy);
                        }
                      }
                      // 🤟 三指：系统手势 (Win+Tab, Win+D, Alt+Tab)
                      else if (details.pointerCount == 3) {
                        // 累加移动距离
                        _threeFingerDx += details.focalPointDelta.dx;
                        _threeFingerDy += details.focalPointDelta.dy;

                        // 如果本次触摸还没触发过手势，且移动距离超过阈值 (例如 80 像素)
                        if (!_hasTriggeredGesture) {
                          // ⬆️ 上滑：任务视图
                          if (_threeFingerDy < -80) {
                            _triggerVibration(heavy: true);
                            _sendAction('task_view');
                            _hasTriggeredGesture = true; // 锁定，防止重复触发
                          }
                          // ⬇️ 下滑：显示桌面
                          else if (_threeFingerDy > 80) {
                            _triggerVibration(heavy: true);
                            _sendAction('show_desktop');
                            _hasTriggeredGesture = true;
                          }
                          // ⬅️➡️ 左右滑：切换应用 (Alt+Tab)
                          else if (_threeFingerDx.abs() > 80) {
                            _triggerVibration(heavy: true);
                            _sendAction('alt_tab');
                            _hasTriggeredGesture = true;
                          }
                        }
                      }
                    },

                    // 🔥 3. 手指抬起
                    // 🔥 3. 手指抬起
                    // 🔥 3. 手指抬起
                    onScaleEnd: (details) {
                      _startFocalPoint = null;

                      // 如果是双指滚动结束，直接返回
                      if (_isScrolling) {
                        _isScrolling = false;
                        // 滚动结束，不算作点击，清空双击计时器
                        _lastFingerUpTime = 0;
                        double velocityY = details.velocity.pixelsPerSecond.dy;

                        // 如果速度大于 300，说明是“用力甩出”，触发惯性动画
                        if (velocityY.abs() > 300.0) {
                          _lastAnimationValue = 0;
                          _scrollController.value = 0;
                          // 使用 FrictionSimulation 模拟摩擦力
                          // 参数1：摩擦系数 (0.05 越小越滑，越大停得越快)
                          // 参数2：起始位置 (0)
                          // 参数3：初始速度 (velocityY)
                          _scrollController.animateWith(FrictionSimulation(
                            0.05,
                            0,
                            velocityY,
                          ));
                        }
                        return;
                      }

                      // 释放拖拽
                      if (_isDragActive) {
                        _isDragActive = false;
                        setState(() {});
                        _sendAction('left_up');
                        _lastFingerUpTime = 0; // 拖拽结束，清空计时器
                        return;
                      }

                      // ✅ 核心修复：精准判断双击拖拽的条件
                      // 只有当这次触摸是“纯点击”（移动距离 < 5.0）时，才记录时间
                      if (!_hasTriggeredGesture && _totalMoveDistance < 5.0) {
                        _lastFingerUpTime =
                            DateTime.now().millisecondsSinceEpoch; // 👈 只有点击才计时
                        _triggerVibration();
                        _sendAction('click');
                      } else {
                        // 👉 如果手指之前是在移动鼠标（滑动），则彻底清零计时器！
                        // 这样你迅速放下手指继续滑动时，就不会误触发拖拽了。
                        _lastFingerUpTime = 0;
                      }
                    },

                    child: Container(
                      margin: const EdgeInsets.fromLTRB(10, 10, 10, 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color:
                                _isDragActive ? Colors.white10 : Colors.white10,
                            width: _isDragActive ? 2 : 1),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                                _isDragActive
                                    ? Icons.brush
                                    : (isLandscape
                                        ? Icons.computer
                                        : Icons.smartphone),
                                size: 80,
                                color: _isDragActive
                                    ? Colors.white10
                                    : const Color.fromARGB(26, 189, 152, 152)),
                            const SizedBox(height: 20),
                            Text(
                              _isDragActive
                                  ? "拖拽/绘画模式 (松手结束)"
                                  : (isScrollReversed
                                      ? "滚动方向已反转"
                                      : "单指移动 · 双指滚动 · 三指手势"),
                              style: TextStyle(
                                  color: _isDragActive
                                      ? Colors.white24
                                      : Colors.white24,
                                  fontWeight: _isDragActive
                                      ? FontWeight.bold
                                      : FontWeight.normal),
                            )
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
              SizedBox(
                height: 60,
                child: Row(
                  children: [
                    Expanded(
                        child: _buildBtn("左键", () => _sendAction('click'))),
                    Expanded(
                        child:
                            _buildBtn("右键", () => _sendAction('right_click'))),
                  ],
                ),
              ),
              const SizedBox(height: 5),
            ],
          ),
          Positioned(
            left: 20,
            top: 20,
            child:
                _buildFloatBtn(Icons.arrow_back, () => Navigator.pop(context)),
          ),
          // ✅ 替换为：包含键盘和设置的两个按钮
          Positioned(
            right: 20,
            top: 20,
            child: Row(
              children: [
                _buildFloatBtn(Icons.keyboard, _showKeyboardSheet), // 👈 新的键盘按钮
                const SizedBox(width: 15),
                _buildFloatBtn(Icons.settings, _showSettingsDialog),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🔥 新增：弹出键盘输入框
  void _showKeyboardSheet() {
    final TextEditingController textController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 允许弹窗被键盘顶上去
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom, // 适配系统键盘高度
            left: 15,
            right: 15,
            top: 15,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                autofocus: true, // 自动弹出键盘
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "输入要发送到电脑的文字...",
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  // 右侧的发送按钮
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send, color: Colors.blueAccent),
                    onPressed: () {
                      _sendText(textController.text);
                      textController.clear(); // 发送后清空
                      Navigator.pop(context); // 关闭弹窗
                    },
                  ),
                ),
                // 按回车键也能发送
                onSubmitted: (value) {
                  _sendText(value);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBtn(String label, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: ElevatedButton(
        onPressed: () {
          _triggerVibration(heavy: true);
          onTap();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF333333),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
    );
  }

  Widget _buildFloatBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 45,
        height: 45,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white10),
        ),
        child: Icon(icon, color: Colors.white70),
      ),
    );
  }
}
