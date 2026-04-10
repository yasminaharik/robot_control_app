import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'services/api_service.dart';
import 'settings_screen.dart';

void main() {
  runApp(const RobotApp());
}

class RobotApp extends StatelessWidget {
  const RobotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartFetchBot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00FF88),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
      ),
      home: const RobotControlPage(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Joystick widget
// ─────────────────────────────────────────────────────────────────────────────
class Joystick extends StatefulWidget {
  final void Function(double x, double y) onMove;
  final void Function() onRelease;
  final double size;

  const Joystick({
    super.key,
    required this.onMove,
    required this.onRelease,
    this.size = 160,
  });

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  Offset _knobOffset = Offset.zero;

  double get _outerRadius => widget.size / 2;
  double get _knobRadius  => widget.size * 0.22;
  double get _maxDrag     => _outerRadius - _knobRadius;

  void _updateFromLocal(Offset local) {
    final center = Offset(_outerRadius, _outerRadius);
    var delta = local - center;
    if (delta.distance > _maxDrag) {
      delta = delta / delta.distance * _maxDrag;
    }
    setState(() => _knobOffset = delta);
    final x =  delta.dx / _maxDrag;
    final y = -delta.dy / _maxDrag;
    widget.onMove(x.clamp(-1.0, 1.0), y.clamp(-1.0, 1.0));
  }

  void _reset() {
    setState(() => _knobOffset = Offset.zero);
    widget.onRelease();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart:  (d) => _updateFromLocal(d.localPosition),
      onPanUpdate: (d) => _updateFromLocal(d.localPosition),
      onPanEnd:    (_) => _reset(),
      onPanCancel: _reset,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _JoystickPainter(
            knobOffset: _knobOffset,
            outerRadius: _outerRadius,
            knobRadius: _knobRadius,
          ),
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  final Offset knobOffset;
  final double outerRadius;
  final double knobRadius;

  _JoystickPainter({
    required this.knobOffset,
    required this.outerRadius,
    required this.knobRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(outerRadius, outerRadius);

    canvas.drawCircle(center, outerRadius,
        Paint()..color = const Color(0xFF1E1E2E));
    canvas.drawCircle(center, outerRadius,
        Paint()
          ..color = const Color(0xFF00FF88).withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    final line = Paint()
      ..color = const Color(0xFF00FF88).withOpacity(0.15)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(center.dx, center.dy - outerRadius + 8),
        Offset(center.dx, center.dy + outerRadius - 8), line);
    canvas.drawLine(Offset(center.dx - outerRadius + 8, center.dy),
        Offset(center.dx + outerRadius - 8, center.dy), line);

    final knobCenter = center + knobOffset;
    canvas.drawCircle(knobCenter, knobRadius + 6,
        Paint()..color = const Color(0xFF00FF88).withOpacity(0.15));
    canvas.drawCircle(knobCenter, knobRadius,
        Paint()..color = const Color(0xFF00FF88));
  }

  @override
  bool shouldRepaint(_JoystickPainter old) => old.knobOffset != knobOffset;
}

// ─────────────────────────────────────────────────────────────────────────────
// Main page
// ─────────────────────────────────────────────────────────────────────────────
class RobotControlPage extends StatefulWidget {
  const RobotControlPage({super.key});

  @override
  State<RobotControlPage> createState() => _RobotControlPageState();
}

class _RobotControlPageState extends State<RobotControlPage>
    with SingleTickerProviderStateMixin {

  BluetoothConnection? _connection;
  bool _isConnected = false;

  List<dynamic> _detections = [];
  Map<String, dynamic>? _selectedTarget;
  bool _cameraActive = false;

  Uint8List? _frameBytes;
  Timer? _frameTimer;
  Timer? _stateTimer;
  bool _fetchingFrame = false;
  bool _pollingState  = false;

  String _loadingMsg = "Waiting for first frame...";
  int _failedFrameAttempts = 0;

  Timer? _driveTimer;
  double _joystickX    = 0;
  double _joystickY    = 0;
  bool _joystickActive = false;
  bool _sendingDrive   = false;

  bool _autonomousMode = false;

  final GlobalKey _videoKey = GlobalKey();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _frameTimer = Timer.periodic(
        const Duration(milliseconds: 80), (_) => _fetchFrame());
    _stateTimer = Timer.periodic(
        const Duration(milliseconds: 600), (_) => _pollState());
    _driveTimer = Timer.periodic(
        const Duration(milliseconds: 100), (_) => _sendDrive());

    _fetchFrame();
    _pollState();
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _stateTimer?.cancel();
    _driveTimer?.cancel();
    _tabController.dispose();
    _connection?.dispose();
    ApiService.stopDrive();
    ApiService.setManualMode(false);
    super.dispose();
  }

  Future<void> _fetchFrame() async {
    if (_fetchingFrame) return;
    _fetchingFrame = true;
    try {
      final frameUrl = await ApiService.getFrameUrl();
      final response = await http
          .get(Uri.parse(frameUrl))
          .timeout(const Duration(milliseconds: 600));

      if (response.statusCode == 200 && mounted) {
        setState(() {
          _frameBytes = response.bodyBytes;
          _failedFrameAttempts = 0;
          _loadingMsg = "";
        });
        _frameTimer?.cancel();
        _frameTimer = Timer.periodic(
            const Duration(milliseconds: 150), (_) => _fetchFrame());
      } else if (response.statusCode == 404) {
        _failedFrameAttempts++;
        if (mounted) {
          setState(() => _loadingMsg = _failedFrameAttempts < 10
              ? "YOLO warming up..."
              : "Waiting for camera frame...");
        }
      }
    } catch (e) {
      _failedFrameAttempts++;
      if (mounted) {
        setState(() => _loadingMsg = "Connecting to backend...");
      }
    } finally {
      _fetchingFrame = false;
    }
  }

  Future<void> _pollState() async {
    if (_pollingState) return;
    _pollingState = true;
    try {
      final state = await ApiService.getState();
      if (!mounted) return;
      setState(() {
        _detections     = state["detections"]     ?? [];
        _selectedTarget = state["selected_target"];
        _cameraActive   = state["camera_active"]  ?? false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cameraActive = false);
    } finally {
      _pollingState = false;
    }
  }

  void _onJoystickMove(double x, double y) {
    _joystickX = x;
    _joystickY = y;
    _joystickActive = true;
  }

  void _onJoystickRelease() {
    _joystickX = 0;
    _joystickY = 0;
    _joystickActive = false;
    ApiService.stopDrive();
  }

  Future<void> _sendDrive() async {
    if (_sendingDrive || !_joystickActive || _autonomousMode) return;
    _sendingDrive = true;
    try {
      await ApiService.sendDrive(_joystickX, _joystickY);
    } catch (_) {
    } finally {
      _sendingDrive = false;
    }
  }

  Future<void> _onModeToggle(bool autonomous) async {
    setState(() => _autonomousMode = autonomous);
    if (autonomous) {
      await ApiService.stopDrive();
      await ApiService.setManualMode(false);
    } else {
      await ApiService.setManualMode(true);
    }
  }

  Future<void> _onVideoTap(TapUpDetails details) async {
    final box = _videoKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    const frameW = 640.0;
    const frameH = 480.0;
    final x = (details.localPosition.dx / size.width  * frameW).round();
    final y = (details.localPosition.dy / size.height * frameH).round();
    final result = await ApiService.selectTargetByPoint(x, y);
    if (!mounted) return;
    setState(() => _selectedTarget = result);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No object found there — tap on a bounding box"),
          duration: Duration(seconds: 1),
          backgroundColor: Color(0xFF1E1E2E),
        ),
      );
    }
  }

  Future<void> _connectToRobot() async {
    const address = "24:6F:28:AB:CD:EF"; // ⚠️ change to your ESP32 MAC
    try {
      final conn = await BluetoothConnection.toAddress(address);
      setState(() { _connection = conn; _isConnected = true; });
    } catch (_) {
      setState(() => _isConnected = false);
    }
  }

  void _onFetch() {
    if (_selectedTarget == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Select a target first!"),
          backgroundColor: Color(0xFF3B1E1E),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("🤖 Fetching ${_selectedTarget!["class_name"]}..."),
        backgroundColor: const Color(0xFF0F2E1A),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onStop() {
    _joystickX = 0;
    _joystickY = 0;
    _joystickActive = false;
    ApiService.stopDrive();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("🛑 Robot stopped"),
        backgroundColor: Color(0xFF3B1E1E),
        duration: Duration(seconds: 1),
      ),
    );
  }

  // ── open settings and restart polling when back ────────────────────────────
  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    // reset frame so it reconnects with new IP
    setState(() {
      _frameBytes = null;
      _failedFrameAttempts = 0;
      _loadingMsg = "Connecting to backend...";
    });
    _frameTimer?.cancel();
    _frameTimer = Timer.periodic(
        const Duration(milliseconds: 80), (_) => _fetchFrame());
    _fetchFrame();
    _pollState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        title: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 9, height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _cameraActive ? const Color(0xFF00FF88) : Colors.red,
                boxShadow: [BoxShadow(
                  color: (_cameraActive
                      ? const Color(0xFF00FF88) : Colors.red).withOpacity(0.6),
                  blurRadius: 6,
                )],
              ),
            ),
            const SizedBox(width: 8),
            const Text("SMARTFETCHBOT",
                style: TextStyle(
                  fontSize: 13, letterSpacing: 2,
                  color: Color(0xFF00FF88), fontFamily: 'monospace',
                )),
          ],
        ),
        actions: [
          Row(
            children: [
              Text(
                _autonomousMode ? "AUTO" : "MANUAL",
                style: TextStyle(
                  fontSize: 10, letterSpacing: 1,
                  color: _autonomousMode
                      ? const Color(0xFF00FF88) : Colors.grey,
                ),
              ),
              Switch(
                value: _autonomousMode,
                onChanged: _onModeToggle,
                activeColor: const Color(0xFF00FF88),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          GestureDetector(
            onTap: _isConnected ? null : _connectToRobot,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.bluetooth,
                  color: _isConnected
                      ? const Color(0xFF00FF88) : Colors.grey,
                  size: 22),
            ),
          ),
          // ── settings icon ────────────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey, size: 22),
            onPressed: _openSettings,
            tooltip: "Set backend IP",
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00FF88),
          labelColor: const Color(0xFF00FF88),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: "CAMERA"),
            Tab(text: "DETECTIONS"),
          ],
        ),
      ),

      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [

                // ── CAMERA TAB ─────────────────────────────────────────────
                Column(
                  children: [
                    GestureDetector(
                      onTapUp: _onVideoTap,
                      child: Container(
                        key: _videoKey,
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 240),
                        color: Colors.black,
                        child: _frameBytes == null
                            ? SizedBox(
                                height: 180,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const CircularProgressIndicator(
                                          color: Color(0xFF00FF88)),
                                      const SizedBox(height: 12),
                                      Text(_loadingMsg,
                                          style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12)),
                                      const SizedBox(height: 6),
                                      Text(
                                        "attempt $_failedFrameAttempts",
                                        style: const TextStyle(
                                            color: Color(0xFF333344),
                                            fontSize: 10),
                                      ),
                                      const SizedBox(height: 12),
                                      // quick link to settings if failing
                                      if (_failedFrameAttempts > 5)
                                        TextButton.icon(
                                          onPressed: _openSettings,
                                          icon: const Icon(Icons.settings,
                                              size: 14,
                                              color: Color(0xFF00FF88)),
                                          label: const Text(
                                            "Change IP",
                                            style: TextStyle(
                                                color: Color(0xFF00FF88),
                                                fontSize: 12),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              )
                            : Image.memory(
                                _frameBytes!,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              ),
                      ),
                    ),

                    Container(
                      color: const Color(0xFF0F0F1A),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: const Row(
                        children: [
                          Icon(Icons.touch_app, size: 11, color: Colors.grey),
                          SizedBox(width: 6),
                          Text("Tap the video to select a target",
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                    ),

                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: _selectedTarget == null
                          ? const SizedBox.shrink()
                          : Container(
                              width: double.infinity,
                              color: const Color(0xFF0A2E1A),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              child: Row(
                                children: [
                                  const Icon(Icons.my_location,
                                      size: 14, color: Color(0xFF00FF88)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "Target: ${_selectedTarget!["class_name"]}"
                                      "  · ID #${_selectedTarget!["track_id"] ?? "—"}"
                                      "  · ${((_selectedTarget!["confidence"] as num) * 100).toStringAsFixed(0)}%",
                                      style: const TextStyle(
                                        color: Color(0xFF00FF88),
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () async {
                                      await ApiService.clearTarget();
                                      setState(() => _selectedTarget = null);
                                    },
                                    child: const Icon(Icons.close,
                                        size: 15, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                    ),

                    const Spacer(),
                  ],
                ),

                // ── DETECTIONS TAB ─────────────────────────────────────────
                _detections.isEmpty
                    ? const Center(
                        child: Text("No objects detected",
                            style: TextStyle(color: Colors.grey)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _detections.length,
                        itemBuilder: (context, index) {
                          final obj = _detections[index];
                          final isSelected = _selectedTarget?["track_id"] ==
                              obj["track_id"];
                          return ListTile(
                            dense: true,
                            tileColor: isSelected
                                ? const Color(0xFF00FF88).withOpacity(0.08)
                                : null,
                            leading: Icon(Icons.radio_button_checked,
                                size: 12,
                                color: isSelected
                                    ? const Color(0xFF00FF88) : Colors.grey),
                            title: Text(obj["class_name"] ?? "unknown",
                                style: TextStyle(
                                  color: isSelected
                                      ? const Color(0xFF00FF88) : Colors.white,
                                  fontSize: 14,
                                )),
                            subtitle: Text(
                              "ID #${obj["track_id"] ?? "—"}  ·  "
                              "${((obj["confidence"] as num) * 100).toStringAsFixed(0)}%",
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 11),
                            ),
                            onTap: () async {
                              await ApiService.selectTarget(obj["track_id"]);
                              setState(() => _selectedTarget = obj);
                            },
                          );
                        },
                      ),
              ],
            ),
          ),

          // ── bottom controls ──────────────────────────────────────────────
          Container(
            color: const Color(0xFF0F0F1A),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: _autonomousMode

                // AUTO MODE
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _selectedTarget != null
                                ? const Color(0xFF00FF88)
                                : const Color(0xFF1E1E2E),
                            foregroundColor: _selectedTarget != null
                                ? Colors.black : Colors.grey,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _onFetch,
                          icon: const Icon(Icons.send, size: 18),
                          label: Text(
                            _selectedTarget != null
                                ? "FETCH  ${_selectedTarget!["class_name"].toString().toUpperCase()}"
                                : "SELECT A TARGET FIRST",
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B1E1E),
                            foregroundColor: Colors.redAccent,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _onStop,
                          icon: const Icon(Icons.stop_circle_outlined, size: 18),
                          label: const Text("STOP",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              )),
                        ),
                      ),
                    ],
                  )

                // MANUAL MODE
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Joystick(
                        size: 140,
                        onMove: _onJoystickMove,
                        onRelease: _onJoystickRelease,
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 110,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _selectedTarget != null
                                    ? const Color(0xFF00FF88)
                                    : const Color(0xFF1E1E2E),
                                foregroundColor: _selectedTarget != null
                                    ? Colors.black : Colors.grey,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _onFetch,
                              icon: const Icon(Icons.send, size: 16),
                              label: Text(
                                _selectedTarget != null
                                    ? "FETCH\n${_selectedTarget!["class_name"].toString().toUpperCase()}"
                                    : "SELECT\nTARGET",
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: 110,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3B1E1E),
                                foregroundColor: Colors.redAccent,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _onStop,
                              icon: const Icon(
                                  Icons.stop_circle_outlined, size: 16),
                              label: const Text("STOP",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  )),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
