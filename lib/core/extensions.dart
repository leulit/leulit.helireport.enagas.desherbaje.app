import 'dart:math';

import 'package:auto_size_text_plus/auto_size_text_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';



extension MapCaseInsensitiveExtensions on Map<String, dynamic> {
  /// Obtiene un valor ignorando mayúsculas/minúsculas del key
  Object? getIgnoreCase(String key) {
    final keyLower = key.toLowerCase();
    
    for (final entry in entries) {
      if (entry.key.toLowerCase() == keyLower) {
        return entry.value;
      }
    }
    
    return null;
  }
  
  /// Obtiene un valor String o retorna un default
  String getStringIgnoreCase(String key, {String defaultValue = ''}) {
    return getIgnoreCase(key)?.toString() ?? defaultValue;
  }
  
  /// Verifica si existe un key (ignorando case)
  bool containsKeyIgnoreCase(String key) {
    return getIgnoreCase(key) != null;
  }
  
  /// Intenta múltiples keys y retorna el primero que encuentre
  Object? getFirstOf(List<String> keys) {
    for (final key in keys) {
      final value = getIgnoreCase(key);
      if (value != null) return value;
    }
    return null;
  }
}


extension GetDialogExtensions on GetInterface {
  /// Muestra un diálogo y ejecuta callback después de cerrarlo
  Future<T?> dialogWithCallback<T>(
    Widget dialog, {
    required Future<void> Function() onClosed,
    bool barrierDismissible = true,
  }) async {
    final result = await Get.dialog<T>(dialog, barrierDismissible: barrierDismissible);
    
    SchedulerBinding.instance.addPostFrameCallback((_) {
      SchedulerBinding.instance.addPostFrameCallback((_) async {
        await onClosed();
      });
    });          
    return result;
  }
}


const whiteColor = Color(0xFFFFFFFF);

extension LatLngDistanceX on LatLng {
  /// Calcula la distancia en metros a otro punto LatLng.
  double distanceTo(LatLng other) {
    const Distance distance = Distance();
    return distance(this, other);
  }
}

extension MarkerExtension on Marker {
  Marker copyWith({
    Key? key,
    LatLng? point,
    double? width,
    double? height,
    Widget? child,
  }) {
    return Marker(
      key: key ?? this.key,
      point: point ?? this.point,
      child: child ?? this.child,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}



extension LatLngBoundsExtensions on LatLngBounds {
  bool overlaps(LatLngBounds other) {
    // Verificar si los límites no se solapan
    final noOverlap =
        (south >
                other.north || // Este límite está completamente al sur del otro
            north <
                other
                    .south || // Este límite está completamente al norte del otro
            east <
                other
                    .west || // Este límite está completamente al oeste del otro
            west >
                other.east); // Este límite está completamente al este del otro

    // Si no hay solapamiento, devolver false
    return !noOverlap;
  }
}

extension MapControllerExtensions on MapController {
  LatLngBounds getVisibleBounds(Size mapSize) {
    // Obtén el centro del mapa y el nivel de zoom
    final center = camera.center;
    final zoom = camera.zoom;

    // Tamaño del mapa en píxeles
    final mapWidth = mapSize.width;
    final mapHeight = mapSize.height;

    // Calcula el tamaño de una unidad de píxel en coordenadas geográficas
    final resolution =
        156543.03392 *
        (1 / (1 << zoom.toInt())); // Resolución en metros por píxel
    final halfWidthInMeters = (mapWidth / 2) * resolution;
    final halfHeightInMeters = (mapHeight / 2) * resolution;

    // Usa la fórmula de Haversine para calcular las coordenadas de los bordes
    final distanceCalculator = Distance();

    // Norte
    final north = distanceCalculator.offset(center, halfHeightInMeters, 0);
    // Sur
    final south = distanceCalculator.offset(center, halfHeightInMeters, 180);
    // Oeste
    final west = distanceCalculator.offset(center, halfWidthInMeters, 270);
    // Este
    final east = distanceCalculator.offset(center, halfWidthInMeters, 90);

    // Devuelve los límites visibles como LatLngBounds
    return LatLngBounds(
      LatLng(north.latitude, west.longitude), // Norte-Oeste
      LatLng(south.latitude, east.longitude), // Sur-Este
    );
  }
}

extension ColorExtension on Color {
  String toHexStr() {
    final r1 = (r * 255).round();
    final g1 = (g * 255).round();
    final b1 = (b * 255).round();

    return '#${r1.toRadixString(16).padLeft(2, '0')}'
        '${g1.toRadixString(16).padLeft(2, '0')}'
        '${b1.toRadixString(16).padLeft(2, '0')}';
  }

  // Función para calcular el color de texto con mejor contraste
  Color getContrastTextColor() {
    // Calcular la luminancia del color de fondo
    double luminance = computeLuminance();
    // Si el fondo es claro, usar texto oscuro; si es oscuro, usar texto claro
    return luminance > 0.5 ? Colors.black87 : whiteColor;
  }

  // Función para crear un color de borde ligeramente más oscuro
  Color getBorderColor() {
    // Reducir el brillo para crear un borde contrastante
    return withValues(alpha: 0.8).darken(0.2);
  }

  Color darken([double amount = 0.1]) {
    assert(amount >= 0 && amount <= 1);

    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));

    return hslDark.toColor();
  }

