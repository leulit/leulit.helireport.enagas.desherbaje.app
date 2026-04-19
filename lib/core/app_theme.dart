import 'package:flutter/material.dart';
import '../domain/entities/actividad_entity.dart';

class AppColors {
  static const moduleGreen      = Color(0xFF388E3C);
  static const moduleGreenLight = Color(0xFFF1F8E9);
  static const moduleGreenDark  = Color(0xFF1B5E20);
  static const moduleGreenText  = Color(0xFF1B5E20);

  static const estadoPropuesta  = Color(0xFFFDD835); // amarillo
  static const estadoValidada   = Color(0xFF1976D2);
  static const estadoContratista   = Color.fromARGB(255, 237, 146, 240);
  static const estadoEjecucion  = Color(0xFFD32F2F); // rojo
  static const estadoFinalizada = Color(0xFF388E3C);
  static const estadoCerrada    = Color(0xFF546E7A);

  static const bgPropuesta  = Color(0xFFFFF9C4); // amarillo claro
  static const bgValidada   = Color(0xFFE3F2FD);
  static const bgContratista   = Color(0xFFE3F2FD);
  static const bgEjecucion  = Color(0xFFFFEBEE); // rojo claro
  static const bgFinalizada = Color(0xFFE8F5E9);
  static const bgCerrada    = Color(0xFFECEFF1);

  static const surface       = Colors.white;
  static const background    = Color(0xFFF5F5F5);
  static const textPrimary   = Color(0xFF212121);
  static const textSecondary = Color(0xFF757575);
  static const divider       = Color(0xFFBDBDBD);

  static Color accentForEstado(EstadoActividad e) => switch (e) {
    EstadoActividad.propuesta  => estadoPropuesta,
    EstadoActividad.validada   => estadoValidada,
    EstadoActividad.contratista   => estadoContratista,
    EstadoActividad.ejecucion  => estadoEjecucion,
    EstadoActividad.finalizada => estadoFinalizada,
    EstadoActividad.cerrada    => estadoCerrada,
  };

  static Color bgForEstado(EstadoActividad e) => switch (e) {
    EstadoActividad.propuesta  => bgPropuesta,
    EstadoActividad.validada   => bgValidada,
    EstadoActividad.contratista   => bgContratista,
    EstadoActividad.ejecucion  => bgEjecucion,
    EstadoActividad.finalizada => bgFinalizada,
    EstadoActividad.cerrada    => bgCerrada,
  };

  /// Color del texto cuando se pinta sobre accentForEstado (badge pequeño).
  /// Amarillo requiere texto oscuro; el resto admite blanco.
  static Color textOnAccentForEstado(EstadoActividad e) => switch (e) {
    EstadoActividad.propuesta => const Color(0xFF5D4037),
    _                         => Colors.white,
  };
}

class AppTextStyles {
  static const headline    = TextStyle(fontSize: 20, fontWeight: FontWeight.w700);
  static const title       = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
  static const subtitle    = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
  static const body        = TextStyle(fontSize: 14);
  static const caption     = TextStyle(fontSize: 12);
  static const badge       = TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: Colors.white);
  static const metric      = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const metricSmall = TextStyle(fontSize: 11, fontStyle: FontStyle.italic);
}

class AppSpacing {
  static const xs  = 4.0;
  static const sm  = 8.0;
  static const md  = 12.0;
  static const lg  = 16.0;
  static const xl  = 24.0;
  static const xxl = 32.0;
}

class AppTheme {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.moduleGreen,
      primary: AppColors.moduleGreen,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.moduleGreenLight,
      foregroundColor: AppColors.moduleGreenText,
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.moduleGreen,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.moduleGreen, width: 2),
      ),
    ),
  );
}
