import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'screens/home_screen.dart';
import 'services/agent_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  runApp(const LucyApp());
}

class LucyApp extends StatefulWidget {
  const LucyApp({super.key});

  @override
  State<LucyApp> createState() => _LucyAppState();
}

class _LucyAppState extends State<LucyApp> {
  late final AgentController _agentController;

  @override
  void initState() {
    super.initState();
    _agentController = AgentController();
    _agentController.initialize();
  }

  @override
  void dispose() {
    _agentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lucy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF6C63FF),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: HomeScreen(controller: _agentController),
    );
  }
}
