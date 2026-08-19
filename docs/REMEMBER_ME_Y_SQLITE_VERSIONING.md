# Remember-Me y Versionado de SQLite — Guía portable

Documento de referencia para portar dos patrones de este proyecto a otra app Flutter/GetX:

1. **Remember-Me** en el login (precarga de usuario/contraseña y persistencia de sesión).
2. **Versionado de tablas SQLite mediante clases/métodos**, con migraciones incrementales y tabla outbox para sincronización.

Toda la documentación se apoya en el código real de este repositorio. Las rutas fuente están indicadas para poder comparar y validar.

---

## 1. Remember-Me

### 1.1 Qué se persiste y dónde

Se usan **dos** almacenes con roles distintos:

| Almacén | Cifrado | Uso |
|---|---|---|
| `flutter_secure_storage` | Sí (Keychain / Keystore) | Token de sesión (JWT) |
| `shared_preferences` | No | Datos de UX: último usuario, preferencias, JSON del usuario, lista de CTs, y — si el usuario lo activa — la contraseña para rellenar el formulario |

> **Nota de seguridad.** En esta app la contraseña se guarda en `SharedPreferences` **en texto plano** cuando el switch "Recordarme" está activo. Es un trade-off de UX aceptado por el proyecto (app empresarial, dispositivos corporativos). Si se porta a una app con otro perfil de riesgo, mover `last_password` a `FlutterSecureStorage` (ver §1.6 mejora recomendada).

### 1.2 Claves usadas

```dart
// Preferencias del formulario de login (SharedPreferences)
static const _keyLastUsuario      = 'last_usuario';
static const _keyLastPassword     = 'last_password';      // ⚠ texto plano
static const _keyRememberPassword = 'remember_password';

// Sesión (FlutterSecureStorage)
static const _tokenKey            = 'auth_token';

// Perfil cacheado (SharedPreferences)
static const _userIdKey           = 'user_id';
static const _userNameKey         = 'user_name';
static const _userUsuarioKey      = 'user_usuario';
static const _userJsonKey         = 'user_json';
static const _userCtsKey          = 'user_cts';           // JSON array de ints
```

### 1.3 Flujo end-to-end

```
Arranque app
    │
    ▼
LoginPageController.onInit()
    └── _loadSavedCredentials()
        ├── read 'remember_password' → bool → rememberPassword.value
        ├── read 'last_usuario'      → usuarioController.text
        └── if remember → read 'last_password' → passwordController.text

Usuario pulsa "Iniciar sesión"
    │
    ▼
login()
    ├── formKey.validate()
    ├── _saveCredentials()                    (antes del POST)
    │   ├── write 'last_usuario'
    │   ├── write 'remember_password'
    │   └── if remember  → write 'last_password'
    │      else          → remove 'last_password'
    ├── AuthRepositoryImpl.login(u, p)
    │   ├── provider.login()                  → UserModel + token
    │   ├── provider.getCts(user.id)          → rellena user.cts
    │   ├── secureStorage.write('auth_token')
    │   └── prefs.write('user_id' | 'user_name' | 'user_json' | 'user_cts')
    └── Get.offAllNamed(AppRoutes.segmentos)

Logout
    └── AuthRepositoryImpl.logout()
        ├── secureStorage.delete('auth_token')
        └── prefs.remove(user_id, user_name, user_usuario, user_json, user_cts)
        // ojo: NO borra last_usuario / last_password / remember_password
        // — el login sigue precargando para la próxima sesión.
```

### 1.4 Código portable

#### 1.4.1 Dependencias (`pubspec.yaml`)

```yaml
dependencies:
  get: ^4.7.2
  shared_preferences: ^2.3.3
  flutter_secure_storage: ^10.0.0
```

#### 1.4.2 Controller (copia directa)

Fuente: `lib/presentation/auth/login_page_controller.dart`

```dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_router.dart';
import '../../data/repository/auth_repository_impl.dart';

class LoginPageController extends GetxController {
  final _repo = AuthRepositoryImpl();

  final usuarioController  = TextEditingController();
  final passwordController = TextEditingController();
  final formKey            = GlobalKey<FormState>();

  final isLoading        = false.obs;
  final showPassword     = false.obs;
  final rememberPassword = false.obs;
  final error            = Rx<String?>(null);

  static const _keyLastUsuario      = 'last_usuario';
  static const _keyLastPassword     = 'last_password';
  static const _keyRememberPassword = 'remember_password';

  @override
  void onInit() {
    super.onInit();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_keyRememberPassword) ?? false;
    rememberPassword.value = remember;

    final lastUsuario = prefs.getString(_keyLastUsuario);
    if (lastUsuario != null) usuarioController.text = lastUsuario;

    if (remember) {
      final lastPassword = prefs.getString(_keyLastPassword);
      if (lastPassword != null) passwordController.text = lastPassword;
    }
  }

  void toggleShowPassword()     => showPassword.value     = !showPassword.value;
  void toggleRememberPassword() => rememberPassword.value = !rememberPassword.value;

  Future<void> login() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    isLoading.value = true;
    error.value = null;
    try {
      await _saveCredentials();
      await _repo.login(
        usuarioController.text.trim(),
        passwordController.text,
      );
      Get.offAllNamed(AppRoutes.home); // ajustar ruta destino
    } catch (e) {
      error.value = _parseError(e);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastUsuario, usuarioController.text.trim());
    await prefs.setBool(_keyRememberPassword, rememberPassword.value);
    if (rememberPassword.value) {
      await prefs.setString(_keyLastPassword, passwordController.text);
    } else {
      await prefs.remove(_keyLastPassword);
    }
  }

  String _parseError(Object e) {
    final str = e.toString();
    if (str.contains('401') || str.contains('credencial')) {
      return 'Usuario o contraseña incorrectos';
    }
    if (str.contains('SocketException') || str.contains('network')) {
      return 'Sin conexión a internet';
    }
    return 'Error al iniciar sesión. Inténtalo de nuevo.';
  }

  @override
  void onClose() {
    usuarioController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}
```

#### 1.4.3 Widget Switch "Recordarme"

```dart
Obx(() => Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    const Text('Recordar contraseña'),
    Switch(
      value: controller.rememberPassword.value,
      onChanged: (_) => controller.toggleRememberPassword(),
    ),
  ],
))
```

#### 1.4.4 Repository que persiste sesión

Fuente: `lib/data/repository/auth_repository_impl.dart`

```dart
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/user_entity.dart';
import '../../domain/repository/auth_repository.dart';
import '../providers/auth_data_provider.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthDataProvider _provider = AuthDataProvider();
  final _storage = const FlutterSecureStorage();

  static const _tokenKey       = 'auth_token';
  static const _userIdKey      = 'user_id';
  static const _userNameKey    = 'user_name';
  static const _userUsuarioKey = 'user_usuario';
  static const _userJsonKey    = 'user_json';
  static const _userCtsKey     = 'user_cts';

  @override
  Future<UserModel> login(String usuario, String password) async {
    final user = await _provider.login(usuario, password);
    user.cts = await _provider.getCts(user.id); // opcional según dominio

    await _storage.write(key: _tokenKey, value: user.token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt   (_userIdKey,      user.id);
    await prefs.setString(_userNameKey,    user.nombre);
    await prefs.setString(_userUsuarioKey, user.usuario);
    await prefs.setString(_userJsonKey,    jsonEncode(user.toJson()));
    await prefs.setString(_userCtsKey,     jsonEncode(user.ctsId()));
    return user;
  }

  @override
  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_userUsuarioKey);
    await prefs.remove(_userJsonKey);
    await prefs.remove(_userCtsKey);
    // No tocar last_usuario / last_password / remember_password:
    // son preferencias del formulario, no del estado de sesión.
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userJsonKey);
    if (userJson == null) return null;
    try {
      final decoded = jsonDecode(userJson) as Map<String, dynamic>;
      final user = UserModel.fromJson(decoded);
      user.token = token;
      return user;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> isAuthenticated() async {
    final token = await _storage.read(key: _tokenKey);
    return token != null && token.isNotEmpty;
  }
}
```

### 1.5 AuthMiddleware (auto-login al arrancar)

El `AuthMiddleware` de GetX lee `auth_token` en el `secureStorage`; si existe se entra directo a la ruta protegida, si no, se redirige al login (donde el controller precarga `last_usuario` / `last_password`).

```dart
class AuthMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    final auth = AuthRepositoryImpl();
    // En GetPage.middlewares se evalúa síncronamente — envuelve en FutureBuilder
    // o valida el token en un splash previo si quieres una sola llamada.
    return null; // simplificado; ver app_router.dart del proyecto
  }
}
```

### 1.6 Mejora recomendada al portar

Si la app destino maneja datos sensibles, mover la contraseña a `FlutterSecureStorage`:

```dart
// Cambiar estas líneas del controller:
await prefs.setString(_keyLastPassword, passwordController.text);
// por:
await _secureStorage.write(key: _keyLastPassword, value: passwordController.text);

// Y simétrico al leer / borrar.
```

El patrón del flujo no cambia, solo el backing store.

---

## 2. Versionado de tablas SQLite mediante clases