  Color get opposite {
    // Convert the color to HSLColor
    HSLColor hslColor = HSLColor.fromColor(this);

    // Calculate the opposite hue by adding 180 and mod by 360
    double oppositeHue = (hslColor.hue + 180) % 360;

    // Create a new HSLColor with the opposite hue and same saturation and lightness
    return HSLColor.fromAHSL(
      hslColor.alpha,
      oppositeHue,
      hslColor.saturation,
      hslColor.lightness,
    ).toColor();
  }

  MaterialAccentColor toAccentColor() {
    return MaterialAccentColor(
      (a.toInt() << 24) | (r.toInt() << 16) | (g.toInt() << 8) | b.toInt(),
      <int, Color>{
        100: withValues(alpha: 0.2),
        200: withValues(alpha: 0.4),
        400: withValues(alpha: 0.6),
        700: withValues(alpha: 0.8),
      },
    );
  }
  /// Convierte el color a una versión neón, optimizada para alto contraste.
  ///
  /// El color resultante es muy luminoso y se destaca sobre fondos oscuros,
  /// como los mapas de imágenes de satélite.
  Color toNeon() {
    // Colores predefinidos para casos extremos.
    if (computeLuminance() > 0.9) return const Color(0xFF00FFFF);
    if (computeLuminance() < 0.1) return const Color(0xFF00FF00);

    // Encontrar el canal de color dominante.
    final maxVal = max(r, max(g, b));

    double newR = r;
    double newG = g;
    double newB = b;

    // Saturar el canal dominante al máximo (1.0) y reducir los demás (factor de 0.5).
    if (maxVal == r) {
      newR = 1.0;
      newG = g * 0.5;
      newB = b * 0.5;
    } else if (maxVal == g) {
      newG = 1.0;
      newR = r * 0.5;
      newB = b * 0.5;
    } else {
      newB = 1.0;
      newR = r * 0.5;
      newG = g * 0.5;
    }

    // Aumentar el brillo general si es necesario, asegurando un mínimo de intensidad.
    final currentLuminance = Color.fromRGBO(
      (newR * 255).round(),
      (newG * 255).round(),
      (newB * 255).round(),
      1.0, // ✅ Siempre usar alpha 1.0 para garantizar visibilidad
    ).computeLuminance();

    if (currentLuminance < 0.5) {
      final factor = 0.5 / currentLuminance;
      newR = (newR * factor).clamp(0.0, 1.0);
      newG = (newG * factor).clamp(0.0, 1.0);
      newB = (newB * factor).clamp(0.0, 1.0);
    }

    return Color.fromRGBO(
      (newR * 255).round(),
      (newG * 255).round(),
      (newB * 255).round(),
      1.0, // ✅ Siempre alpha 1.0 para que el color neón sea completamente visible
    );
  }
}

