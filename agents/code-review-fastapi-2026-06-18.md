# Code Review — learn-fastapi
**Fecha:** 2026-06-18  
**Herramienta:** Bugbot (Cursor AI)

---

## BLOCKs — impiden el merge

### 1. `AsyncSession` incorrecta rompe todas las queries
**Archivo:** `app/database.py:23-40`

`database.py` configura `sessionmaker` con `AsyncSession` de `sqlalchemy.ext.asyncio`, pero todos los services llaman `await session.exec(...)`. Ese método solo existe en el `AsyncSession` de SQLModel (`sqlmodel.ext.asyncio.session`). Cada endpoint va a lanzar `AttributeError` en la primera query.

**Fix:** Cambiar el import a `from sqlmodel.ext.asyncio.session import AsyncSession`.

---

### 2. Dependencia `greenlet` faltante en `requirements.txt`
**Archivo:** `requirements.txt:1-31`

`requirements.txt` no tiene `greenlet` ni `sqlalchemy[asyncio]`, pero el `session.exec()` async de SQLModel usa `greenlet_spawn`. Una instalación limpia puede fallar en runtime con `"the greenlet library is required to use this function"` antes de completar cualquier query.

**Fix:** Agregar a `requirements.txt`:
```
sqlalchemy[asyncio]
greenlet
```

---

## FLAGs — hay que arreglarlo, no bloquea

### 3. Paginación sin validación causa 500
**Archivo:** `app/routers/players.py:34-36`

`page` y `page_size` son `int` sin bounds en `Query(ge=...)`. `page=0` o valores negativos producen un `OFFSET` negativo en SQL que PostgreSQL rechaza, devolviendo 500 en vez de 422.

**Fix:**
```python
page: int = Query(default=1, ge=1),
page_size: int = Query(default=20, ge=1, le=100),
```

---

### 4. `.env.example` apunta a `localhost` dentro del container
**Archivo:** `.env.example:4`

`DATABASE_URL` apunta a `localhost:5432`, pero cuando se corre con `docker-compose up`, el container `api` no puede alcanzar Postgres via `localhost` — necesita el nombre del servicio `db`.

**Fix:** Cambiar en `.env.example`:
```
DATABASE_URL=postgresql+asyncpg://user:password@db:5432/scoutdb
```

---

### 5. `echo=True` en el engine de producción
**Archivo:** `app/database.py:29`

El async engine se crea con `echo=True`, loguea cada statement SQL incondicionalmente. Agrega I/O overhead bajo carga y puede filtrar parámetros de queries y patrones de datos en logs centralizados.

**Fix:**
```python
echo=settings.DEBUG,  # solo en dev
```

---

### 6. `page_size` sin límite superior — DoS trivial
**Archivo:** `app/routers/players.py:36`

Sin upper bound en `page_size`, un cliente puede pedir una página enorme y forzar que la query materialice y ordene un result set masivo en un solo request.

**Fix:** `page_size: int = Query(default=20, ge=1, le=100)` (ver fix #3 — mismo cambio).

---

### 7. Nombres de tablas pueden no coincidir con el schema
**Archivo:** `app/models.py:21-60`

Los modelos usan los defaults de SQLModel (`club`, `player`, `match`), mientras que la docs describe un schema compartido con Django que puede usar nombres plurales o con prefijo de app (`players`, `clubs`). Si hay mismatch, el service lee tablas vacías o equivocadas.

**Fix:** Declarar los nombres explícitamente en cada modelo:
```python
class Player(SQLModel, table=True):
    __tablename__ = "players"
```

---

## NOTEs — sugerencias opcionales

### 8. Tests requieren `DATABASE_URL` aunque no deberían
**Archivo:** `app/config.py:31`

El README dice que los tests no necesitan Postgres, pero importar `app.main` instancia `Settings()` que requiere `DATABASE_URL` aunque los tests sobreescriban `get_session` con SQLite. La collection falla sin un `.env` o URL dummy.

---

### 9. `create_all` en startup contra DB compartida con Django
**Archivo:** `app/main.py:29-32`

El lifespan siempre corre `SQLModel.metadata.create_all` contra la DB configurada. Los comentarios dicen que producción debería usar migraciones y que la DB la gestiona Django, pero el startup todavía muta el schema si faltan tablas.

---

## Resumen

| Severidad | Cantidad |
|---|---|
| BLOCK | 2 |
| FLAG | 5 |
| NOTE | 2 |
