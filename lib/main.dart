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

  // مصفوفة لتخزين الأجهزة المكتشفة كأجسام تحتوي على الاسم، الآي بي، والبورت
  List<Map<String, String>> _discoveredDevices = [];
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
      SnackBar(content: Text('جاري إرسال الفيديو إلى الجهاز المستهدف عِبر [$ip:$port] 📺')),
    );
  }

  // محرك الفحص الأوتوماتيكي الذكي لجلب البيانات الوصفية والاسم الحقيقي للجهاز عِبر الـ IP والبورت
  Future<void> _autoDiscoverDeviceDetails(String ip, int port) async {
    try {
      // الاتصال الأولي بالـ Socket للتأكد من استجابة المنفذ
      final socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 200));
      socket.destroy();

      String deviceName = "جهاز ذكي مجهول";
      
      // محاولة أوتوماتيكية لقراءة ملفات التعريف (XML/JSON) الخاصة ببروتوكولات UPnP/DLNA/Chromecast
      try {
        final pathsToTry = ['/ssdp/device-desc.xml', '/description.xml', '/device.xml', '/setup/xml'];
        for (var path in pathsToTry) {
          final response = await http.get(Uri.parse('http://$ip:$port$path')).timeout(const Duration(milliseconds: 400));
          if (response.statusCode == 200 && response.body.contains('<friendlyName>')) {
            // استخراج الاسم الحقيقي للجهاز من ملف الـ XML التابع للشاشة أو الريسيفر
            final match = RegExp(r'<friendlyName>(.*?)</friendlyName>').firstMatch(response.body);
            if (match != null && match.group(1) != null) {
              deviceName = match.group(1)!;
              break;
            }
          }
        }
        
        // محاولة إضافية لأجهزة الكروم كاست وأندرويد تي في التي تبث عبر منافذ الـ JSON
        if (deviceName == "جهاز ذكي مجهول" && port == 8008) {
          final response = await http.get(Uri.parse('http://$ip:$port/setup/eureka_info')).timeout(const Duration(milliseconds: 400));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['name'] != null) deviceName = data['name'];
          }
        }
      } catch (_) {
        // تصنيف افتراضي ذكي بحسب رقم المنفذ المستجيب في حال تعذر جلب الاسم النصي
        if (port == 23232) deviceName = "ريسيفر DLNA القياسي";
        if (port == 8008) deviceName = "جهاز Chromecast / Android TV";
        if (port == 8080 || port == 49152) deviceName = "شاشة ذكية UPnP";
      }

      if (mounted) {
        setState(() {
          // منع تكرار نفس الجهاز في القائمة
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

  // دالة المسح الشامل المتوازي لجميع المنافذ المحتملة لأجهزة البث في الشبكة المحلية
  void _scanLocalNetworkForReceivers() async {
    setState(() {
      _isScanning = true;
      _discoveredDevices.clear();
    });

    String baseIp = "192.168.1";

    try {
      // كشف الآي بي الفرعي الفعلي للشبكة الحالية المتصل بها الهاتف أوتوماتيكيًا
      final interfaces = await NetworkInterface.list(includeLoopback: false, type: InternetAddressType.IPv4);
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        final ipParts = interfaces.first.addresses.first.address.split('.');
        if (ipParts.length == 4) {
          baseIp = "${ipParts[0]}.${ipParts[1]}.${ipParts[2]}";
        }
      }
    } catch (_) {}

    // قائمة بأشهر المنافذ (Ports) العالمية المستخدمة أوتوماتيكيًا في أنظمة DLNA, UPnP, Chromecast, Smart TVs
    final List<int> portsToScan =;
    List<Future> scanTasks = [];

    // إطلاق عملية فحص أوتوماتيكية مكثفة لجميع أجهزة الشبكة (1-254) عِبر كافة المنافذ بالتوازي لسرعة فائقة
    for (int i = 1; i <= 254; i++) {
      final targetIp = "$baseIp.$i";
      for (var port in portsToScan) {
        scanTasks.add(_autoDiscoverDeviceDetails(targetIp, port));
      }
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
                  Text("جاري مسح الشبكة أوتوماتيكيًا..."),
                ],
              )
            : const Text("الأجهزة الحقيقية المكتشفة 📡"),
        content: SizedBox(
          width: double.maxFinite,
          child: _discoveredDevices.isEmpty 
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text("لم يتم العثور على أي شاشات أو أجهزة كاست متصلة بالشبكة حالياً.", textAlign: TextAlign.center),
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
                        // إظهار عنوان الآي بي والبورت الحقيقي بشكل منظم ومقروء تحت الاسم مباشرة
                        subtitle: Text("IP: ${device['ip']}   |   Port: ${device['port']}", style: TextStyle(color: Colors.grey[400], fontSize: 12)),
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

  void _injectSmartMediaSniffer() async {
    if (_webViewController == null) return;
    String cleanJs = "var origOpen=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(method,url){if(url&&(url.includes('.mp4')||url.includes('.m3u8')||url.includes('.mpd')||url.includes('videoplayback'))){window.flutter_inappwebview.callHandler('mediaSnifferHandler',url);}return origOpen.apply(this,arguments);};function scanTags(){var vids=document.getElementsByTagName('video');for(var i=0;i<vids.length;i++){if(vids[i].src)window.flutter_inappwebview.callHandler('mediaSnifferHandler',vids[i].src);var sources=vids[i].getElementsByTagName('source');for(var j=0;j<sources.length;j++){if(sources[j].src)window.flutter_inappwebview.callHandler('mediaSnifferHandler',sources[j].src);}}}setInterval(scanTags,2000);scanTags();";
    try {
      await _webViewController!.evaluateJavascript(source: cleanJs);
    } catch (_) {}
  }

  Widget _buildBrowserTab() {
    return Column(
      children: [
        Container(
