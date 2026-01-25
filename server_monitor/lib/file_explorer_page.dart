import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class FileExplorerPage extends StatefulWidget {
  final String serverUrl;
  final String secretCode;

  const FileExplorerPage(
      {super.key, required this.serverUrl, required this.secretCode});

  @override
  State<FileExplorerPage> createState() => _FileExplorerPageState();
}

class _FileExplorerPageState extends State<FileExplorerPage> {
  // 当前路径，空代表根目录（显示所有盘符）
  String currentPath = '';
  List<dynamic> files = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFiles(currentPath);
  }

  // 📡 请求文件列表
  Future<void> _fetchFiles(String path) async {
    setState(() => isLoading = true);
    try {
      final url = Uri.parse(
          '${widget.serverUrl}/files?path=${Uri.encodeComponent(path)}');
      final response =
          await http.get(url, headers: {'X-Secret-Code': widget.secretCode});
      if (response.statusCode == 200) {
        setState(() {
          files = jsonDecode(response.body);
          currentPath = path;
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  // ⬇️ 触发下载 (直接用手机浏览器或下载器打开，最稳定)
  // ⬇️ 触发下载 (把暗号通过 code 参数传给浏览器)
  void _downloadFile(String filePath) async {
    // 🔥 新增：在网址后面加上 &code=你的配对码
    final downloadUrl =
        '${widget.serverUrl}/download?path=${Uri.encodeComponent(filePath)}&code=${widget.secretCode}';

    final Uri url = Uri.parse(downloadUrl);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法启动下载')));
    }
  }

  // 🔙 返回上一级
  void _goBack() {
    if (currentPath.isEmpty) return; // 已经是根目录了
    // 简单的路径切割逻辑
    List<String> parts = currentPath.split(r'\');
    if (parts.length <= 1 || (parts.length == 2 && parts[1].isEmpty)) {
      _fetchFiles(''); // 回到根盘符
    } else {
      parts.removeLast();
      _fetchFiles(parts.join(r'\'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E293B),
      appBar: AppBar(
        backgroundColor: Colors.black45,
        title: Text(currentPath.isEmpty ? "我的电脑" : currentPath,
            style: const TextStyle(fontSize: 16)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (currentPath.isEmpty)
                Navigator.pop(context);
              else
                _goBack();
            }),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: files.length,
              itemBuilder: (context, index) {
                final item = files[index];
                final isDir = item['type'] == 'dir';

                return ListTile(
                  leading: Icon(
                    isDir ? Icons.folder : Icons.insert_drive_file,
                    color: isDir ? Colors.amber : Colors.blueAccent,
                    size: 36,
                  ),
                  title: Text(item['name'],
                      style: const TextStyle(color: Colors.white)),
                  subtitle: !isDir
                      ? Text(
                          '${(item['size'] / 1024 / 1024).toStringAsFixed(2)} MB',
                          style: const TextStyle(color: Colors.white54))
                      : null,
                  trailing: !isDir
                      ? IconButton(
                          icon: const Icon(Icons.download,
                              color: Colors.greenAccent),
                          onPressed: () => _downloadFile(item['path']),
                        )
                      : const Icon(Icons.chevron_right, color: Colors.white24),
                  onTap: () {
                    // 点击文件夹则进入，点击文件则下载
                    if (isDir) {
                      _fetchFiles(item['path']);
                    } else {
                      _downloadFile(item['path']);
                    }
                  },
                );
              },
            ),
    );
  }
}
