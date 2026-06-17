import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'state/huddle_controller.dart';
import 'theme.dart';

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
        theme: HuddleTheme.light(),
        darkTheme: HuddleTheme.dark(),
        home: const HomeScreen(),
      ),
    );
  }
}
