import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'state/huddle_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HuddleApp());
}

class HuddleApp extends StatelessWidget {
  const HuddleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<HuddleController>(
      create: (_) => HuddleController()..init(),
      child: MaterialApp(
        title: 'Huddle',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5C6BC0)),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF5C6BC0),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
