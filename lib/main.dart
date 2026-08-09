import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
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
      home: const MainDashboard(), // تشغيل لوحة التحكم الرئيسية مباشرة
    );
  }
}

// ==========================================
// لوحة التحكم الرئيسية والملاحة السفلية (Dashboard)
// ==========================================
class MainDashboard extends StatefulWidget {
  const MainDashboard({Key? key}) : super(key: key);

  @override
  _MainDashboardState createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _selectedIndex = 0;

  // قائمة الصفحات الخاصة بتطبيقك (المتصفح، المشغل، البث)
  final List<Widget> _pages = [
    const Center(child: Text('شاشة المتصفح (Webview Browser)')), // استبدلها بكود المتصفح الخاص بك لاحقاً
    const Center(child: Text('شاشة المشغل (Video Player)')),     // استبدلها بكود المشغل الخاص بك لاحقاً
    const CastScreen(videoUrlToCast: 'https://googleapis.com'),
  ];

  @override
  Widget build(BuildContext context) {
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
          setState(() {
            _selectedIndex = idx;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.public), 
            label: 'متصفح',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.play_circle), 
            label: 'مشغل',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.cast_connected), 
            label: 'بث حقيقي',
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 1. مصفوفة بيانات الأجهزة المكتشفة الحقيقية
// ==========================================
class DLNADevice {
  final String name;
  final String ip;
  final int port;
  final String controlUrl;
  final String locationUrl;

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
// 2. خدمة اكتشاف الأجهزة الحقيقية والبث بالشبكة
// ==========================================
class DLNACastService {
  final StreamController<List<DLNADevice>> _devicesController = StreamController<List<DLNADevice>>.broadcast();
  final List<DLNADevice> _discoveredDevices = [];
  RawDatagramSocket? _udpSocket;

  Stream<List<DLNADevice>> get devicesStream => _devicesController.stream;

  Future<void> startScanning() async {
    _discoveredDevices.clear();
    _devicesController.add([]);

    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.multicastLoopback = false;

      final String mSearchQuery = 
          'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 3\r\n'
          'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n' 
          '\r\n';

      final List<int> dataToSend = utf8.encode(mSearchQuery);
      final InternetAddress multicastAddress = InternetAddress('239.255.255.250');

      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? packet = _udpSocket!.receive();
          if (packet != null) {
            String response = utf8.decode(packet.data);
            _handleSearchResponse(response, packet.address.address);
          }
        }
      });

      for (int i = 0; i < 3; i++) {
        _udpSocket!.send(dataToSend, multicastAddress, 1900);
        await Future.delayed(const Duration(milliseconds: 300));
      }

