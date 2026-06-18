"""
models.py — Modelos de base de datos con SQLModel.

SQLModel es la "fusión" de Pydantic y SQLAlchemy creada por el mismo autor de FastAPI.
La idea central: una sola clase Python actúa TANTO como tabla de DB (SQLAlchemy)
COMO esquema de validación (Pydantic). Esto elimina la duplicación de tener
una clase para la tabla y otra para el DTO.

table=True: este flag le dice a SQLModel que esta clase es una tabla real de DB.
Sin él, la clase sería solo un modelo Pydantic (útil para los schemas de respuesta).

Contexto del dominio:
Estas tablas representan el esquema que "ya existe" en el sistema Django de administración.
Este microservicio FastAPI solo las lee — no hace escrituras.
"""

from typing import Optional
from sqlmodel import Field, SQLModel, Relationship


class Club(SQLModel, table=True):
    """
    Tabla de clubes de fútbol.

    FIX: declarar __tablename__ explícitamente para que coincida con el schema
    real de la DB (que puede ser plural o con prefijo de app en Django).
    Sin esto, SQLModel usa "club" por default y podría no coincidir con "clubs".
    """

    __tablename__ = "clubs"  # type: ignore[assignment]

    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True)  # index=True crea un índice en la DB
    country: str
    league: str

    # Relationship: equivalente a una relación OneToMany de TypeORM.
    # "back_populates" define el nombre del atributo en el modelo opuesto.
    # Este campo NO es una columna de DB — es solo Python-side para navegar la relación.
    players: list["Player"] = Relationship(back_populates="club")


class Player(SQLModel, table=True):
    """
    Tabla de jugadores.
    """

    __tablename__ = "players"  # type: ignore[assignment]

    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True)
    position: str
    birth_date: Optional[str] = None  # Guardado como string ISO para simplicidad

    # ForeignKey: la columna real en la DB que referencia a club.id
    club_id: Optional[int] = Field(default=None, foreign_key="club.id")

    # Relationship al lado Many (muchos players pertenecen a un club)
    club: Optional[Club] = Relationship(back_populates="players")

    # Un jugador puede tener muchos partidos (stats individuales por partido)
    matches: list["Match"] = Relationship(back_populates="player")


class Match(SQLModel, table=True):
    """
    Tabla de participaciones de jugadores en partidos.
    Cada fila = un jugador en un partido específico, con sus stats.

    En un sistema real esto podría ser más complejo (tabla separada de partidos,
    tabla de alineaciones, etc.), pero para este microservicio de estadísticas
    esta estructura plana es suficiente.
    """

    __tablename__ = "matches"  # type: ignore[assignment]

    id: Optional[int] = Field(default=None, primary_key=True)
    player_id: int = Field(foreign_key="player.id", index=True)
    match_date: str  # ISO date string, ej: "2024-03-15"
    goals: int = Field(default=0)
    assists: int = Field(default=0)
    minutes_played: int = Field(default=0)

    player: Optional[Player] = Relationship(back_populates="matches")
