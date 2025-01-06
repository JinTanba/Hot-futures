    //    address predictionAddress = vm.envAddress("PREDICTION_TOKEN");
    //    RangeScalarMarketNoState token = RangeScalarMarketNoState(predictionAddress);
    //    address oracle = token.oracle();
    //    console.log("oracle", oracle);

    // SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "verifier-solidity-sdk/Reclaim.sol";
import "forge-std/Script.sol";
import "../src/PredictionTokenFramwork.sol";
import "../src/zkTLSOracle.sol";
contract Play is Script {
   function run() public {

       vm.startBroadcast();
       address predictionAddress = vm.envAddress("PREDICTION_TOKEN");
       address oracleAddress = vm.envAddress("ORACLE_ADDRESS");

    
   }
}

// forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast