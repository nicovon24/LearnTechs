// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ── OpenZeppelin ──────────────────────────────────────────────────────────────
//
// Ownable: agrega un "owner" al contrato con el modifier onlyOwner.
// POR QUÉ OZ en vez de escribirlo a mano: el código está auditado por firmas
// de seguridad profesionales. Escribir tu propio control de acceso es una
// fuente clásica de vulnerabilidades.
//
// ReentrancyGuard: agrega el modifier nonReentrant que previene el reentrancy
// attack — el bug más costoso de la historia de Ethereum (hack del DAO, 2016).
// Más detalles en la función claim() más abajo.
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title  PredictionPool
 * @author LearnTechs / Prodeazo
 * @notice Pool de apuestas on-chain para resultados de partidos de fútbol.
 *         Varios usuarios apuestan ETH. Cuando el owner reporta el resultado
 *         real, el pozo se reparte proporcionalmente entre los que acertaron.
 *
 * FLUJO COMPLETO:
 *   1. Owner llama createMatch() con los dos resultados posibles y un deadline.
 *   2. Usuarios llaman predict() enviando ETH antes del deadline.
 *   3. Owner llama reportResult() después del deadline con el resultado ganador.
 *   4. Ganadores llaman claim() para retirar su parte proporcional del pozo.
 */
