import 'package:flutter/material.dart';
import 'core/app_di.dart';
import 'main_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  //await AppDI.init();
  AppDI.init().then((_) => print("✅ AppDI Cargado"));
  runApp(const MainApp());
}




