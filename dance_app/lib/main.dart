import 'package:flutter/material.dart';
import 'package:dance_app/view/project_list_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dance Comparison',
      theme: ThemeData(
        // Dark theme with cool blue accents
        brightness: Brightness.dark,
        primaryColor: Colors.blue[700],
        colorScheme: ColorScheme.dark(
          primary: Colors.blue[700]!,
          secondary: Colors.tealAccent,
          background: Colors.black87,
          surface: Colors.grey[900]!,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black87,
          elevation: 0,
        ),
        scaffoldBackgroundColor: Colors.black87,
        cardTheme: CardTheme(
          color: Colors.grey[900],
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const ProjectListScreen(),
    );
  }
}
