import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
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
// Bounding box overlay painter
// ─────────────────────────────────────────────────────────────────────────────
class BoundingBoxPainter extends CustomPainter {
  final List<dynamic> detections;
  final Map<String, dynamic>? selectedTarget;
  final Size frameSize;

  BoundingBoxPainter({
    required this.detections,
    required this.selectedTarget,
    required this.frameSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    final scaleX = size.width  / frameSize.width;
    final scaleY = size.height / frameSize.height;

    for (final det in detections) {
      final box = det["box"];
      if (box == null || box.length != 4) continue;

      final x1 = (box[0] as num).toDouble() * scaleX;
      final y1 = (box[1] as num).toDouble() * scaleY;
      final x2 = (box[2] as num).toDouble() * scaleX;
      final y2 = (box[3] as num).toDouble() * scaleY;

      final isSelected = selectedTarget != null &&
          selectedTarget!["track_id"] == det["track_id"];

      final color = isSelected
          ? const Color(0xFF00FF88)
          : Colors.white.withOpacity(0.85);

      canvas.drawRect(
        Rect.fromLTRB(x1, y1, x2, y2),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 2.5 : 1.5,
      );

      final label =
          "${det["class_name"]} ${((det["confidence"] as num) * 100).toStringAsFixed(0)}%"
          "${det["track_id"] != null ? " #${det["track_id"]}" : ""}";

      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.black,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelBg = Rect.fromLTWH(
        x1, y1 - textPainter.height - 4,
        textPainter.width + 8, textPainter.height + 4,
      );

      canvas.drawRect(labelBg, Paint()..color = color);
      textPainter.paint(canvas, Offset(x1 + 4, y1 - textPainter.height - 2));
    }
  }

  @override
  bool shouldRepaint(BoundingBoxPainter old) =>
      old.detections != detections || old.selectedTarget != selectedTarget;
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

  // ── vision state ──────────────────────────────────────────────────────────
  List<dynamic> _detections = [];
  Map<String, dynamic>? _selectedTarget;
  bool _cameraActive = false;
  int? _frameWidth;
  int? _frameHeight;

  // ── autonomy state ────────────────────────────────────────────────────────
  bool _autonomyEnabled = false;
  String _autonomyStatus = "idle";
  String _missionPhase = "IDLE";

  Timer? _stateTimer;
  bool _pollingState = false;

  // ── WebRTC ────────────────────────────────────────────────────────────────
  RTCPeerConnection? _peerConnection;
  final RTCVideoRenderer _videoRenderer = RTCVideoRenderer();
  bool _webrtcConnected = false;
  bool _webrtcConnecting = false;
  String _webrtcStatus = "Connecting...";

  // ── joystick ───────────────────────────────────────────────────────────────
  Timer? _driveTimer;
  double _joystickX    = 0;
  double _joystickY    = 0;
  bool _joystickActive = false;
  bool _sendingDrive   = false;

  // ── mode ───────────────────────────────────────────────────────────────────
  bool _autonomousMode     = false;
  bool _manualModeEnabled  = false;
  bool _demoSequenceRunning = false;

  final GlobalKey _videoKey = GlobalKey();
  late TabController _tabController;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _videoRenderer.initialize();

    _stateTimer = Timer.periodic(
        const Duration(milliseconds: 200), (_) => _pollState());
    _driveTimer = Timer.periodic(
        const Duration(milliseconds: 100), (_) => _sendDrive());

    _pollState();
    _startWebRTC();
    _enableManualModeWithRetry();
  }

  @override
  void dispose() {
    _stateTimer?.cancel();
    _driveTimer?.cancel();
    _tabController.dispose();
    _stopWebRTC();
    _videoRenderer.dispose();
    ApiService.stopDrive();
    ApiService.setManualMode(false);
    super.dispose();
  }

