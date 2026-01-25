import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class ScreenTabletPage extends StatefulWidget {
  final String serverUrl;
  final String secretCode;

  const ScreenTabletPage({
    super.key,
    required this.serverUrl,
    required this.secretCode,
  });

  @override
  State<ScreenTabletPage> createState() => _ScreenTabletPageState();
}

class _ScreenTabletPageState extends State<ScreenTabletPage> {
  final http.Client _client = http.Client();
  late final WebSocketChannel _streamChannel;

  // 🔥 状态控制变量 (必须放在 class 里面，build 外面)
  bool _isSingleFingerDown = false;
  int _lastMoveTime = 0; // 🔥 用于限流的时间戳

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // 🔥🔥🔥 彻底修复的连接逻辑：提取纯 IP，强制连接 8765 端口
    Uri baseUri = Uri.parse(widget.serverUrl);
    String wsUrl = 'ws://${baseUri.host}:8765';
    print("正在连接投屏: $wsUrl"); // 你可以在调试台看到真正的连接地址

    _streamChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _streamChannel.sink.close();
    _client.close();
    super.dispose();
  }

  // 发送绝对定位 (单指画画)
  void _sendAbsoluteTouch(Offset localPos, Size size,
      {String action = 'absolute_move'}) {
    double xPct = (localPos.dx / size.width).clamp(0.0, 1.0);
    double yPct = (localPos.dy / size.height).clamp(0.0, 1.0);
    _sendApi({'action': action, 'x': xPct, 'y': yPct});
  }

  // 发送相对动作 (双指滚动/松开左键)
  void _sendAction(String action, {double dy = 0, String text = ''}) {
    _sendApi({'action': action, 'dy': dy, 'text': text});
  }

  Future<void> _sendApi(Map<String, dynamic> body) async {
    try {
      final endpoint = body.containsKey('text') && body['text'] != ''
          ? '/keyboard'
          : '/mouse';
      final url = Uri.parse('${widget.serverUrl}$endpoint');
      _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Secret-Code': widget.secretCode
        },
        body: jsonEncode(body),
      );
    } catch (e) {/* 忽略网络错误防止崩溃 */}
  }

  // 弹出键盘
  void _showKeyboardSheet() {
    final TextEditingController textController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 15,
              right: 15,
              top: 15),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "输入文字...",
                  filled: true,
                  fillColor: Colors.black26,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send, color: Colors.blueAccent),
                    onPressed: () {
                      _sendAction('type', text: textController.text);
                      Navigator.pop(context);
                    },
                  ),
                ),
                onSubmitted: (value) {
                  _sendAction('type', text: value);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 🔥 1. 16:9 完美画面框
          Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                children: [
                  // 1.1 视频底层
                  StreamBuilder(
                    stream: _streamChannel.stream,
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return SizedBox.expand(
                          child: Image.memory(
                            snapshot.data as Uint8List,
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                            // 🔥 新增：开启高保真双三次插值抗锯齿，文字边缘瞬间锐利！
                            filterQuality: FilterQuality.medium,
                          ),
                        );
                      }
                      return const Center(
                          child:
                              CircularProgressIndicator(color: Colors.white24));
                    },
                  ),

                  // 1.2 触控捕获网 (大小与视频严丝合缝)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        behavior: HitTestBehavior.translucent,

                        // 🔥 手指按下
                        onScaleStart: (details) {
                          if (details.pointerCount == 1) {
                            _isSingleFingerDown = true;
                            _sendAbsoluteTouch(
                                details.localFocalPoint, constraints.biggest,
                                action: 'absolute_move_down');
                          } else {
                            _isSingleFingerDown = false;
                            _sendAction('left_up');
                          }
                        },

                        // 🔥 手指移动 (带限流保护！)
                        onScaleUpdate: (details) {
                          int now = DateTime.now().millisecondsSinceEpoch;

                          // 单指：画画 (限流约 60fps)
                          if (details.pointerCount == 1 &&
                              _isSingleFingerDown) {
                            if (now - _lastMoveTime > 16) {
                              _sendAbsoluteTouch(
                                  details.localFocalPoint, constraints.biggest,
                                  action: 'absolute_move');
                              _lastMoveTime = now;
                            }
                          }
                          // 双指：滚动 (限流约 30fps)
                          else if (details.pointerCount == 2) {
                            if (details.focalPointDelta.dy != 0 &&
                                (now - _lastMoveTime > 30)) {
                              _sendAction('scroll',
                                  dy: details.focalPointDelta.dy / 2);
                              _lastMoveTime = now;
                            }
                          }
                        },

                        // 🔥 手指抬起
                        onScaleEnd: (details) {
                          if (_isSingleFingerDown) {
                            _isSingleFingerDown = false;
                            _sendAction('left_up');
                          }
                        },
                        child: Container(color: Colors.transparent),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // 3. UI 按钮层
          Positioned(
              left: 20,
              top: 20,
              child: _buildBtn(Icons.arrow_back, () => Navigator.pop(context))),
          Positioned(
              right: 20,
              top: 20,
              child: _buildBtn(Icons.keyboard, _showKeyboardSheet)),
        ],
      ),
    );
  }

  Widget _buildBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: Colors.black45, borderRadius: BorderRadius.circular(30)),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}
