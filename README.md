# LearnTechs

Espacio de aprendizaje personal donde exploro diferentes lenguajes y tecnologías construyendo proyectos reales con IA.

La idea es simple: en vez de hacer tutoriales pasivos, uso IA para generar proyectos funcionales que pueda leer, estudiar, romper y entender. Cada carpeta es una tecnología distinta con su propio proyecto y una guía de referencia rápida que resume los conceptos clave.

---

## Proyectos

### `learn-blockchain` — Solidity + Foundry
Pool de apuestas on-chain para resultados de partidos de fútbol. Cubre Solidity (storage, payable, mappings, eventos, modifiers), el patrón Checks-Effects-Interactions para prevenir el reentrancy attack, OpenZeppelin (Ownable, ReentrancyGuard), y testing con fuzzing en Foundry.
- Guía: `BLOCKCHAIN.md`

### `learn-nestjs` — NestJS + TypeScript
API REST de scouting deportivo. Cubre el stack completo de NestJS: módulos, controllers, services, TypeORM, DTOs con validación, guards JWT, interceptors y exception filters.
- Guía: `NESTJS.md`

### `learn-fastapi` — FastAPI + Python
Microservicio de estadísticas de jugadores. Cubre FastAPI, Pydantic, SQLModel, async/await, Depends(), y testing con pytest.
- Guía: `FASTAPI.md`

### `learn-java` — Java + Spring Boot + Kafka
Dos microservicios que se comunican via Kafka: uno ingiere eventos de partidos y otro agrega estadísticas en PostgreSQL. Cubre Spring Boot, JPA, Bean Validation, y JUnit + Mockito.
- Guía: `JAVA.md`

### `learn-aws` — AWS CDK + Serverless
API de predicciones de partidos 100% serverless. Cubre Lambda, DynamoDB, API Gateway, Cognito, SNS y CloudWatch con infraestructura definida como código en TypeScript (CDK). Testing local con Floci.
- Guía: `AWS.md`

### `learn-ai-engineering` — AI Engineering + Next.js
Chatbot de scouting que combina cuatro capas de AI Engineering: API directa de Anthropic con Tool Use, streaming con Vercel AI SDK, RAG con pgvector y embeddings de OpenAI, y orquestación explícita de agentes con LangGraph.
- Guía: `AI_ENGINEERING.md`

---

## `agents/`

Carpeta con reportes y análisis generados por agentes de IA sobre este mismo repositorio:

- `code-reviews-18-6.md` — code review completo de todos los proyectos (bugs encontrados y corregidos)
- `workflow.md` — análisis del workflow de desarrollo SPEC → PLAN → CODE → REVIEW

---

## Filosofía

Cada proyecto tiene:
1. **Código comentado** — cada decisión técnica está explicada inline, no solo el "qué" sino el "por qué"
2. **Guía de referencia** — un `.md` que resume los conceptos del lenguaje/framework con analogías y ejemplos del mismo dominio (fútbol/scouting)
3. **Code reviews** — los proyectos pasan por Bugbot para detectar bugs reales y aprender de los errores

El objetivo no es tener código perfecto desde el día uno — es tener código legible, entendible y mejorable, que sirva como punto de partida para profundizar en cada tecnología.