> **Aviso (2026-08-19):** este apartado NO refleja la arquitectura de este repo desde el rediseño del patrón outbox (2026-06). Hoy el esquema es modular por entidad (`_entity_schema_version` + `LocalStore<T>.migrate(DatabaseExecutor, from, to)` + `OfflineDatabase.migrateEntity` transaccional — ver CLAUDE.md §"Schema modular"); el fichero `outbox_schema.dart` que se cita más abajo ya no existe en el repo. El §1 (Remember-Me) de este documento sigue vigente.

### 2.1 Idea central

Cada tabla vive en su **propio método `_create…Table(Database db)`** de la clase `LocalDatabase`. `onCreate` llama a todos; `onUpgrade` llama solo a los afectados por cada salto de versión. Así:

- Cada cambio de schema es una migración explícita, numerada y auditables en el histórico.
- El salto entre versiones describe la intención (crear tabla nueva, purgar cache obsoleta, renombrar columna...).
- Añadir una tabla nueva es: un nuevo método + una línea en `onCreate` + un `if (oldVersion < N)` en `onUpgrade`.
- La tabla outbox (`sync_queue`) está encapsulada en su propia clase `OutboxSchema` para poder reutilizarla fuera de la app principal.

### 2.2 Esqueleto del LocalDatabase

Fuente: `lib/data/local/local_database.dart`

```dart
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../core/sync/sync.dart'; // OutboxSchema

class LocalDatabase {
  static LocalDatabase? _instance;
  static Database? _db;

  LocalDatabase._();
  static LocalDatabase get instance => _instance ??= LocalDatabase._();

  Future<Database> get database async => _db ??= await _initDb();

  Future<Database> _initDb() async {
    final dbPath   = await getDatabasesPath();
    final fullPath = path.join(dbPath, 'mi_app.db');
    return openDatabase(
      fullPath,
      version: 8,              // ← versión ACTUAL del schema
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // --- onCreate: app instalada desde cero ------------------------------

  Future<void> _onCreate(Database db, int version) async {
    await _createSegmentosTable(db);
    await _createImagenesTable(db);
    await _createGasoductosTable(db);
    await _createPksTable(db);
    await OutboxSchema.ensure(db);
  }

  // --- onUpgrade: migraciones incrementales ----------------------------

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createGasoductosTable(db);
    }
    if (oldVersion < 4) {
      await OutboxSchema.ensure(db);
    }
    if (oldVersion < 5) {
      // ActividadEntity → SegmentoEntity: tabla refactorizada.
      // El backend es fuente de verdad; se descarta caché local.
      await db.execute('DROP TABLE IF EXISTS actividades');
      await db.delete('sync_queue',
          where: 'entity_type = ?', whereArgs: ['actividad']);
      await _createSegmentosTable(db);
    }
    if (oldVersion < 6) {
      await db.execute('DROP TABLE IF EXISTS imagenes_actividad');
      await db.delete('sync_queue',
          where: 'entity_type = ?', whereArgs: ['imagen']);
      await _createImagenesTable(db);
    }
    if (oldVersion < 7) {
      await db.execute('DROP TABLE IF EXISTS gasoductos');
      await _createGasoductosTable(db);
    }
    if (oldVersion < 8) {
      await _createPksTable(db);
    }
  }

  // --- definiciones de tablas ------------------------------------------

  Future<void> _createSegmentosTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS segmentos (
        id                INTEGER PRIMARY KEY,
        ct_id             INTEGER NOT NULL DEFAULT 0,
        nombre            TEXT,
        descripcion       TEXT NOT NULL DEFAULT '',
        estado            TEXT NOT NULL DEFAULT 'Propuesta',
        ubicacion_gis     TEXT,
        created_at        TEXT,
        synced_at         TEXT,
        needs_sync        INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_segmentos_ct    ON segmentos(ct_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_segmentos_sync  ON segmentos(needs_sync)');
  }

  Future<void> _createImagenesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS imagenes_segmento (
        client_id      TEXT PRIMARY KEY,
        id             INTEGER,
        segmento_id    INTEGER NOT NULL,
        tipo_foto      TEXT NOT NULL,
        ruta           TEXT NOT NULL,
        url            TEXT,
        latitud        REAL,
        longitud       REAL,
        capturada_at   TEXT NOT NULL,
        subida_at      TEXT,
        synced_at      TEXT,
        needs_sync     INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_imagenes_segmento_seg '
      'ON imagenes_segmento(segmento_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_imagenes_segmento_remote '
      'ON imagenes_segmento(id) WHERE id IS NOT NULL',
    );
  }

  Future<void> _createPksTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pks (
        id        TEXT NOT NULL,
        ct_id     INTEGER NOT NULL,
        label     TEXT NOT NULL DEFAULT '',
        lat       REAL NOT NULL,
        lng       REAL NOT NULL,
        synced_at TEXT NOT NULL DEFAULT (datetime('now')),
        PRIMARY KEY (id, ct_id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pks_ct ON pks(ct_id)');
  }

  Future<void> _createGasoductosTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS gasoductos (
        id           TEXT NOT NULL,
        nombre       TEXT NOT NULL DEFAULT '',
        ct_id        INTEGER NOT NULL,
        points_json  TEXT NOT NULL,
        synced_at    TEXT NOT NULL DEFAULT (datetime('now')),
        PRIMARY KEY (id, ct_id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gasoductos_ct ON gasoductos(ct_id)');
  }
}
```

