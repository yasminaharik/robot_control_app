import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String _ipKey = "backend_ip";
  static const String _defaultIp = "192.168.1.100";

  // ── IP management ─────────────────────────────────────────────────────────
  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString(_ipKey) ?? _defaultIp;
    return "http://$ip:8000";
  }

  static Future<void> saveIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ipKey, ip);
  }

  static Future<String> getSavedIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ipKey) ?? _defaultIp;
  }

  // ── helpers ───────────────────────────────────────────────────────────────
  static Future<http.Response> _get(String path, {int timeoutMs = 800}) async {
    final base = await getBaseUrl();
    return http
        .get(Uri.parse("$base$path"))
        .timeout(Duration(milliseconds: timeoutMs));
  }

  static Future<http.Response> _post(String path,
      {Map<String, dynamic>? body, int timeoutMs = 500}) async {
    final base = await getBaseUrl();
    return http
        .post(
          Uri.parse("$base$path"),
          headers: {"Content-Type": "application/json"},
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(Duration(milliseconds: timeoutMs));
  }

  static Future<http.Response> _delete(String path) async {
    final base = await getBaseUrl();
    return http.delete(Uri.parse("$base$path"));
  }

  // ── frame URL ─────────────────────────────────────────────────────────────
  static Future<String> getFrameUrl() async {
    final base = await getBaseUrl();
    return "$base/frame";
  }

  // ── health check ──────────────────────────────────────────────────────────
  static Future<bool> checkHealth() async {
    try {
      final res = await _get("/health", timeoutMs: 3000);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── vision ────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getState() async {
    final res = await _get("/state");
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception("Failed to load state");
  }

  static Future<Map<String, dynamic>?> selectTargetByPoint(
      int x, int y) async {
    final res =
        await _post("/select-target-by-point", body: {"x": x, "y": y});
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      return body["selected_target"] as Map<String, dynamic>?;
    }
    return null;
  }

  static Future<void> selectTarget(int trackId) async {
    await _post("/select-target", body: {"track_id": trackId});
  }

  static Future<void> clearTarget() async {
    await _delete("/select-target");
  }

  // ── manual drive ──────────────────────────────────────────────────────────
  static Future<void> setManualMode(bool enabled) async {
    await _post("/manual-mode", body: {"enabled": enabled});
  }

  // x/y in [-1.0, 1.0] — backend converts to linear_v + angular_w → Arduino
  static Future<void> sendDrive(double x, double y) async {
    await _post("/manual-drive", body: {"x": x, "y": y}, timeoutMs: 300);
  }

  static Future<void> stopDrive() async {
    await _post("/manual-stop", timeoutMs: 300);
  }
}