// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;
import "verifier-solidity-sdk/Reclaim.sol";
import "verifier-solidity-sdk/Addresses.sol";
import "./PredictionTokenFramwork.sol";

contract Oracle {
    address immutable predictionToken;
    address immutable reclaimAddress;
    bytes32 permittedProviderHashInStr;

    constructor(address _predictionToken, string memory _permittedProviderHashInStr) {
        predictionToken = _predictionToken;
        reclaimAddress = Addresses.BASE_SEPOLIA;
        permittedProviderHashInStr = keccak256(bytes(_permittedProviderHashInStr));
    }

    function createMarketWithZKP(uint256 minRange, uint256 maxRange, uint256 step, Reclaim.Proof memory proof) external {
        Reclaim(Addresses.BASE_SEPOLIA).verifyProof(proof); //zkp
        require(permittedProviderHashInStr == keccak256(bytes(Utils.getFromExtractedParams(proof.claimInfo.context, "providerHash"))), "wrong procider is used");
        uint256 targetAccountFollowerOrLikeCount = Utils.stringToUint(Utils.getFromExtractedParams(proof.claimInfo.context, "screen_name"));
        string memory targetAccountId  = Utils.getFromExtractedParams(proof.claimInfo.context, "followers_count");
        RangeScalarMarketNoState(predictionToken).createMarket(
            targetAccountId,
            targetAccountFollowerOrLikeCount,
            minRange,
            maxRange,
            step
        );
    }

    function resolveMarket(uint256 marketId,Reclaim.Proof memory proof) external {
        Reclaim(Addresses.BASE_SEPOLIA).verifyProof(proof); //zkp
        require(permittedProviderHashInStr == keccak256(bytes(Utils.getFromExtractedParams(proof.claimInfo.context, "providerHash"))), "wrong procider is used");
        uint256 targetAccountFollowerOrLikeCount = Utils.stringToUint(Utils.getFromExtractedParams(proof.claimInfo.context, "screen_name"));
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
