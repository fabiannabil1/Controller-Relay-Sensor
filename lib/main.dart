import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:convert';

void main() {
  runApp(MQTTApp());
}

class MQTTApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MQTT Mobile Control',
      theme: ThemeData(
        primarySwatch: Colors.green,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          primary: Colors.green,
          secondary: Colors.lightGreen,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        cardTheme: CardTheme(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: MQTTHomePage(),
    );
  }
}

class MQTTHomePage extends StatefulWidget {
  @override
  _MQTTHomePageState createState() => _MQTTHomePageState();
}

final Map<String, dynamic> _scheduleEntries = {
  "ID": "1",
  "Relay": "1",
  "Hour": "00",
  "Minute": "00",
  "Duration": "1",
  "Repeat": "1",
  "Status": "ON",
  "Delete ID": "1",
};

final TextEditingController _scheduleIdController = TextEditingController();
final TextEditingController _deleteIdController = TextEditingController();
final TextEditingController _customRepeatController = TextEditingController();

class _MQTTHomePageState extends State<MQTTHomePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  MqttServerClient? _client;
  bool _connected = false;

  // Connection parameters
  final TextEditingController _brokerController = TextEditingController(
    text: '103.127.97.36',
  );
  final TextEditingController _portController = TextEditingController(
    text: '1883',
  );
  final TextEditingController _topicController = TextEditingController(
    text: 'smart/nabil/relay',
  );
  final TextEditingController _userController = TextEditingController(
    text: 'duricare',
  );
  final TextEditingController _passController = TextEditingController(
    text: '100704',
  );
  // Di bagian deklarasi controller tambahkan:
  final TextEditingController _clientIdController = TextEditingController(
    text: 'duricare_client',
  );

  // Switch states
  final List<bool> _switchStates = List.filled(8, false);

  // Sensor values with labels
  final Map<String, Map<String, dynamic>> _sensorValues = {
    'S1': {'value': '--', 'label': 'Sensor Hujan', 'icon': Icons.water_drop},
    'S2': {'value': '--', 'label': 'Kelembapan', 'icon': Icons.landscape},
    'S3': {'value': '--', 'label': 'Kelembapan', 'icon': Icons.air},
    'S4': {'value': '--', 'label': 'Suhu Udara', 'icon': Icons.thermostat},
  };

  // Log controllers
  final TextEditingController _sensorLogController = TextEditingController();
  final TextEditingController _scheduleLogController = TextEditingController();

  @override
  void dispose() {
    _disconnect();
    _customRepeatController.dispose();

    super.dispose();
  }

  Future<void> _connect() async {
    if (_connected) return;

    // final client = MqttServerClient(_brokerController.text, '');
    final client = MqttServerClient.withPort(
      _brokerController.text,
      'duricare_${DateTime.now().millisecondsSinceEpoch}', // Client ID unik
      int.tryParse(_portController.text) ?? 1883,
    );
    client.port = int.tryParse(_portController.text) ?? 1883;
    client.keepAlivePeriod = 60;
    client.logging(on: false);

    try {
      await client.connect(_userController.text, _passController.text);
      setState(() {
        _client = client;
        _connected = true;
      });

      client.subscribe('smart/nabil/sensor', MqttQos.atMostOnce);
      client.subscribe('smart/nabil/jadwal', MqttQos.atMostOnce);

      client.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
        final recMess = c![0].payload as MqttPublishMessage;
        final String message = MqttPublishPayload.bytesToStringAsString(
          recMess.payload.message,
        );

        if (c[0].topic == 'smart/nabil/sensor') {
          _updateSensorData(jsonDecode(message));
        } else if (c[0].topic == 'smart/nabil/jadwal') {
          _updateScheduleLog('Received: $message');
        }
      });

      _updateLogs('Connected successfully!');
    } catch (e) {
      client.disconnect();
      _updateLogs('Connection failed: $e');
    }
  }

  void _disconnect() {
    if (_client != null &&
        _client!.connectionStatus!.state == MqttConnectionState.connected) {
      _client!.disconnect();
    }
    setState(() {
      _connected = false;
      _client = null;
    });
  }

  void _toggleSwitch(int index) {
    if (!_connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please connect first!'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final newState = !_switchStates[index];
    setState(() => _switchStates[index] = newState);
    final command = '${index + 1}${newState ? 'ON' : 'OFF'}';
    _publishMessage(command);
  }

  void _publishMessage(String message) {
    if (!_connected) return;
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    _client!.publishMessage(
      _topicController.text,
      MqttQos.atMostOnce,
      builder.payload!,
    );
    _updateScheduleLog('Sent: $message');
  }

  void _updateSensorData(Map<String, dynamic> data) {
    setState(() {
      data.forEach((key, value) {
        if (_sensorValues.containsKey(key)) {
          _sensorValues[key]!['value'] = value.toString();
        }
      });
    });
    _updateLogs('Sensor data updated');
  }

  void _updateLogs(String message) {
    final timestamp = DateTime.now().toString().split('.')[0];
    _sensorLogController.text += '[$timestamp] $message\n';
  }

  void _sendSchedule() {
    if (_formKey.currentState?.validate() ?? false) {
      try {
        // Ambil nilai dari controller text
        final scheduleId = int.parse(_scheduleIdController.text);
        final relay = int.parse(_scheduleEntries["Relay"]!);
        final hour = int.parse(_scheduleEntries["Hour"]!);
        final minute = int.parse(_scheduleEntries["Minute"]!);
        final duration = int.parse(_scheduleEntries["Duration"]!);
        final repeat = int.parse(_scheduleEntries["Repeat"]!);
        final status = _scheduleEntries["Status"]!;

        // Validasi durasi
        if (duration < 1 || duration > 1440) {
          throw "Duration must be between 1-1440 minutes";
        }

        // Validasi ID
        // if (scheduleId < 1 || scheduleId > 8) {
        //   throw "Schedule ID must be between 1-8";
        // }

        final schedule = {
          "id": scheduleId,
          "relay": relay,
          "hour": hour,
          "minute": minute,
          "duration": duration,
          "repeat": repeat,
          "status": status,
        };

        _publishMessage(
          jsonEncode({
            "schedules": [schedule],
          }),
        );
        _updateScheduleLog("Schedule sent: ${jsonEncode(schedule)}");
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _deleteSchedule() {
    if (_formKey.currentState?.validate() ?? false) {
      try {
        final deleteId = int.parse(_deleteIdController.text);
        _publishMessage("DELETE:$deleteId");
        _updateScheduleLog("Delete request sent for ID: $deleteId");
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Delete error: $e")));
      }
    }
  }

  // Perbarui method _updateScheduleLog untuk menangani JSON
  void _updateScheduleLog(String message) {
    final timestamp = DateTime.now().toString().split('.')[0];
    setState(() {
      _scheduleLogController.text += '[$timestamp] $message\n';
    });
  }

  String _getSensorUnit(String sensorKey) {
    switch (sensorKey) {
      case 'S1':
        return '%'; // Hujan
      case 'S2':
        return '%'; // Kelembapan Tanah
      case 'S3':
        return '%'; // Kelembapan Udara
      case 'S4':
        return '°C'; // Suhu Udara
      default:
        return '';
    }
  }

  Color _getConnectionColor() {
    return _connected ? Colors.green.shade700 : Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Fabian Smart System',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.green.shade700,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Icon(
              _connected ? Icons.wifi : Icons.wifi_off,
              color: Colors.white,
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.green.shade50, Colors.white],
          ),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Connection Status Indicator
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  decoration: BoxDecoration(
                    color: _getConnectionColor(),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _connected ? Icons.check_circle : Icons.error,
                        color: Colors.white,
                      ),
                      SizedBox(width: 8),
                      Text(
                        _connected ? 'Connected' : 'Disconnected',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),

                // Connection Panel
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.settings_ethernet,
                              color: Colors.green.shade700,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Connection Settings',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                        Divider(color: Colors.green.shade200),
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _brokerController,
                                decoration: InputDecoration(
                                  labelText: 'Broker',
                                  prefixIcon: Icon(
                                    Icons.dns,
                                    color: Colors.green,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
                                ),
                              ),
                              SizedBox(height: 12),
                              TextFormField(
                                controller: _portController,
                                decoration: InputDecoration(
                                  labelText: 'Port',
                                  prefixIcon: Icon(
                                    Icons.router,
                                    color: Colors.green,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                              SizedBox(height: 12),
                              TextFormField(
                                controller: _topicController,
                                decoration: InputDecoration(
                                  labelText: 'Topic',
                                  prefixIcon: Icon(
                                    Icons.topic,
                                    color: Colors.green,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
                                ),
                              ),
                              SizedBox(height: 12),
                              TextFormField(
                                controller: _userController,
                                decoration: InputDecoration(
                                  labelText: 'Username',
                                  prefixIcon: Icon(
                                    Icons.person,
                                    color: Colors.green,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
                                ),
                              ),
                              SizedBox(height: 12),
                              TextFormField(
                                controller: _passController,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: Icon(
                                    Icons.lock,
                                    color: Colors.green,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
                                ),
                                obscureText: true,
                              ),
                              SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton.icon(
                                  onPressed:
                                      _connected ? _disconnect : _connect,
                                  icon: Icon(
                                    _connected ? Icons.link_off : Icons.link,
                                    color: Colors.white,
                                  ),
                                  label: Text(
                                    _connected ? 'Disconnect' : 'Connect',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        _connected
                                            ? Colors.red.shade600
                                            : Colors.green.shade600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 16),

                // Sensor Monitoring
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.sensors, color: Colors.green.shade700),
                            SizedBox(width: 8),
                            Text(
                              'Sensor Monitoring',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                        Divider(color: Colors.green.shade200),

                        GridView.builder(
                          shrinkWrap: true,
                          physics: NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 1.5,
                              ),
                          itemCount: _sensorValues.length,
                          itemBuilder: (context, index) {
                            final sensorKey = _sensorValues.keys.elementAt(
                              index,
                            );
                            final sensorData = _sensorValues[sensorKey]!;

                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.green.shade100,
                                    Colors.green.shade200,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.green.shade300,
                                ),
                              ),
                              padding: EdgeInsets.all(12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        sensorData['icon'],
                                        color: Colors.green.shade700,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        sensorData['label'],
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        sensorData['value'],
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade900,
                                        ),
                                      ),
                                      SizedBox(width: 2),
                                      Text(
                                        _getSensorUnit(sensorKey),
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        SizedBox(height: 16),
                        TextField(
                          controller: _sensorLogController,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: 'Sensor Log',
                            labelStyle: TextStyle(color: Colors.green.shade700),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.green.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.green.shade500,
                                width: 2,
                              ),
                            ),
                          ),
                          readOnly: true,
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 16),

                // Switch Controls
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.toggle_on, color: Colors.green.shade700),
                            SizedBox(width: 8),
                            Text(
                              'Zone Controls',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                        Divider(color: Colors.green.shade200),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 0.9,
                              ),
                          itemCount: 8,
                          itemBuilder: (context, index) {
                            return InkWell(
                              onTap: () => _toggleSwitch(index),
                              child: Container(
                                decoration: BoxDecoration(
                                  color:
                                      _switchStates[index]
                                          ? Colors.green.shade600
                                          : Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _switchStates[index]
                                          ? Icons.lightbulb
                                          : Icons.lightbulb_outline,
                                      color:
                                          _switchStates[index]
                                              ? Colors.white
                                              : Colors.grey.shade600,
                                      size: 28,
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Zone ${index + 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            _switchStates[index]
                                                ? Colors.white
                                                : Colors.grey.shade700,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      _switchStates[index] ? 'ON' : 'OFF',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            _switchStates[index]
                                                ? Colors.white.withOpacity(0.8)
                                                : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 16),

                // Schedule Monitoring
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.schedule, color: Colors.green.shade700),
                            SizedBox(width: 8),
                            Text(
                              'Schedule Control',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                        Divider(color: Colors.green.shade200),
                        TextFormField(
                          controller: _scheduleIdController,
                          decoration: InputDecoration(
                            labelText: 'Schedule ID',
                            prefixIcon: Icon(
                              Icons.numbers,
                              color: Colors.green,
                            ),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _scheduleEntries["Relay"],
                                items: List.generate(
                                  8,
                                  (i) => DropdownMenuItem(
                                    value: "${i + 1}",
                                    child: Text("Relay ${i + 1}"),
                                  ),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _scheduleEntries["Relay"] = value!;
                                  });
                                },
                                decoration: InputDecoration(
                                  labelText: 'Relay',
                                  prefixIcon: Icon(
                                    Icons.device_hub,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _scheduleEntries["Hour"],
                                items: List.generate(
                                  24,
                                  (i) => DropdownMenuItem(
                                    value: i.toString().padLeft(2, '0'),
                                    child: Text(
                                      "${i.toString().padLeft(2, '0')} H",
                                    ),
                                  ),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _scheduleEntries["Hour"] = value!;
                                  });
                                },
                                decoration: InputDecoration(
                                  labelText: 'Hour',
                                  prefixIcon: Icon(
                                    Icons.timer,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _scheduleEntries["Minute"],
                                items: List.generate(
                                  60,
                                  (i) => DropdownMenuItem(
                                    value: i.toString().padLeft(2, '0'),
                                    child: Text(
                                      "${i.toString().padLeft(2, '0')} M",
                                    ),
                                  ),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _scheduleEntries["Minute"] = value!;
                                  });
                                },
                                decoration: InputDecoration(
                                  labelText: 'Minute',
                                  prefixIcon: Icon(
                                    Icons.timer,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                initialValue: _scheduleEntries["Duration"],
                                decoration: InputDecoration(
                                  labelText: 'Duration (min)',
                                  prefixIcon: Icon(
                                    Icons.timelapse,
                                    color: Colors.green,
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (value) {
                                  setState(() {
                                    _scheduleEntries["Duration"] = value;
                                  });
                                },
                                validator: (value) {
                                  if (value == null ||
                                      int.tryParse(value) == null) {
                                    return "Invalid number";
                                  }
                                  int duration = int.parse(value);
                                  if (duration < 1 || duration > 1440) {
                                    return "1-1440 minutes";
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<String>(
                                value: _scheduleEntries["Repeat"],
                                items: [
                                  DropdownMenuItem(
                                    value: "1",
                                    child: Text("Once"),
                                  ),
                                  DropdownMenuItem(
                                    value: "7",
                                    child: Text("Weekly"),
                                  ),
                                  DropdownMenuItem(
                                    value: "30",
                                    child: Text("Monthly"),
                                  ),
                                  DropdownMenuItem(
                                    value: "custom",
                                    child: Text("Custom"),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _scheduleEntries["Repeat"] = value!;
                                    // Reset custom value jika memilih opsi preset
                                    if (value != "custom") {
                                      _customRepeatController.text = "";
                                    }
                                  });
                                },
                                decoration: InputDecoration(
                                  labelText: 'Repeat',
                                  prefixIcon: Icon(
                                    Icons.repeat,
                                    color: Colors.green,
                                  ),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            SizedBox(width: 8),
                            if (_scheduleEntries["Repeat"] == "custom")
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _customRepeatController,
                                  decoration: InputDecoration(
                                    labelText: 'Days',
                                    prefixIcon: Icon(
                                      Icons.calendar_today,
                                      color: Colors.blue,
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (value) {
                                    if (_scheduleEntries["Repeat"] ==
                                            "custom" &&
                                        (value == null || value.isEmpty)) {
                                      return 'Enter days';
                                    }
                                    final days = int.tryParse(value ?? '');
                                    if (days == null || days < 1) {
                                      return 'Invalid days';
                                    }
                                    return null;
                                  },
                                  onChanged: (value) {
                                    if (value.isNotEmpty) {
                                      _scheduleEntries["Repeat"] = value;
                                    }
                                  },
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Text('Status:', style: TextStyle(fontSize: 16)),
                            Radio<String>(
                              value: "ON",
                              groupValue: _scheduleEntries["Status"],
                              onChanged: (value) {
                                setState(() {
                                  _scheduleEntries["Status"] = value!;
                                });
                              },
                            ),
                            Text('ON'),
                            Radio<String>(
                              value: "OFF",
                              groupValue: _scheduleEntries["Status"],
                              onChanged: (value) {
                                setState(() {
                                  _scheduleEntries["Status"] = value!;
                                });
                              },
                            ),
                            Text('OFF'),
                          ],
                        ),
                        SizedBox(height: 12),
                        Column(
                          children: [
                            // Baris pertama untuk 2 button
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed:
                                        _connected ? _sendSchedule : null,
                                    icon: Icon(Icons.send),
                                    label: Text("Send Schedule"),
                                  ),
                                ),
                                SizedBox(width: 8), // Jarak antara button
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed:
                                        _connected
                                            ? () =>
                                                _publishMessage("cek jadwal")
                                            : null,
                                    icon: Icon(Icons.refresh),
                                    label: Text("Check Schedule"),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8), // Jarak antar baris
                            // Baris kedua untuk delete button full width
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _connected ? _deleteSchedule : null,
                                icon: Icon(Icons.delete),
                                label: Text("Delete Schedule"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        TextFormField(
                          controller: _deleteIdController,
                          decoration: InputDecoration(
                            labelText: 'Schedule ID to Delete',
                            prefixIcon: Icon(
                              Icons.delete_forever,
                              color: Colors.red,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        SizedBox(height: 12),
                        TextField(
                          controller: _scheduleLogController,
                          maxLines: 20,
                          decoration: InputDecoration(
                            labelText: 'Schedule Log',
                            border: OutlineInputBorder(),
                          ),
                          readOnly: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
