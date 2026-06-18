/**
 * lib/db/players.ts — Función de acceso a stats de jugadores
 *
 * POR QUÉ está separada del agente:
 *   Las funciones de acceso a datos son independientes del agente.
 *   El nodo `fetchStats` del grafo de LangGraph las llama, pero también
 *   podrías llamarlas desde cualquier otro lugar (un dashboard, un cron job, etc.)
 *   Separar "qué datos pido" de "cómo decide el agente" es una buena práctica.
 */

import { supabase } from "./supabase";
import type { PlayerStats } from "@/lib/types";

/**
 * Busca un jugador por nombre (búsqueda parcial, case-insensitive) y
 * devuelve sus stats, o null si no se encuentra.
 *
 * POR QUÉ ilike y no eq:
 *   El usuario puede preguntar "¿cómo viene Villalba?" — no siempre va a
 *   escribir el nombre completo exacto. ilike hace búsqueda con wildcards
 *   (% = cualquier cantidad de caracteres).
 */
export async function getPlayerStats(
  playerName: string
): Promise<PlayerStats | null> {
  const { data, error } = await supabase
    .from("players")
    .select("*")
    .ilike("name", `%${playerName}%`)   // búsqueda parcial, case-insensitive
    .order("name", { ascending: true }) // orden determinístico: evita devolver
                                        // un jugador arbitrario si hay varios matches
    .limit(1)                           // tomamos solo el primer resultado
    .single();                          // queremos un objeto, no un array

  if (error || !data) {
    console.warn(`[getPlayerStats] No se encontró jugador: ${playerName}`);
    return null;
  }

  // Mapeamos de snake_case (Postgres) a camelCase (TypeScript)
  return {
    id: data.id,
    name: data.name,
    position: data.position,
    age: data.age,
    team: data.team,
    goals: data.goals,
    assists: data.assists,
    matches: data.matches,
    minutesPlayed: data.minutes_played,
    passAccuracy: data.pass_accuracy,
    rating: data.rating,
  };
}
