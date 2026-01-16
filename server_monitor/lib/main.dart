import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

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
  // --- 动态数据变量 ---
  String _cpu = "0";
  String _ram = "0";
  String _disk = "0";
  String _gpu = "0";
  String _statusText = "正在连接...";
  Color _statusColor = Colors.orange;
  Timer? _timer;

  // ⚠️⚠️⚠️ 只有这里需要改 IP ⚠️⚠️⚠️
  final String _baseUrl = 'http://10.161.245.81:5000';

  // --- 核心：配置信息的“缓存记忆” ---
  // 如果这个变量有值，就不去网络请求；如果是 null，才去请求
  Future<Map<String, dynamic>>? _specsMemo;

  @override
  void initState() {
    super.initState();
    // 启动每秒轮询
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) => _fetchStatus(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // --- 1. 获取动态数据 (轮询) ---
  Future<void> _fetchStatus() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/status'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _cpu = double.parse(data['cpu'].toString()).toStringAsFixed(1);
          _ram = double.parse(data['ram'].toString()).toStringAsFixed(1);
          _disk = double.parse(data['disk'].toString()).toStringAsFixed(1);
          _gpu = double.parse(data['gpu'].toString()).toStringAsFixed(1);
          _statusText = "🟢 系统正常";
          _statusColor = Colors.greenAccent;

          if (double.parse(_cpu) > 80 || double.parse(_gpu) > 80) {
            _statusColor = Colors.redAccent;
            _statusText = "🔥 高温预警";
          }
        });
      }
    } catch (e) {
      setState(() {
        _statusText = "🔴 连接断开";
        _statusColor = Colors.grey;
      });
    }
  }

  // --- 2. 获取配置数据 (网络请求函数) ---
  Future<Map<String, dynamic>> _fetchSpecsFromNetwork() async {
    final response = await http.get(Uri.parse('$_baseUrl/specs'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Server Error');
    }
  }

  // --- 3. 显示弹窗 (带缓存逻辑) ---
  Future<void> _showSpecs(BuildContext context) async {
    // 逻辑：如果记忆为空，才去发起请求
    if (_specsMemo == null) {
      _specsMemo = _fetchSpecsFromNetwork();
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // 背景交给子组件处理
      isScrollControlled: true,
      builder: (context) {
        // 使用 StatefulBuilder 为了让弹窗内部可以响应刷新按钮
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SpecsSheet(
              specsFuture: _specsMemo!, // 把记好的数据传进去
              onRefresh: () {
                // 当用户点击刷新时：
                // 1. 更新主界面的记忆 (强制重新获取)
                setState(() {
                  _specsMemo = _fetchSpecsFromNetwork();
                });
                // 2. 更新弹窗界面 (让它转圈并显示新数据)
                setModalState(() {});
              },
            );
          },
        );
      },
    );
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
              _buildGauge("CPU 核心", "$_cpu%", Colors.blueAccent, Icons.memory),
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

// --- 独立的弹窗组件 (只负责显示) ---
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
              // 1. 加载中
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              // 2. 加载失败
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.redAccent,
                        size: 40,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "获取失败: ${snapshot.error}",
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: onRefresh,
                        child: const Text("重试"),
                      ),
                    ],
                  ),
                );
              }

              // 3. 加载成功
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
                          onPressed: () {
                            onRefresh(); // 触发刷新
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("正在刷新配置..."),
                                duration: Duration(milliseconds: 500),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    _buildSpecRow(Icons.laptop_windows, "操作系统", specs['os']),
                    _buildSpecRow(Icons.memory, "CPU 型号", specs['cpu']),
                    _buildSpecRow(Icons.grid_view, "核心数", specs['cores']),
                    _buildSpecRow(Icons.storage, "总内存", specs['ram']),
                    _buildSpecRow(
                      Icons.videogame_asset,
                      "显卡 GPU",
                      specs['gpu'],
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
