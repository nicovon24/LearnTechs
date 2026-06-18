/**
 * /api/chat — Etapa 2+4: AI SDK + LangGraph juntos
 *
 * POR QUÉ combinamos LangGraph con el AI SDK acá:
 *   - LangGraph maneja la ORQUESTACIÓN: qué tools llamar y en qué orden
 *     (classify → fetchStats/fetchReports → synthesize).
 *   - El frontend recibe el texto via un ReadableStream manual que escribimos
 *     directamente, sin pasar por un segundo LLM.
 *
 * POR QUÉ NO usamos un segundo streamText para "retransmitir":
 *   Pasar la respuesta del agente a otro LLM para que la "retransmita" es
 *   no-determinístico: el modelo puede reordenar, omitir o reescribir el
 *   marcador PLAYER_STATS_DATA que usa la Generative UI. El fix es escribir
 *   el ReadableStream directamente con el texto ya construido.
 *
 * SOBRE GENERATIVE UI:
 *   Cuando el grafo devuelve stats de un jugador, el marcador
 *   PLAYER_STATS_DATA:{json}:END_PLAYER_STATS se escribe determinísticamente
 *   al stream. El frontend lo parsea y renderiza PlayerCard.
 */

import { NextRequest, NextResponse } from "next/server";
import { runScoutingAgent } from "@/lib/agent/graph";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const messages = body.messages as Array<{ role: string; content: string }>;

    if (!messages || messages.length === 0) {
      return NextResponse.json(
        { error: "messages es requerido" },
        { status: 400 }
      );
    }

    // Tomamos el último mensaje del usuario como la pregunta actual
    const lastUserMessage = messages
      .filter((m) => m.role === "user")
      .at(-1);

    if (!lastUserMessage) {
      return NextResponse.json(
        { error: "No hay mensaje del usuario" },
        { status: 400 }
      );
    }

    // ── 1. Ejecutar el grafo de LangGraph ────────────────────────────────────
    //
    // runScoutingAgent() corre todo el flujo:
    //   classify → (fetchStats / fetchReports) → synthesize
    // y devuelve la respuesta final más el estado completo del grafo.
    const { response, state } = await runScoutingAgent(lastUserMessage.content);

    // ── 2. Construir el texto final con el marcador de Generative UI ─────────
    //
    // Si el grafo obtuvo stats de un jugador, anteponemos el marcador JSON al
    // texto de respuesta. Esto se escribe directamente al stream — sin pasar
    // por ningún LLM — garantizando que el marcador siempre llega intacto.
    let finalText = response;

    if (state.playerStats) {
      const statsJson = JSON.stringify(state.playerStats);
      finalText = `PLAYER_STATS_DATA:${statsJson}:END_PLAYER_STATS\n\n${response}`;
    }

    // ── 3. Streamear la respuesta al frontend con un ReadableStream manual ───
    //
    // Escribimos el texto directamente al stream en chunks pequeños para dar
    // la sensación de streaming progresivo (mejor UX que respuesta de golpe).
    // Al no pasar por un segundo LLM el marcador PLAYER_STATS_DATA nunca
    // puede ser alterado.
    const encoder = new TextEncoder();
    const stream = new ReadableStream({
      start(controller) {
        // Dividimos en chunks de ~20 chars para simular streaming
        const chunkSize = 20;
        for (let i = 0; i < finalText.length; i += chunkSize) {
          controller.enqueue(encoder.encode(finalText.slice(i, i + chunkSize)));
        }
        controller.close();
      },
    });

    return new Response(stream, {
      headers: { "Content-Type": "text/plain; charset=utf-8" },
    });
  } catch (error) {
    console.error("[chat] Error:", error);
    return NextResponse.json(
      { error: "Error al procesar la consulta" },
      { status: 500 }
    );
  }
}
