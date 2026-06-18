"""
routers/players.py — Endpoints de estadísticas de jugadores.

APIRouter es el equivalente al @Controller() de NestJS:
agrupa endpoints relacionados y se registra en main.py con un prefix.

La diferencia con NestJS: en FastAPI no hay clases para los controllers,
son funciones decoradas. Más parecido a Express que a Nest, pero con
el poder de los type hints para validación y documentación automática.

Conceptos de este archivo:
- @router.get(): decorador que registra la función como handler HTTP GET.
- response_model: le dice a FastAPI el schema de respuesta esperado.
  FastAPI valida que la respuesta tenga esa forma Y la usa para generar los docs.
- Depends(): el sistema de DI de FastAPI. Acepta cualquier callable (función, clase).
  FastAPI resuelve las dependencias automáticamente antes de llamar al endpoint.
- Query params: parámetros con valor default son automáticamente tratados como
  query params (?page=1&page_size=10). Sin default → son requeridos.
"""

from fastapi import APIRouter, Depends, Query
from sqlmodel.ext.asyncio.session import AsyncSession

from app.database import get_session
from app.schemas import PlayerStatsResponse, TopScorersResponse
from app.services import player_service

# prefix y tags se definen en main.py al hacer include_router,
# pero también se pueden poner aquí si el router siempre va a tener el mismo prefix.
router = APIRouter()


@router.get("/top-scorers", response_model=TopScorersResponse)
async def get_top_scorers(
    # FIX: Query() con ge/le previene valores negativos o extremadamente grandes
    # que generarían OFFSET/LIMIT inválidos en SQL (→ 500) o DoS trivial.
    page: int = Query(default=1, ge=1, description="Número de página"),
    page_size: int = Query(default=10, ge=1, le=100, description="Resultados por página"),
    session: AsyncSession = Depends(get_session),
):
    """
    Ranking de jugadores con más goles, con paginación.

    IMPORTANTE: este endpoint debe estar ANTES de /{id}/stats en el archivo.
    FastAPI matchea rutas en orden de registro. Si /{id} estuviera primero,
    "/top-scorers" sería interpretado como id="top-scorers" y daría error de tipo.
    Este es un gotcha clásico de FastAPI que conviene conocer.

    Query params automáticos:
    - ?page=1 (default: 1)
    - ?page_size=10 (default: 10)
    FastAPI los parsea y valida del query string sin configuración extra.
    """
    return await player_service.get_top_scorers(
        session=session,
        page=page,
        page_size=page_size,
    )


@router.get("/{player_id}/stats", response_model=PlayerStatsResponse)
async def get_player_stats(
    player_id: int,
    session: AsyncSession = Depends(get_session),
):
    """
    Estadísticas agregadas de un jugador: partidos, goles, asistencias, promedio.

    player_id viene del path (/players/42/stats → player_id=42).
    FastAPI lo convierte automáticamente a int y valida que sea un entero válido.
    Si pasás /players/abc/stats → error 422 automático (Unprocessable Entity).

    Depends(get_session): FastAPI llama a get_session(), espera el yield,
    inyecta la sesión aquí, y después del return llama al código post-yield
    (cierra la sesión). Todo transparente para el handler.
    """
    return await player_service.get_player_stats(player_id=player_id, session=session)
