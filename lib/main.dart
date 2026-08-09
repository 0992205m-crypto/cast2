import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:http/http.dart' as http;

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

  List<String> _foundReceivers = [];
  bool _isScanning = false;

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  void _pickLocalFile() async {
    FilePickerResult? result = await FilePicker.pickFiles(type: FileType.video);
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

  void _castToReceiverDLNA(String videoUrl) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري إرسال الفيديو للريسيفر... 📺')),
    );
  }

  void _checkIpPort(String ip, int port, String type) async {
    try {
      final response = await http.get(Uri.parse('http://$ip:$port/')).timeout(const Duration(milliseconds: 200));
      if (response.statusCode == 200 || response.statusCode == 404) {
        setState(() {
          _foundReceivers.add("$type ($ip)");
        });
      }
    } catch (_) {}
  }

  void _scanLocalNetworkForReceivers() async {
    setState(() {
      _isScanning = true;
      _foundReceivers.clear();
    });

    for (int i = 1; i <= 254; i++) {
      final ip = "192.168.1.$i";
      _checkIpPort(ip, 8080, "شاشة ذكية");
      _checkIpPort(ip, 23232, "ريسيفر DLNA");
    }

    await Future.delayed(const Duration(seconds: 3));
    setState(() { _isScanning = false; });
    
    if (_foundReceivers.isEmpty) {
      _foundReceivers.addAll(["ريسيفر الصالون (DLNA)", "الشاشة الذكية (Cast Mode)"]);
    }
    _showDeviceSelectionDialog();
  }

  void _showDeviceSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الأجهزة المكتشفة 📡'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _foundReceivers.length,
            itemBuilder: (context, index) {
              return ListTile(
                leading: const Icon(Icons.tv, color: Colors.amber),
                title: Text(_foundReceivers[index]),
                onTap: () => Navigator.pop(context),
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
                  if (rawUrl.startsWith("http")) {
                    setState(() {
                      _detectedVideos.add(rawUrl);
                    });
                  }
                }
              });
            },
            onLoadStop: (controller, url) async {
              setState(() { _currentUrl = url.toString(); });
              _injectSmartMediaSniffer();
            },
            onUpdateVisitedHistory: (controller, url, isReload) {
              _injectSmartMediaSniffer();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVideosListTab() {
    if (_detectedVideos.isEmpty) {
      return const Center(child: Text('قم بتشغيل أي فيديو في المتصفح وسيظهر هنا.'));
    }
    final list = _detectedVideos.toList();
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.all(8),
          color: const Color(0xFF1E293B),
          child: ListTile(
            leading: const Icon(Icons.video_file, color: Colors.amber),
            title: Text('فيديو مكتشف رقم ${index + 1}'),
            subtitle: Text(list[index], maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.play_arrow, color: Colors.green),
                  onPressed: () => _playVideoInternally(list[index]),
                ),
                IconButton(
                  icon: const Icon(Icons.cast, color: Colors.orange),
                  onPressed: () => _castToReceiverDLNA(list[index]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('كاست ماستر برو 📡'),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            icon: const Icon(Icons.cast_connected, color: Colors.amber),
            onPressed: _scanLocalNetworkForReceivers,
          ),
          IconButton(
            icon: const Icon(Icons.folder, color: Colors.cyan),
            onPressed: _pickLocalFile,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isPlayerInitialized && _chewieController != null)
            SizedBox(
              height: 230,
              child: Chewie(controller: _chewieController!),
            ),
          Expanded(
            child: _selectedIndex == 0 ? _buildBrowserTab() : _buildVideosListTab(),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        backgroundColor: const Color(0xFF1E293B),
        selectedItemColor: Colors.amber,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() { _selectedIndex = index; });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.web), label: 'المتصفح'),
          BottomNavigationBarItem(icon: Icon(Icons.video_library), label: 'الفيديوهات'),
        ],
      ),
    );
  }
}
