// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Script de deploy de Foundry para PredictionPool.
 *
 * POR QUÉ un Script de Foundry en vez de un script de Hardhat en JS:
 * - Está escrito en Solidity — mismo lenguaje que el contrato.
 * - vm.startBroadcast() / vm.stopBroadcast() marca qué transacciones
 *   se firman y mandan a la red real (vs simulación local).
 * - forge script simula el deploy primero y te muestra el costo en gas
 *   antes de gastarlo de verdad.
 *
 * USO (ver README para el setup completo):
 *
 *   # Simular sin deployar (gratis, útil para verificar):
 *   forge script script/Deploy.s.sol --rpc-url $RPC_URL
 *
 *   # Deployar a Sepolia testnet:
 *   forge script script/Deploy.s.sol \
 *     --rpc-url $RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --etherscan-api-key $ETHERSCAN_API_KEY
 *
 * VARIABLES DE ENTORNO NECESARIAS (nunca hardcodear en el código):
 *   RPC_URL             → endpoint de Alchemy o Infura para Sepolia
 *   PRIVATE_KEY         → clave privada de tu wallet de TESTNET (no de mainnet)
 *   ETHERSCAN_API_KEY   → para verificar el contrato en Etherscan (opcional)
 *
 * ⚠️  NUNCA uses una wallet con fondos reales para deployar a testnet durante
 *     el aprendizaje. Generá una wallet nueva solo para tests.
 */

import {Script, console} from "forge-std/Script.sol";
import {PredictionPool} from "../src/PredictionPool.sol";

contract DeployPredictionPool is Script {
    function run() external returns (PredictionPool pool) {
        // vm.envUint / vm.envAddress: lee variables de entorno de forma segura.
        // Si la variable no existe, el script falla con un mensaje claro
        // en vez de usar un valor por defecto silencioso.
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying PredictionPool...");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        // vm.startBroadcast(): todo lo que esté entre start y stop se firma
        // con deployerPrivateKey y se manda a la red configurada en --rpc-url.
        // Lo que está fuera del broadcast es solo simulación local.
        vm.startBroadcast(deployerPrivateKey);

        pool = new PredictionPool();

        vm.stopBroadcast();

        console.log("PredictionPool deployed at:", address(pool));
        console.log("Owner:", pool.owner());

        // Tip: después del deploy, guardá esta dirección en tu .env
        // para interactuar con el contrato desde scripts o el frontend.
    }
}
