import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:leulit_flutter_fullresponsive/leulit_flutter_fullreponsive.dart';
import 'core/app_router.dart';
import 'core/app_theme.dart';

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenSizeInitializer(
      child: GetMaterialApp(
        title: 'Helireport Desherbaje',
        theme: AppTheme.theme,
        debugShowCheckedModeBanner: false,
        initialRoute: AppRoutes.login,
        getPages: AppPages.pages,
      )
    );
  }
}
