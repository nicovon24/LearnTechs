# Workflow de Desarrollo — Análisis y Referencia
**Fecha de análisis:** 2026-06-18  
**Autor:** Nicolas Von Muhlinen

---

## El flujo

```
Idea
  ↓
Sesión Architect  →  SPEC + PLAN  →  Aprobación humana
  ↓
Sesión Developer  →  Código + commits atómicos
  ↓
Sesión Reviewer   →  BLOCK / FLAG / NOTE  →  Aprobación humana
  ↓
Push
```

Tres roles, tres sesiones separadas. El principio central: **el Reviewer evalúa el resultado en sus propios términos**, sin heredar el razonamiento que llevó a esa implementación.

---

## 1. Conceptos de base — por qué funciona

### Roles en sesiones separadas = subagentes sin archivos de configuración

Abrir una sesión nueva para cada rol persigue exactamente el mismo objetivo que un subagente con contexto aislado: que el Reviewer no "sepa" por qué el Developer tomó cada decisión. No necesitás `.claude/agents/` ni herramientas externas para lograr aislamiento — solo que la sesión sea realmente nueva (ver sección 4).

### Vocabulario controlado en el Reviewer (BLOCK / FLAG / NOTE)

Un review libre tiende a salir como "se ve bien, algunos detalles menores" — vago y sin urgencia clara. Forzar una categoría por hallazgo es el mismo principio que usan las herramientas de code review reales: separar lo que **bloquea un merge** de lo que es una sugerencia opcional. Sin este vocabulario, todo tiene la misma urgencia percibida, que es la misma que ninguna.

### Gates de aprobación humana en tres puntos

Después del SPEC+PLAN, después del código, y antes del push. Nunca el flujo avanza sin que vos mirés el punto de decisión. Es la versión manual de lo que las herramientas de workflow fuerzan con commits atómicos y comandos separados.

### "Collapse all" para cambios triviales

La disciplina completa solo vale la pena cuando el cambio la justifica. Para refactors de una línea o fixes obvios, ir directo al código sin ceremonia. La válvula de escape es parte del sistema, no una excepción.

---

## 2. Setup actual

### La base documental — Phase 0 (antes de cualquier línea de código)

| Archivo | Propósito |
|---|---|
| `AGENTS.md` | Session protocol e invariants — reglas que cualquier sesión debe leer antes de actuar |
| `docs/vision.md` | El "por qué" del proyecto |
| `docs/architecture.md` | Decisiones de arquitectura y sus razones |
| `docs/current.md` | Estado actual del sistema |
| `docs/changelog.md` | Historial de cambios |
| `docs/workflow.md` | Este documento |
| `docs/infrastructure.md` | Setup de infra y deploy |
| `docs/api.md` | Contrato de la API |
| `docs/testing.md` | Estrategia y convenciones de tests |

El `AGENTS.md` cumple el mismo rol que una `constitution.md` o un `PROJECT.md`: **reglas que cualquier sesión nueva debe leer antes de hacer nada**. El valor está en que se escribe en Phase 0 — cuando el sistema todavía es simple y las decisiones son frescas.

### El plan de fases

Cada feature se organiza en fases. Cada fase declara:
- Objetivo concreto
- Entregables verificables
- Los mensajes de commit planeados de antemano
- Un paso de "Verification" antes de pasar a la siguiente

Commits atómicos planeados + verificación antes de avanzar — el mismo principio que las "waves" de herramientas tipo GSD, implementado manualmente.

### El template de SPEC (`docs/specs/NNN-feature-name.md`)

La pieza más importante del template es el campo **"Out of Scope"**. Obliga a declarar explícitamente qué NO se va a hacer — previene que el Developer agregue cosas no pedidas, que es uno de los modos de falla más comunes en sesiones largas de AI.

```
Context          → por qué se necesita esta feature
Requirements     → qué tiene que hacer (checkboxes testeables)
Acceptance Criteria → cómo se verifica que está hecho
Out of Scope     → qué NO incluye esta feature
Affected files   → archivos esperados que van a cambiar
```

---

## 3. Prompts para cada rol

Estos prompts fuerzan los dos comportamientos que más importan: **sesión nueva de verdad** y **evidencia real** en vez de afirmaciones.

### Architect