### 2.3 OutboxSchema (clase independiente)

Fuente: `lib/core/sync/outbox/outbox_schema.dart`

```dart
import 'package:sqflite/sqflite.dart';

abstract class OutboxSchema {
  static const tableName = 'sync_queue';

  static const _createTable = '''
    CREATE TABLE IF NOT EXISTS $tableName (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type  TEXT    NOT NULL,
      entity_id    TEXT    NOT NULL,
      operation    TEXT    NOT NULL,
      status       TEXT    NOT NULL DEFAULT 'pending',
      attempts     INTEGER NOT NULL DEFAULT 0,
      last_error   TEXT,
      payload      TEXT,
      created_at   INTEGER NOT NULL,
      synced_at    INTEGER,
      remote_id    TEXT,
      UNIQUE(entity_type, entity_id, operation)
    )
  ''';

  static const _indexStatus =
      'CREATE INDEX IF NOT EXISTS idx_${tableName}_status ON $tableName(status)';
  static const _indexType =
      'CREATE INDEX IF NOT EXISTS idx_${tableName}_type   ON $tableName(entity_type, status)';

  static Future<void> ensure(Database db) async {
    await db.execute(_createTable);
    await db.execute(_indexStatus);
    await db.execute(_indexType);
  }
}
```

El constraint `UNIQUE(entity_type, entity_id, operation)` garantiza **idempotencia**: si la UI enqueue dos veces la misma operación sobre la misma entidad, sqlite rechaza el duplicado.

### 2.4 Columnas de sync recomendadas

Cada tabla que se sincroniza con backend debería incluir:

| Columna | Tipo | Uso |
|---|---|---|
| `id` | INTEGER | ID remoto asignado por el backend. `NULL` mientras no se haya subido. |
| `client_id` | TEXT | UUID generado en cliente (p. ej. `Uuid().v4()`). Estable desde la creación offline; es la primary key local de entidades que aún no tienen `id`. |
| `needs_sync` | INTEGER (0/1) | Flag que el SyncEngine usa para recorrer cambios pendientes. |
| `synced_at` | TEXT | Timestamp de la última sincronización exitosa. |

La tabla outbox (`sync_queue`) almacena la **intención** (op pendiente), mientras que `needs_sync` sobre cada entidad permite reconstruir el outbox o filtrar rápidamente lo pendiente.

### 2.5 Historial de migraciones de este proyecto

| Versión | Cambio | Motivo |
|---|---|---|
| 2 | +tabla `gasoductos` | Cache de trazas de gasoducto |
| 4 | +tabla `sync_queue` | Activación del outbox pattern |
| 5 | `actividades` → `segmentos` | Refactor de dominio (drop + recreate) |
| 6 | `imagenes_actividad` → `imagenes_segmento` (+`client_id`) | Nueva estructura, outbox idempotente |
| 7 | `gasoductos.ct TEXT` → `ct_id INTEGER` | Tipado coherente con el backend |
| 8 | +tabla `pks` | Cache de puntos kilométricos |

> **Estrategia del proyecto:** migraciones destructivas (DROP + recreate) porque el backend es fuente de verdad; la caché local es desechable. En apps donde el dispositivo es fuente de verdad, sustituir por `ALTER TABLE … ADD COLUMN` con `DEFAULT`.

### 2.6 Añadir una tabla nueva (receta)

1. **Subir la versión** en `_initDb`: `version: 9`.
2. **Añadir el método de creación**:
   ```dart
   Future<void> _createNuevaTablaTable(Database db) async {
     await db.execute('''
       CREATE TABLE IF NOT EXISTS nueva_tabla (
         id          INTEGER PRIMARY KEY,
         campo       TEXT NOT NULL,
         synced_at   TEXT,
         needs_sync  INTEGER NOT NULL DEFAULT 0
       )
     ''');
   }
   ```
