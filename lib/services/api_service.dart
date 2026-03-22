import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = "http://192.168.10.151:8000"; // ⚠️ CHANGE THIS

  static Future<List<dynamic>> getDetections() async {
    final response = await http.get(Uri.parse("$baseUrl/detections"));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to load detections");
    }
  }

  static Future<void> selectTarget(int trackId) async {
    final response = await http.post(
      Uri.parse("$baseUrl/select-target"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "track_id": trackId
      }),
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to select target");
    }
  }
}