extension FormateadorDeFechaHora on DateTime {
  String formatear(String formato) {
    try {
      final formatter = DateFormat(formato);
      return formatter.format(this);
    } catch (e) {
      return "";
    }
  }
}

extension StringExtensions on String {
  /// Extrae el contenido entre el último guión y el punto
  /// Ejemplo: "ct-almeria-gasoductos.json" -> "gasoductos"
  String extractBetweenLastDashAndDot() {
    final lastDashIndex = lastIndexOf('-');
    final lastDotIndex = lastIndexOf('.');
    
    if (lastDashIndex == -1 || lastDotIndex == -1 || lastDashIndex >= lastDotIndex) {
      return ''; // Retorna vacío si no encuentra el patrón
    }
    
    return substring(lastDashIndex + 1, lastDotIndex);
  }
  
  /// Extrae el tipo de archivo de nombres como "ct-ciudad-tipo.extension"
  String extractFileType() {
    return extractBetweenLastDashAndDot();
  }
}

extension ConvertidorDeFechaHora on String {
  DateTime? datetimeParser({required String? formato}) {
    try {
      final formatter = DateFormat(formato ?? '');
      return formatter.parse(this);
    } catch (e) {
      return null;
    }
  }

  Color toColorFromHex() {
    var hexColor = replaceAll("#", "");
    if (hexColor.length == 6) {
      hexColor = "FF$hexColor";
    }
    if (hexColor.length == 8) {
      return Color(int.parse("0x$hexColor"));
    }
    return whiteColor; // Retorna blanco si el string no es un color válido
  }
}

extension ConvertidorDeDouble on String {
  double doubleParser({String? formato}) {
    try {
      return double.parse(this);
    } catch (e) {
      return 0;
    }
  }

  String normalizeString() {
    return toLowerCase().trim();
  }
}

extension FilenameParser on String {

  String extractCtFromUrl() {
    // Extraer el nombre del archivo de la URL
    final fileName = split('/').last;
    
    // Remover la extensión .json
    final nameWithoutExtension = fileName.replaceAll('.json', '');
    
    // Remover el sufijo -gasoductos
    final ctName = nameWithoutExtension.replaceAll('-gasoductos', '');
    
    return ctName;
  }
  
  /// Método más genérico para extraer CT de cualquier URL de tracks
  String extractCtName() {
    final fileName = split('/').last; // Obtener nombre del archivo
    final withoutExtension = fileName.split('.').first; // Remover extensión
    
    // Remover sufijos conocidos
    final suffixes = ['-gasoductos', '-estaciones', '-valvulas', '-compresores'];
    String result = withoutExtension;
    
    for (final suffix in suffixes) {
      result = result.replaceAll(suffix, '');
    }
    
    return result;
  }
  
  String extractLastPart() {
    return split('-').last.split('.').first;
  }

  String extractPrefix() {
    // Elimina la extensión y toma todos los paquetes menos el último
    final name = split('.').first; // quita la extensión
    final parts = name.split('-');
    if (parts.length <= 1) return name;
    return parts.sublist(0, parts.length - 1).join('-');
  }
}

extension BuildContextEntension<T> on BuildContext {
  /*
    IPAD
    int get referenceScreenWidth => 820;
    int get referenceScreenHeight => 1180;
    */
  // IPHONE 14 PRO
  int get referenceScreenWidth => 393;
  int get referenceScreenHeight => 852;
  double get referenceAspectRatio =>
      referenceScreenWidth / referenceScreenHeight;

