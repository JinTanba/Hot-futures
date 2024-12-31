// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "forge-std/Test.sol";
import "../src/Counter.sol";

contract EnvTestTest is Test {
   EnvTest public envTest;

   function setUp() public {
       envTest = new EnvTest();
   }

   function test_sepoliaAddress() public view {
       // Sepoliaアドレスの確認
       address sepolia = envTest.sepolia();
       console.log("Sepolia address:", sepolia);
       assertEq(sepolia, Addresses.BASE_SEPOLIA);
   }

   function test_number() public {
       // 初期値の確認
       assertEq(envTest.number(), 0);

       // increment()実行
       envTest.increment();
       assertEq(envTest.number(), 1);

       // setNumber()実行
       envTest.setNumber(100);
       assertEq(envTest.number(), 100);
   }
}