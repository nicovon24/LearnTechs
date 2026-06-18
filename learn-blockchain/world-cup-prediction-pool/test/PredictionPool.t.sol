// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Tests de Foundry para PredictionPool.
 *
 * POR QUÉ tests en Solidity (Foundry) en vez de JavaScript (Hardhat):
 * - No hay context-switching de lenguaje — todo en Solidity.
 * - Fuzzing incorporado de fábrica: Foundry corre miles de inputs aleatorios
 *   automáticamente cuando el parámetro del test empieza con una palabra clave.
 * - Mucho más rápido para iterar: forge test corre en milisegundos.
 *
 * ESTRUCTURA DE CADA TEST en Foundry:
 *   setUp()     → corre antes de CADA test (como beforeEach en Jest/JUnit)
 *   test_*()    → test determinístico con valores fijos
 *   testFuzz_*()→ Foundry detecta el prefijo y activa el fuzzer automáticamente
 *
 * vm.* → cheatcodes de Foundry: funciones especiales que solo existen en tests
 * para manipular el estado de la EVM (avanzar tiempo, cambiar msg.sender, etc.)
 */

import {Test, console} from "forge-std/Test.sol";
import {PredictionPool} from "../src/PredictionPool.sol";

contract PredictionPoolTest is Test {

    // ── Constantes del fixture ────────────────────────────────────────────────

    PredictionPool public pool;

    // Wallets de prueba — en Foundry se crean con makeAddr() que deriva
    // una dirección determinística del string (útil para que los logs sean legibles)
    address public owner;
    address public alice;
    address public bob;
    address public charlie;

    uint256 constant MATCH_ID   = 1;
    string  constant OUTCOME_A  = "Argentina";
    string  constant OUTCOME_B  = "Francia";
    uint256 deadline;

    // ── setUp — corre antes de cada test ─────────────────────────────────────

    function setUp() public {
        owner   = makeAddr("owner");
        alice   = makeAddr("alice");
        bob     = makeAddr("bob");
        charlie = makeAddr("charlie");

        // vm.prank: la SIGUIENTE llamada se ejecuta como si viniera de `owner`
        // Equivalente a "actuar como este usuario" — cambiar msg.sender por una llamada
        vm.prank(owner);
        pool = new PredictionPool();

        // Deadline en 1 hora a partir del timestamp actual del bloque de test
        deadline = block.timestamp + 1 hours;

        // Dar ETH de prueba a las wallets (vm.deal = cheatcode que asigna balance)
        vm.deal(alice,   10 ether);
        vm.deal(bob,     10 ether);
        vm.deal(charlie, 10 ether);
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    /**
     * @dev Crea el partido estándar del fixture.
     *      Separado para no repetir en cada test.
     */
    function _createStandardMatch() internal {
        vm.prank(owner);
        pool.createMatch(MATCH_ID, OUTCOME_A, OUTCOME_B, deadline);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // HAPPY PATH — flujo completo de punta a punta
    // ══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Test del happy path completo:
     *   Alice apuesta 1 ETH a Argentina, Bob apuesta 2 ETH a Argentina,
     *   Charlie apuesta 3 ETH a Francia. Argentina gana.
     *   Pozo total = 6 ETH. Total en ganador = 3 ETH (Alice 1 + Bob 2).
     *   Alice recibe: (6 * 1) / 3 = 2 ETH.
     *   Bob recibe:   (6 * 2) / 3 = 4 ETH.
     */
    function test_HappyPath_CompleteFlow() public {
        _createStandardMatch();

        // Apuestas — vm.prank cambia msg.sender para la siguiente llamada
        // {value: X} es cómo en Foundry se envía ETH junto a la llamada
        vm.prank(alice);
        pool.predict{value: 1 ether}(MATCH_ID, OUTCOME_A);

        vm.prank(bob);
        pool.predict{value: 2 ether}(MATCH_ID, OUTCOME_A);

        vm.prank(charlie);
        pool.predict{value: 3 ether}(MATCH_ID, OUTCOME_B);

        // Verificar que el pozo se acumuló correctamente
        (, , , , , uint256 totalPool, ) = pool.matches(MATCH_ID);
        assertEq(totalPool, 6 ether, "Total pool should be 6 ETH");

        // Avanzar el tiempo más allá del deadline para poder reportar resultado
        // vm.warp: cheatcode que setea block.timestamp
        vm.warp(deadline + 1);

        vm.prank(owner);
        pool.reportResult(MATCH_ID, OUTCOME_A);

        // Alice reclama — debería recibir 2 ETH
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        pool.claim(MATCH_ID);
        assertEq(alice.balance - aliceBalanceBefore, 2 ether, "Alice should receive 2 ETH");

        // Bob reclama — debería recibir 4 ETH
        uint256 bobBalanceBefore = bob.balance;
        vm.prank(bob);
        pool.claim(MATCH_ID);
        assertEq(bob.balance - bobBalanceBefore, 4 ether, "Bob should receive 4 ETH");

        // Charlie no puede reclamar — apostó al perdedor
        vm.prank(charlie);
        vm.expectRevert("You did not predict the winning outcome");
        pool.claim(MATCH_ID);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // TESTS DE CASOS DE ERROR
    // ══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Un usuario no puede reclamar dos veces.
     * @dev Este test verifica que el EFFECTS del patrón CEI funciona:
     *      p.claimed = true antes de enviar ETH previene la segunda extracción.
     */
    function test_CannotClaimTwice() public {
        _createStandardMatch();

        vm.prank(alice);
        pool.predict{value: 1 ether}(MATCH_ID, OUTCOME_A);

        vm.warp(deadline + 1);
        vm.prank(owner);
        pool.reportResult(MATCH_ID, OUTCOME_A);

        // Primer claim — debe funcionar
        vm.prank(alice);
        pool.claim(MATCH_ID);

        // Segundo claim — debe revertir
        vm.prank(alice);
        vm.expectRevert("Reward already claimed");
        pool.claim(MATCH_ID);
    }

    /**
     * @notice No se puede apostar después del deadline.
     */
    function test_CannotPredictAfterDeadline() public {
        _createStandardMatch();

        // Avanzar el tiempo más allá del deadline
        vm.warp(deadline + 1);

        vm.prank(alice);
        vm.expectRevert("Betting deadline has passed");
        pool.predict{value: 1 ether}(MATCH_ID, OUTCOME_A);
    }

    /**
     * @notice Solo el owner puede crear partidos.
     */
    function test_OnlyOwnerCanCreateMatch() public {
        vm.prank(alice);
        vm.expectRevert(); // Ownable revierte con OwnableUnauthorizedAccount
        pool.createMatch(MATCH_ID, OUTCOME_A, OUTCOME_B, deadline);
    }

    /**
     * @notice Solo el owner puede reportar el resultado.
     */
    function test_OnlyOwnerCanReportResult() public {
        _createStandardMatch();

        vm.warp(deadline + 1);

        vm.prank(alice);
        vm.expectRevert();
        pool.reportResult(MATCH_ID, OUTCOME_A);
    }

    /**
     * @notice No se puede reportar el resultado dos veces.
     */
    function test_CannotReportResultTwice() public {
        _createStandardMatch();
        vm.warp(deadline + 1);

        vm.prank(owner);
        pool.reportResult(MATCH_ID, OUTCOME_A);

        vm.prank(owner);
        vm.expectRevert("Result already reported");
        pool.reportResult(MATCH_ID, OUTCOME_A);
    }

    /**
     * @notice No se puede apostar un outcome inválido.
     */
    function test_CannotPredictInvalidOutcome() public {
        _createStandardMatch();

        vm.prank(alice);
        vm.expectRevert("Invalid outcome — must match one of the two defined outcomes");
        pool.predict{value: 1 ether}(MATCH_ID, "Brasil");
    }

    /**
     * @notice No se puede crear un partido con deadline en el pasado.
     */
    function test_CannotCreateMatchWithPastDeadline() public {
        vm.prank(owner);
        vm.expectRevert("Deadline must be in the future");
        pool.createMatch(MATCH_ID, OUTCOME_A, OUTCOME_B, block.timestamp - 1);
    }

    /**
     * @notice Un usuario no puede apostar sin enviar ETH.
     */
    function test_CannotPredictWithZeroValue() public {
        _createStandardMatch();

        vm.prank(alice);
        vm.expectRevert("Must send ETH to predict");
        pool.predict{value: 0}(MATCH_ID, OUTCOME_A);
    }

    /**
     * @notice Un usuario no puede apostar dos veces en el mismo partido.
     */
    function test_CannotPredictTwiceInSameMatch() public {
        _createStandardMatch();

        vm.prank(alice);
        pool.predict{value: 1 ether}(MATCH_ID, OUTCOME_A);

        vm.prank(alice);
        vm.expectRevert("Already placed a prediction for this match");
        pool.predict{value: 1 ether}(MATCH_ID, OUTCOME_B);
    }

    /**
     * @notice No se puede reclamar antes de que se reporte el resultado.
     */
    function test_CannotClaimBeforeResultReported() public {
        _createStandardMatch();

        vm.prank(alice);
        pool.predict{value: 1 ether}(MATCH_ID, OUTCOME_A);

        vm.prank(alice);
        vm.expectRevert("Result not reported yet");
        pool.claim(MATCH_ID);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // FUZZING — invariantes de seguridad
    // ══════════════════════════════════════════════════════════════════════════

    /**
     * @notice INVARIANTE: la suma de todos los premios nunca supera el pozo total.
     *
     * POR QUÉ esto importa:
     * Si esta invariante se viola, el contrato paga más ETH del que recibió —
     * equivalente a "imprimir dinero" o vaciarse. Es el tipo de bug que un
     * fuzzer encuentra automáticamente con inputs que vos no pensarías probar.
     *
     * CÓMO funciona el fuzzing en Foundry:
     * Los parámetros del test (aliceAmount, bobAmount) son generados aleatoriamente
     * por Foundry, corriendo este test `runs` veces (configurado en foundry.toml).
     * El `bound()` helper restringe los valores a rangos válidos.
     *
     * @param aliceAmount Monto aleatorio que apostará Alice (1 wei a 5 ETH)
     * @param bobAmount   Monto aleatorio que apostará Bob   (1 wei a 5 ETH)
     */
    function testFuzz_RewardNeverExceedsTotalPool(
        uint256 aliceAmount,
        uint256 bobAmount
    ) public {
        // bound(): restringe el valor aleatorio a un rango útil.
        // Sin esto, el fuzzer puede generar valores que hagan revertir por falta de ETH.
        aliceAmount = bound(aliceAmount, 1 wei, 5 ether);
        bobAmount   = bound(bobAmount,   1 wei, 5 ether);

        // Dar suficiente ETH a los usuarios para este fuzz run
        vm.deal(alice, aliceAmount);
        vm.deal(bob,   bobAmount);

        _createStandardMatch();

        // Alice apuesta a Argentina, Bob a Francia
        vm.prank(alice);
        pool.predict{value: aliceAmount}(MATCH_ID, OUTCOME_A);

        vm.prank(bob);
        pool.predict{value: bobAmount}(MATCH_ID, OUTCOME_B);

        vm.warp(deadline + 1);

        // Argentina gana — solo Alice puede reclamar
        vm.prank(owner);
        pool.reportResult(MATCH_ID, OUTCOME_A);

        (, , , , , uint256 totalPool, ) = pool.matches(MATCH_ID);

        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        pool.claim(MATCH_ID);

        uint256 aliceReward = alice.balance - aliceBalanceBefore;

        // LA INVARIANTE: el premio de Alice nunca puede superar el pozo total
        assertLe(aliceReward, totalPool, "Reward must never exceed total pool");

        // Verificamos también que Alice recibió exactamente lo que le corresponde
        // En este caso Alice es la única ganadora → se lleva todo el pozo
        assertEq(aliceReward, totalPool, "Sole winner should receive entire pool");
    }

    /**
     * @notice INVARIANTE: con múltiples ganadores, la suma de premios == totalPool.
     *
     * Cuando hay varios ganadores, sus premios proporcionales deben sumar exactamente
     * el pozo total (sin pérdidas ni ganancias para el contrato).
     *
     * Nota: puede haber una diferencia de 1 wei por división entera en Solidity.
     * El `assertApproxEqAbs` permite un margen de 1 wei.
     *
     * @param aliceAmount Monto aleatorio de Alice
     * @param bobAmount   Monto aleatorio de Bob (ambos votan al mismo resultado)
     */
    function testFuzz_MultipleWinnersRewardsSumToPool(
        uint256 aliceAmount,
        uint256 bobAmount
    ) public {
        aliceAmount = bound(aliceAmount, 1 wei, 5 ether);
        bobAmount   = bound(bobAmount,   1 wei, 5 ether);

        vm.deal(alice,   aliceAmount);
        vm.deal(bob,     bobAmount);
        vm.deal(charlie, 1 ether);

        _createStandardMatch();

        // Alice y Bob apuestan al ganador; Charlie al perdedor
        vm.prank(alice);
        pool.predict{value: aliceAmount}(MATCH_ID, OUTCOME_A);

        vm.prank(bob);
        pool.predict{value: bobAmount}(MATCH_ID, OUTCOME_A);

        vm.prank(charlie);
        pool.predict{value: 1 ether}(MATCH_ID, OUTCOME_B);

        vm.warp(deadline + 1);
        vm.prank(owner);
        pool.reportResult(MATCH_ID, OUTCOME_A);

        (, , , , , uint256 totalPool, ) = pool.matches(MATCH_ID);

        uint256 aliceBalanceBefore   = alice.balance;
        uint256 bobBalanceBefore     = bob.balance;

        vm.prank(alice);
        pool.claim(MATCH_ID);

        vm.prank(bob);
        pool.claim(MATCH_ID);

        uint256 aliceReward = alice.balance - aliceBalanceBefore;
        uint256 bobReward   = bob.balance   - bobBalanceBefore;
        uint256 totalPaid   = aliceReward + bobReward;

        // La suma de premios debe ser igual al pozo total (±1 wei por redondeo)
        assertApproxEqAbs(totalPaid, totalPool, 1, "Sum of rewards should equal total pool");
    }

    // ══════════════════════════════════════════════════════════════════════════
    // TESTS DE VIEWS
    // ══════════════════════════════════════════════════════════════════════════

    function test_GetPotentialReward_ReturnsCorrectAmount() public {
        _createStandardMatch();

        vm.prank(alice);
        pool.predict{value: 2 ether}(MATCH_ID, OUTCOME_A);

        vm.prank(bob);
        pool.predict{value: 2 ether}(MATCH_ID, OUTCOME_B);

        // Antes de reportar resultado → 0
        assertEq(pool.getPotentialReward(MATCH_ID, alice), 0);

        vm.warp(deadline + 1);
        vm.prank(owner);
        pool.reportResult(MATCH_ID, OUTCOME_A);

        // Alice apostó 2 de 2 al ganador → se lleva los 4 ETH del pozo
        assertEq(pool.getPotentialReward(MATCH_ID, alice), 4 ether);
        // Bob apostó al perdedor → 0
        assertEq(pool.getPotentialReward(MATCH_ID, bob),   0);
    }
}