```
Sos el Architect de este proyecto. Esta es una sesión nueva — no tenés 
ni necesitás el historial de conversaciones anteriores sobre este proyecto.

Tarea: [describir la feature acá]

Tu única salida son dos cosas:
1. docs/specs/NNN-feature-name.md siguiendo el template del proyecto:
   Context, Requirements, Acceptance Criteria (como checkboxes testeables,
   no frases vagas), Out of Scope, Affected files.
2. Un PLAN breve: orden de implementación, archivos a tocar, decisiones 
   técnicas relevantes.

No escribas código. No toques ningún archivo fuera de docs/specs/.
Cuando termines, decime "Listo para aprobación" y esperá mi confirmación
antes de asumir que el Developer puede arrancar.
```

### Developer

```
Sos el Developer de este proyecto. Esta es una sesión nueva.

Implementá exactamente lo que dice docs/specs/NNN-feature-name.md.
No agregues nada que no esté en "Requirements" ni toques nada listado 
en "Out of Scope" — si te parece que falta algo, decímelo en vez de
agregarlo por tu cuenta.

Un commit atómico por entregable, no uno gigante al final.
Antes de decir que terminaste, corré la suite de tests relevante y pegame 
el output real del comando — no me digas "debería funcionar" ni 
"los tests deberían pasar".
```

### Reviewer ← el más importante

```
Sos el Reviewer de este proyecto. Esta es una sesión nueva — no tenés, 
y no quiero que tengas, el contexto de la sesión del Developer que generó
este código. Evaluá el resultado en sus propios términos, no el razonamiento
detrás.

Te paso: (1) docs/specs/NNN-feature-name.md, (2) el diff de los commits 
de esta feature (git log + git diff).

Hacé esto en orden:
1. Corré la suite de tests vos mismo y pegá el output real — no asumas 
   que pasan porque el Developer dijo que sí.
2. Revisá el diff contra cada item de "Acceptance Criteria" del spec, 
   marcando cuáles están cumplidos y cuáles no.
3. Buscá código fuera de "Out of Scope" que se haya agregado sin que 
   el spec lo pidiera.
4. Clasificá cada hallazgo como:
   - BLOCK → impide el merge
   - FLAG  → hay que arreglarlo pero no bloquea
   - NOTE  → sugerencia opcional

No digas "se ve bien" sin evidencia. Si corriste los tests y pasaron, 
mostrame la línea de output que lo confirma, no solo la conclusión.
```

> **La regla más importante:** abrí cada rol en una pestaña/sesión de chat nueva, no como un mensaje más dentro de la misma conversación. Si el Reviewer arranca en el mismo hilo donde ya está el código del Developer, ya perdió el aislamiento que es el punto central de tenerlo como rol separado.

---

## 4. Preguntas abiertas — sin inventar problemas

### ¿"Sesión separada" es una conversación nueva de cero, o un cambio de tema en el mismo hilo?

Esta es la pregunta más importante. Si es lo segundo, no hay aislamiento de contexto real — el Reviewer todavía "sabe" todo el razonamiento del Developer y puede heredar su sesgo. Si es una conversación nueva, ya estás haciendo lo correcto.

### ¿El Reviewer corre los tests, o solo lee el diff?

Si es solo lectura de código, falta la pieza de "evidencia": pedirle que ejecute `npm test` (o el comando equivalente) y muestre el output real. Un Reviewer que no corre los tests solo hace análisis estático — útil pero incompleto.

### ¿Quién actualiza `AGENTS.md` y cuándo?

Si nadie lo toca después de Phase 0, corre el riesgo de quedar desactualizado. Un protocolo de sesión viejo es peor que no tener ninguno, porque las sesiones nuevas confían en él como si fuera verdad. Necesita un propietario y un trigger para actualizarlo (por ejemplo, al final de cada fase).

### Flujo secuencial vs. paralelo

El flujo actual es `Phase 1 → 2 → 3 ...` sin paralelización. Para un developer solo, esto no es un problema. La única situación donde perdería tiempo real es si dos fases son completamente independientes entre sí — en ese caso correrlas en serie sin necesidad. Para proyectos futuros más grandes, vale la pena marcar en el plan qué fases pueden correr en paralelo.

---

## 5. Áreas de mejora

### Mejora 1 — Hacer el aislamiento de contexto explícito en el prompt

En vez de confiar en que cada sesión "empieza de cero", incluir al principio de cada prompt:

```
# Contexto de sesión
Rol: Reviewer
Sesión: NUEVA — no heredás razonamiento de sesiones anteriores
Inputs que recibís: [spec] [diff]
Inputs que NO tenés ni necesitás: el chat de la sesión del Developer
```

