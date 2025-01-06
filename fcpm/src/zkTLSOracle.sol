// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;
import "verifier-solidity-sdk/Reclaim.sol";
import "verifier-solidity-sdk/Addresses.sol";
import "./PredictionTokenFramwork.sol";
import "forge-std/console.sol";

contract Oracle {
    address public predictionToken;
    address immutable reclaimAddress;
    address immutable owner;

    struct Provider {
        string countKey;
        string userIdKey;
    }

    mapping(bytes32 => Provider) public providers;

    constructor() {
        reclaimAddress = Addresses.BASE_SEPOLIA;
        owner = msg.sender;
    }

    function setToken(address _predictionToken) external {
        require(msg.sender == owner, "only owner");
        predictionToken = _predictionToken;
    }

    function createProvider(string calldata _permittedProviderHashInStr, string calldata countKey, string calldata userIdKey) external {
        require(msg.sender == owner, "only owner");
        Provider storage provider = providers[keccak256(bytes(_permittedProviderHashInStr))];
        provider.countKey = countKey;
        provider.userIdKey = userIdKey;
    }

    function createMarketWithZKP(uint256 minRange, uint256 maxRange, uint256 step,uint256 duration, Reclaim.Proof memory proof) external {
        Reclaim(reclaimAddress).verifyProof(proof); //zkp

        bytes32 oracleProviderHash = keccak256(bytes(Utils.extractValue(proof.claimInfo.context, "providerHash")));
        Provider memory usedProvider = providers[oracleProviderHash];
        require(keccak256(bytes(usedProvider.countKey)) != keccak256(bytes("")), "there is no provider");

        uint256 targetAccountFollowerOrLikeCount = Utils.stringToUint(Utils.getFromExtractedParams(proof.claimInfo.context, usedProvider.countKey));
        string memory targetAccountId  = Utils.getFromExtractedParams(proof.claimInfo.context, usedProvider.userIdKey);
        
        RangeScalarMarketNoState(predictionToken).createMarket(
            targetAccountId,
            targetAccountFollowerOrLikeCount,
            minRange,
            maxRange,
            step,
            oracleProviderHash,
            duration
        );
        console.log("---- createMarket ----");
        console.log(targetAccountId);
        console.log(targetAccountFollowerOrLikeCount);
    }

    function resolveMarket(uint256 marketId, Reclaim.Proof memory proof) external {
        console.log('----- Oracle:resolveMarket ---------');
        Reclaim(reclaimAddress).verifyProof(proof); //zkp
        console.log("succees to verify");
        RangeScalarMarketNoState.Market memory market = RangeScalarMarketNoState(predictionToken).getMarket(marketId);
        console.log("may be there!");
        bytes32 oracleProviderHash = keccak256(bytes(Utils.extractValue(proof.claimInfo.context, "providerHash")));
        console.log("NO?????????? WHY???????");
        // require(keccak256(bytes(market.targetAccountId)) == keccak256.) should check userID;
        require(market.oracleProviderHash == oracleProviderHash, "wrong provider is used");
        console.log("not wrong provider is used");
        Provider memory usedProvider = providers[market.oracleProviderHash];
        console.log('usedProvider');
        require(keccak256(bytes(usedProvider.countKey)) != keccak256(bytes("")), "there is no provider");
        console.log('not there is no provider');
        uint256 targetAccountFollowerOrLikeCount = Utils.stringToUint(Utils.getFromExtractedParams(proof.claimInfo.context, usedProvider.countKey));
        console.log("targetAccountFollowerOrLikeCount", targetAccountFollowerOrLikeCount);
        RangeScalarMarketNoState(predictionToken).resolveMarket(marketId, targetAccountFollowerOrLikeCount);

    }

}

library Utils {
    function extractValue(string memory json, string memory key) public pure returns (string memory) {
        string memory quotedKey = string(abi.encodePacked('"', key, '":'));
        bytes memory jsonBytes = bytes(json);
        bytes memory keyBytes = bytes(quotedKey);

        uint256 i = 0;
        while (i < jsonBytes.length - keyBytes.length) {
            bool found = true;
            for (uint256 j = 0; j < keyBytes.length; j++) {
                if (jsonBytes[i + j] != keyBytes[j]) {
                    found = false;
                    break;
                }
            }

            if (found) {
                uint256 valueStart = i + keyBytes.length;
                while (valueStart < jsonBytes.length && jsonBytes[valueStart] == " ") {
                    valueStart++;
                }

                uint256 valueEnd = valueStart;
                bool isString = jsonBytes[valueStart] == '"';
                bool isObject = jsonBytes[valueStart] == "{";

                if (isString) {
                    valueStart++;
                    valueEnd = valueStart;
                    while (valueEnd < jsonBytes.length) {
                        if (jsonBytes[valueEnd] == '"' && jsonBytes[valueEnd - 1] != "\\") {
                            break;
                        }
                        valueEnd++;
                    }
                } else if (isObject) {
                    uint256 openBraces = 1;
                    valueEnd = valueStart + 1;
                    while (valueEnd < jsonBytes.length && openBraces > 0) {
                        if (jsonBytes[valueEnd] == "{") {
                            openBraces++;
                        } else if (jsonBytes[valueEnd] == "}") {
                            openBraces--;
                        }
                        if (openBraces > 0) {
                            valueEnd++;
                        }
                    }
                    valueEnd++;
                } else {
                    while (valueEnd < jsonBytes.length) {
                        if (jsonBytes[valueEnd] == "," || jsonBytes[valueEnd] == "}") {
                            break;
                        }
                        valueEnd++;
                    }
                }

                bytes memory value = new bytes(valueEnd - valueStart);
                for (uint256 j = 0; j < valueEnd - valueStart; j++) {
                    value[j] = jsonBytes[valueStart + j];
                }

                return string(value);
            }
            i++;
        }

        return "";
    }

    function getFromExtractedParams(string memory json, string memory paramKey) public pure returns (string memory) {
        string memory extractedParams = extractValue(json, "extractedParameters");
        if (bytes(extractedParams).length == 0) {
            return "";
        }
        return extractValue(extractedParams, paramKey);
    }

    function stringToAddress(string memory _address) public pure returns (address) {
        bytes memory tmp = bytes(_address);
        require(tmp.length == 42 && tmp[0] == "0" && tmp[1] == "x", "Invalid address format");

        bytes20 result;
        uint160 value = 0;

        for (uint256 i = 2; i < 42; i++) {
            bytes1 char = tmp[i];
            uint8 digit;

            if (uint8(char) >= 48 && uint8(char) <= 57) {
                digit = uint8(char) - 48;
            } else if (uint8(char) >= 65 && uint8(char) <= 70) {
                digit = uint8(char) - 55;
            } else if (uint8(char) >= 97 && uint8(char) <= 102) {
                digit = uint8(char) - 87;
            } else {
                revert("Invalid character in address");
            }

            value = value * 16 + digit;
        }

        result = bytes20(value);
        return address(result);
    }

    function stringToUint(string memory _str) public pure returns (uint256) {
        bytes memory b = bytes(_str);
        uint256 result = 0;

        for (uint256 i = 0; i < b.length; i++) {
            uint8 char = uint8(b[i]);
            require(char >= 48 && char <= 57, "Invalid character");
            result = result * 10 + (char - 48);
        }

        return result;
    }
}
