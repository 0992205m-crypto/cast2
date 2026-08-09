import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
      title: 'Cast2 - Ultimate Web Video Caster',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MainDashboard(),
    );
  }
}

// ==========================================
// Main Dashboard with bottom navigation
// ==========================================
class MainDashboard extends StatefulWidget {
  const MainDashboard({Key? key}) : super(key: key);

  @override
  _MainDashboardState createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> _pages = [
      const Center(child: Text('شاشة المتصفح (Webview Browser)')),
      const Center(child: Text('شاشة المشغل (Video Player)')),
      const CastScreen(videoUrlToCast: 'https://googleapis.com'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('كاست ماستر برو', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF071126),
        centerTitle: true,
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.amber,
        unselectedItemColor: Colors.grey,
        onTap: (idx) {
          setState(() => _selectedIndex = idx);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.public), label: 'متصفح'),
          BottomNavigationBarItem(icon: Icon(Icons.play_circle), label: 'مشغل'),
          BottomNavigationBarItem(icon: Icon(Icons.cast_connected), label: 'بث حقيقي'),
        ],
      ),
    );
  }
}

// ==========================================
// DLNA Device model
// ==========================================
class DLNADevice {
  final String name;
  final String ip;
  final int port;
  final String controlUrl; // absolute control URL to send SOAP
  final String locationUrl; // device description URL

  DLNADevice({
    required this.name,
    required this.ip,
    required this.port,
    required this.controlUrl,
    required this.locationUrl,
  });

  @override
  String toString() => 'Device: $name ($ip:$port)';
}

// ==========================================
// DLNA Cast Service (SSDP discovery + SOAP play)
// ==========================================
class DLNACastService {
  final StreamController<List<DLNADevice>> _devicesController =
      StreamController<List<DLNADevice>>.broadcast();
  final List<DLNADevice> _discoveredDevices = [];
  RawDatagramSocket? _udpSocket;
  bool _scanning = false;

  Stream<List<DLNADevice>> get devicesStream => _devicesController.stream;

  Future<void> startScanning({Duration timeout = const Duration(seconds: 6)}) async {
    if (_scanning) return;
    _scanning = true;
    _discoveredDevices.clear();
    _devicesController.add(List.from(_discoveredDevices));

    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpSocket!.broadcastEnabled = true;

      const String mSearchQuery = 'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 2\r\n'
          'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
          '\r\n';

      final List<int> data = utf8.encode(mSearchQuery);
      final InternetAddress multicastAddr = InternetAddress('239.255.255.250');

      _udpSocket!.listen((RawSocketEvent event) async {
        if (event == RawSocketEvent.read) {
          final dg = _udpSocket!.receive();
          if (dg == null) return;
          final response = utf8.decode(dg.data);
          final senderIp = dg.address.address;
          await _handleSearchResponse(response, senderIp);
        }
      });

      // send a few times to increase chance of response
      for (int i = 0; i < 3; i++) {
        _udpSocket!.send(data, multicastAddr, 1900);
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // stop after timeout
      await Future.delayed(timeout);
    } catch (e) {
      debugPrint('Error during SSDP scan: $e');
    } finally {
      stopScanning();
    }
  }

