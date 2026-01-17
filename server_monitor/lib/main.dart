import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart'; // 必须先运行 flutter pub add fl_chart

void main() {
  runApp(const MonitorApp());
}

class MonitorApp extends StatelessWidget {
  const MonitorApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Server Monitor',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
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
  String _gpu = "0";
  String _gpuTemp = "0"; //温度变量
  String _netUp = "0 KB/s"; //网速变量
  String _netDown = "0 KB/s";
  Map<String, dynamic>? _specs;

  // 历史数据
  final List<FlSpot> _cpuHistory = [];
  final List<FlSpot> _gpuHistory = [];
  final List<FlSpot> _ramHistory = [];
  final List<FlSpot> _netUpHistory = [];
  final List<FlSpot> _netDownHistory = [];
  double _timeCounter = 0;

  String _statusText = "初始化中...";
  Color _statusColor = Colors.orange;
  Timer? _timer;

  String _baseUrl = '';
  String _secretCode = '';
  bool _isAuthDialogShowing = false;
  int _bgIndex = 0;
  final ValueNotifier<int> _chartNotifier = ValueNotifier(0);
  // 🔥🔥🔥 这里的皮肤列表升级了！(共5款) 🔥🔥🔥
  final List<BoxDecoration> _backgrounds = [
    // 1. 深海蓝 (默认 - 沉稳)
    const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
      ),
    ),
    // 2. 赛博紫 (酷炫)
    const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2E0249), Color(0xFF570A57), Color(0xFFA91079)],
      ),
    ),
    // 3. 黑客绿 (极客)
    const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF000000), Color(0xFF0F3D0F)],
      ),
    ),
    // 4. 梦幻极光 (找回来的！颜值担当)
    const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3A1C71), Color(0xFFD76D77), Color(0xFFFFAF7B)],
      ),
    ),
    // 5. 🎁 赔礼赠送：火星救援 (热烈)
    const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF8E0E00), Color(0xFF1F1C18)],
      ),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) => _fetchStatus(),
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _baseUrl = prefs.getString('server_ip') ?? '';
      _secretCode = prefs.getString('secret_code') ?? '';
      _bgIndex = prefs.getInt('bg_index') ?? 0;
    });
    if (_baseUrl.isEmpty || _secretCode.isEmpty) {
      Future.delayed(
        const Duration(milliseconds: 500),
        () => _showAuthDialog(isForce: true),
      );
    } else {
      _fetchSpecs();
    }
  }

  void _changeBackground() async {
    setState(() => _bgIndex = (_bgIndex + 1) % _backgrounds.length);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('bg_index', _bgIndex);
  }

  Future<void> _disconnectAndClear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('server_ip');
    await prefs.remove('secret_code');
    setState(() {
      _baseUrl = '';
      _secretCode = '';
      _specs = null;
      _statusText = "未连接";
      _statusColor = Colors.grey;
      _cpu = "0";
      _ram = "0";
      _gpu = "0";
      _gpuTemp = "0";
      _cpuHistory.clear();
      _gpuHistory.clear();
      _ramHistory.clear();
      _timeCounter = 0;
    });
    if (mounted) {
      Navigator.pop(context);
      Future.delayed(
        const Duration(milliseconds: 500),
        () => _showAuthDialog(isForce: true),
      );
    }
  }

  Future<void> _fetchSpecs() async {
    if (_baseUrl.isEmpty) return;
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/specs'),
            headers: {'X-Secret-Code': _secretCode},
          )
          .timeout(const Duration(seconds: 7));
      if (response.statusCode == 200)
        setState(() {
          _specs = jsonDecode(response.body);
        });
    } catch (e) {
      print("配置获取失败");
    }
  }

  // 🔥🔥🔥 新增：发送电源指令的函数 🔥🔥🔥
  Future<void> _sendPowerCommand(String action, String title) async {
    // 1. 先弹窗确认，防止手滑
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text("确认$title？", style: const TextStyle(color: Colors.white)),
        content: Text(
          "确定要远程$title电脑吗？",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("取消"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: action == 'shutdown'
                  ? Colors.red
                  : Colors.orange,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("确定"),
          ),
        ],
      ),
    );

    // 2. 发送请求
    if (confirm == true) {
      try {
        final response = await http.post(
          Uri.parse('$_baseUrl/power'), // 刚才 Python 加的接口
          headers: {
            'X-Secret-Code': _secretCode,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'action': action}),
        );
        if (response.statusCode == 200 && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("✅ 指令已发送: $title")));
        }
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("❌ 发送失败")));
      }
    }
  }

  // 🔥🔥🔥 新增：画圆形按钮的小工具 🔥🔥🔥
  Widget _buildPowerBtn(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Icon(icon, color: color, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

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
        final data = jsonDecode(response.body);
        double cpuVal = double.parse((data['cpu'] ?? 0).toString());
        double ramVal = double.parse((data['ram'] ?? 0).toString());
        double gpuVal = double.parse((data['gpu'] ?? 0).toString());
        double tempVal = double.parse(
          (data['gpu_temp'] ?? 0).toString(),
        ); // 获取温度

        setState(() {
          _cpu = cpuVal.toStringAsFixed(1);
          _ram = ramVal.toStringAsFixed(1);
          _gpu = gpuVal.toStringAsFixed(1);
          _gpuTemp = tempVal > 0
              ? "${tempVal.toStringAsFixed(0)}°C"
              : ""; // 只有大于0才显示
          _statusText = "🟢 实时监控中";
          _statusColor = Colors.greenAccent;

          double upBytes = double.parse((data['net_up'] ?? 0).toString());
          double downBytes = double.parse((data['net_down'] ?? 0).toString());
          // 辅助小函数：把数字变成 KB/s 或 MB/s
          String formatSpeed(double bytes) {
            if (bytes > 1024 * 1024) {
              return "${(bytes / 1024 / 1024).toStringAsFixed(1)} MB/s";
            } else {
              return "${(bytes / 1024).toStringAsFixed(1)} KB/s";
            }
          }

          _netUp = formatSpeed(upBytes);
          _netDown = formatSpeed(downBytes);
          if (_netUpHistory.length > 60) _netUpHistory.removeAt(0);
          _netUpHistory.add(FlSpot(_timeCounter, upBytes / 1024)); // 存 KB/s

          if (_netDownHistory.length > 60) _netDownHistory.removeAt(0);
          _netDownHistory.add(FlSpot(_timeCounter, downBytes / 1024));

          _timeCounter++;
          if (_cpuHistory.length > 60) _cpuHistory.removeAt(0);
          _cpuHistory.add(FlSpot(_timeCounter, cpuVal));
          if (_gpuHistory.length > 60) _gpuHistory.removeAt(0);
          _gpuHistory.add(FlSpot(_timeCounter, gpuVal));
          if (_ramHistory.length > 60) _ramHistory.removeAt(0);
          _ramHistory.add(FlSpot(_timeCounter, ramVal));
          _chartNotifier.value++;
        });
        if (_specs == null) _fetchSpecs();
      } else if (response.statusCode == 401) {
        setState(() {
          _statusText = "🔒 验证失败";
          _statusColor = Colors.red;
        });
        if (!_isAuthDialogShowing) _showAuthDialog(errorMessage: "❌ 配对码错误");
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _statusText = "🔴 断开连接";
          _statusColor = Colors.grey;
        });
    }
  }

  // 🔥 修复版：支持实时动态刷新的折线图
  // 🔥 最终增强版：支持自定义单位（比如 KB/s）
  // 🔥 最终智能版：自动在 KB/s 和 MB/s 之间切换显示
  void _showChartSheet(
    String title,
    List<FlSpot> data,
    Color color, {
    String unit = "%",
  }) {
    HapticFeedback.lightImpact();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return ValueListenableBuilder<int>(
          valueListenable: _chartNotifier,
          builder: (context, value, child) {
            // 1. 先算出原始数值 (KB)
            double maxValRaw = data.isNotEmpty
                ? data.map((e) => e.y).reduce((a, b) => a > b ? a : b)
                : 0;
            double currentValRaw = data.isNotEmpty ? data.last.y : 0;

            // 2. 🔥 智能判断：如果要显示的是网速(KB/s)，且数值超过了 1000，就自动转成 MB/s
            String displayCurrent = "";
            String displayMax = "";
            String displayUnit = unit;

            if (unit == "KB/s" && maxValRaw > 1000) {
              // 超过 1000 KB，启动 MB 模式
              displayUnit = "MB/s";
              displayCurrent = (currentValRaw / 1024).toStringAsFixed(
                2,
              ); // 保留2位小数
              displayMax = (maxValRaw / 1024).toStringAsFixed(2);
            } else {
              // 还是 KB 模式
              displayCurrent = currentValRaw.toStringAsFixed(1);
              displayMax = maxValRaw.toStringAsFixed(1);
            }

            return Padding(
              padding: const EdgeInsets.all(25),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "$title 趋势",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // 显示智能转换后的数值
                      Text(
                        "$displayCurrent $displayUnit",
                        style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "MAX: $displayMax $displayUnit",
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    height: 200,
                    child: LineChart(
                      LineChartData(
                        // 图表本身依然使用原始数据(KB)绘制，这样波形才连贯
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (value) =>
                              FlLine(color: Colors.white10, strokeWidth: 1),
                        ),
                        titlesData: FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        minX: data.isNotEmpty
                            ? (data.last.x - 60 > 0 ? data.last.x - 60 : 0)
                            : 0,
                        maxX: data.isNotEmpty ? data.last.x : 60,
                        minY: 0,
                        lineBarsData: [
                          LineChartBarData(
                            spots: data,
                            isCurved: true,
                            color: color,
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: color.withOpacity(0.2),
                            ),
                          ),
                        ],
                      ),
                      duration: Duration.zero,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _autoDiscoverServer(String inputCode) async {
    setState(() {
      _statusText = "🔍 搜索中...";
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
            if (_isAuthDialogShowing && mounted) Navigator.pop(context);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text("✅ 连接成功")));
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
    });
    _fetchSpecs();
  }

  void _showAuthDialog({bool isForce = false, String? errorMessage}) {
    _isAuthDialogShowing = true;
    final codeCtrl = TextEditingController(text: _secretCode);
    final ipCtrl = TextEditingController(
      text: _baseUrl.replaceAll('http://', '').replaceAll(':5000', ''),
    );

    showDialog(
      context: context,
      barrierDismissible: !isForce,
      builder: (context) => WillPopScope(
        onWillPop: () async => !isForce,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text("🔗 连接电脑", style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (errorMessage != null)
                Text(errorMessage, style: const TextStyle(color: Colors.red)),
              TextField(
                controller: codeCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "配对码",
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              TextField(
                controller: ipCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "IP (可选)",
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
          actions: [
            if (_baseUrl.isNotEmpty)
              TextButton(
                onPressed: _disconnectAndClear,
                child: const Text(
                  "重置",
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ElevatedButton(
              onPressed: () {
                if (codeCtrl.text.isEmpty) return;
                ipCtrl.text.isNotEmpty
                    ? _saveSettings(
                        ipCtrl.text,
                        codeCtrl.text,
                      ).then((_) => Navigator.pop(context))
                    : _autoDiscoverServer(codeCtrl.text);
              },
              child: const Text("连接"),
            ),
          ],
          actionsAlignment: MainAxisAlignment.spaceBetween,
        ),
      ),
    ).then((_) => _isAuthDialogShowing = false);
  }

  void _openTaskManager() {
    if (_baseUrl.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("请先连接")));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            TaskManagerScreen(baseUrl: _baseUrl, secretCode: _secretCode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _backgrounds[_bgIndex],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Server Monitor'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.palette_outlined, color: Colors.white),
              onPressed: _changeBackground,
            ),
            IconButton(
              icon: const Icon(Icons.list_alt, color: Colors.blueAccent),
              onPressed: _openTaskManager,
            ),
            IconButton(
              icon: const Icon(Icons.link, color: Colors.white),
              onPressed: () => _showAuthDialog(),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _statusColor),
                      ),
                      child: Text(
                        _statusText,
                        style: TextStyle(
                          color: _statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // 1. CPU (没有副标题，传空字符串)
                    _buildGauge(
                      "CPU 负载",
                      "$_cpu%",
                      "",
                      Colors.blueAccent,
                      Icons.memory,
                      () => _showChartSheet(
                        "CPU",
                        _cpuHistory,
                        Colors.blueAccent,
                      ),
                    ),

                    const SizedBox(height: 15), // 间距可以稍微缩小一点
                    // 2. GPU (把温度传进去)
                    _buildGauge(
                      "GPU 显卡",
                      "$_gpu%",
                      _gpuTemp,
                      Colors.orangeAccent,
                      Icons.videogame_asset,
                      () => _showChartSheet(
                        "GPU",
                        _gpuHistory,
                        Colors.orangeAccent,
                      ),
                    ),

                    const SizedBox(height: 15),
                    // 3. 内存 (传空字符串，或者你可以显示具体用了多少GB)
                    _buildGauge(
                      "内存占用",
                      "$_ram%",
                      "",
                      Colors.purpleAccent,
                      Icons.storage,
                      () => _showChartSheet(
                        "内存",
                        _ramHistory,
                        Colors.purpleAccent,
                      ),
                    ),

                    const SizedBox(height: 15),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          // --- 左边：下载速度 (点了会弹窗) ---
                          Expanded(
                            child: InkWell(
                              // 点击时弹出绿色波形图，单位显示 KB/s
                              onTap: () => _showChartSheet(
                                "下载速度",
                                _netDownHistory,
                                Colors.greenAccent,
                                unit: "KB/s",
                              ),
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(20),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(
                                          Icons.download,
                                          color: Colors.greenAccent,
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          "下载",
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      _netDown,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // --- 中间：竖线分隔符 ---
                          Container(
                            width: 1,
                            height: 40,
                            color: Colors.white10,
                          ),

                          // --- 右边：上传速度 (点了会弹窗) ---
                          Expanded(
                            child: InkWell(
                              // 点击时弹出蓝色波形图
                              onTap: () => _showChartSheet(
                                "上传速度",
                                _netUpHistory,
                                Colors.blueAccent,
                                unit: "KB/s",
                              ),
                              borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(20),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(
                                          Icons.upload,
                                          color: Colors.blueAccent,
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          "上传",
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      _netUp,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),
                    if (_baseUrl.isNotEmpty) ...[
                      const Text(
                        "远程控制",
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildPowerBtn(
                            Icons.lock,
                            "锁定",
                            Colors.blueGrey,
                            () => _sendPowerCommand('lock', '锁定'),
                          ),
                          _buildPowerBtn(
                            Icons.restart_alt,
                            "重启",
                            Colors.orange,
                            () => _sendPowerCommand('restart', '重启'),
                          ),
                          _buildPowerBtn(
                            Icons.power_settings_new,
                            "关机",
                            Colors.red,
                            () => _sendPowerCommand('shutdown', '关机'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: InkWell(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.black87,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      builder: (context) => DraggableScrollableSheet(
                        initialChildSize: 0.5,
                        minChildSize: 0.3,
                        maxChildSize: 0.9,
                        expand: false,
                        builder: (ctx, scroll) => SingleChildScrollView(
                          controller: scroll,
                          padding: const EdgeInsets.all(25),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "💻 硬件配置",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 20),
                              if (_specs != null) ...[
                                _row(Icons.window, "系统", _specs!['os']),
                                _row(Icons.memory, "CPU", _specs!['cpu']),
                                _row(
                                  Icons.videogame_asset,
                                  "GPU",
                                  _specs!['gpu'],
                                ),
                                _row(Icons.storage, "RAM", _specs!['ram']),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.computer, color: Colors.white70),
                        SizedBox(width: 10),
                        Text(
                          "查看电脑配置",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ), // 🔥 已修复文字过长
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(label, style: const TextStyle(color: Colors.white54)),
      subtitle: Text(value, style: const TextStyle(color: Colors.white)),
    );
  }

  // 🔥 核心修改：增加了 temp 参数
  // 🔥 修复版：完美治愈强迫症的布局
  // 🔥 强迫症福音版：数值绝对居中，两边对称
  // 🔥 最终版：回归经典布局 (两端对齐)，温度乖乖呆在数值下面
  // 🔥 最终修正版：温度显示在左侧标题 ("GPU 显卡") 的正下方
  Widget _buildGauge(
    String label,
    String value,
    String subValue,
    Color color,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween, // 左右两端对齐
          children: [
            // --- 左边区域：图标 + [标题 & 温度] ---
            Row(
              children: [
                // 1. 圆形图标
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 15), // 图标和文字的间距
                // 2. 标题和温度 (竖着排，靠左对齐)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start, // 🔥 关键：文字靠左对齐
                  children: [
                    Text(
                      label, // "GPU 显卡"
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // 如果有温度，显示在标题下面
                    if (subValue.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subValue, // "56°C"
                          style: TextStyle(
                            color: color.withOpacity(0.8), // 颜色淡一点，和图标同色系
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // --- 右边区域：纯净的数值 + 折线图图标 ---
            Row(
              children: [
                Text(
                  value, // "5.0%"
                  style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.show_chart, color: Colors.white12, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 任务管理器部分保持不变，放在文件最下方
// 🔥 完整修复版：任务管理器 (包含类型转换修复 + 确认弹窗)
// --- 任务管理器 (带彩色首字母图标) ---
// --- 任务管理器 (丝滑流畅版) ---
class TaskManagerScreen extends StatefulWidget {
  final String baseUrl;
  final String secretCode;
  const TaskManagerScreen({
    super.key,
    required this.baseUrl,
    required this.secretCode,
  });

  @override
  State<TaskManagerScreen> createState() => _TaskManagerScreenState();
}

class _TaskManagerScreenState extends State<TaskManagerScreen> {
  List<dynamic> _processes = [];
  bool _isFirstLoad = true; // 🔥 优化1：区分是否是第一次加载

  // 🔥 优化2：把颜色列表提出来变成静态常量，避免重复创建，极大节省内存
  static const List<Color> _iconColors = [
    Colors.blueAccent,
    Colors.orangeAccent,
    Colors.purpleAccent,
    Colors.greenAccent,
    Colors.redAccent,
    Colors.tealAccent,
    Colors.pinkAccent,
    Colors.amberAccent,
    Colors.indigoAccent,
    Colors.cyanAccent,
    Colors.limeAccent,
    Colors.deepOrangeAccent,
  ];

  @override
  void initState() {
    super.initState();
    _fetchProcesses();
  }

  Future<void> _fetchProcesses() async {
    // 只有第一次进来才转圈，后面刷新时不转圈，避免闪烁
    if (_isFirstLoad) {
      setState(() => _isFirstLoad = true);
    }

    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/processes'),
        headers: {'X-Secret-Code': widget.secretCode},
      );
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _processes = jsonDecode(response.body);
            _isFirstLoad = false; // 加载完了一次，以后就不显示大转圈了
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isFirstLoad = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("获取进程列表失败，请检查网络")));
      }
    }
  }

  Future<void> _killProcess(int pid, String name) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("⚠️ 警告", style: TextStyle(color: Colors.redAccent)),
        content: Text(
          "确定要强制结束 '$name' (PID: $pid) 吗？\n未保存的数据将会丢失。",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("取消"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("强制结束"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final response = await http.post(
          Uri.parse('${widget.baseUrl}/kill'),
          headers: {
            'X-Secret-Code': widget.secretCode,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'pid': pid}),
        );

        if (response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text("已结束进程: $name")));
          }
          _fetchProcesses(); // 杀完自动刷新
        } else {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text("操作失败")));
          }
        }
      } catch (e) {
        /* ignore */
      }
    }
  }

  // 🔥 优化3：极其轻量的图标生成函数
  Widget _buildAppIcon(String processName) {
    String letter = processName.isNotEmpty ? processName[0].toUpperCase() : "?";

    // 使用哈希算法快速决定颜色，不再重复创建数组
    final int hash = processName.codeUnits.fold(0, (p, c) => p + c);
    final Color bgColor = _iconColors[hash % _iconColors.length];

    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor.withOpacity(0.15), // 背景更通透一点
        shape: BoxShape.circle,
        border: Border.all(color: bgColor.withOpacity(0.3), width: 1),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: bgColor,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text("任务管理器", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        // 🔥 优化4：右上角还是保留刷新按钮，给喜欢点按钮的人用
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () {
              // 点击时给个震动反馈，体验更好
              HapticFeedback.lightImpact();
              _fetchProcesses();
            },
          ),
        ],
      ),
      // 🔥 优化5：加入 RefreshIndicator，实现“下拉刷新”
      body: _isFirstLoad
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchProcesses, // 下拉时触发刷新
              color: Colors.blueAccent,
              backgroundColor: const Color(0xFF1E293B),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(), // 保证即使列表很短也能下拉
                itemCount: _processes.length,
                // itemExtent: 72, // 如果卡顿依然严重，解开这行注释（强制固定高度），性能会拉满
                itemBuilder: (context, index) {
                  final p = _processes[index];
                  final memPercent = (p['memory_percent'] as num).toDouble();
                  final String name = p['name'];

                  return Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04), // 背景稍微淡一点，减少渲染压力
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 5,
                      ),
                      leading: _buildAppIcon(name),
                      title: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            // 内存条
                            SizedBox(
                              width: 60,
                              child: LinearProgressIndicator(
                                value: memPercent / 100, // 假设最大100%
                                backgroundColor: Colors.white10,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  memPercent > 50
                                      ? Colors.redAccent
                                      : Colors.blueAccent,
                                ),
                                minHeight: 4,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              "${memPercent.toStringAsFixed(1)}%",
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.power_settings_new,
                          color: Colors.redAccent,
                          size: 22,
                        ),
                        onPressed: () => _killProcess(p['pid'], p['name']),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
