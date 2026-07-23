# Backend — Recuperar contraseña por código OTP (app Desherbaje)

Flujo: la app pide email → backend manda un **código de 6 dígitos** por email →
el operador teclea el código + la contraseña nueva en la misma pantalla → cambio.
Todo dentro de la app, sin enlaces ni navegador.

**2 endpoints.** Ambos bajo `/api/enagas/v1`, misma firma HMAC que el resto (sin
sesión ni Bearer).

---

## Endpoint 1 — Pedir código

```
POST /api/enagas/v1/users/recuperar-password
Body: { "email": "operador@empresa.com" }
```

**Siempre 200.** El desenlace va en el cuerpo:

```jsonc
{ "success": true,  "message": "Te hemos enviado un código de 6 dígitos a tu email." }
{ "success": false, "message": "Ese email no existe en la base de datos de usuarios." }
{ "success": false, "message": "No hemos podido enviar el email en este momento. Inténtalo de nuevo en unos minutos." }
```

Lógica:
1. `SELECT id, nombre, email FROM usuarios WHERE email = ? AND deleted IS NULL`. Sin fila → `success:false` "no existe".
2. Invalidar códigos previos del email: `UPDATE password_reset_tokens SET used_at = NOW() WHERE email = ? AND used_at IS NULL`.
3. Generar código: **6 dígitos**, `String(crypto.randomInt(0, 1000000)).padStart(6, '0')`.
4. Insertar fila con `expires_at = NOW() + 10 min` y `attempts = 0`.
5. Enviar email con el código (`EmailService`, ya existe). Cuerpo tipo: "Tu código de recuperación es **473829**. Caduca en 10 minutos."
6. `EmailService.isConfigured()` false o envío lanza → `success:false` "no hemos podido enviar".

---

## Endpoint 2 — Cambiar contraseña (valida código + cambia, en una sola llamada)

```
POST /api/enagas/v1/users/restablecer-password
Body: { "email": "...", "codigo": "473829", "newPassword": "nueva123" }

200 → { "success": true,  "message": "Contraseña actualizada. Ya puedes iniciar sesión." }
400 → { "error": "Código incorrecto o caducado" }
400 → { "error": "La contraseña debe tener al menos 6 caracteres" }
```

Lógica:
1. Validar el código (reglas abajo). Inválido → 400 `{error}`.
2. Validar `newPassword` (mínimo 6 chars, o lo que decidáis) → 400 `{error}`.
3. `UPDATE usuarios SET password = ? WHERE id = ?`.
4. `UPDATE password_reset_tokens SET used_at = NOW() WHERE id = ?` (un solo uso).

La app lee `message` en 200 y `error` en 400, y los muestra tal cual. Que sean legibles en español.

---

## Reglas de validación del código

Un código es válido si, para ese `email`:
- Existe fila con ese `token` (= el código).
- `used_at IS NULL`.
- `expires_at > NOW()`.
- `attempts < 5`.

En cada intento fallido: `UPDATE ... SET attempts = attempts + 1 WHERE email = ? AND used_at IS NULL`. Con 5 fallos el código queda quemado (fuerza a pedir uno nuevo) → protege contra fuerza bruta sobre 6 dígitos.

---

## Tabla

Migración `database/migrations/015_create_password_reset_tokens.sql`:

```sql
CREATE TABLE IF NOT EXISTS `password_reset_tokens` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `usuario_id` INT UNSIGNED NOT NULL,
  `email`      VARCHAR(255) NOT NULL,
  `token`      VARCHAR(6)   NOT NULL,          -- el código OTP de 6 dígitos
  `attempts`   TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `expires_at` DATETIME     NOT NULL,
  `used_at`    DATETIME     NULL DEFAULT NULL,
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `idx_email` (`email`),
  INDEX `idx_expires` (`expires_at`),
  CONSTRAINT `fk_reset_token_usuario`
    FOREIGN KEY (`usuario_id`) REFERENCES `usuarios`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

Nota: `token` NO es único (el código de 6 dígitos se repite entre usuarios). La identidad de un intento es `(email, token, used_at IS NULL)`.

---

## Ficheros a tocar (patrón del propio repo)

- `src/api/routes/usuarios.routes.js` → registrar las 2 rutas con su schema de body.
- `src/services/usuarios.service.js` → `solicitarRecuperacion(email)`, `restablecerPassword(email, codigo, newPassword)`.
- `src/infrastructure/repositories/usuarios.repository.js` → `findByEmail`, `createResetCode`, `findValidCode`, `incrementAttempts`, `invalidateCodesByEmail`, `markUsed`, `updatePassword`.

---

## Aviso importante — contraseña en claro

Hoy `usuarios.password` se guarda **en claro** (`WHERE u.usuario = ? AND u.password = ?` en `findByCredentialsWithCts`). El endpoint 2 guardaría también en claro para no romper el login. Si queréis hashear, es una migración aparte que toca login, `/users/new` y `/users/save` a la vez — no lo mezcléis con esto.

---

## Env

Ya soportadas por `EmailService` (`config/index.js`):
```
ENAGAS_SMTP_HOST / _PORT / _USER / _PASSWORD / _FROM_NAME / _FROM_EMAIL
```
El flujo OTP **no** necesita `APP_URL` (no hay enlace).
