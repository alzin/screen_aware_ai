import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/agent_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ScreenAwareApp());
}

class ScreenAwareApp extends StatefulWidget {
  const ScreenAwareApp({super.key});

  @override
  State<ScreenAwareApp> createState() => _ScreenAwareAppState();
}

class _ScreenAwareAppState extends State<ScreenAwareApp> {
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
      title: 'Screen Aware AI',
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
