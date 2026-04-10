import 'package:flutter/material.dart';
import 'services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  bool _checking = false;
  String? _statusMsg;
  bool? _statusOk;

  @override
  void initState() {
    super.initState();
    _loadSavedIp();
  }

  Future<void> _loadSavedIp() async {
    final ip = await ApiService.getSavedIp();
    _controller.text = ip;
  }

  Future<void> _save() async {
    final ip = _controller.text.trim();
    if (ip.isEmpty) return;

    await ApiService.saveIp(ip);
    setState(() {
      _checking = true;
      _statusMsg = "Testing connection...";
      _statusOk = null;
    });

    final ok = await ApiService.checkHealth();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _statusOk = ok;
      _statusMsg = ok
          ? "✅ Connected successfully!"
          : "❌ Could not reach backend — check IP and make sure server is running";
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        title: const Text(
          "SETTINGS",
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 2,
            color: Color(0xFF00FF88),
            fontFamily: 'monospace',
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF00FF88)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── section title ──────────────────────────────────────────────
            const Text(
              "BACKEND IP ADDRESS",
              style: TextStyle(
                color: Colors.grey,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),

            // ── explanation ────────────────────────────────────────────────
            const Text(
              "Enter your laptop's WiFi IP address. "
              "Make sure your phone and laptop are on the same WiFi network.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 20),

            // ── IP input ───────────────────────────────────────────────────
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(
                color: Color(0xFF00FF88),
                fontFamily: 'monospace',
                fontSize: 18,
                letterSpacing: 1,
              ),
              decoration: InputDecoration(
                hintText: "e.g. 192.168.1.45",
                hintStyle: TextStyle(
                    color: Colors.grey.withOpacity(0.4),
                    fontFamily: 'monospace'),
                filled: true,
                fillColor: const Color(0xFF1E1E2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Color(0xFF00FF88), width: 1.5),
                ),
                prefixText: "http://",
                prefixStyle: TextStyle(
                    color: Colors.grey.withOpacity(0.5),
                    fontFamily: 'monospace'),
                suffixText: ":8000",
                suffixStyle: TextStyle(
                    color: Colors.grey.withOpacity(0.5),
                    fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 16),

            // ── save button ────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF88),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _checking ? null : _save,
                child: _checking
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Text(
                        "SAVE & TEST CONNECTION",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 16),

            // ── status message ─────────────────────────────────────────────
            if (_statusMsg != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _statusOk == true
                      ? const Color(0xFF0A2E1A)
                      : const Color(0xFF2E0A0A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _statusMsg!,
                  style: TextStyle(
                    color: _statusOk == true
                        ? const Color(0xFF00FF88)
                        : Colors.redAccent,
                    fontSize: 13,
                  ),
                ),
              ),

            const SizedBox(height: 32),

            // ── how to find IP ─────────────────────────────────────────────
            const Text(
              "HOW TO FIND YOUR LAPTOP'S IP",
              style: TextStyle(
                color: Colors.grey,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            _ipStep("Windows",
                "Open Command Prompt → type ipconfig → look for 'Wireless LAN adapter Wi-Fi' → IPv4 Address"),
            _ipStep("Mac / Linux",
                "Open Terminal → type ifconfig | grep 'inet ' → use the address next to en0"),
          ],
        ),
      ),
    );
  }

  Widget _ipStep(String os, String instruction) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(os,
                style: const TextStyle(
                    color: Color(0xFF00FF88),
                    fontSize: 11,
                    fontFamily: 'monospace')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(instruction,
                style:
                    const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}