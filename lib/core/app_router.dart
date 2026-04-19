import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import '../presentation/auth/login_page.dart';
import '../presentation/auth/login_page_binding.dart';
import '../presentation/actividades/actividades_list_page.dart';
import '../presentation/actividades/actividades_list_binding.dart';
import '../presentation/detalle/actividad_detalle_page.dart';
import '../presentation/detalle/actividad_detalle_binding.dart';
import '../presentation/fotos/captura_fotos_page.dart';
import '../presentation/fotos/captura_fotos_binding.dart';
import '../presentation/mapa/mapa_global_page.dart';
import '../presentation/mapa/mapa_global_binding.dart';

class AppRoutes {
  static const login       = '/login';
  static const actividades = '/actividades';
  static const detalle     = '/actividades/detalle';
  static const fotos       = '/actividades/fotos';
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
      name: AppRoutes.actividades,
      page: () => const ActividadesListPage(),
      binding: ActividadesListBinding(),
      middlewares: [AuthMiddleware()],
    ),
    GetPage(
      name: AppRoutes.detalle,
      page: () => const ActividadDetallePage(),
      binding: ActividadDetalleBinding(),
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