  Future<void> _handleSearchResponse(String response, String deviceIp) async {
    try {
      final locMatch = RegExp(r'LOCATION:\s*(.*)', caseSensitive: false).firstMatch(response);
      if (locMatch == null) return;
      final locationUrl = locMatch.group(1)!.trim();
      if (locationUrl.isEmpty) return;
      if (_discoveredDevices.any((d) => d.locationUrl == locationUrl)) return;

      final uri = Uri.parse(locationUrl);
      final int realPort = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);

      late final http.Response httpResp;
      try {
        httpResp = await http.get(uri).timeout(const Duration(seconds: 4));
      } catch (_) {
        return;
      }
      if (httpResp.statusCode != 200) return;

      final body = httpResp.body;
      final friendly = _extractFriendlyName(body) ?? 'جهاز ريسيفر ذكي ($deviceIp)';
      final controlUrl = _extractControlUrl(body, locationUrl) ?? '';

      if (controlUrl.isEmpty) return;

      final device = DLNADevice(
        name: friendly,
        ip: deviceIp,
        port: realPort,
        controlUrl: controlUrl,
        locationUrl: locationUrl,
      );

      _discoveredDevices.add(device);
      _devicesController.add(List.from(_discoveredDevices));
    } catch (e) {
      debugPrint('Error handling response from $deviceIp: $e');
    }
  }

  void stopScanning() {
    try {
      _udpSocket?.close();
    } catch (_) {}
    _udpSocket = null;
    _scanning = false;
  }

  void dispose() {
    stopScanning();
    try {
      _devicesController.close();
    } catch (_) {}
  }

  String? _extractFriendlyName(String xml) {
    try {
      final m = RegExp(r'<friendlyName>([\s\S]*?)</friendlyName>', caseSensitive: false).firstMatch(xml);
      if (m != null) return m.group(1)!.trim();
    } catch (_) {}
    return null;
  }

  String? _extractControlUrl(String xml, String locationUrl) {
    try {
      // find the AVTransport service block
      final serviceMatches = RegExp(r'<service>([\s\S]*?)</service>', caseSensitive: false).allMatches(xml);
      for (final s in serviceMatches) {
        final block = s.group(1)!;
        if (block.toLowerCase().contains('avtransport')) {
          final cMatch = RegExp(r'<controlURL>([\s\S]*?)</controlURL>', caseSensitive: false).firstMatch(block);
          if (cMatch != null) {
            final controlSub = cMatch.group(1)!.trim();
            final base = Uri.parse(locationUrl);
            final resolved = base.resolve(controlSub).toString();
            return resolved;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  // send SetAVTransportURI then Play
  Future<bool> castVideo(DLNADevice device, String mediaUrl) async {
    try {
      final Uri controlUri = Uri.parse(device.controlUrl);

      final setEnvelope = '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" 
            s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <CurrentURI>${_xmlEscape(mediaUrl)}</CurrentURI>
      <CurrentURIMetaData></CurrentURIMetaData>
    </u:SetAVTransportURI>
  </s:Body>
</s:Envelope>
''';

      final playEnvelope = '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" 
            s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <Speed>1</Speed>
    </u:Play>
  </s:Body>
</s:Envelope>
''';

      final headersSet = {
        'Content-Type': 'text/xml; charset="utf-8"',
        'SOAPACTION': '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"',
      };

      final respSet = await http.post(controlUri, headers: headersSet, body: setEnvelope).timeout(const Duration(seconds: 6));
      if (respSet.statusCode < 200 || respSet.statusCode >= 300) {
        debugPrint('SetAVTransportURI failed: ${respSet.statusCode}');
        return false;
      }

      final headersPlay = {
        'Content-Type': 'text/xml; charset="utf-8"',
        'SOAPACTION': '"urn:schemas-upnp-org:service:AVTransport:1#Play"',
      };

      final respPlay = await http.post(controlUri, headers: headersPlay, body: playEnvelope).timeout(const Duration(seconds: 6));
      if (respPlay.statusCode < 200 || respPlay.statusCode >= 300) {
        debugPrint('Play failed: ${respPlay.statusCode}');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error casting video: $e');
      return false;
    }
  }

  String _xmlEscape(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

// ==========================================
// Simple CastScreen UI: enter URL, scan, list devices, cast
// ==========================================
class CastScreen extends StatefulWidget {
  final String videoUrlToCast;
  const CastScreen({Key? key, required this.videoUrlToCast}) : super(key: key);

  @override
  State<CastScreen> createState() => _CastScreenState();
}

class _CastScreenState extends State<CastScreen> {
  final DLNACastService _service = DLNACastService();
  final TextEditingController _urlController = TextEditingController();
  List<DLNADevice> _devices = [];
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.videoUrlToCast;
    _service.devicesStream.listen((list) {
      setState(() {
        _devices = list;
      });
    });
  }

  @override
  void dispose() {
    _service.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() => _scanning = true);
    await _service.startScanning();
    setState(() => _scanning = false);
  }

  Future<void> _castToDevice(DLNADevice device) async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل رابط الفيديو أولاً')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('جاري الإرسال...')));
    final success = await _service.castVideo(device, url);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ? 'تم الإرسال بنجاح' : 'فشل الإرسال')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'رابط الفيديو لإرساله',
              hintText: 'https://example.com/video.mp4',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _scanning ? null : _startScan,
                icon: const Icon(Icons.search),
                label: Text(_scanning ? 'يجري المسح...' : 'مسح الأجهزة'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _devices.isNotEmpty ? () => _castToDevice(_devices.first) : null,
                icon: const Icon(Icons.cast),
                label: const Text('إرسال لأول جهاز'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _devices.isEmpty
                ? const Center(child: Text('لم يتم العثور على أجهزة. اضغط مسح للبحث.'))
                : ListView.separated(
                    itemBuilder: (context, index) {
                      final d = _devices[index];
                      return ListTile(
                        leading: const Icon(Icons.connected_tv, color: Colors.amber),
                        title: Text(d.name),
                        subtitle: Text('${d.ip}:${d.port}\n${d.locationUrl}', style: const TextStyle(fontSize: 12)),
                        isThreeLine: true,
                        trailing: ElevatedButton(
                          onPressed: () => _castToDevice(d),
                          child: const Text('إرسال'),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const Divider(),
                    itemCount: _devices.length,
                  ),
          ),
        ],
      ),
    );
  }
