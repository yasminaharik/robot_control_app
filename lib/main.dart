import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:typed_data';
import 'services/api_service.dart'; // ✅ IMPORTANT

void main() {
  runApp(RobotApp());
}

class RobotApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Fetch Bot',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: RobotControlPage(),
    );
  }
}

class RobotControlPage extends StatefulWidget {
  @override
  _RobotControlPageState createState() => _RobotControlPageState();
}

class _RobotControlPageState extends State<RobotControlPage> {

  BluetoothConnection? connection;
  bool isConnected = false;

  // 🔹 CONNECT TO ESP32
  Future<void> connectToRobot() async {
    String address = "24:6F:28:AB:CD:EF"; // ⚠️ CHANGE THIS

    try {
      BluetoothConnection newConnection =
          await BluetoothConnection.toAddress(address);

      setState(() {
        connection = newConnection;
        isConnected = true;
      });

      print("Connected to ESP32");

    } catch (e) {
      print("Connection error");
    }
  }

  // 🔹 SEND COMMAND
  void sendCommand(String command) {
    if (connection != null && connection!.isConnected) {
      connection!.output.add(Uint8List.fromList(command.codeUnits));
    }
  }

  // 🔹 BUTTON WIDGET
  Widget controlButton(String label, String command) {
    return ElevatedButton(
      onPressed: () {
        sendCommand(command);
      },
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text("Smart Fetch Bot"),
      ),

      body: Column(
        children: [

          // 🔹 DETECTIONS (API)
          Expanded(
            child: FutureBuilder(
              future: ApiService.getDetections(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }

                final detections = snapshot.data as List;

                if (detections.isEmpty) {
                  return Center(child: Text("No objects detected"));
                }

                return ListView.builder(
                  itemCount: detections.length,
                  itemBuilder: (context, index) {
                    final obj = detections[index];

                    return ListTile(
                      title: Text(obj["class_name"]),
                      subtitle: Text("ID: ${obj["track_id"]}"),
                      onTap: () {
                        ApiService.selectTarget(obj["track_id"]);
                      },
                    );
                  },
                );
              },
            ),
          ),

          // 🔹 CONTROL PANEL
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [

                ElevatedButton(
                  onPressed: connectToRobot,
                  child: Text("Connect to Robot"),
                ),

                SizedBox(height: 10),

                Text(
                  isConnected ? "Robot Connected" : "Robot Not Connected",
                  style: TextStyle(fontSize: 18),
                ),

                SizedBox(height: 20),

                controlButton("Forward", "F"),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    controlButton("Left", "L"),
                    SizedBox(width: 10),
                    controlButton("Stop", "S"),
                    SizedBox(width: 10),
                    controlButton("Right", "R"),
                  ],
                ),

                SizedBox(height: 10),

                controlButton("Backward", "B"),
              ],
            ),
          ),
        ],
      ),
    );
  }
}