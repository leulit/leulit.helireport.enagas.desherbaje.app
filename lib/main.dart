import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'main_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Carga los símbolos de fecha del locale 'es' que usa DateFormat(..., 'es')
  // (p.ej. la pantalla de Sincronización). Sin esto: LocaleDataException.
  await initializeDateFormatting('es', null);
  runApp(const MainApp());
}
