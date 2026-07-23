# Backend — Recuperar contraseña (app Desherbaje)

Estado: la app móvil YA llama al endpoint. Falta implementarlo en `BACKEND-ENAGAS`.

## 1. Endpoint que la app llama

```
POST /api/enagas/v1/users/recuperar-password
Body: { "email": "operador@empresa.com" }
```

- Misma firma HMAC que el resto de la API (`X-HMAC-Signature`, `X-Timestamp`). Sin sesión ni Bearer.
- Respuestas — **siempre 200**, el desenlace va en el cuerpo:

```jsonc
// OK
{ "success": true,  "message": "En breve recibirás un email con las instrucciones para recuperar tu contraseña." }
// Email no existe / usuario borrado
{ "success": false, "message": "Ese email no existe en la base de datos de usuarios. Comprueba que la dirección sea correcta." }
// Fallo de envío SMTP
{ "success": false, "message": "No hemos podido enviar el email en este momento. Inténtalo de nuevo en unos minutos." }
```

- 4xx/5xx solo para errores reales de servidor, con `{ "error": "..." }`.
- La app muestra `message` tal cual al operador. Que sea legible en español.

## 2. Tabla de tokens

Nueva migración `database/migrations/015_create_password_reset_tokens.sql`:

```sql
CREATE TABLE IF NOT EXISTS `password_reset_tokens` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `usuario_id` INT UNSIGNED NOT NULL,
  `email`      VARCHAR(255) NOT NULL,
  `token`      VARCHAR(64)  NOT NULL,
  `expires_at` DATETIME     NOT NULL,
  `used_at`    DATETIME     NULL DEFAULT NULL,
  `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_token` (`token`),
  INDEX `idx_email` (`email`),
  INDEX `idx_expires` (`expires_at`),
  CONSTRAINT `fk_reset_token_usuario`
    FOREIGN KEY (`usuario_id`) REFERENCES `usuarios`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

## 3. Lógica del endpoint

1. `SELECT id, nombre, email FROM usuarios WHERE email = ? AND deleted IS NULL` → si no hay fila, devolver el `success:false` de "email no existe".
2. Invalidar tokens previos de ese email (`UPDATE ... SET used_at = NOW() WHERE email = ? AND used_at IS NULL`).
3. Generar token: `crypto.randomBytes(32).toString('hex')`. `expires_at = NOW() + 30 min`.
4. Insertar en `password_reset_tokens`.
5. Enviar email con `EmailService` (`src/infrastructure/email/email.service.js`, ya existe, usa `ENAGAS_SMTP_*`). Enlace del email:
   `{APP_URL}/reset-password?email={email urlencoded}&token={token}`
   con `APP_URL` = nueva env `ENAGAS_APP_URL` (URL de la webapp).
6. Si `EmailService.isConfigured()` es `false` o el envío lanza → devolver el `success:false` de "no hemos podido enviar".

Ficheros a tocar (patrón del propio repo):
- `src/api/routes/usuarios.routes.js` → registrar la ruta con schema `body: { email: string, required }`.
- `src/services/usuarios.service.js` → `solicitarRecuperacion(email)`.
- `src/infrastructure/repositories/usuarios.repository.js` → `findByEmail`, `createPasswordResetToken`, `invalidateTokensByEmail`.

## 4. Cambio de contraseña (webapp, fuera del alcance de la app móvil)

La app solo dispara el email. La página `/reset-password` necesita dos endpoints más:

```
POST /api/enagas/v1/users/validar-token
Body: { "email", "token" }
200 → { "valid": true, "email": "..." }
400 → { "error": "Token inválido o expirado" }

POST /api/enagas/v1/users/restablecer-password
Body: { "email", "token", "newPassword" }
200 → { "success": true, "message": "Contraseña actualizada" }
400 → { "error": "Token inválido o expirado" }
```

`restablecer-password`: validar token (no usado, no expirado), `UPDATE usuarios SET password = ?`, marcar `used_at = NOW()`.

**Aviso:** hoy `usuarios.password` se guarda en claro (`WHERE u.usuario = ? AND u.password = ?` en `findByCredentialsWithCts`). Guardar la nueva contraseña con hash rompería el login de todos los clientes. Si se quiere hashear, es una migración aparte que toca login, `/users/new` y `/users/save` a la vez.

## 5. Env nuevas

```
ENAGAS_APP_URL=https://enagastool.helireport.com     # base del enlace del email
ENAGAS_SMTP_HOST / _PORT / _USER / _PASSWORD / _FROM_NAME / _FROM_EMAIL   # ya soportadas
```
