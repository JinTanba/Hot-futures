// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;
import "verifier-solidity-sdk/Reclaim.sol";
import "verifier-solidity-sdk/Addresses.sol";

contract EnvTest {
    uint256 public number;
    address public sepolia;

    constructor() {
        address _sepolia = Addresses.BASE_SEPOLIA;
        sepolia = _sepolia;
    }

    function setNumber(uint256 _number) public {
        number = _number;
    }

    function increment() public {
        number++;
    }

}
