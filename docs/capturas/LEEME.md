# Capturas del manual de operario v3

Suelta aquí los PNG con **exactamente estos nombres**. El manual ya tiene el hueco
reservado: mientras falte un fichero se ve un marco punteado con su nombre dentro;
en cuanto lo pongas y regeneres, la captura ocupa ese hueco.

Dispositivo acordado: **iPhone**, orientación vertical.

> El punto 1 (diálogos de permiso de ubicación) **no necesita captura**: el manual los
> dibuja en HTML/CSS con el texto real del `Info.plist`. Si algún día cambian esos textos
> en `ios/Runner/Info.plist`, hay que reflejarlo en el bloque `.shot.mock` de `manual_v4.html`.

| Fichero | Qué tiene que verse |
|---|---|
| `02_login.png` | Login completo: usuario relleno, *Recordar contraseña* activado, botones **Iniciar sesión** / **Sincronizar**, enlace **¿Contraseña olvidada?** y la versión abajo |
| `03_recuperar_dialogo.png` | Diálogo **Recuperar contraseña** con el campo Email |
| `04_recuperar_codigo.png` | Pantalla del código de 6 dígitos + nueva contraseña + **Reenviar código** |
| `05_lista.png` | Lista agrupada por CT con la barra verde completa arriba — que se vean los **5 iconos**, incluido el de traza |
| `06_detalle_datos.png` | Pestaña **Datos**: cabecera, las 4 pestañas, desplegables Tipo/Estado, descripción y el mapa con **Editar extremos** |
| `07_detalle_mensajes.png` | Pestaña **Mensajes** con al menos dos burbujas (una propia verde, una ajena gris) y la caja de escritura |
| `08_camara_foto.png` | Cámara de la app en modo **FOTO** (pestaña FOTO activa en verde) |
| `09_camara_video.png` | Cámara **grabando** en modo VÍDEO, con el indicador **REC** visible |
| `10_traza_finalizar.png` | Diálogo **Finalizar registro de traza** con el nombre propuesto y **Aceptar**. Si cabe, el botón rojo ⏹ de la barra |
| `11_mapa.png` | Mapa global con zoom ≥14: segmentos de colores y algún PK/hito. Mejor con la **leyenda abierta** |
| `12_lineas_corte.png` | Modo corte activo con las **dos líneas ya marcadas** (4 puntos numerados), panel de estado abajo y el botón en **azul con ✓** |
| `13_editar_extremos.png` | Edición de extremos: los dos marcadores, longitud/superficie y los botones **Cancelar / Guardar** |
| `14_sync_descargar.png` | Sincronización con la tarjeta **Listo para trabajar en campo**, chip **Online**, contador **6 de 6 al día** y las 6 filas |
| `15_forzar_envio.png` | Forzar envío con un envío **EN CURSO**: barra de progreso, texto de progreso y el botón rojo **Cancelar todo** |
| `16_envio_resultado.png` | Banner de resultado con la línea de contadores. Si se puede provocar, con algún motivo de rechazo debajo |
| `17_reset.png` | Diálogo **Reset de datos locales** con el aviso y el botón rojo **Borrar todo** |

## Regenerar el PDF

```bash
docs/build_manual.sh
```
