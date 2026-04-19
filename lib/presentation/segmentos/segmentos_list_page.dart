import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/app_router.dart';
import '../widgets/segmento_list_card_widget.dart';
import 'segmentos_list_controller.dart';

// ─── Colores de tema ────────────────────────────────────────────────────────
const _kGreen = Color(0xFF388E3C);
const _kGreenLight = Color(0xFFA5D6A7);
const _kGreenBg = Color(0xFFF1F8E9);

class SegmentosListPage extends GetView<SegmentosListController> {
  const SegmentosListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF1F8E9),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 2,
            color: const Color(0xFFA5D6A7),
          ),
        ),
        leading: const Padding(
          padding: EdgeInsets.all(8.0),
          child: Icon(Icons.eco, color: Color(0xFF388E3C)),
        ),
        title: Obx(() => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Segmentos',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B5E20),
                  ),
                ),
                Text(
                  '${controller.filtradas.length} segmentos',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            )),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined, color: Color(0xFF388E3C)),
            tooltip: 'Ver mapa',
            onPressed: () => Get.toNamed(AppRoutes.mapa),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF388E3C)),
            onPressed: controller.loadSegmentos,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF388E3C)),
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          _FiltrosBar(controller: controller),
          // Lista
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF388E3C),
                  ),
                );
              }
              if (controller.error.value != null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 8),
                      Text(controller.error.value!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: controller.loadSegmentos,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                );
              }
              if (controller.filtradas.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.work_off, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('Sin segmentos',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: controller.loadSegmentos,
                color: const Color(0xFF388E3C),
                child: ListView.builder(
                  itemCount: controller.filtradas.length,
                  itemBuilder: (_, i) => SegmentoListCard(
                    segmento: controller.filtradas[i],
                    onTap: () =>
                        controller.goToDetalle(controller.filtradas[i]),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  void _logout() {
    Get.dialog(
      AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Seguro que quieres cerrar sesión?'),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              Get.back();
              Get.offAllNamed(AppRoutes.login);
            },
            child: const Text('Salir', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ─── Barra de filtros ────────────────────────────────────────────────────────

class _FiltrosBar extends StatelessWidget {
  final SegmentosListController controller;

  const _FiltrosBar({required this.controller});

  static final _inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: _kGreenLight),
  );
  static final _focusedBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: _kGreen, width: 1.5),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kGreenBg,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) => controller.filterDescripcion.value = v,
              decoration: InputDecoration(
                hintText: 'Buscar por descripción…',
                hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: _kGreen, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: _inputBorder,
                enabledBorder: _inputBorder,
                focusedBorder: _focusedBorder,
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          /*
          const SizedBox(width: 8),
          Obx(() => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kGreenLight),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<TipoActividad?>(
                    value: controller.selectedTipo.value,
                    hint: const Text(
                      'Tipo',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF1B5E20)),
                    borderRadius: BorderRadius.circular(10),
                    isDense: true,
                    items: [
                      const DropdownMenuItem<TipoActividad?>(
                        value: null,
                        child: Text('Todos'),
                      ),
                      ...TipoActividad.values.map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(t.etiqueta),
                        ),
                      ),
                    ],
                    onChanged: controller.filterByTipo,
                  ),
                ),
              )),
              */
        ],
      ),
    );
  }
}
