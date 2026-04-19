/// Descriptor neutro de un fichero a descargar por [JsonLoaderService]. El
/// [group] permite a los consumidores filtrar los eventos `geoJsonLoaded` por
/// dominio (`'gasoducto'`, `'segmentos_geo'`, …) sin acoplar el loader a un
/// tipo concreto. El [filename] es la URL completa que se descargará.
class FileData {
  final String group;
  final String filename;

  /// Identificador opcional propio del consumidor (ej. `ctId`). El loader no
  /// lo usa, simplemente lo propaga en `originalFileData` para que el handler
  /// pueda saber a qué entidad pertenecen los datos.
  final Object? tag;

  const FileData({
    required this.group,
    required this.filename,
    this.tag,
  });

  @override
  String toString() => 'FileData(group: $group, filename: $filename)';
}