  bool get isMobile => MediaQuery.of(this).size.width <= 500.0;
  bool get isTablet =>
      MediaQuery.of(this).size.width < 1024.0 &&
      MediaQuery.of(this).size.width >= 650.0;
  bool get isSmallTablet =>
      MediaQuery.of(this).size.width < 650.0 &&
      MediaQuery.of(this).size.width > 500.0;
  bool get isDesktop => MediaQuery.of(this).size.width >= 1024.0;
  bool get isSmall =>
      MediaQuery.of(this).size.width < 850.0 &&
      MediaQuery.of(this).size.width >= 560.0;
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;
  Size get size => MediaQuery.of(this).size;

  double get defaultIconSize => rSize(7);
  double get dialogIconSize => rSize(15);

  double get aspectRatio => MediaQuery.of(this).size.aspectRatio;
  double get devicePixelRatio => MediaQuery.of(this).devicePixelRatio;
  double get screenRatio {
    if (orientation == Orientation.portrait) {
      return screenHeight / screenWidth;
    } else {
      return (screenWidth / screenHeight);
    }
  }

  double rWidth(double w) {
    double p = referenceScreenWidth / w;
    double valor = screenWidth / p;
    //double valor =  w * this.screenRatio;
    return valor;
  }

  double rHeight(double h) {
    double p = referenceScreenHeight / h;
    double valor = screenHeight / p;

    //double valor = h * this.screenRatio;
    return valor;
  }

  double rWidthLimit({
    required double w,
    required double max,
    required double min,
  }) {
    double valor = rWidth(w);
    if (valor > max) {
      return max;
    }
    if (valor < min) {
      return min;
    }
    return valor;
  }

  double rHeightLimit({
    required double h,
    required double max,
    required double min,
  }) {
    double valor = rHeight(h);
    if (valor > max) {
      return max;
    }
    if (valor < min) {
      return min;
    }
    return valor;
  }

  /*
    double pWidth(double p) => width * p / this.screenRatio;
    double pHeight(double p) {
      double valor = height * p / this.screenRatio;
      return valor;
    }
    */
  double rSize(double s) {
    double pw = s / referenceScreenWidth;
    double ph = s / referenceScreenHeight;
    double p = pw > ph ? pw : ph;
    double n = screenWidth > screenHeight ? screenWidth : screenHeight;
    double valor = n * p;
    return valor;
  }

  double rFontSize(double fs) {
    double valor = rSize(fs);
    return valor;
  }

  TextStyle? get tooltipstyle =>
      Theme.of(this).textTheme.displayMedium!.copyWith(
        fontWeight: FontWeight.bold,
        fontSize: rFontSize(8.0),
        color: Colors.yellow,
      );

