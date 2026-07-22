import 'package:flutter/widgets.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'main_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Photo Picker del sistema: evita READ_MEDIA_IMAGES/VIDEO (política Play).
  final ImagePickerPlatform picker = ImagePickerPlatform.instance;
  if (picker is ImagePickerAndroid) picker.useAndroidPhotoPicker = true;
  // Carga los símbolos de fecha del locale 'es' que usa DateFormat(..., 'es')
  // (p.ej. la pantalla de Sincronización). Sin esto: LocaleDataException.
  await initializeDateFormatting('es', null);
  runApp(const MainApp());
}
