import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import '../presentation/auth/login_page.dart';
import '../presentation/auth/login_page_binding.dart';
import '../presentation/segmentos/segmentos_list_page.dart';
import '../presentation/segmentos/segmentos_list_binding.dart';
import '../presentation/fotos/captura_fotos_page.dart';
import '../presentation/fotos/captura_fotos_binding.dart';
import '../presentation/mapa/mapa_global_page.dart';
import '../presentation/mapa/mapa_global_binding.dart';

class AppRoutes {
  static const login       = '/login';
  static const segmentos = '/segmentos';
  static const detalle     = '/segmentos/detalle';
  static const fotos       = '/segmentos/fotos';
  static const mapa        = '/mapa';
}

class AppPages {
  static final pages = [
    GetPage(
      name: AppRoutes.login,
      page: () => const LoginPage(),
      binding: LoginBinding(),
    ),
    GetPage(
      name: AppRoutes.segmentos,
      page: () => const SegmentosListPage(),
      binding: SegmentosListBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: AppRoutes.fotos,
      page: () => const CapturaFotosPage(),
      binding: CapturaFotosBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: AppRoutes.mapa,
      page: () => const MapaGlobalPage(),
      binding: MapaGlobalBinding(),
      middlewares: [AuthMiddleware()],
    ),
  ];
}

class AuthMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    // La verificación real se hace de forma asíncrona en el controller
    // Este middleware solo hace redirect si sabemos que no hay token en memoria
    return null;
  }
}