  TextStyle? get displayMedium => Theme.of(
    this,
  ).textTheme.displayMedium!.copyWith(fontSize: rFontSize(18.0));
  TextStyle? get displaySmall => Theme.of(
    this,
  ).textTheme.displaySmall!.copyWith(fontSize: rFontSize(12.0));
  TextStyle? get headlineLarge => Theme.of(this).textTheme.headlineLarge;
  TextStyle? get headlineMedium =>
      Theme.of(this).textTheme.headlineMedium!.copyWith(color: whiteColor);
  TextStyle? get titleLarge => Theme.of(this).textTheme.titleLarge!.copyWith(
    overflow: TextOverflow.ellipsis,
    fontWeight: FontWeight.bold,
    color: Colors.black,
  );
  TextStyle? get titleMedium => Theme.of(this).textTheme.titleMedium!.copyWith(
    overflow: TextOverflow.ellipsis,
    fontWeight: FontWeight.bold,
    color: Colors.black,
  );
  TextStyle? get titleSmall => Theme.of(this).textTheme.titleSmall!.copyWith(
    overflow: TextOverflow.ellipsis,
    fontWeight: FontWeight.bold,
    color: Colors.black,
  );
  TextStyle? get hintStyle => Theme.of(this).textTheme.titleSmall!.copyWith(
    fontWeight: FontWeight.bold,
    color: Colors.black,
  );
  TextStyle? get labelLarge =>
      Theme.of(this).textTheme.labelLarge!.copyWith(color: Colors.black, overflow: TextOverflow.ellipsis);
  TextStyle? get bodySmall =>
      Theme.of(this).textTheme.bodySmall!.copyWith(color: Colors.black, overflow: TextOverflow.ellipsis);
  TextStyle? get bodyMedium =>
      Theme.of(this).textTheme.bodyMedium!.copyWith(color: Colors.black, overflow: TextOverflow.ellipsis);
  TextStyle? get inputLabel => Theme.of(
    this,
  ).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.bold);
  TextStyle? get inputText =>
      Theme.of(this).textTheme.bodyMedium!.copyWith(color: Colors.black);
  TextStyle? get dialogTextTitle => Theme.of(this).textTheme.bodyMedium!
      .copyWith(fontWeight: FontWeight.bold, fontSize: rFontSize(12.0));
  TextStyle? get buttonMedium => Theme.of(this).textTheme.bodyMedium!.copyWith(
    fontWeight: FontWeight.bold,
    fontSize: rFontSize(18.0),
  );
  TextStyle? get buttonDialog => Theme.of(this).textTheme.bodyMedium!.copyWith(
    fontWeight: FontWeight.bold,
    fontSize: rFontSize(12.0),
  );
  TextStyle? get titleTextStyle =>
      Theme.of(this).appBarTheme.titleTextStyle!.copyWith(color: Colors.black);
  TextStyle? get bodyExtraSmall => bodySmall?.copyWith(
    fontSize: rFontSize(10),
    height: 1.6,
    letterSpacing: .5,
  );
  TextStyle? get bodyLarge =>
      Theme.of(this).textTheme.bodyLarge!.copyWith(color: Colors.black);
  TextStyle? get dividerTextSmall => bodySmall?.copyWith(
    letterSpacing: 0.5,
    fontWeight: FontWeight.w700,
    fontSize: rFontSize(12.0),
  );
  TextStyle? get dividerTextLarge => bodySmall?.copyWith(
    letterSpacing: 1.5,
    fontWeight: FontWeight.w700,
    fontSize: rFontSize(13.0),
    height: 1.23,
  );
  TextStyle? get markertext => Theme.of(this).textTheme.titleMedium!.copyWith(
    fontWeight: FontWeight.bold,
    fontSize: rFontSize(3.0),
  );

  Color get primaryColor => Theme.of(this).primaryColor;
  Color get primaryColorDark => Theme.of(this).primaryColorDark;
  Color get primaryColorLight => Theme.of(this).primaryColorLight;
  Color get primary => Theme.of(this).colorScheme.primary;
  Color get onPrimary => Theme.of(this).colorScheme.onPrimary;
  Color get secondary => Theme.of(this).colorScheme.secondary;
  Color get onSecondary => Theme.of(this).colorScheme.onSecondary;
  Color get cardColor => Theme.of(this).cardColor;
  Color get errorColor => Theme.of(this).colorScheme.error;
  Color get surface => Theme.of(this).colorScheme.surface;

  Color get canvasColor => Theme.of(this).canvasColor;
  Color get focusColor => Theme.of(this).focusColor;
  Color get disabledColor => Theme.of(this).disabledColor;
  Color get dividerColor => Theme.of(this).dividerColor;
  Color get highlightColor => Theme.of(this).highlightColor;
  Color get hintColor => Theme.of(this).hintColor;
  Color get hoverColor => Theme.of(this).hoverColor;
  Color get primaryDark => Theme.of(this).primaryColorDark;
  Color get primaryLight => Theme.of(this).primaryColorLight;
  Color get shadowColor => Theme.of(this).shadowColor;
  Color get polylineColor => Colors.yellow;
  Color get buttonColor => Colors.blue[900]!;
  Color get actionButtonColor => whiteColor;

  BoxDecoration get maindecoration => BoxDecoration(
    borderRadius: BorderRadius.circular(0.0),
    color: whiteColor,
    border: const Border(
      top: BorderSide(width: 1, color: Colors.blueGrey),
      bottom: BorderSide(width: 1, color: Colors.blueGrey),
      left: BorderSide(width: 1, color: Colors.blueGrey),
      right: BorderSide(width: 1, color: Colors.blueGrey),
    ),
  );

  BoxDecoration get buttondecoration => BoxDecoration(
    borderRadius: BorderRadius.circular(8.0),
    color: buttonColor.withValues(alpha: 0.75),
    border: const Border(
      top: BorderSide(width: 1, color: whiteColor),
      bottom: BorderSide(width: 1, color: whiteColor),
      left: BorderSide(width: 1, color: whiteColor),
      right: BorderSide(width: 1, color: whiteColor),
    ),
  );

  BoxDecoration get bottomlinedecoration => const BoxDecoration(
    color: whiteColor,
    border: Border(bottom: BorderSide(width: 1, color: whiteColor)),
  );

  BoxDecoration get squaredecoration => const BoxDecoration(
    border: Border(
      bottom: BorderSide(width: 1, color: Colors.blueGrey),
      top: BorderSide(width: 1, color: Colors.blueGrey),
      left: BorderSide(width: 1, color: Colors.blueGrey),
      right: BorderSide(width: 1, color: Colors.blueGrey),
    ),
  );

  BoxDecoration get squaredecorationSelected => const BoxDecoration(
    border: Border(
      bottom: BorderSide(width: 2, color: Colors.yellow),
      top: BorderSide(width: 2, color: Colors.yellow),
      left: BorderSide(width: 2, color: Colors.yellow),
      right: BorderSide(width: 2, color: Colors.yellow),
    ),
  );

  BoxDecoration get markerdecoration => const BoxDecoration(
    color: Colors.blueAccent,
    border: Border(
      bottom: BorderSide(width: 1, color: Colors.yellow),
      top: BorderSide(width: 1, color: Colors.yellow),
      left: BorderSide(width: 1, color: Colors.yellow),
      right: BorderSide(width: 1, color: Colors.yellow),
    ),
  );

  BoxDecoration get actionbuttondecoration => BoxDecoration(
    color: Colors.blue[900]!,
    border: Border(
      top: BorderSide(width: 1, color: Colors.blue[900]!.getBorderColor()),
      bottom: BorderSide(width: 1, color: Colors.blue[900]!.getBorderColor()),
      left: BorderSide(width: 1, color: Colors.blue[900]!.getBorderColor()),
      right: BorderSide(width: 1, color: Colors.blue[900]!.getBorderColor()),
    ),
  );

  InputDecoration get boldInputDecoration => InputDecoration(
    fillColor: Colors.blueGrey.withValues(alpha: 0.1),
    filled: true,
    border: OutlineInputBorder(
      borderSide: BorderSide(
        color: Colors.black, // Color negro
        width: 2.0, // Ancho doble
      ),
    ),
    focusedBorder: OutlineInputBorder(
      // Opcional: Borde al enfocar
      borderSide: BorderSide(color: Colors.black, width: 2.0),
    ),
    enabledBorder: OutlineInputBorder(
      // Opcional: Borde cuando está habilitado
      borderSide: BorderSide(color: Colors.black, width: 2.0),
    ),
    floatingLabelBehavior: FloatingLabelBehavior.always, // Label siempre arriba
    labelStyle: TextStyle(
      fontWeight: FontWeight.bold, // Label en negrita
      fontSize: 14, // Tamaño más pequeño para diferenciar
      color: Colors.blueGrey.shade800, // Color más oscuro para mayor contraste
      letterSpacing: 0.5, // Espaciado entre letras
    ),
    hintStyle: TextStyle(
      fontWeight: FontWeight.normal,
      fontSize: 16,
      color: Colors.grey.shade600,
    ),
  );

  InputDecoration get normalInputDecoration => InputDecoration(
    border: OutlineInputBorder(
      borderSide: BorderSide(
        color: Colors.black54, // Color negro
        width: 1.0, // Ancho doble
      ),
    ),
    focusedBorder: OutlineInputBorder(
      // Opcional: Borde al enfocar
      borderSide: BorderSide(color: Colors.black54, width: 1.0),
    ),
    enabledBorder: OutlineInputBorder(
      // Opcional: Borde cuando está habilitado
      borderSide: BorderSide(color: Colors.black54, width: 1.0),
    ),
    floatingLabelBehavior: FloatingLabelBehavior.always, // Label siempre arriba
    labelStyle: TextStyle(
      color: Colors.blueGrey.shade800, // Color más oscuro
      fontWeight: FontWeight.w600, // Semi-negrita
      fontSize: 14, // Tamaño más pequeño
      letterSpacing: 0.5,
    ),
    hintStyle: TextStyle(
      color: Colors.grey.shade600,
      fontWeight: FontWeight.normal,
      fontSize: 16, // Valor ligeramente más grande que el label
    ),
  );



  InputDecoration get inputDecoration => InputDecoration(
    alignLabelWithHint: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8.0),
      borderSide: BorderSide(
        color: Colors.grey.shade200, // Borde gris muy claro
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8.0),
      borderSide: BorderSide(
        color: Colors.grey.shade200, // Borde gris muy claro
      ),
    ),
    errorStyle: TextStyle(
      color: Colors.red.shade900, // Color de texto de error rojo intenso
    ),
    labelStyle: const TextStyle(
      color: whiteColor, // Texto blanco
    ),
  );

  double get longestSide => MediaQuery.of(this).size.longestSide;
  double get shortestSide => MediaQuery.of(this).size.shortestSide;
  Orientation get orientation => MediaQuery.of(this).orientation;
  EdgeInsets get padding => MediaQuery.of(this).padding;
}

