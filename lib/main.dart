import  dart:async ;
import  dart:io ;

import  package:flutter/material.dart ;
import  package:flutter_inappwebview/flutter_inappwebview.dart ;
import  package:file_picker/file_picker.dart ;
import  package:video_player/video_player.dart ;
import  package:chewie/chewie.dart ;

import  services/network_service.dart ;
import  services/cast_service.dart ;

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
      title:  كاست ماستر برو ,
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

  // كشف الفيديوهات من الـWebView
  final Set<String> _detectedVideos = <String>{};

  // WebView controller
  InAppWebViewController? _webViewController;
  String _currentUrl =  https://www.youtube.com ;

  // مشغل الفيديو
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isPlayerInitialized = false;

  // خدمات الشبكة والكاست
  final NetworkService _networkService = NetworkService();
  final CastService _castService = CastService();

  final List<Map<String, String>> _discoveredDevices = [];
  bool _isScanning = false;

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  // ملف محلي أو رابط
  Future<void> _pickLocalFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null && result.files.single.path != null) {
      await _playVideoInternally(result.files.single.path!);
    }
  }

  Future<void> _playVideoInternally(String url) async {
    setState(() {
      _isPlayerInitialized = false;
    });

    await _videoPlayerController?.pause();
    await _videoPlayerController?.dispose();
    _chewieController?.dispose();

    if (url.startsWith( http )) {
      _videoPlayerController = VideoPlayerController.network(url);
    } else {
      _videoPlayerController = VideoPlayerController.file(File(url));
    }

    await _videoPlayerController!.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: false,
      allowMuting: true,
    );

    setState(() {
      _isPlayerInitialized = true;
    });
  }

  // استدعاء خدمة المسح الشبكي
  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _discoveredDevices.clear();
    });

    final devices = await _networkService.discoverDevices(timeout: const Duration(seconds: 4));
    setState(() {
      _discoveredDevices.addAll(devices.map((d) => {
             name : d.friendlyName ?? d.location,
             ip : d.address,
             port : d.port?.toString() ??   ,
             location : d.location,
             controlUrl : d.controlUrl ??   ,
          }));
      _isScanning = false;
    });

    _showDeviceSelectionDialog();
  }

  void _showDeviceSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: _isScanning
            ? const Row(
                children: [
                  CircularProgressIndicator(color: Colors.amber),
                  SizedBox(width: 12),
                  Text( جاري المسح... ),
                ],
              )
            : const Text( الأجهزة المكتشفة ),
        content: SizedBox(
          width: double.maxFinite,
          child: _discoveredDevices.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                     لم يتم العثور على أي أجهزة. ,
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _discoveredDevices.length,
                  itemBuilder: (context, index) {
                    final d = _discoveredDevices[index];
                    return Card(
                      color: const Color(0xFF1E293B),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        leading: const Icon(Icons.connected_tv, color: Colors.amber),
                        title: Text(d[ name ] ??  غير معروف , style: const TextStyle(color: Colors.white)),
                        subtitle: Text( IP: ${d[ ip ]} | Port: ${d[ port ]} , style: const TextStyle(color: Colors.grey)),
                        onTap: () async {
                          Navigator.pop(context);
                          if (_detectedVideos.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text( قم بتشغيل فيديو أولاً )));
                            return;
                          }
                          final media = _detectedVideos.first;
                          final location = d[ location ]!;
                          // نفّذ إرسال DLNA عملي
                          final success = await _castService.castToDlna(location, d[ controlUrl ]!, media);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ?  تم الإرسال بنجاح  :  فشل الإرسال )));
                        },
                      ),
                    );
                  }),
        ),
      ),
    );
  }

  // حقن JS لاكتشاف روابط الفيديو
  Future<void> _injectSmartMediaSniffer() async {
    if (_webViewController == null) return;
    const js = r"""
(function(){
  try {
    var origOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      try {
        if (url && (url.indexOf( .mp4 ) !== -1 || url.indexOf( .m3u8 ) !== -1 || url.indexOf( .mpd ) !== -1 || url.indexOf( videoplayback ) !== -1)) {
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler( mediaSnifferHandler , url);
          }
        }
      } catch(e){}
      return origOpen.apply(this, arguments);
    };

    function scanTags(){
      try {
        var vids = document.getElementsByTagName( video );
        for(var i=0;i<vids.length;i++){
          try {
            if(vids[i].src) window.flutter_inappwebview.callHandler( mediaSnifferHandler , vids[i].src);
            var sources = vids[i].getElementsByTagName( source );
            for(var j=0;j<sources.length;j++){
              if(sources[j].src) window.flutter_inappwebview.callHandler( mediaSnifferHandler , sources[j].src);
            }
          } catch(e){}
        }
      } catch(e){}
    }
    setInterval(scanTags,2000);
    scanTags();
  } catch(e){}
})();
""";
    try {
      await _webViewController!.evaluateJavascript(source: js);
    } catch (_) {}
  }

  Widget _buildBrowserTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: const Color(0xFF1E293B),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText:  أدخل رابط أو ابحث... ,
                    prefixIcon: Icon(Icons.search),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (value) {
                    String url = value.trim();
                    if (!url.startsWith( http )) {
                      url =  https://www.google.com/search?q=${Uri.encodeComponent(value)} ;
                    }
                    _currentUrl = url;
                    _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _webViewController?.reload(),
              )
            ],
          ),
        ),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
            onWebViewCreated: (controller) {
              _webViewController = controller;
              _webViewController!.addJavaScriptHandler(handlerName:  mediaSnifferHandler , callback: (args) {
                if (args.isNotEmpty) {
                  final raw = args.first.toString();
                  if (raw.isNotEmpty) {
                    setState(() {
                      _detectedVideos.add(raw);
                    });
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text( تم اكتشاف فيديو: $raw ), duration: const Duration(seconds: 2)));
                  }
                }
              });
            },
            onLoadStop: (controller, url) async {
              await _injectSmartMediaSniffer();
            },
          ),
        ),
        if (_detectedVideos.isNotEmpty)
          Container(
            color: const Color(0xFF0B1220),
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(child: Text( الفيديوهات المكتشفة: ${_detectedVideos.length} , style: const TextStyle(color: Colors.white))),
                ElevatedButton.icon(
                  onPressed: () async {
                    final first = _detectedVideos.first;
                    await _playVideoInternally(first);
                    setState(() => _selectedIndex = 1);
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text( تشغيل ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _startScan,
                  icon: const Icon(Icons.cast),
                  label: const Text( مسح الأجهزة ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPlayerTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          if (_isPlayerInitialized && _chewieController != null)
            AspectRatio(
              aspectRatio: _videoPlayerController!.value.aspectRatio,
              child: Chewie(controller: _chewieController!),
            )
          else
            Container(
              height: 220,
              color: const Color(0xFF0B1220),
              child: const Center(child: Text( لا يوجد فيديو جارٍ التشغيل , style: TextStyle(color: Colors.white))),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(onPressed: _pickLocalFile, icon: const Icon(Icons.upload_file), label: const Text( اختر ملف )),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  if (_detectedVideos.isNotEmpty && _discoveredDevices.isNotEmpty) {
                    final device = _discoveredDevices.first;
                    final success = await _castService.castToDlna(device[ location ]!, device[ controlUrl ]!, _detectedVideos.first);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ?  تم الإرسال  :  فشل الإرسال )));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text( تأكد من اكتشاف جهاز وتشغيل فيديو )));
                  }
                },
                icon: const Icon(Icons.cast),
                label: const Text( إرسال ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                ListTile(title: const Text( الفيديوهات المكتشفة ), subtitle: Text(_detectedVideos.join( \n ))),
                const Divider(),
                ListTile(title: const Text( الأجهزة المكتشفة ), subtitle: Text(_discoveredDevices.map((d) =>  ${d[ name ]} (${d[ ip ]}:${d[ port ]}) ).join( \n ))),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [_buildBrowserTab(), _buildPlayerTab()];

    return Scaffold(
      appBar: AppBar(title: const Text( كاست ماستر برو ), backgroundColor: const Color(0xFF071126)),
      body: tabs[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        backgroundColor: const Color(0xFF0B1220),
        selectedItemColor: Colors.amber,
        unselectedItemColor: Colors.grey,
        onTap: (idx) => setState(() => _selectedIndex = idx),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.public), label:  متصفح ),
          BottomNavigationBarItem(icon: Icon(Icons.play_circle), label:  مشغل ),
        ],
      ),
    );
  }
}
