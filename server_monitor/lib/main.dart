import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MonitorApp());
}

class MonitorApp extends StatelessWidget {
  const MonitorApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Server Monitor',
      theme: ThemeData.dark(),
      home: const MonitorScreen(),
    );
  }
}

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});
  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  String _cpu = "0";
  String _ram = "0";
  String _disk = "0";
  String _gpu = "0";
  String _statusText = "初始化中...";
  Color _statusColor = Colors.orange;
  Timer? _timer;

  String _baseUrl = '';
  String _secretCode = '';
  Future<Map<String, dynamic>>? _specsMemo;
  bool _isAuthDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) => _fetchStatus(),
    );
  }

  // 1. 启动时加载设置
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _baseUrl = prefs.getString('server_ip') ?? '';
      _secretCode = prefs.getString('secret_code') ?? '';
    });

    // 启动时，如果没 IP 或者 没密码，直接弹窗
    if (_baseUrl.isEmpty || _secretCode.isEmpty) {
      Future.delayed(
        const Duration(milliseconds: 500),
        () => _showAuthDialog(isForce: true),
      );
    }
  }

  // 2. 核心：带“钥匙”获取数据
  Future<void> _fetchStatus() async {
    if (_baseUrl.isEmpty) return;

    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/status'),
            headers: {'X-Secret-Code': _secretCode},
          )
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        // 认证成功
        final data = jsonDecode(response.body);
        setState(() {
          // 加上防空值保护，防止后端发来null导致报错
          _cpu = double.parse((data['cpu'] ?? 0).toString()).toStringAsFixed(1);
          _ram = double.parse((data['ram'] ?? 0).toString()).toStringAsFixed(1);
          _disk = double.parse(
            (data['disk'] ?? 0).toString(),
          ).toStringAsFixed(1);
          _gpu = double.parse((data['gpu'] ?? 0).toString()).toStringAsFixed(1);

          _statusText = "🟢 已加密连接";
          _statusColor = Colors.greenAccent;

          if (double.parse(_cpu) > 80 || double.parse(_gpu) > 80) {
            _statusColor = Colors.redAccent;
            _statusText = "🔥 高温预警";
          }
        });
      } else if (response.statusCode == 401) {
        // 认证失败
        setState(() {
          _statusText = "🔒 配对码过期";
          _statusColor = Colors.red;
        });
        if (!_isAuthDialogShowing) {
          _showAuthDialog(errorMessage: "电脑端配对码已更新，请重新输入");
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = "🔴 连接断开";
          _statusColor = Colors.grey;
        });
      }
    }
  }

  // 3. 自动发现
  Future<void> _autoDiscoverServer(String inputCode) async {
    setState(() {
      _statusText = "正在验证配对码...";
    });
    try {
      var socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.send(
        utf8.encode("FIND_SERVER:$inputCode"),
        InternetAddress('255.255.255.255'),
        50001,
      );

      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? dg = socket.receive();
          if (dg != null && utf8.decode(dg.data) == "HERE_I_AM") {
            _saveSettings(dg.address.address, inputCode);
            socket.close();
            if (_isAuthDialogShowing && mounted) {
              Navigator.pop(context);
            }
          }
        }
      });
    } catch (e) {
      print(e);
    }
  }

  Future<void> _saveSettings(String ip, String code) async {
    if (!ip.startsWith('http')) ip = 'http://$ip:5000';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', ip);
    await prefs.setString('secret_code', code);
    setState(() {
      _baseUrl = ip;
      _secretCode = code;
      _specsMemo = null; // 清空缓存，下次点击重新获取
    });
  }

  // 4. 万能连接弹窗
  void _showAuthDialog({bool isForce = false, String? errorMessage}) {
    _isAuthDialogShowing = true;
    final TextEditingController codeController = TextEditingController(
      text: _secretCode,
    );
    final TextEditingController ipController = TextEditingController(
      text: _baseUrl.replaceAll('http://', '').replaceAll(':5000', ''),
    );

    showDialog(
      context: context,
      barrierDismissible: !isForce,
      builder: (context) {
        return WillPopScope(
          onWillPop: () async => !isForce,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text(
              "🔐 连接服务器",
              style: TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 15),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                errorMessage,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "配对码 (必填)",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 5),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 24,
                      letterSpacing: 5,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(
                      hintText: "6位数字",
                      hintStyle: TextStyle(
                        color: Colors.white12,
                        fontSize: 16,
                        letterSpacing: 0,
                      ),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.greenAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "服务器 IP (选填，自动搜索失败时使用)",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 5),
                  TextField(
                    controller: ipController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: "例如 192.168.1.5",
                      hintStyle: TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderSide: BorderSide.none),
                      prefixIcon: Icon(Icons.wifi, color: Colors.blueAccent),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (!isForce)
                TextButton(
                  onPressed: () {
                    _isAuthDialogShowing = false;
                    Navigator.pop(context);
                  },
                  child: const Text("取消"),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 25,
                    vertical: 12,
                  ),
                ),
                onPressed: () {
                  if (codeController.text.length < 6) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("请输入完整的6位配对码")),
                    );
                    return;
                  }

                  if (ipController.text.isNotEmpty) {
                    _saveSettings(ipController.text, codeController.text);
                    Future.delayed(
                      const Duration(milliseconds: 500),
                      () => _fetchStatus(),
                    );
                    _isAuthDialogShowing = false;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("正在尝试直接连接 IP...")),
                    );
                  } else {
                    _autoDiscoverServer(codeController.text);
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text("正在搜索局域网...")));
                  }
                },
                child: const Text("连接", style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        );
      },
    ).then((_) => _isAuthDialogShowing = false);
  }

  // --- 🔥 修复：获取详情逻辑 ---
  Future<Map<String, dynamic>> _fetchSpecsFromNetwork() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/specs'),
            headers: {'X-Secret-Code': _secretCode},
          )
          .timeout(const Duration(seconds: 5)); // 5秒超时

      if (response.statusCode == 200) {
        // 🔥 关键：使用 utf8.decode 防止中文乱码
        return jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
      } else {
        throw Exception('Auth Failed');
      }
    } catch (e) {
      throw Exception('Load Error');
    }
  }

  Future<void> _showSpecs(BuildContext context) async {
    if (_baseUrl.isEmpty) {
      _showAuthDialog();
      return;
    }
    // 每次打开都尝试重新获取，防止数据过时
    _specsMemo = _fetchSpecsFromNetwork();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SpecsSheet(
              specsFuture: _specsMemo!,
              onRefresh: () {
                setState(() {
                  _specsMemo = _fetchSpecsFromNetwork();
                });
                setModalState(() {});
              },
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Server Monitor'),
        backgroundColor: Colors.transparent,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.link, color: Colors.white),
            onPressed: () => _showAuthDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () => _showSpecs(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Text(
                _baseUrl.isEmpty ? "未连接" : "Server: $_baseUrl",
                style: const TextStyle(color: Colors.white24, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _statusColor),
                ),
                child: Text(_statusText, style: TextStyle(color: _statusColor)),
              ),
              const SizedBox(height: 30),
              _buildGauge("处理器 CPU", "$_cpu%", Colors.blueAccent, Icons.memory),
              const SizedBox(height: 20),
              _buildGauge(
                "内存 RAM",
                "$_ram%",
                Colors.purpleAccent,
                Icons.storage,
              ),
              const SizedBox(height: 20),
              _buildGauge(
                "显卡 GPU",
                "$_gpu%",
                Colors.orangeAccent,
                Icons.videogame_asset,
              ),
              const SizedBox(height: 20),
              _buildGauge("磁盘空间", "$_disk%", Colors.grey, Icons.pie_chart),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGauge(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(width: 15),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class SpecsSheet extends StatelessWidget {
  final Future<Map<String, dynamic>> specsFuture;
  final VoidCallback onRefresh;
  const SpecsSheet({
    super.key,
    required this.specsFuture,
    required this.onRefresh,
  });
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.8,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: FutureBuilder<Map<String, dynamic>>(
            future: specsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "获取配置失败",
                        style: TextStyle(color: Colors.white),
                      ),
                      TextButton(onPressed: onRefresh, child: const Text("重试")),
                    ],
                  ),
                );
              }
              final specs = snapshot.data!;
              return SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.all(30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "💻 本机配置",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.refresh,
                            color: Colors.blueAccent,
                          ),
                          onPressed: onRefresh,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // 🔥 修复：每个字段都加了 ?? 保护，防止空值崩溃
                    _buildSpecRow(
                      Icons.laptop_windows,
                      "操作系统",
                      specs['os'] ?? "未知系统",
                    ),
                    _buildSpecRow(
                      Icons.memory,
                      "CPU 型号",
                      specs['cpu'] ?? "未知 CPU",
                    ),
                    _buildSpecRow(
                      Icons.grid_view,
                      "核心数",
                      specs['cores'] ?? "-",
                    ),
                    _buildSpecRow(Icons.storage, "总内存", specs['ram'] ?? "-"),
                    _buildSpecRow(
                      Icons.videogame_asset,
                      "显卡 GPU",
                      // 如果 Python 没找到显卡，这里会显示 "未知/集成显卡"
                      specs['gpu'] ?? "未知/集成显卡",
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSpecRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.blueAccent, size: 28),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
