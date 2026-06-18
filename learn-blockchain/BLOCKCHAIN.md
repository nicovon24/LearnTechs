# Blockchain + Solidity — Guía de referencia rápida

---

## La idea central

En un backend tradicional (NestJS, FastAPI) vos tenés un servidor que guarda estado en una DB que controlás. En Ethereum, el "servidor" es una red de miles de nodos independientes y el "estado" vive en todos ellos simultáneamente. Nadie puede apagar ese servidor ni alterar los datos ya confirmados.

```
Backend tradicional:         Ethereum:
  Tu código                    Tu código (Solidity)
      ↓                              ↓ compilar
  Tu servidor                    Bytecode EVM
      ↓                              ↓ deployar
  Tu base de datos              Blockchain (todos los nodos)
      ↓                              ↓
  Vos lo controlás             Nadie lo controla — es inmutable
```

La consecuencia: **un bug en producción no se puede parchear con un deploy nuevo**. Por eso la seguridad importa mucho más acá que en software tradicional.

---

## 1. Estructura de un contrato — `pragma` y `contract`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;    // versión del compilador

contract MiContrato {
    // variables de estado → viven en la blockchain forever
    uint256 public contador;

    // constructor → se ejecuta UNA vez cuando se deploya
    constructor() {
        contador = 0;
    }

    // función → cualquiera puede llamarla (pagando gas)
    function incrementar() external {
        contador += 1;
    }
}
```

---

## 2. Tipos y variables de estado

**Qué es:** cada variable declarada fuera de una función vive en el storage de la blockchain. Leer cuesta gas, escribir cuesta más.

```solidity
contract Tipos {
    // Enteros (sin signo — no hay negativos)
    uint256 public precio;          // 0 a 2^256-1
    uint8   public nivel;           // 0 a 255 — más pequeño pero NO más barato en EVM

    // Dirección de una wallet o contrato (20 bytes)
    address public owner;

    // Booleano
    bool public activo;

    // Mapping: el "objeto"/diccionario de Solidity
    // mapping(address => uint256): cuánto ETH depositó cada address
    mapping(address => uint256) public balances;

    // Array dinámico
    uint256[] public lista;

    // String — costoso en storage, mejor usar bytes32 si el string es corto y fijo
    string public nombre;
}
```

**Comparación con TypeScript:**

| TypeScript | Solidity | Diferencia clave |
|---|---|---|
| `number` | `uint256` | No hay negativos por defecto en Solidity |
| `string` | `string` / `bytes32` | `bytes32` más barato para strings cortos |
| `object` / `Record<K,V>` | `mapping(K => V)` | No se puede iterar un mapping |
| `boolean` | `bool` | Igual |
| `class instance` | `struct` | Structs no tienen métodos |

---

## 3. Visibilidad — quién puede llamar qué

```solidity
contract Visibilidad {
    uint256 private dato;        // solo este contrato
    uint256 internal datoBase;   // este contrato + contratos hijos (herencia)
    uint256 public datoPublico;  // cualquiera puede leer (getter automático)

    // external: solo puede llamarse desde fuera del contrato
    // (más barato que public para parámetros calldata)
    function externalFn() external { }

    // public: puede llamarse desde afuera Y desde adentro
    function publicFn() public { }

    // internal: solo este contrato y sus hijos (equivalente a protected en OOP)
    function internalFn() internal { }

    // private: solo este contrato (equivalente a private en OOP)
    function privateFn() private { }
}
```

**Regla práctica:** usá `external` para funciones que solo van a llamarse desde fuera. Es más eficiente porque los parámetros `calldata` no se copian a `memory`.

---

## 4. `msg.sender` y `msg.value` — el corazón de los permisos

```solidity
contract Mensajes {
    address public owner;
    mapping(address => uint256) public depositos;

    constructor() {
        // msg.sender en el constructor = la wallet que deploya el contrato
        owner = msg.sender;
    }

    // payable: esta función puede recibir ETH
    // msg.value = el ETH (en wei) enviado con la llamada
    function depositar() external payable {
        require(msg.value > 0, "Manda algo de ETH");
        // msg.sender = quien llama a esta función
        depositos[msg.sender] += msg.value;
    }

    function soloOwner() external {
        require(msg.sender == owner, "Solo el owner");
        // solo el owner puede ejecutar lo que venga acá
    }
}
```

---

## 5. Modifiers — lógica reutilizable antes de una función

**Qué es:** un bloque de código que corre antes del cuerpo de la función. El `_` es donde corre el cuerpo de la función original.

**Analogía:** exactamente como un Guard de NestJS — intercepta la ejecución y decide si continúa o revierte.

```solidity
contract Modifiers {
    address public owner;
    bool public pausado;

    modifier onlyOwner() {
        require(msg.sender == owner, "Solo el owner");
        _;  // ← acá corre el cuerpo de la función decorada
    }

    modifier cuandoActivo() {
        require(!pausado, "Contrato pausado");
        _;
    }

    // Se puede apilar modifiers — corren en orden de izquierda a derecha
    function accionCritica() external onlyOwner cuandoActivo {
        // solo el owner puede llamar esto, y solo cuando no está pausado
    }
}
```

---

## 6. Eventos — logging on-chain

```solidity
contract Eventos {
    // Declaración del evento
    // indexed: permite filtrar por ese campo desde un frontend
    event Transferencia(
        address indexed from,
        address indexed to,
        uint256 amount
    );

    function transferir(address to, uint256 amount) external {
        // ... lógica ...

        // Emitir el evento — queda registrado en los logs de la transacción
        emit Transferencia(msg.sender, to, amount);
    }
}
```

**Por qué eventos en vez de variables de estado:**

| Variable de estado | Evento |
|---|---|
| Cuesta ~20,000 gas (SSTORE) | Cuesta ~375 gas base |
| El contrato puede leerla | El contrato NO puede leer sus propios eventos |
| Persiste en storage | Solo en logs de la transacción |
| Para estado que el contrato necesita | Para notificaciones al frontend |

---

## 7. Mappings — el diccionario de Solidity

```solidity
contract Mappings {
    // mapping(tipoKey => tipoValor)
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => bool)) public aprobaciones; // anidado

    function depositar() external payable {
        balances[msg.sender] += msg.value;
    }

    function getBalance(address usuario) external view returns (uint256) {
        // Si la key no existe, devuelve el valor zero del tipo (0, false, address(0))
        return balances[usuario];
    }
}
```

**La limitación clave:** no podés iterar un mapping (no hay `Object.keys()` ni `.forEach()`). Si necesitás iterar, llevá también un array separado con las keys:

```solidity
address[] public usuarios;                     // para iterar
mapping(address => uint256) public balances;   // para acceso O(1)
```

---

## 8. Patrón Checks-Effects-Interactions (CEI)

**El patrón más importante de seguridad en Solidity.** Previene el reentrancy attack.

```solidity
function retirar(uint256 amount) external {
    // ── CHECKS — validar TODO antes de tocar estado ──────────────────────
    require(balances[msg.sender] >= amount, "Saldo insuficiente");
    require(amount > 0, "Monto inválido");

    // ── EFFECTS — actualizar estado interno ANTES de llamadas externas ───
    // Si alguien re-entra acá, el CHECKS de arriba va a fallar
    balances[msg.sender] -= amount;

    // ── INTERACTIONS — llamadas externas AL FINAL ─────────────────────────
    (bool ok, ) = payable(msg.sender).call{value: amount}("");
    require(ok, "Transferencia fallida");
}
```

**El reentrancy attack sin CEI:**
```
Tu contrato                    Contrato malicioso
    │                               │
    ├── retirar(1 ETH)              │
    │   calcular premio             │
    │   enviar ETH ─────────────────►│
    │                               │ receive() {
    │                               │   retirar(1 ETH) ← re-entra!
    │◄──────────────────────────────┤ }
    │   (balances todavía en 1 ETH) │
    │   re-entrada pasa los checks  │
    │   envía otro ETH ─────────────►│
    │   repite hasta vaciar pool    │
```

---

## 9. OpenZeppelin — la librería estándar

**Por qué usarla:** es el equivalente a `@nestjs/jwt` o `passport` en Node — código auditado por expertos en seguridad que no tiene sentido reinventar.

```solidity
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract MiContrato is Ownable, ReentrancyGuard {
    constructor() Ownable(msg.sender) {}

    // onlyOwner: revierte si msg.sender != owner
    function adminAction() external onlyOwner {
        // solo el owner
    }

    // nonReentrant: bloquea re-entrada a esta función
    function retirar() external nonReentrant {
        // ...
    }
}
```

**Contratos de OZ más usados:**

| Contrato | Para qué sirve |
|---|---|
| `Ownable` | Control de acceso con un owner |
| `AccessControl` | Roles múltiples (ADMIN_ROLE, MINTER_ROLE...) |
| `ReentrancyGuard` | Prevenir reentrancy attack |
| `ERC20` | Token fungible estándar |
| `ERC721` | NFT estándar |
| `Pausable` | Pausar el contrato en emergencias |

---

## 10. Testing con Foundry

```solidity
// Test.t.sol
import {Test} from "forge-std/Test.sol";

contract MiTest is Test {
    MiContrato public contrato;

    // Corre antes de CADA test (como beforeEach en Jest)
    function setUp() public {
        contrato = new MiContrato();
    }

    // Test determinístico
    function test_funcionaCorrectamente() public {
        assertEq(contrato.contador(), 0);
        contrato.incrementar();
        assertEq(contrato.contador(), 1);
    }

    // Test de fuzzing — Foundry genera valores aleatorios automáticamente
    function testFuzz_siemprePositivo(uint256 n) public {
        n = bound(n, 1, 100); // restringe el rango
        contrato.sumar(n);
        assertGt(contrato.contador(), 0);
    }
}
```

**Cheatcodes de Foundry más usados:**

| Cheatcode | Qué hace |
|---|---|
| `vm.prank(addr)` | La siguiente llamada viene de `addr` |
| `vm.startPrank(addr)` | Todas las llamadas hasta `vm.stopPrank()` vienen de `addr` |
| `vm.deal(addr, amount)` | Asigna balance de ETH a `addr` |
| `vm.warp(timestamp)` | Setea `block.timestamp` |
| `vm.roll(blockNum)` | Setea `block.number` |
| `vm.expectRevert(msg)` | La siguiente llamada DEBE revertir con ese mensaje |
| `bound(x, min, max)` | Restringe un valor fuzz a un rango válido |

---

## Resumen visual: qué archivo hace qué

```
world-cup-prediction-pool/
├── foundry.toml          → configuración del proyecto (solc version, remappings, fuzz runs)
│
├── src/
│   └── PredictionPool.sol → el contrato — estado, funciones, eventos, seguridad
│
├── test/
│   └── PredictionPool.t.sol → tests y fuzzing en Solidity puro
│
├── script/
│   └── Deploy.s.sol      → script de deploy a Sepolia testnet
│
└── lib/
    └── openzeppelin-contracts/ → instalado con `forge install OpenZeppelin/openzeppelin-contracts`
```

---

## Flujo completo de una transacción

`predict(matchId, "Argentina")` con 0.5 ETH:

1. El usuario firma la transacción con su clave privada (en MetaMask)
2. La transacción viaja a la red y espera en el mempool
3. Un validador la incluye en un bloque
4. La EVM ejecuta el bytecode de `predict()` con los parámetros
5. Se verifica cada `require()` — si alguno falla, toda la tx revierte y se cobra el gas igual
6. Si todo pasa, se actualiza el storage (`predictions[matchId][msg.sender]`, `m.totalPool`)
7. Se emite el evento `PredictionMade`
8. El nuevo estado queda grabado en el bloque, encadenado al anterior, para siempre
