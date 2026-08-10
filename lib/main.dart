// lib/main.dart
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
// DL](#)