3. **Invocarlo desde `_onCreate`**:
   ```dart
   await _createNuevaTablaTable(db);
   ```
4. **Invocarlo desde `_onUpgrade`** para los dispositivos que ya tienen la app instalada:
   ```dart
   if (oldVersion < 9) {
     await _createNuevaTablaTable(db);
   }
   ```

### 2.7 Añadir una columna a una tabla existente

Migración **aditiva** (preserva datos):

```dart
if (oldVersion < 10) {
  await db.execute('''
    ALTER TABLE segmentos
    ADD COLUMN nueva_columna TEXT NOT NULL DEFAULT ''
  ''');
}
```

Restricciones SQLite:
- `ADD COLUMN` requiere `DEFAULT` si la columna es `NOT NULL`.
- No existe `DROP COLUMN` ni `RENAME COLUMN` en versiones antiguas de sqlite. Si es necesario: crear tabla nueva → `INSERT INTO nueva SELECT … FROM vieja` → `DROP TABLE vieja` → `ALTER TABLE nueva RENAME TO vieja`.

Migración **destructiva** (descarta datos locales, los repuebla el backend):

```dart
if (oldVersion < 10) {
  await db.execute('DROP TABLE IF EXISTS segmentos');
  await db.delete('sync_queue',
      where: 'entity_type = ?', whereArgs: ['segmento']);
  await _createSegmentosTable(db);
}
```

### 2.8 Reglas prácticas

- **Todos los `CREATE TABLE` usan `IF NOT EXISTS`** → los métodos son idempotentes y se pueden llamar también desde `onUpgrade` sin miedo.
- **Índices también con `IF NOT EXISTS`** por la misma razón.
- **Tras un DROP destructivo, purgar el outbox** de la entidad afectada:
  ```dart
  await db.delete('sync_queue',
      where: 'entity_type = ?', whereArgs: ['<entity>']);
  ```
  De lo contrario el SyncEngine intentará sincronizar registros que ya no existen localmente.
- **Nunca tocar `onUpgrade` pasado** — solo añadir nuevos `if (oldVersion < N)` al final. Si modificas una migración ya publicada, los usuarios que saltaron por ella ejecutarán la nueva versión la próxima vez, lo que rompe supuestos.
- **Foreign keys**: sqlite las tiene **desactivadas por defecto**. Si las necesitas, activarlas en `onConfigure`:
  ```dart
  return openDatabase(
    fullPath,
    version: 8,
    onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    onCreate: _onCreate,
    onUpgrade: _onUpgrade,
  );
  ```

---

## 3. Checklist de portabilidad

Al trasladar estos patrones a otra app:

**Remember-Me**
- [ ] Añadir `shared_preferences` y `flutter_secure_storage` al `pubspec.yaml`.
- [ ] Copiar `LoginPageController` y adaptar `AppRoutes.home` al destino.
- [ ] Copiar `AuthRepositoryImpl` y adaptar `AuthDataProvider` al endpoint real.
- [ ] Ajustar `logout()` para NO borrar `last_usuario` / `last_password` / `remember_password` si quieres que la precarga siga funcionando tras logout (el proyecto actual se comporta así).
- [ ] Decidir si la contraseña se guarda en plano (SharedPreferences) o cifrada (SecureStorage) según perfil de seguridad.
- [ ] Añadir el Switch de "Recordarme" al formulario (ver §1.4.3).

**SQLite versioning**
- [ ] Copiar esqueleto de `LocalDatabase` y ajustar nombre de fichero `.db`.
- [ ] Crear un método `_create<Tabla>Table(db)` por cada entidad del dominio.
- [ ] Incluir columnas `id`, `client_id` (si aplica offline-first), `needs_sync`, `synced_at` en cada entidad.
- [ ] Copiar `OutboxSchema` tal cual si se va a usar el outbox pattern (ver skill `flutter-offline-sync`).
- [ ] Empezar con `version: 1`. Documentar cada incremento en un histórico equivalente al §2.5.
- [ ] Activar `PRAGMA foreign_keys = ON` en `onConfigure` si el modelo usa FKs.

---

## 4. Referencias en este repositorio

- Login page + controller: `lib/presentation/auth/`
- Repository de auth: `lib/data/repository/auth_repository_impl.dart`
- Provider de auth: `lib/data/providers/auth_data_provider.dart`
- Base de datos local: `lib/data/local/local_database.dart`
- Schema del outbox: `lib/core/sync/outbox/outbox_schema.dart`
- Skill con el patrón offline-first completo: `.claude/skills/flutter-offline-sync/SKILL.md`
