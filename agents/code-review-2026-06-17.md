# Code Review — LearnTechs Projects
**Fecha:** 2026-06-17  
**Herramienta:** Bugbot (Cursor AI)  
**Alcance:** learn-ai-engineering, learn-java, learn-aws

---

## Hallazgos

### 1. Segundo LLM puede corromper la respuesta del agente
**Archivo:** `learn-ai-engineering/scout-ai-copilot/app/api/chat/route.ts` líneas 72-100  
**Severidad:** Alta

**Descripción:**  
Después de que LangGraph produce la respuesta final con Sonnet, la ruta envía ese texto a través de un segundo llamado `streamText` en Haiku pidiéndole que retransmita el contenido sin cambios. El frontend renderiza `PlayerCard` parseando un marcador `PLAYER_STATS_DATA` del body del stream, pero ese marcador se inyecta en el prompt de Haiku en lugar de escribirse determinísticamente al response stream. Un relay no determinístico puede omitir, reordenar o reescribir el marcador y el texto de la respuesta, por lo que Generative UI falla silenciosamente y los usuarios pueden ver una respuesta diferente a la sintetizada por el agente.

**Fix aplicado:** Se eliminó el segundo `streamText` de Haiku. Ahora se escribe directamente el texto del agente al `ReadableStream`, incluyendo el marcador `PLAYER_STATS_DATA` de forma determinística.

---

### 2. Búsqueda parcial de nombre puede devolver el jugador equivocado
**Archivo:** `learn-ai-engineering/scout-ai-copilot/lib/db/players.ts` líneas 26-31  
**Severidad:** Media

**Descripción:**  
`getPlayerStats` resuelve jugadores con un match parcial `ilike` y `limit(1)` pero sin `order by`. Cuando más de una fila coincide con el substring, Postgres devuelve una primera fila arbitraria, por lo que el agente puede adjuntar las estadísticas del jugador equivocado a una pregunta sobre otra persona.

**Fix aplicado:** Se agregó `.order('name', { ascending: true })` antes del `.limit(1)` para garantizar resultados determinísticos.

---

## Estado general
- **learn-java** y **learn-aws**: Sin bugs críticos detectados. Código sólido.
- **learn-ai-engineering**: Dos bugs corregidos (ver arriba).
