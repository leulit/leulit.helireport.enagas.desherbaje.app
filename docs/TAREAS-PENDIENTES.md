2025-08-19
--> Poder cargar varias fotos a la vez desde la galeria

2026-08-18
--> Líneas de corte: una polyline de gasoducto con TODOS sus vértices fuera de pantalla pero cuyo tramo cruza el viewport queda excluida del corte. `MapaGlobalController.visibleGasoductoPolylines` filtra con `points.any(bounds.contains)`, así que esa traza no aparece ni en la validación de las líneas (aviso "no cruza ningún gasoducto") ni en la extracción de segmentos. Ocurre con vértices muy separados a zoom alto. Arreglo: filtrar por intersección del bounding box de la polyline con `visibleBounds`, no por pertenencia de vértices.

2027-07-28 
--> Tendríamos que una vez una operario envía los datos al final de la jornada, enviar también de forma transparente sin que el lo sepa aquellas actividades/segmentos en los que se ha cambiado el estado o se han añadido mensajes. Es decir deberían aparecer en forzar envío todas aquellas actividades/segmentos que se modifican durante el día independientemente del estado. Lo que cambiaría es cuales se borran de la base de datos local. Verificar también si se actualizan al sincronizar en la pantalla de sincronizar.


Al crear un nuevo segmento, debe salir directamente la traza dibujada al guardar la nueva actividad (ya activado)
Al activar los items de vigilancia, activar para que salga la foto
Activar que, en cuanto el Contratista proponga una modificación en el segmento, le llegue mail al personal de Enagás. También notificación en la plataforma
Activar que, en cuanto Enagás acepte/rechace una modificación en el segmento, le llegue mail al personal del Contratista. También notificación en la plataforma
Pido nuevamente los usuarios de ECOESPACIO y SINTRA y te los envío en cuanto los tenga
Activar la posibilidad de grabar el track de los trabajos realizados