  // ── manual mode retry ─────────────────────────────────────────────────────
  Future<void> _enableManualModeWithRetry() async {
    if (_autonomousMode) return;
    for (int attempt = 0; attempt < 10; attempt++) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || _autonomousMode) return;
      try {
        await ApiService.setManualMode(true);
        _manualModeEnabled = true;
        return;
      } catch (_) {}
    }
  }

  // ── WebRTC ────────────────────────────────────────────────────────────────
  Future<void> _startWebRTC() async {
    if (_webrtcConnecting || _webrtcConnected) return;
    setState(() {
      _webrtcConnecting = true;
      _webrtcStatus = "Connecting...";
    });

    try {
      final config = {
        'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]
      };

      _peerConnection = await createPeerConnection(config);

      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          setState(() {
            _videoRenderer.srcObject = event.streams[0];
            _webrtcConnected = true;
            _webrtcConnecting = false;
            _webrtcStatus = "Connected";
          });
        }
      };

      _peerConnection!.onIceConnectionState = (state) {
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          setState(() {
            _webrtcConnected = false;
            _webrtcStatus = "Disconnected";
          });
        }
      };

      await _peerConnection!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );

      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      final answer = await ApiService.sendWebRTCOffer(offer.sdp!, offer.type!);

      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type']),
      );
    } catch (e) {
      setState(() {
        _webrtcConnecting = false;
        _webrtcConnected = false;
        _webrtcStatus = "Failed — tap Retry";
      });
    }
  }

  Future<void> _stopWebRTC() async {
    await _peerConnection?.close();
    _peerConnection = null;
    _videoRenderer.srcObject = null;
  }

  Future<void> _retryWebRTC() async {
    await _stopWebRTC();
    setState(() {
      _webrtcConnected = false;
      _webrtcConnecting = false;
    });
    await _startWebRTC();
  }

  // ── poll state ─────────────────────────────────────────────────────────────
  Future<void> _pollState() async {
    if (_pollingState) return;
    _pollingState = true;
    try {
      final state = await ApiService.getState();
      if (!mounted) return;
      setState(() {
        _detections      = state["detections"]      ?? [];
        _selectedTarget  = state["selected_target"];
        _cameraActive    = state["camera_active"]   ?? false;
        _frameWidth      = state["frame_width"];
        _frameHeight     = state["frame_height"];
        _autonomyEnabled = state["autonomy_enabled"] ?? false;
        _autonomyStatus  = state["autonomy_status"]  ?? "idle";
        _missionPhase    = state["mission_phase"]    ?? "IDLE";
      });

      // poll demo sequence status to know when to unlock joystick
      try {
        final demoStatus = await ApiService.getDemoSequenceStatus();
        if (mounted) {
          setState(() {
            _demoSequenceRunning = demoStatus["running"] == true;
          });
        }
      } catch (_) {}

    } catch (_) {
      if (!mounted) return;
      setState(() => _cameraActive = false);
    } finally {
      _pollingState = false;
    }
  }

  // ── tap on video ───────────────────────────────────────────────────────────
  Future<void> _onVideoTap(TapUpDetails details) async {
    final box = _videoKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    final frameW = (_frameWidth  ?? 640).toDouble();
    final frameH = (_frameHeight ?? 480).toDouble();
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

  // ── joystick ───────────────────────────────────────────────────────────────
  void _onJoystickMove(double x, double y) {
    _joystickX = x; _joystickY = y; _joystickActive = true;
  }

  void _onJoystickRelease() {
    _joystickX = 0; _joystickY = 0; _joystickActive = false;
    ApiService.stopDrive();
  }

  Future<void> _sendDrive() async {
    if (_sendingDrive || _autonomousMode || _demoSequenceRunning) return;
    _sendingDrive = true;
    try {
      // make sure manual mode is enabled
      if (!_manualModeEnabled) {
        await ApiService.setManualMode(true);
        _manualModeEnabled = true;
      }
      if (_joystickActive) {
        // send actual joystick command
        await ApiService.sendDrive(_joystickX, _joystickY);
      } else {
        // send zero drive as keepalive so backend doesn't reset manual mode
        await ApiService.sendDrive(0, 0);
      }
    } catch (_) {
    } finally {
      _sendingDrive = false;
    }
  }

  // ── mode toggle ────────────────────────────────────────────────────────────
  Future<void> _onModeToggle(bool autonomous) async {
    setState(() => _autonomousMode = autonomous);
    if (autonomous) {
      await ApiService.stopDrive();
      await ApiService.setManualMode(false);
      _manualModeEnabled = false;
    } else {
      if (_autonomyEnabled) {
        await ApiService.stopAutonomy(reason: "switched to manual");
      }
      await ApiService.setManualMode(true);
      _manualModeEnabled = true;
    }
  }

  // ── fetch ──────────────────────────────────────────────────────────────────
  Future<void> _onFetch() async {
    if (_autonomousMode) {
      // AUTO — full autonomous mission
      if (_selectedTarget == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Select a target first!"),
            backgroundColor: Color(0xFF3B1E1E),
          ),
        );
        return;
      }
      try {
        await ApiService.startAutonomy();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("🤖 Fetching ${_selectedTarget!["class_name"]}..."),
            backgroundColor: const Color(0xFF0F2E1A),
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to start fetch: $e"),
            backgroundColor: const Color(0xFF3B1E1E),
          ),
        );
      }
    } else {
      // MANUAL — scripted demo pickup sequence
      try {
        // make sure manual mode is enabled first
        if (!_manualModeEnabled) {
          await ApiService.setManualMode(true);
          _manualModeEnabled = true;
        }
        await ApiService.startDemoFetch();
        setState(() => _demoSequenceRunning = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🦾 Pickup sequence started — joystick disabled"),
            backgroundColor: Color(0xFF1A2E1A),
            duration: Duration(seconds: 2),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to start pickup: $e"),
            backgroundColor: const Color(0xFF3B1E1E),
          ),
        );
      }
    }
  }

  // ── demo place ─────────────────────────────────────────────────────────────
  Future<void> _onDemoPlace() async {
    try {
      // make sure manual mode is enabled first
      if (!_manualModeEnabled) {
        await ApiService.setManualMode(true);
        _manualModeEnabled = true;
      }
      await ApiService.startDemoPlace();
      setState(() => _demoSequenceRunning = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("📦 Place sequence started — joystick disabled"),
          backgroundColor: Color(0xFF1A1A2E),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to start place: $e"),
          backgroundColor: const Color(0xFF3B1E1E),
        ),
      );
    }
  }

  // ── stop ───────────────────────────────────────────────────────────────────
  Future<void> _onStop() async {
    _joystickX = 0; _joystickY = 0; _joystickActive = false;
    await ApiService.stopDrive();
    if (_autonomyEnabled) {
      await ApiService.stopAutonomy(reason: "user pressed stop");
    }
    if (_demoSequenceRunning) {
      await ApiService.stopDemoSequence();
      setState(() => _demoSequenceRunning = false);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("🛑 Robot stopped"),
        backgroundColor: Color(0xFF3B1E1E),
        duration: Duration(seconds: 1),
      ),
    );
  }

  // ── settings ───────────────────────────────────────────────────────────────
  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    await _retryWebRTC();
    _pollState();
  }

  // ── mission phase label ────────────────────────────────────────────────────
  String get _missionPhaseLabel {
    switch (_missionPhase) {
      case "SEARCH_FOR_TARGET":       return "🔍 Searching...";
      case "APPROACH_TARGET":         return "➡️ Approaching...";
      case "FINE_ALIGN_FOR_PICKUP":   return "🎯 Aligning...";
      case "EXECUTE_PICKUP":          return "🦾 Picking up...";
      case "VERIFY_PICKUP":           return "✅ Verifying pickup...";
      default:                        return "";
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
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
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey, size: 22),
            onPressed: _openSettings,
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
                      onDoubleTap: _retryWebRTC,
                      child: Container(
                        key: _videoKey,
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 240),
                        color: Colors.black,
                        child: _webrtcConnected
                            ? Stack(
                                children: [
                                  RTCVideoView(
                                    _videoRenderer,
                                    objectFit: RTCVideoViewObjectFit
                                        .RTCVideoViewObjectFitContain,
                                  ),
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: BoundingBoxPainter(
                                        detections: _detections,
                                        selectedTarget: _selectedTarget,
                                        frameSize: Size(
                                          (_frameWidth  ?? 640).toDouble(),
                                          (_frameHeight ?? 480).toDouble(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : SizedBox(
                                height: 200,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_webrtcConnecting)
                                        const CircularProgressIndicator(
                                            color: Color(0xFF00FF88))
                                      else
                                        const Icon(Icons.videocam_off,
                                            color: Colors.grey, size: 36),
                                      const SizedBox(height: 10),
                                      Text(_webrtcStatus,
                                          style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12)),
                                      if (!_webrtcConnecting) ...[
                                        const SizedBox(height: 8),
                                        TextButton.icon(
                                          onPressed: _retryWebRTC,
                                          icon: const Icon(Icons.refresh,
                                              size: 14,
                                              color: Color(0xFF00FF88)),
                                          label: const Text("Retry",
                                              style: TextStyle(
                                                  color: Color(0xFF00FF88),
                                                  fontSize: 12)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
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
                          Text("Tap to select · Double tap to reconnect",
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                    ),

                    // mission phase banner
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: _autonomyEnabled && _missionPhaseLabel.isNotEmpty
                          ? Container(
                              width: double.infinity,
                              color: const Color(0xFF1A1A0A),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              child: Text(
                                _missionPhaseLabel,
                                style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    // demo sequence banner
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: _demoSequenceRunning
                          ? Container(
                              width: double.infinity,
                              color: const Color(0xFF1A2E1A),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              child: const Text(
                                "🦾 Sequence running — joystick locked",
                                style: TextStyle(
                                  color: Color(0xFF00FF88),
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    // selected target banner
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

                // ── AUTO MODE ─────────────────────────────────────────────
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _autonomyEnabled
                                ? const Color(0xFFFFD700)
                                : (_selectedTarget != null
                                    ? const Color(0xFF00FF88)
                                    : const Color(0xFF1E1E2E)),
                            foregroundColor: _autonomyEnabled
                                ? Colors.black
                                : (_selectedTarget != null
                                    ? Colors.black : Colors.grey),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _autonomyEnabled ? null : _onFetch,
                          icon: Icon(
                            _autonomyEnabled
                                ? Icons.hourglass_top : Icons.send,
                            size: 18,
                          ),
                          label: Text(
                            _autonomyEnabled
                                ? (_missionPhaseLabel.isNotEmpty
                                    ? _missionPhaseLabel
                                    : "Mission running...")
                                : (_selectedTarget != null
                                    ? "FETCH  ${_selectedTarget!["class_name"].toString().toUpperCase()}"
                                    : "SELECT A TARGET FIRST"),
                            style: const TextStyle(
                              fontSize: 13,
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
                          icon: const Icon(Icons.stop_circle_outlined,
                              size: 18),
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

                // ── MANUAL MODE ───────────────────────────────────────────
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [

                          // joystick — disabled during demo sequence
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              Opacity(
                                opacity: _demoSequenceRunning ? 0.3 : 1.0,
                                child: Joystick(
                                  size: 130,
                                  onMove: _demoSequenceRunning
                                      ? (x, y) {}
                                      : _onJoystickMove,
                                  onRelease: _demoSequenceRunning
                                      ? () {}
                                      : _onJoystickRelease,
                                ),
                              ),
                              if (_demoSequenceRunning)
                                const Text(
                                  "SEQUENCE\nRUNNING",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                            ],
                          ),

                          // PICK UP + STOP buttons
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 110,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _demoSequenceRunning
                                        ? const Color(0xFF2E2E1A)
                                        : const Color(0xFF1A2E1A),
                                    foregroundColor: _demoSequenceRunning
                                        ? Colors.grey
                                        : const Color(0xFF00FF88),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10, horizontal: 8),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  onPressed:
                                      _demoSequenceRunning ? null : _onFetch,
                                  icon: const Icon(Icons.download, size: 16),
                                  label: const Text("PICK UP",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      )),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: 110,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3B1E1E),
                                    foregroundColor: Colors.redAccent,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10, horizontal: 8),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
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

                      const SizedBox(height: 8),

                      // PUT DOWN button — full width below
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _demoSequenceRunning
                                ? const Color(0xFF1A1A2E).withOpacity(0.4)
                                : const Color(0xFF1A1A2E),
                            foregroundColor: _demoSequenceRunning
                                ? Colors.grey
                                : const Color(0xFF7B9FFF),
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed:
                              _demoSequenceRunning ? null : _onDemoPlace,
                          icon: const Icon(Icons.upload, size: 16),
                          label: const Text("PUT DOWN",
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}