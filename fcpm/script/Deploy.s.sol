// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "forge-std/Script.sol";
import "../src/PredictionTokenFramwork.sol";
import "../src/zkTLSOracle.sol";
contract DeployScript is Script {
   function run() public {
       vm.startBroadcast();
       Oracle oracle = new Oracle();
       RangeScalarMarketNoState ctf = new RangeScalarMarketNoState(address(oracle));
       oracle.setToken(address(ctf));
       console.log("----- oracle ------");
       console.log(address(oracle));
       console.log("---- token --------");
       console.log(address(ctf));
       string memory _permittedProviderHashInStr = "0x30dd72fae0c3e8b7395a2e966339c6ce399e4b2fadbd68f27eb120aa0b9ca28e";
       string memory countKey = "followers_count";
       string memory userIdKey = "screen_name";
       oracle.createProvider(_permittedProviderHashInStr, countKey, userIdKey);
       console.log("complite deploy!!!");
       vm.stopBroadcast();
   }
}

// forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast