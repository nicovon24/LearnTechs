# World Cup Prediction Pool

Pool de apuestas on-chain para resultados de partidos de fútbol. Varios usuarios apuestan ETH de testnet prediciendo el ganador de un partido. Cuando el admin reporta el resultado real, el pozo se reparte proporcionalmente entre los que acertaron.

Conectado al universo de **Prodeazo** — el mismo dominio de predicciones, ahora completamente descentralizado.

---

## Setup

### 1. Instalar Foundry

```bash
# En Linux/Mac:
curl -L https://foundry.paradigm.xyz | bash
foundryup

# En Windows (PowerShell como administrador):
# Opción 1 — usando WSL (recomendado):
wsl curl -L https://foundry.paradigm.xyz | bash

# Opción 2 — binario directo de GitHub:
# Descargar forge.exe de https://github.com/foundry-rs/foundry/releases
# y agregarlo al PATH
```

Verificar instalación:
```bash
forge --version   # debe mostrar: forge x.x.x
cast --version
anvil --version
```

### 2. Instalar dependencias del proyecto

```bash
cd world-cup-prediction-pool

# Instala OpenZeppelin como git submodule en lib/
forge install OpenZeppelin/openzeppelin-contracts --no-commit

# Verifica que foundry.toml tiene el remapping correcto:
# remappings = ["@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/"]
```

### 3. Compilar

```bash
forge build
```

---

## Tests

```bash
# Correr todos los tests
forge test

# Con logs detallados (muestra console.log y eventos)
forge test -vvv

# Correr un test específico por nombre
forge test --match-test test_HappyPath_CompleteFlow -vvv

# Correr solo los tests de fuzzing
forge test --match-test testFuzz -vvv

# Ver cobertura de código
forge coverage
```

**Tests incluidos:**
- `test_HappyPath_CompleteFlow` — flujo completo: crear partido, varios usuarios apuestan, se reporta resultado, los ganadores reciben el monto correcto
- `test_CannotClaimTwice` — protección contra doble claim (patrón CEI)
- `test_CannotPredictAfterDeadline` — control del deadline
- `test_OnlyOwnerCanCreateMatch` / `test_OnlyOwnerCanReportResult` — control de acceso
- `test_CannotReportResultTwice` — idempotencia
- `testFuzz_RewardNeverExceedsTotalPool` — invariante de seguridad con 1000 inputs aleatorios
- `testFuzz_MultipleWinnersRewardsSumToPool` — conservación del pozo con múltiples ganadores

---

## Deploy a Sepolia testnet

### Variables de entorno

Crear un archivo `.env` (nunca commitear):

```bash
# Endpoint de nodo — obtené uno gratis en https://alchemy.com o https://infura.io
RPC_URL=https://eth-sepolia.g.alchemy.com/v2/TU_API_KEY

# Clave privada de una wallet de TESTNET SOLAMENTE
# ⚠️  NUNCA uses una wallet con fondos reales
# Generá una nueva en MetaMask → Configuración → Avanzado → Mostrar clave privada
PRIVATE_KEY=0x...

# Para verificar el contrato en Etherscan (opcional)
# https://etherscan.io/myapikey
ETHERSCAN_API_KEY=...
```

### Obtener ETH de testnet (gratis)

1. Instalar MetaMask y cambiar a la red Sepolia
2. Ir a un faucet: https://sepoliafaucet.com o https://faucet.quicknode.com/ethereum/sepolia
3. Pegar tu address y pedir ETH de prueba

### Correr el deploy

```bash
# Cargar variables de entorno
source .env   # Linux/Mac
# En PowerShell: $env:RPC_URL = "..."; $env:PRIVATE_KEY = "..."

# Simular sin deployar (gratis, útil para verificar primero)
forge script script/Deploy.s.sol --rpc-url $RPC_URL

# Deploy real a Sepolia + verificación en Etherscan
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

El comando imprime la dirección del contrato deployado. Guardala para interactuar con él.

### Interactuar con el contrato deployado (cast)

`cast` es la herramienta de Foundry para llamar contratos desde la terminal:

```bash
export CONTRACT=0xDIRECCION_DEL_CONTRATO

# Crear un partido (escribir — cuesta gas)
cast send $CONTRACT \
  "createMatch(uint256,string,string,uint256)" \
  1 "Argentina" "Francia" $(( $(date +%s) + 3600 )) \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL

# Apostar 0.01 ETH a Argentina (enviar ETH con la llamada)
cast send $CONTRACT \
  "predict(uint256,string)" 1 "Argentina" \
  --value 0.01ether \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL

# Leer el estado del partido (gratis — no gasta gas)
cast call $CONTRACT "matches(uint256)" 1 --rpc-url $RPC_URL
```

---

## Por qué el patrón Checks-Effects-Interactions importa en `claim()`

La función `claim()` envía ETH a `msg.sender`. Si `msg.sender` es un contrato malicioso, su función `receive()` puede volver a llamar `claim()` antes de que la primera ejecución termine — el **reentrancy attack**.

**Sin CEI (vulnerable):**
```solidity
function claim(uint256 matchId) external {
    uint256 reward = calcularPremio(matchId); // 1. calcula
    payable(msg.sender).call{value: reward}(""); // 2. envía
    predictions[matchId][msg.sender].claimed = true; // 3. marca — TARDE
    // El atacante re-entró en el paso 2, antes del paso 3
}
```

**Con CEI (seguro, como está implementado):**
```solidity
function claim(uint256 matchId) external nonReentrant {
    // CHECKS: validar
    require(!p.claimed, "Already claimed");
    uint256 reward = calcularPremio();

    // EFFECTS: actualizar estado primero
    p.claimed = true;                              // ← primero esto

    // INTERACTIONS: llamada externa al final
    payable(msg.sender).call{value: reward}("");  // ← recién después
    // Si alguien re-entra acá, p.claimed ya es true → el require revierte
}
```

El contrato usa **ambas** defensas: el orden CEI manual + el modifier `nonReentrant` de OpenZeppelin, porque en seguridad la defensa en profundidad siempre es mejor.

---

## Estructura del proyecto

```
world-cup-prediction-pool/
├── foundry.toml              → configuración: versión de solc, remappings, fuzz runs
├── src/
│   └── PredictionPool.sol    → el contrato principal
├── test/
│   └── PredictionPool.t.sol  → tests + fuzzing en Solidity
├── script/
│   └── Deploy.s.sol          → script de deploy a Sepolia
└── lib/
    └── openzeppelin-contracts/ → instalado con forge install
```
