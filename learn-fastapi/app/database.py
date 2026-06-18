"""
database.py — Motor de base de datos y sesión async.

Conceptos clave de este archivo:

1. create_async_engine: crea la conexión a Postgres en modo async.
   SQLAlchemy tiene dos "mundos": sync (el clásico) y async (a partir de 1.4+).
   FastAPI vive en el mundo async, por eso usamos la versión async del engine.

2. AsyncSession: la sesión de base de datos async. Cada request HTTP debería
   tener su propia sesión (como una transacción) que se abre y cierra
   automáticamente. Esto evita que sesiones "sucias" de un request contaminen otro.

3. get_session (generador async): esta función es un "dependency" de FastAPI.
   El patrón "yield" la convierte en un context manager:
   - Todo lo que está ANTES del yield es setup (abrir sesión).
   - Todo lo que está DESPUÉS del yield es teardown (cerrar sesión).
   FastAPI se encarga de llamar al teardown automáticamente cuando el request termina,
   incluso si hubo una excepción. Equivalente a un interceptor de NestJS que maneja
   el ciclo de vida de recursos.
"""

from sqlalchemy.ext.asyncio import create_async_engine
# FIX: usar AsyncSession de sqlmodel.ext.asyncio.session, NO de sqlalchemy.
# El método session.exec() que usamos en los services solo existe en la versión
# de SQLModel — la de SQLAlchemy puro lanza AttributeError en runtime.
from sqlmodel.ext.asyncio.session import AsyncSession
from sqlalchemy.orm import sessionmaker
from app.config import settings

# echo=True loguea el SQL generado — muy útil para dev, pero agrega I/O overhead
# en producción y puede filtrar datos sensibles en logs centralizados.
# FIX: condicionarlo al flag DEBUG en vez de dejarlo siempre encendido.
engine = create_async_engine(settings.DATABASE_URL, echo=settings.DEBUG)

# AsyncSessionLocal es una "fábrica" de sesiones.
# expire_on_commit=False: por defecto SQLAlchemy "expira" los objetos después de
# un commit, forzando un re-fetch de la DB. En modo async eso puede causar errores
# si intentás acceder a un campo después del commit fuera de la sesión.
# Con False, los objetos siguen accesibles después del commit.
AsyncSessionLocal = sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def get_session():
    """
    Dependency de FastAPI para inyectar una sesión de DB en los endpoints.

    Uso en un endpoint:
        @router.get("/")
        async def list_players(session: AsyncSession = Depends(get_session)):
            ...

    FastAPI llama a esta función por cada request, abre la sesión, inyecta
    el objeto en el endpoint, y la cierra al terminar — sin que tengas que
    escribir try/finally en cada endpoint.
    """
    async with AsyncSessionLocal() as session:
        yield session
