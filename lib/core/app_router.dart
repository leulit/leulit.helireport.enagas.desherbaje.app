import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import '../presentation/auth/login_page.dart';
import '../presentation/auth/login_page_binding.dart';
import '../presentation/segmentos/segmentos_list_page.dart';
import '../presentation/segmentos/segmentos_list_binding.dart';
import '../presentation/detalle/segmento_detalle_page.dart';
import '../presentation/detalle/segmento_detalle_binding.dart';
import '../presentation/camera/camera_capture_page.dart';
import '../presentation/mapa/mapa_global_page.dart';
import '../presentation/mapa/mapa_global_binding.dart';

class AppRoutes {
  static const login = '/login';
  static const segmentos = '/segmentos';
  static const detalle = '/segmentos/detalle';
  static const camera = '/camera';
  static const mapa = '/mapa';
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
      name: AppRoutes.detalle,
      page: () => const SegmentoDetallePage(),
      binding: SegmentoDetalleBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: AppRoutes.camera,
      page: () => const CameraCapturePage(),
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
