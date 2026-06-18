"""
config.py — Configuración centralizada de la aplicación.

Pydantic BaseSettings lee automáticamente las variables de entorno
(y el archivo .env si python-dotenv está instalado). Esto es el equivalente
al ConfigModule.forRoot() de NestJS: un único punto de verdad para la config,
con tipado y validación automática.

Por qué usar Settings en vez de os.getenv() directo:
- Validación: si falta DATABASE_URL, la app falla al arrancar con un mensaje claro.
- Tipado: el resto del código sabe exactamente qué tipo tiene cada setting.
- Testabilidad: se puede inyectar una instancia distinta en tests.
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # URL de conexión a la base de datos.
    # El driver "postgresql+asyncpg" le indica a SQLAlchemy que use asyncpg
    # (el driver async) en vez de psycopg2 (síncrono).
    DATABASE_URL: str

    # DEBUG controla el SQL echo del engine. En producción debe ser False
    # para evitar loguear queries completas con sus parámetros.
    DEBUG: bool = False

    # model_config reemplaza la clase Config interna de Pydantic v1.
    # env_file le dice a Pydantic dónde buscar el archivo de variables de entorno.
    model_config = SettingsConfigDict(env_file=".env")


# Instancia global — se importa desde cualquier parte del proyecto.
# Se crea UNA sola vez al iniciar la app (patrón singleton simple).
settings = Settings()