contract PredictionPool is Ownable, ReentrancyGuard {

    // ── Structs ───────────────────────────────────────────────────────────────

    /**
     * @dev Representa un partido y su estado completo.
     *
     * POR QUÉ almacenamos outcomeHash (bytes32) en vez del string directamente:
     * Comparar strings en Solidity requiere keccak256() — no existe `==` para
     * strings. Guardar el hash evita re-hashear en cada comparación y ahorra gas.
     *
     * POR QUÉ cada variable de estado tiene un costo:
     * En la EVM, escribir en storage (SSTORE) cuesta ~20,000 gas la primera vez.
     * Leer (SLOAD) cuesta ~2,100 gas. Por eso la eficiencia del storage importa
     * mucho más acá que en un backend donde "guardar en DB" es casi gratuito.
     */
    struct Match {
        bytes32 outcomeHashA;  // keccak256("Argentina") — no el string, el hash
        bytes32 outcomeHashB;  // keccak256("Francia")
        uint256 deadline;      // timestamp UNIX límite para apostar
        bytes32 winningHash;   // keccak256 del ganador, seteado en reportResult()
        bool resultReported;   // true una vez que el owner reportó
        uint256 totalPool;     // suma de TODO el ETH apostado
        uint256 totalOnWinner; // suma del ETH apostado SOLO al resultado ganador
    }

    /**
     * @dev La apuesta de un usuario en un partido específico.
     */
    struct Prediction {
        bytes32 outcomeHash; // a qué resultado apostó
        uint256 amount;      // cuánto ETH apostó (en wei — 1 ETH = 1e18 wei)
        bool claimed;        // ya retiró su premio?
    }

    // ── Storage (variables de estado) ─────────────────────────────────────────
    //
    // Todo lo que se declare acá vive permanentemente en la blockchain.
    // Cada slot de storage = 32 bytes. Solidity agrupa variables pequeñas
    // en un mismo slot para ahorrar gas (slot packing).

    // Todos los partidos por id
    mapping(uint256 => Match) public matches;

    // La apuesta de cada usuario por partido
    // mapping anidado: no se puede iterar, pero acceso en O(1)
    mapping(uint256 => mapping(address => Prediction)) public predictions;

    // Total apostado por outcome en cada partido.
    // Se acumula durante predict() para que reportResult() lo lea en O(1).
    // matchOutcomeTotals[matchId][outcomeHash] = total en wei
    mapping(uint256 => mapping(bytes32 => uint256)) public matchOutcomeTotals;

    // ── Eventos ───────────────────────────────────────────────────────────────
    //
    // POR QUÉ usar eventos:
    // Los eventos se almacenan en los logs de la transacción, no en el storage.
    // Cuestan mucho menos gas que escribir en storage. Un frontend puede
    // escucharlos con ethers.js/viem sin hacer polling constante al nodo.
    //
    // indexed: permite filtrar eventos por ese campo. Sin indexed, para buscar
    // "todos los eventos del matchId=42" habría que escanear todos los logs.

    event MatchCreated(uint256 indexed matchId, string outcomeA, string outcomeB, uint256 deadline);
    event PredictionMade(uint256 indexed matchId, address indexed user, string outcome, uint256 amount);
    event ResultReported(uint256 indexed matchId, string winningOutcome);
    event RewardClaimed(uint256 indexed matchId, address indexed user, uint256 reward);

    // ── Constructor ───────────────────────────────────────────────────────────

    /**
     * @dev Ownable(msg.sender) setea al deployer como el owner inicial.
     * msg.sender en el constructor es la wallet que firma la transacción de deploy.
     */
    constructor() Ownable(msg.sender) {}

    // ── Funciones externas ────────────────────────────────────────────────────

    /**
     * @notice El owner crea un partido con dos outcomes posibles y un deadline.
     * @dev onlyOwner: modifier de OpenZeppelin. Revierte si msg.sender != owner.
     *      Es el equivalente a un Guard de NestJS, pero en Solidity.
     *
     * calldata vs memory para strings:
     * calldata es la zona de datos del input de la transacción. Es más barato
     * que memory porque no se copia. Para external functions con parámetros
     * que no se modifican, calldata es el patrón recomendado.
     */
    function createMatch(
        uint256 matchId,
        string calldata outcomeA,
        string calldata outcomeB,
        uint256 deadline
    ) external onlyOwner {
        require(deadline > block.timestamp,       "Deadline must be in the future");
        require(matches[matchId].deadline == 0,   "Match already exists");
        require(bytes(outcomeA).length > 0,        "outcomeA cannot be empty");
        require(bytes(outcomeB).length > 0,        "outcomeB cannot be empty");

        matches[matchId] = Match({
            outcomeHashA:   keccak256(bytes(outcomeA)),
            outcomeHashB:   keccak256(bytes(outcomeB)),
            deadline:       deadline,
            winningHash:    bytes32(0),
            resultReported: false,
            totalPool:      0,
            totalOnWinner:  0
        });

        emit MatchCreated(matchId, outcomeA, outcomeB, deadline);
    }

    /**
     * @notice Apuesta ETH al resultado de un partido.
     * @dev payable: permite que esta función reciba ETH junto a la llamada.
     *      Sin payable, cualquier tx que incluya ETH (msg.value > 0) revierte.
     *
     * msg.value: el ETH (en wei) enviado en esta transacción.
     * msg.sender: la dirección que llama a esta función.
     *
     * POR QUÉ solo una apuesta por usuario por partido:
     * Simplifica la lógica del claim. Si hubiera múltiples apuestas por usuario,
     * habría que acumular o iterar — más gas, más complejidad, más superficie de ataque.
     */
    function predict(uint256 matchId, string calldata outcome) external payable {
        Match storage m = matches[matchId];
        require(m.deadline > 0,                    "Match does not exist");
        require(block.timestamp < m.deadline,      "Betting deadline has passed");
        require(!m.resultReported,                 "Result already reported");
        require(msg.value > 0,                     "Must send ETH to predict");
        require(
            predictions[matchId][msg.sender].amount == 0,
            "Already placed a prediction for this match"
        );

        bytes32 outcomeHash = keccak256(bytes(outcome));
        require(
            outcomeHash == m.outcomeHashA || outcomeHash == m.outcomeHashB,
            "Invalid outcome — must match one of the two defined outcomes"
        );

        // Guardar la predicción del usuario
        predictions[matchId][msg.sender] = Prediction({
            outcomeHash: outcomeHash,
            amount:      msg.value,
            claimed:     false
        });

        // Acumular en el pozo total
        m.totalPool += msg.value;

        // Acumular el total por outcome para que reportResult() lo lea en O(1)
        // sin tener que iterar todos los predictions (que no se puede en un mapping)
        matchOutcomeTotals[matchId][outcomeHash] += msg.value;

        emit PredictionMade(matchId, msg.sender, outcome, msg.value);
    }

    /**
     * @notice El owner reporta el resultado real del partido.
     * @dev Solo puede llamarse una vez y solo después del deadline.
     *      Lee matchOutcomeTotals para saber cuánto se apostó al ganador.
     */
    function reportResult(uint256 matchId, string calldata winningOutcome) external onlyOwner {
        Match storage m = matches[matchId];
        require(m.deadline > 0,                "Match does not exist");
        require(block.timestamp >= m.deadline, "Betting is still open");
        require(!m.resultReported,             "Result already reported");

        bytes32 winningHash = keccak256(bytes(winningOutcome));
        require(
            winningHash == m.outcomeHashA || winningHash == m.outcomeHashB,
            "Invalid winning outcome"
        );

        m.winningHash    = winningHash;
        m.resultReported = true;
        m.totalOnWinner  = matchOutcomeTotals[matchId][winningHash];

        emit ResultReported(matchId, winningOutcome);
    }

    /**
     * @notice Los ganadores retiran su parte proporcional del pozo total.
     *
     * ╔═══════════════════════════════════════════════════════════════════════╗
     * ║         PATRÓN CHECKS-EFFECTS-INTERACTIONS (CEI)                    ║
     * ║         La pieza más importante de seguridad en Solidity             ║
     * ╚═══════════════════════════════════════════════════════════════════════╝
     *
     * EL REENTRANCY ATTACK — cómo funciona sin CEI:
     * ─────────────────────────────────────────────
     *   1. Un contrato malicioso llama a claim().
     *   2. claim() calcula el premio y llama payable(msg.sender).call{value: reward}().
     *   3. El receive() del contrato malicioso se ejecuta automáticamente.
     *   4. receive() vuelve a llamar claim() ANTES de que la primera ejecución
     *      llegue a marcar p.claimed = true.
     *   5. La segunda llamada pasa TODOS los checks (p.claimed sigue en false).
     *   6. Se envía ETH de nuevo. Se repite hasta vaciar el contrato.
     *   → El hack del DAO (2016) drenó ~$60M con exactamente este patrón.
     *
     * EL FIX — patrón CEI:
     * ───────────────────────
     *   CHECKS:      validar todo antes de tocar estado.
     *   EFFECTS:     actualizar estado interno del contrato (p.claimed = true).
     *   INTERACTIONS: RECIÉN después hacer la llamada externa (enviar ETH).
     *
     *   Si alguien re-entra después de EFFECTS, el check `!p.claimed` revierte.
     *
     * ReentrancyGuard (nonReentrant) es la segunda capa de defensa:
     *   Bloquea cualquier re-entrada a esta función aunque el orden CEI fallara.
     *   Usamos AMBAS defensas porque en seguridad la defensa en profundidad
     *   siempre es mejor que confiar en una sola capa.
     *
     * FÓRMULA DEL PREMIO:
     *   reward = totalPool * (apuestaUsuario / totalApostadoAlGanador)
     *          = (totalPool * apuestaUsuario) / totalOnWinner
     *
     *   Multiplicamos antes de dividir para evitar truncamiento por división entera.
     *   Ejemplo: totalPool=10, apuesta=3, totalOnWinner=5 → reward = (10*3)/5 = 6
     *   (te llevás el 60% del pozo porque apostaste el 60% del lado ganador)
     */
    function claim(uint256 matchId) external nonReentrant {

        // ── CHECKS ────────────────────────────────────────────────────────────
        Match storage m = matches[matchId];
        require(m.resultReported,        "Result not reported yet");

        Prediction storage p = predictions[matchId][msg.sender];
        require(p.amount > 0,            "No prediction found for this address");
        require(!p.claimed,              "Reward already claimed");
        require(
            p.outcomeHash == m.winningHash,
            "You did not predict the winning outcome"
        );
        require(m.totalOnWinner > 0,     "No ETH was bet on the winning outcome");

        uint256 reward = (m.totalPool * p.amount) / m.totalOnWinner;
        require(reward > 0,              "Calculated reward is zero");

        // ── EFFECTS ───────────────────────────────────────────────────────────
        // Estado actualizado ANTES de la llamada externa.
        // Una re-entrada después de esta línea va a encontrar p.claimed == true
        // y revertir en el check de arriba.
        p.claimed = true;

        // ── INTERACTIONS ──────────────────────────────────────────────────────
        // .call{value: reward}("") es el patrón recomendado en Solidity moderno.
        // Más robusto que transfer() o send(), que tienen un límite fijo de gas
        // que puede causar fallas cuando el receptor es un contrato con lógica
        // en su receive().
        (bool success, ) = payable(msg.sender).call{value: reward}("");
        require(success, "ETH transfer failed");

        emit RewardClaimed(matchId, msg.sender, reward);
    }

    // ── Views — lectura gratuita off-chain ────────────────────────────────────

    /**
     * @notice Devuelve el monto apostado y si ya reclamó para un usuario.
     * @dev view no modifica estado → gratis de llamar desde un frontend.
     */
    function getUserPrediction(uint256 matchId, address user)
        external
        view
        returns (uint256 amount, bool claimed)
    {
        Prediction storage p = predictions[matchId][user];
        return (p.amount, p.claimed);
    }

    /**
     * @notice Calcula el premio potencial de un usuario antes de que reclame.
     * @dev Útil para que un frontend muestre "vas a recibir X ETH".
     *      Devuelve 0 si el resultado no fue reportado, el usuario no ganó,
     *      o ya reclamó.
     */
    function getPotentialReward(uint256 matchId, address user) external view returns (uint256) {
        Match storage m = matches[matchId];
        if (!m.resultReported) return 0;

        Prediction storage p = predictions[matchId][user];
        if (p.amount == 0 || p.claimed)         return 0;
        if (p.outcomeHash != m.winningHash)     return 0;
        if (m.totalOnWinner == 0)               return 0;

        return (m.totalPool * p.amount) / m.totalOnWinner;
    }
}
