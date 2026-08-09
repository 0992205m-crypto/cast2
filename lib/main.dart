import 'package:flutter/material.dart';
import 'dlna_cast_service.dart'; // استدعاء ملف الخدمة الذي أنشأناه بالأعلى

class CastScreen extends StatefulWidget {
  final String videoUrlToCast; // رابط الفيديو المستخرج من المتصفح الخاص بك

  const CastScreen({Key? key, required this.videoUrlToCast}) : super(key: key);

  @override
  _CastScreenState createState() => _CastScreenState();
}

class _CastScreenState extends State<CastScreen> {
  final DLNACastService _castService = DLNACastService();
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _uiScanDevices(); // بدء البحث التلقائي عند فتح الشاشة
  }

  void _uiScanDevices() async {
    setState(() { _isScanning = true; });
    await _castService.startScanning();
    // ننتظر انتهاء المهلة المحددة في الخدمة (7 ثوانٍ) لتغيير حالة المؤشر
    await Future.delayed(Duration(seconds: 7));
    if (mounted) {
      setState(() { _isScanning = false; });
    }
  }

  @override
  void dispose() {
    _castService.stopScanning();
    _castService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('بث إلى التلفزيون / الريسيفر'),
        centerTitle: true,
        actions: [
          _isScanning
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _uiScanDevices,
                  tooltip: 'إعادة البحث عن أجهزة حقيقية',
                )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.blueGrey.shade50,
            width: double.infinity,
            child: Text(
              'رابط الفيديو الحالي:\n${widget.videoUrlToCast}',
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: StreamBuilder<List<DLNADevice>>(
              stream: _castService.devicesStream,
              initialData: const [],
              builder: (context, snapshot) {
                final devices = snapshot.data ?? [];

                if (devices.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.tv_off, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text(
                          'لم يتم العثور على أجهزة حقيقية بعد.',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'تأكد أن الريسيفر والهاتف متصلان بنفس شبكة الـ Wi-Fi',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      elevation: 2,
                      child: ListTile(
                        leading: const Icon(Icons.connected_tv, color: Colors.blue, size: 36),
                        title: Text(
                          device.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'IP: ${device.ip}  |  Port: ${device.port}',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                        ),
                        trailing: ElevatedButton.icon(
                          onPressed: () => _handleCastAction(device),
                          icon: const Icon(Icons.cast_connected, size: 18),
                          label: const Text('بث الآن'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _handleCastAction(DLNADevice device) async {
    // إظهار رسالة بدء الاتصال
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('جاري إرسال البث إلى ${device.name}...')),
    );

    bool success = await _castService.castVideo(device, widget.videoUrlToCast);

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم بدء البث بنجاح! تحقق من جهاز الريسيفر الخاص بك.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ فشل البث. تأكد من أن الريسيفر يدعم صيغة هذا الفيديو.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
