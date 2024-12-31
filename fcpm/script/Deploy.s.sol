// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "forge-std/Script.sol";
import "../src/Counter.sol";

contract DeployScript is Script {
   function run() public {
       vm.startBroadcast();
       EnvTest envTest = new EnvTest();
       console.log("deployed address: ", address(envTest));
       vm.stopBroadcast();
   }
}