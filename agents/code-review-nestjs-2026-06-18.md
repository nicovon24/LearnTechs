# Code Review — learn-nestjs
**Fecha:** 2026-06-18  
**Herramienta:** Bugbot (Cursor AI)

---

## BLOCKs — impiden el merge

### 1. E2E test espera una ruta que no existe
**Archivo:** `test/app.e2e-spec.ts:19-23`

El spec assert que `GET /` devuelve 200 con `Hello World!`, pero la aplicación no tiene ningún controller raíz ni ruta `/`. El comando `npm run test:e2e` falla siempre y da falsa confianza de que la API está bien conectada.

**Fix:** Actualizar el e2e spec para testear una ruta real que sí existe (ej. `GET /players` devuelve 200).

---

### 2. TypeORM `synchronize: true` sin guardia de entorno
**Archivo:** `src/app.module.ts:46-55`

`TypeOrmModule.forRoot` tiene `synchronize: true` sin ninguna condición de entorno. Desplegando con credenciales de producción, TypeORM puede auto-alterar el schema y borrar columnas o datos sin migraciones.

**Fix:**
```typescript
synchronize: process.env.NODE_ENV !== 'production',
```

---

### 3. JWT secret hardcodeado como fallback
**Archivo:** `src/auth/auth.module.ts:35-38`

`JwtModule.register` y `JwtStrategy` caen al valor `'super-secret-change-in-production'` cuando `JWT_SECRET` no está definido. Cualquiera que conozca el default puede forjar tokens válidos contra un deploy mal configurado.

**Fix:** Lanzar error en startup si `JWT_SECRET` no está definido:
```typescript
if (!process.env.JWT_SECRET) throw new Error('JWT_SECRET env var is required');
secret: process.env.JWT_SECRET,
```

---

### 4. Delete de player rompe con matches relacionados
**Archivo:** `src/players/players.service.ts:56-59`

`remove` borra un `Player` sin limpiar las filas de la tabla pivot `match_players`. Una vez que un jugador es agregado a un partido, `DELETE /players/:id` lanza una violación de foreign-key y devuelve 500 en vez de una respuesta controlada.

**Fix:** Limpiar la relación antes de borrar, o usar `cascade: true` en la entidad.

---

## FLAGs — hay que arreglarlo, no bloquea

### 5. Registro duplicado devuelve 500
**Archivo:** `src/auth/auth.service.ts:41-59`

Llamados concurrentes a `register` con el mismo email o username pueden pasar ambos el pre-check; el segundo `save` falla en el índice unique y lanza un error de DB no manejado, devolviendo 500 en vez de 409 Conflict.

**Fix:** Envolver el `save` en un try/catch y detectar la violación de unique constraint para devolver `ConflictException`.

---

### 6. N+1 queries en `getAllPlayersStats`
**Archivo:** `src/stats/stats.service.ts:80-83`

`getAllPlayersStats` carga todos los jugadores y luego llama `getPlayerStats` por cada fila, emitiendo una query de existencia y un QueryBuilder por jugador. `GET /stats` degrada linealmente y es un vector de DoS fácil sin autenticación.

**Fix:** Hacer un JOIN en una sola query en vez de N queries separadas.

---

### 7. JWT no revalida existencia del usuario
**Archivo:** `src/auth/strategies/jwt.strategy.ts:44-46`

`validate` confía en el payload del JWT y nunca carga el usuario desde la base de datos. Los tokens siguen siendo válidos hasta 7 días después de que se borre la cuenta o se roten las credenciales.

**Fix:**
```typescript
async validate(payload: JwtPayload) {
  const user = await this.userRepository.findOneBy({ id: payload.sub });
  if (!user) throw new UnauthorizedException();
  return user;
}
```

---

### 8. UUIDs inválidos en params causan 500
**Archivo:** `src/players/players.controller.ts:61-62`

Los parámetros `:id` son strings planos sin `ParseUUIDPipe`. UUIDs mal formados llegan a PostgreSQL, disparan un error de query y devuelven 500 en vez de 400 Bad Request.

**Fix:**
```typescript
@Get(':id')
findOne(@Param('id', ParseUUIDPipe) id: string) { ... }
```

---

### 9. E2E bootstrap omite el stack de producción
**Archivo:** `test/app.e2e-spec.ts:15-16`

El e2e usa `createNestApplication()` sin `FastifyAdapter`, `ValidationPipe` global, `LoggingInterceptor`, ni `AllExceptionsFilter` del `main.ts`. Un e2e que pase no prueba que el stack HTTP real funcione correctamente.

**Fix:** El e2e bootstrap debe replicar exactamente el setup de `main.ts`.

---

### 10. Auth endpoints sin rate limiting
**Archivo:** `src/auth/auth.controller.ts:35-52`

`POST /auth/register` y `POST /auth/login` públicos no tienen throttling ni lockout. Un atacante puede hacer brute-force de passwords o flood de registros sin restricción.

**Fix:** Agregar `@nestjs/throttler` con un límite razonable (ej. 5 requests/minuto por IP en endpoints de auth).

---

## NOTEs — sugerencias opcionales

### 11. `removePlayerFromMatch` silencioso cuando el jugador no estaba
**Archivo:** `src/matches/matches.service.ts:107-110`

Filtra el jugador y guarda incluso cuando el jugador nunca estuvo en el partido, devolviendo 200 sin indicar que no cambió nada. Los callers no pueden distinguir éxito de un no-op.

---

### 12. `LoggingInterceptor` no loguea requests fallidos
**Archivo:** `src/common/interceptors/logging.interceptor.ts:40-44`

El timing se loguea solo en el path de éxito (`tap()`). Las excepciones lanzadas saltean la línea de log, así que el tráfico 4xx/5xx es invisible en el log de acceso global.

---

## Resumen

| Severidad | Cantidad |
|---|---|
| BLOCK | 4 |
| FLAG | 6 |
| NOTE | 2 |