Esto no es redundante — es un recordatorio explícito que previene que el modelo trate de "completar la historia" usando contexto implícito.

### Mejora 2 — Acceptance Criteria como checkboxes ejecutables, no frases

En vez de:
```
- El endpoint devuelve los datos del usuario
```

Escribir:
```
- [ ] GET /users/:id devuelve 200 con { id, name, email } cuando el usuario existe
- [ ] GET /users/:id devuelve 404 cuando el id no existe en la DB
- [ ] GET /users/:id devuelve 401 sin token JWT
```

El Reviewer puede marcar cada checkbox con evidencia del test output en vez de opinar si "la feature está completa".

### Mejora 3 — Log de decisiones en el SPEC

Agregar una sección `## Decisiones técnicas` al template de SPEC donde el Architect anota las decisiones que tomó y por qué las descartó. Ejemplo:

```markdown
## Decisiones técnicas
- **Cache en Redis vs. in-memory**: elegimos in-memory por simplicidad en Phase 1. 
  Redis queda para Phase 3 cuando tengamos múltiples instancias.
- **UUID vs. auto-increment**: UUID para no exponer el tamaño de la tabla.
```

Esto evita que el Developer o el Reviewer "re-descubran" razonamiento que el Architect ya hizo.

### Mejora 4 — Agregar un paso de "Smoke test" al final del Developer antes del Reviewer

Antes de pasarle el diff al Reviewer, el Developer corre un smoke test manual del happy path y lo documenta:

```
## Smoke test manual
- [ ] Levanté el servidor localmente
- [ ] Probé POST /predictions con datos válidos → 201 ✓
- [ ] Probé sin JWT → 401 ✓
- [ ] Probé con body inválido → 422 ✓
Output de tests: [pegar el output real acá]
```

El Reviewer entonces sabe que los casos básicos ya se probaron y puede enfocarse en edge cases y análisis de código.

### Mejora 5 — Checklist de "Out of Scope" en el Reviewer

Agregar explícitamente al prompt del Reviewer:

```
Abrí el diff y buscá:
1. Archivos tocados que NO están en "Affected files" del spec
2. Funcionalidad nueva que no está en "Requirements"
3. Cambios en "Out of Scope"

Si encontrás cualquiera de los tres, es automáticamente un FLAG o BLOCK.
```

Sin esta instrucción explícita, el Reviewer tiende a enfocarse en la calidad del código dentro del scope, y no en si el Developer se excedió del scope.

### Mejora 6 — `AGENTS.md` con fecha de última actualización y owner

```markdown
# AGENTS.md
**Última actualización:** 2026-06-18
**Owner:** Nicolas (actualizar al terminar cada fase o cuando cambie la arquitectura)

## Session protocol
...
```

La fecha visible hace evidente cuándo el documento lleva mucho tiempo sin actualizarse.

---

## 6. Comparación con herramientas del ecosistema

| Tu workflow | Equivalente en herramientas | Diferencia clave |
|---|---|---|
| Sesión Architect con SPEC | Spec-Kit `spec-new` | El tuyo es más flexible, sin instalación |
| Sesión Developer con commits atómicos | GSD "waves" | GSD puede paralelizar fases, el tuyo es secuencial |
| Sesión Reviewer con BLOCK/FLAG/NOTE | Bugbot / CodeRabbit | Bugbot corre automático, el tuyo requiere apertura manual |
| `AGENTS.md` | `PROJECT.md` de GSD / `constitution.md` de Spec-Kit | Mismo concepto, distinto nombre |
| Gate de aprobación humana | `Human in the loop` de LangGraph | El tuyo es manual, LangGraph lo puede automatizar |
| Template de SPEC con "Out of Scope" | Stories en Linear con "Won't do" | Mismo principio: definir límites explícitos |

La ventaja del workflow manual sobre las herramientas: **cero dependencias, funciona en cualquier interface de chat**. La desventaja: requiere disciplina para no saltarse pasos bajo presión de tiempo.

---

## Resumen de una línea

> Separar los roles en sesiones distintas no es una formalidad — es la única manera de que el Reviewer evalúe el resultado en sus propios términos, sin heredar los sesgos del Developer. Todo lo demás (SPEC con Out of Scope, commits atómicos, BLOCK/FLAG/NOTE) son mecanismos para hacer esa separación efectiva en la práctica.
