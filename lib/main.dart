import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UltimateCastApp());
}

class UltimateCastApp extends StatelessWidget {
  const UltimateCastApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'كاست ماستر برو',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
      ),
      home: const MainDashboard(),
    );
  }
}

class MainDashboard extends StatefulWidget {
  const MainDashboard({Key? key}) : super(key: key);

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _selectedIndex = 0;
  final Set<String> _detectedVideos = {};
  String _currentUrl = "https://youtube.com";
  InAppWebViewController? _webViewController;

  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isPlayerInitialized = false;

  final List<Map<String, String>> _discoveredDevices = [];
  bool _isScanning = false;

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  void _pickLocalFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null && result.files.single.path != null) {
      _playVideoInternally(result.files.single.path!);
    }
  }

  void _playVideoInternally(String url) async {
    setState(() { _isPlayerInitialized = false; });
    _videoPlayerController?.dispose();
    _chewieController?.dispose();

    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(url));
    await _videoPlayerController!.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
    );

    setState(() { _isPlayerInitialized = true; });
  }

  void _castToReceiverDLNA(String videoUrl, String ip, String port) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('جاري إرسال الفيديو للريسيفر... 📺')),
    );
  }

  Future<void> _autoDiscoverDeviceDetails(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 200));
      socket.destroy();

      String deviceName = "جهاز ذكي مجهول";
      
      try {
        final pathsToTry = ['/ssdp/device-desc.xml', '/description.xml', '/device.xml', '/setup/xml'];
        for (var path in pathsToTry) {
          final response = await http.get(Uri.parse('http://$ip:$port$path')).timeout(const Duration(milliseconds: 400));
          if (response.statusCode == 200 && response.body.contains('<friendlyName>')) {
            final match = RegExp(r'<friendlyName>(.*?)</friendlyName>').firstMatch(response.body);
            if (match != null && match.group(1) != null) {
              deviceName = match.group(1)!;
              break;
            }
          }
        }
        
        if (deviceName == "جهاز ذكي مجهول" && port == 8008) {
          final response = await http.get(Uri.parse('http://$ip:$port/setup/eureka_info')).timeout(const Duration(milliseconds: 400));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['name'] != null) deviceName = data['name'];
          }
        }
      } catch (_) {
        if (port == 23232) deviceName = "ريسيفر DLNA القياسي";
        if (port == 8008) deviceName = "جهاز Chromecast / Android TV";
        if (port == 8080 || port == 49152) deviceName = "شاشة ذكية UPnP";
      }

      if (mounted) {
        setState(() {
          bool alreadyExists = _discoveredDevices.any((d) => d['ip'] == ip && d['port'] == port.toString());
          if (!alreadyExists) {
            _discoveredDevices.add({
              'name': deviceName,
              'ip': ip,
              'port': port.toString(),
            });
          }
        });
      }
    } catch (_) {}
  }

  void _scanLocalNetworkForReceivers() async {
    setState(() {
      _isScanning = true;
      _discoveredDevices.clear();
    });

    String baseIp = "192.168.1";

    try {
      final interfaces = await NetworkInterface.list(includeLoopback: false, type: InternetAddressType.IPv4);
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        final ipParts = interfaces.first.addresses.first.address.split('.');
        if (ipParts.length == 4) {
          baseIp = "${ipParts[0]}.${ipParts[1]}.${ipParts[2]}";
        }
      }
    } catch (_) {}

    final List<Future> scanTasks = [];

    for (int i = 1; i <= 254; i++) {
      final targetIp = "$baseIp.$i";
      scanTasks.add(_autoDiscoverDeviceDetails(targetIp, 8080));
      scanTasks.add(_autoDiscoverDeviceDetails(targetIp, 23232));
      scanTasks.add(_autoDiscoverDeviceDetails(targetIp, 8008));
      scanTasks.add(_autoDiscoverDeviceDetails(targetIp, 49152));
    }

    await Future.wait(scanTasks);

    if (mounted) {
      setState(() { _isScanning = false; });
      _showDeviceSelectionDialog();
    }
  }

  void _showDeviceSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: _isScanning 
            ? const Row(
                children: [
                  CircularProgressIndicator(color: Colors.amber),
                  SizedBox(width: 15),
                  Text("جاري مسح الشبكة..."),
                ],
              )
            : const Text("الأجهزة الحقيقية المكتشفة 📡"),
        content: SizedBox(
          width: double.maxFinite,
          child: _discoveredDevices.isEmpty 
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text("لم يتم العثور على أي أجهزة كاست متصلة حالياً.", textAlign: TextAlign.center),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _discoveredDevices.length,
                  itemBuilder: (context, index) {
                    final device = _discoveredDevices[index];
                    return Card(
                      color: const Color(0xFF1E293B),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.connected_tv, color: Colors.amber, size: 30),
                        title: Text(device['name']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        subtitle: Text("IP: ${device['ip']} | Port: ${device['port']}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        onTap: () {
                          Navigator.pop(context);
                          if (_detectedVideos.isNotEmpty) {
                            _castToReceiverDLNA(_detectedVideos.first, device['ip']!, device['port']!);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('قم بتشغيل فيديو أولاً ليتم إرساله للشاشة')),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  // تم ضغط الكود هنا بالكامل في سطر واحد نقي لمنع مشاكل الأسطر المتعددة في المترجم
  void _injectSmartMediaSniffer() async {
    if (_webViewController == null) return;
    try {
      await _webViewController!.evaluateJavascript(source: "var origOpen=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(method,url){if(url&&(url.indexOf('.mp4')!==-1||url.indexOf('.m3u8')!==-1||url.indexOf('.mpd')!==-1||url.indexOf('videoplayback')!==-1)){window.flutter_inappwebview.callHandler('mediaSnifferHandler',url);}return origOpen.apply(this,arguments);};function scanTags(){var vids=document.getElementsByTagName('video');for(var i=0;i<vids.length;i++){if(vids[i].src)window.flutter_inappwebview.callHandler('mediaSnifferHandler',vids[i].src);var sources=vids[i].getElementsByTagName('source');for(var j=0;j<sources.length;j++){if(sources[j].src)window.flutter_inappwebview.callHandler('mediaSnifferHandler',sources[j].src);}}}setInterval(scanTags,2000);scanTags();");
    } catch (_) {}
  }

  Widget _buildBrowserTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: const Color(0xFF1E293B),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'أدخل رابط أو ابحث...',
              prefixIcon: Icon(Icons.search),
              border: InputBorder.none,
            ),
            onSubmitted: (value) {
              String url = value;
              if (!url.startsWith("http")) {
                url = "https://google.com";
              }
              _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
            },
          ),
        ),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
            onWebViewCreated: (controller) {
              _webViewController = controller;
              _webViewController!.addJavaScriptHandler(handlerName: 'mediaSnifferHandler', callback: (args) {
                if (args.isNotEmpty) {
                  String rawUrl = args.first.toString();
