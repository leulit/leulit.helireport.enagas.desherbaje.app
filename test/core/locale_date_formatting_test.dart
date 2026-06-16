import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

// Regresión: la pantalla de Sincronización formatea fechas con
// DateFormat('d MMM HH:mm', 'es'). Sin initializeDateFormatting('es') eso lanza
// LocaleDataException en runtime (pantalla roja en "Datos maestros"). main()
// debe inicializar el locale antes de runApp.
void main() {
  test('DateFormat(..., "es") lanza sin inicializar el locale', () {
    // No se ha llamado initializeDateFormatting('es') todavía.
    expect(
      () => DateFormat('d MMM HH:mm', 'es').format(DateTime(2026, 6, 16, 22, 5)),
      throwsA(anything),
    );
  });

  test('DateFormat(..., "es") funciona tras initializeDateFormatting("es")',
      () async {
    await initializeDateFormatting('es', null);
    final out =
        DateFormat('d MMM HH:mm', 'es').format(DateTime(2026, 6, 16, 22, 5));
    expect(out, isNotEmpty);
    expect(out.toLowerCase(), contains('jun')); // mes abreviado en español
  });
}
