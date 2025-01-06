// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "forge-std/console.sol";

contract RangeScalarMarketNoState is ERC1155 {

    struct Market {
        string targetAccountId;
        uint256 currentAccountFollowerCount;
        bool resolved;
        uint256 finalValue;
        uint256 minRange;  
        uint256 maxRange;    
        uint256 step;
        bytes32 oracleProviderHash;
        uint256 deadline;
    }

    address public oracle;
    uint256 public marketIdCounter;

    mapping(uint256 => Market) public markets;

    constructor(address _oracle) ERC1155("") {
        oracle = _oracle;
    }

    function createMarket(
        string memory targetAccountId,
        uint256 currentAccountFollowerCount,
        uint256 minRange,
        uint256 maxRange,
        uint256 step,
        bytes32 oracleProviderHash,//こいつきもしね
        uint256 duration
    )
        external
    {
        require(msg.sender == oracle, "use oracle`s createMarketFunction");
        require(minRange < maxRange, "minRange < maxRange");
        require(step > 0, "step > 0");
        require((maxRange - minRange) % step == 0, "range must be divisible by step");

        marketIdCounter++;
        markets[marketIdCounter] = Market({
            targetAccountId: targetAccountId,
            currentAccountFollowerCount: currentAccountFollowerCount,
            resolved: false,
            finalValue: 0,
            minRange: minRange,
            maxRange: maxRange,
            step: step,
            oracleProviderHash: oracleProviderHash,
            deadline: block.timestamp + duration
        });
    }

    function split(uint256 marketId) external payable {
        require(msg.value > 0, "No collateral sent");

        Market storage market = markets[marketId];
        uint256 numRanges = _getNumRanges(market);

        uint256 outcomeCount = 2 * numRanges;

        uint256[] memory tokenIds = new uint256[](outcomeCount);
        uint256[] memory amounts  = new uint256[](outcomeCount);

        for (uint256 i = 0; i < numRanges; i++) {
            uint256 shortId = _encodeTokenId(marketId, i, true);
            uint256 longId  = _encodeTokenId(marketId, i, false);

            tokenIds[2*i] = shortId;
            amounts[2*i]  = msg.value;
            tokenIds[2*i+1] = longId;
            amounts[2*i+1]  = msg.value;
        }

        _mintBatch(msg.sender, tokenIds, amounts, "");
    }


    function merge(uint256 marketId, uint256 amount) external {
        Market storage market = markets[marketId];
        require(!market.resolved, "Cannot merge after resolution");
        // require(block.timestamp < market.deadline, "Cannot merge after deadline"); //TODO: foundryのanvilは時間止まってる
        (uint256[] memory tokenIds, uint256[] memory amounts) = _getTokenIdsAndAmounts(marketId, amount);
        _burnBatch(msg.sender, tokenIds, amounts);
        payable(msg.sender).transfer(amount);
    }


    function resolveMarket(uint256 marketId, uint256 currentFolloweCount) external {
        console.log("--------Token:resolveMarket--------");
        require(msg.sender == oracle, "Only oracle can resolve");
        Market storage market = markets[marketId];
        // require(market.deadline < block.timestamp, "market is not over");//TODO: foundryのanvilは時間止まってる
        require(!market.resolved, "Already resolved");
        market.resolved = true;
        market.finalValue = currentFolloweCount - market.currentAccountFollowerCount;
        console.log('so less than 0????');
    }

    function redeemPositions(uint256 marketId) external {
        Market storage market = markets[marketId];
        require(market.resolved, "Market not resolved yet");

        uint256 x = market.finalValue;
        uint256 totalPayout = 0;

        uint256 numRanges = _getNumRanges(market);
        (bool found, uint256 subrangeIndex) = _findSubrangeForValue(market, x);

        uint256[] memory burnTokenIds = new uint256[](2 * numRanges);
        uint256[] memory burnAmounts  = new uint256[](2 * numRanges);

        for (uint256 i = 0; i < numRanges; i++) {
            uint256 shortId = _encodeTokenId(marketId, i, true);
            uint256 longId  = _encodeTokenId(marketId, i, false);

            uint256 shortBalance = balanceOf(msg.sender, shortId);
            uint256 longBalance  = balanceOf(msg.sender, longId);

            if (shortBalance > 0 && found && i == subrangeIndex) {
                uint256 shortPayout = _calculatePayoutWithinIncludedRange(
                    market,
                    i,
                    x,
                    true,
                    shortBalance
                );
                totalPayout += shortPayout;
                burnTokenIds[2 * i] = shortId;
                burnAmounts[2 * i]  = shortBalance;
            } else {
                burnTokenIds[2 * i] = shortId;
                burnAmounts[2 * i]  = 0;
            }

            if (longBalance > 0 && found && i == subrangeIndex) {
                uint256 longPayout = _calculatePayoutWithinIncludedRange(
                    market,
                    i,
                    x,
                    false,
                    longBalance
                );

                totalPayout += longPayout;
                burnTokenIds[2 * i + 1] = longId;
                burnAmounts[2 * i + 1]  = longBalance;
            } else {
                burnTokenIds[2 * i + 1] = longId;
                burnAmounts[2 * i + 1]  = 0;
            }
        }

        _burnBatch(msg.sender, burnTokenIds, burnAmounts);

        if (totalPayout > 0) {
            payable(msg.sender).transfer(totalPayout);
        }
    }


    function _findSubrangeForValue(Market storage market, uint256 x)
        internal
        view
        returns (bool found, uint256 index)
    {
        uint256 numRanges = _getNumRanges(market);

        for (uint256 i = 0; i < numRanges; i++) {
            uint256 subrangeMin = market.minRange + i * market.step;
            uint256 subrangeMax = subrangeMin + market.step;

            if (x >= subrangeMin && x < subrangeMax) {
                return (true, i);
            }
        }
        return (false, 0);
    }


    function _calculatePayoutWithinIncludedRange(
        Market storage market,
        uint256 rangeIndex,
        uint256 x,
        bool isShort,
        uint256 amount
    )
        internal
        view
        returns (uint256)
    {
        uint256 subrangeMin = market.minRange + rangeIndex * market.step;
        uint256 subrangeMax = subrangeMin + market.step;

        if (isShort) {
            uint256 numerator = (subrangeMax > x) ? (subrangeMax - x) : 0;
            uint256 denominator = market.step;
            return (amount * numerator) / denominator;
        } else {
            uint256 numerator = (x > subrangeMin) ? (x - subrangeMin) : 0;
            uint256 denominator = market.step;
            return (amount * numerator) / denominator;
        }
    }

    function _getNumRanges(Market storage market) internal view returns (uint256) {
        return (market.maxRange - market.minRange) / market.step;
    }

    //[...128][]
    function _encodeTokenId(
        uint256 _marketId,
        uint256 _rangeIndex,
        bool _isShort
    )
        internal
        pure
        returns (uint256)
    {
        return
            (_marketId << 128)
            | (_rangeIndex << 1)
            | (_isShort ? 1 : 0);
    }

    function _decodeTokenId(uint256 tokenId)
        internal
        pure
        returns (uint256 marketId, uint256 rangeIndex, bool isShort)
    {
        marketId = tokenId >> 128;

        uint256 lower128 = tokenId & ((uint256(1) << 128) - 1);
        isShort = (lower128 & 1) == 1;
        rangeIndex = (lower128 >> 1);
    }

    function _getTokenIdsAndAmounts(uint256 marketId,uint256 baseAmount) internal view returns (uint256[] memory tokenIds, uint256[] memory amounts) {
        Market storage market = markets[marketId];
        uint256 numRanges = _getNumRanges(market);

        tokenIds = new uint256[](numRanges * 2);
        amounts  = new uint256[](numRanges * 2);

        for (uint256 i = 0; i < numRanges; i++) {
            uint256 shortId = _encodeTokenId(marketId, i, true);
            uint256 longId  = _encodeTokenId(marketId, i, false);

            tokenIds[2 * i]     = shortId;
            tokenIds[2 * i + 1] = longId;

            amounts[2 * i]     = baseAmount;
            amounts[2 * i + 1] = baseAmount;
        }

        return (tokenIds, amounts);
    }

    function getMarket(uint256 marketId) external view returns(Market memory) {
        return markets[marketId];
    }
}