extension ElevatedButtonExtension on ElevatedButton {
  ElevatedButton customButton(String text, VoidCallback onPressed) =>
      ElevatedButton(
        onPressed: onPressed,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all<Color>(
            whiteColor,
          ), // Fondo blanco
          side: WidgetStateProperty.all<BorderSide>(
            BorderSide(color: Colors.grey.shade500),
          ), // Borde gris medio
          foregroundColor: WidgetStateProperty.all<Color>(
            Colors.black,
          ), // Color de texto negro
        ),
        child: AutoSizeText(text),
      );
}


 extension NumFormatting on num {                                                                                                                                                               
    /// Formatea el número con coma como separador decimal                                                                                                                                       
    String toStringWithComma({int decimals = 2}) {
      final formatter = NumberFormat('#,##0.${'0' * decimals}', 'es_ES');                                                                                                                        
      return formatter.format(this);                        
    }                                                                                                                                                                                            
  } 

extension WidgetExt on Widget {
  Expanded expanded({int flex = 1}) => Expanded(flex: flex, child: this);

  Opacity setOpacity(double val) => Opacity(opacity: val, child: this);

  Padding withPadding(EdgeInsets padding) => Padding(padding: padding, child: this);

  SizedBox box({double? width, double? height}) => SizedBox(width: width, height: height, child: this);

  Center center() => Center(child: this);

  Widget centered({EdgeInsetsGeometry? padding, Color? color}) {
    return Container(alignment: Alignment.center, padding: padding, color: color, child: this);
  }

  Widget onClick(Function() onClick) => InkWell(onTap: onClick, child: this);

  RotatedBox rotate(int quarterTurns) => RotatedBox(quarterTurns: quarterTurns, child: this);
}


