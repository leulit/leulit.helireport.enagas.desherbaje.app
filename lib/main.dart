import 'package:flutter/material.dart';
import 'core/app_di.dart';
import 'main_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDI.init();
  runApp(const MainApp());
}