      Future.delayed(const Duration(seconds: 7), () => stopScanning());

    } catch (e) {
      debugPrint("خطأ أثناء البحث عن الأجهزة: $e");
    }
  }

  Future<void> _handleSearchResponse(String response, String deviceIp) async {
    if (!response.toUpperCase().contains('LOCATION:')) return;

    try {
      final lines = response.split('\r\n');
      String locationUrl = '';
      for (var line in lines) {
        if (line.toUpperCase().startsWith('LOCATION:')) {
          locationUrl = line.substring(9).trim();
          break;
        }
      }

      if (locationUrl.isEmpty) return;

      if (_discoveredDevices.any((d) => d.locationUrl == locationUrl)) return;

      Uri uri = Uri.parse(locationUrl);
      int realPort = uri.port;

      final httpResponse = await http.get(uri).timeout(const Duration(seconds: 4));
      if (httpResponse.statusCode == 200) {
        String xmlBody = httpResponse.body;
        String friendlyName = _extractFriendlyName(xmlBody);
        String controlUrl = _extractControlUrl(xmlBody, locationUrl);

        if (friendlyName.isEmpty) {
          friendlyName = "جهاز ريسيفر ذكي ($deviceIp)";
        }

        DLNADevice newDevice = DLNADevice(
          name: friendlyName,
          ip: deviceIp,
          port: realPort,
          controlUrl: controlUrl,
          locationUrl: locationUrl,
        );

        _discoveredDevices.add(newDevice);
        _devicesController.add(List.from(_discoveredDevices));
      }
    } catch (e) {
      debugPrint("خطأ أثناء معالجة بيانات جهاز $deviceIp: $e");
    }
  }

  void stopScanning() {
    _udpSocket?.close();
    _udpSocket = null;
  }

  String _extractFriendlyName(String xmlContent) {
    try {
      const startTag = '<friendlyName>';
      const endTag = '</friendlyName>';
      
      int startIndex = xmlContent.indexOf(startTag);
      if (startIndex != -1) {
        int endIndex = xmlContent.indexOf(endTag, startIndex + startTag.length);
        if (endIndex != -1) {
          return xmlContent.substring(startIndex + startTag.length, endIndex).trim();
        }
      }
    } catch (_) {}
    return '';
  }

  String _extractControlUrl(String xmlContent, String locationUrl) {
    try {
      const serviceTag = 'urn:schemas-upnp-org:service:AVTransport:1';
      const controlStartTag = '<controlURL>';
      const controlEndTag = '</controlURL>';

      int serviceIndex = xmlContent.indexOf(serviceTag);
      if (serviceIndex != -1) {
        int startIndex = xmlContent.indexOf(controlStartTag, serviceIndex);
        if (startIndex != -1) {
          int endIndex = xmlContent.indexOf(controlEndTag, startIndex + controlStartTag.length);
          if (endIndex != -1) {
            String controlSubUrl = xmlContent.substring(startIndex + controlStartTag.length, endIndex).trim();
            
            Uri baseUri = Uri.parse(locationUrl);
            if (controlSubUrl.startsWith('http')) {
              return controlSubUrl;
            } else {
              String path = controlSubUrl.startsWith('/') ? controlSubUrl : '/$controlSubUrl';
              return Uri(
                scheme: baseUri.scheme,
                host: baseUri.host,
                port: baseUri.port,
                path: path,
              ).toString();
            }
          }
        }
      }
    } catch (_) {}
    return '';
  }

  Future<bool> castVideo(DLNADevice device, String videoUrl) async {
    if (device.controlUrl.isEmpty) return false;

    final String soapActionSetUrl = '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"';
    final String soapBodySetUrl = 
        '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://xmlsoap.org" s:encodingStyle="http://xmlsoap.org">'
        '<s:Body>'
        '<u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
        '<InstanceID>0</InstanceID>'
        '<CurrentURI>$videoUrl</CurrentURI>'
        '<CurrentURIMetaData></CurrentURIMetaData>'
        '</u:SetAVTransportURI>'
        '</s:Body>'
        '</s:Envelope>';

    final String soapActionPlay = '"urn:schemas-upnp-org:service:AVTransport:1#Play"';
    final String soapBodyPlay = 
        '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://xmlsoap.org" s:encodingStyle="http://xmlsoap.org">'
        '<s:Body>'
        '<u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
        '<InstanceID>0</InstanceID>'
        '<Speed>1</Speed>'
        '</u:Play>'
        '</s:Body>'
        '</s:Envelope>';

    try {
      var responseSet = await http.post(
        Uri.parse(device.controlUrl),
        headers: {
          'Content-Type': 'text/xml; charset="utf-8"',
          'SOAPACTION': soapActionSetUrl,
        },
        body: soapBodySetUrl,
      ).timeout(const Duration(seconds: 6));

      if (responseSet.statusCode == 200 || responseSet.statusCode == 201) {
        var responsePlay = await http.post(
          Uri.parse(device.controlUrl),
          headers: {
            'Content-Type': 'text/xml; charset="utf-8"',
            'SOAPACTION': soapActionPlay,
          },
          body: soapBodyPlay,
        ).timeout(const Duration(seconds: 6));
