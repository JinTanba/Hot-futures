// SPD-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RangeScalarMarketNoState is ERC1155, Ownable {

    struct Market {
        string targetAccountId;
        uint256 currentAccountFollowerCount;
        bool resolved;
        uint256 finalValue;
        uint256 minRange;  
        uint256 maxRange;    
        uint256 step;
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
        uint256 step
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
            step: step
        });
    }

    function split(uint256 marketId) external payable {
        Market storage market = markets[marketId];
        require(!market.resolved, "Market resolved");
        require(msg.value > 0, "No collateral sent");

        uint256 numRanges = _getNumRanges(market);

        for (uint256 i = 0; i < numRanges; i++) {
            uint256 shortId = _encodeTokenId(marketId, i, true);
            uint256 longId  = _encodeTokenId(marketId, i, false);

            _mint(msg.sender, shortId, msg.value, "");
            _mint(msg.sender, longId,  msg.value, "");
        }
    }

    function merge(uint256 marketId, uint256 amount) external {
        Market storage market = markets[marketId];
        require(!market.resolved, "Cannot merge after resolution");

        uint256 numRanges = _getNumRanges(market);

        for (uint256 i = 0; i < numRanges; i++) {
            uint256 shortId = _encodeTokenId(marketId, i, true);
            uint256 longId  = _encodeTokenId(marketId, i, false);

            _burn(msg.sender, shortId, amount);
            _burn(msg.sender, longId,  amount);
        }

        payable(msg.sender).transfer(amount);
    }

    function resolveMarket(uint256 marketId, uint256 currentFolloweCount) external {
        require(msg.sender == oracle, "Only oracle can resolve");
        Market storage market = markets[marketId];
        require(!market.resolved, "Already resolved");

        market.resolved = true;
        market.finalValue = currentFolloweCount - market.currentAccountFollowerCount;
    }

    function redeemPositions(
        uint256 marketId,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    )
        external
    {
        require(tokenIds.length == amounts.length, "Length mismatch");
        Market storage market = markets[marketId];
        require(market.resolved, "Market not resolved yet");

        uint256 x = market.finalValue;
        (bool found, uint256 xRangeIndex) = _findSubrangeForValue(market, x);

        uint256 totalPayout;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 amount  = amounts[i];

            (uint256 decodedMarketId, uint256 rangeIndex, bool isShort)
                = _decodeTokenId(tokenId);

            require(decodedMarketId == marketId, "Token not in this market");

            _burn(msg.sender, tokenId, amount);

            if (!found || (rangeIndex != xRangeIndex)) {
                continue;
            }

            uint256 payout = _calculatePayoutWithinIncludedRange(
                market, 
                xRangeIndex,
                x,
                isShort,
                amount
            );
            totalPayout += payout;
        }

        payable(msg.sender).transfer(totalPayout);
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
            uint256 numerator   = (subrangeMax > x) ? (subrangeMax - x) : 0;
            uint256 denominator = market.step;
            return (amount * numerator) / denominator;
        } else {
            uint256 numerator   = (x > subrangeMin) ? (x - subrangeMin) : 0;
            uint256 denominator = market.step;
            return (amount * numerator) / denominator;
        }
    }

    function _getNumRanges(Market storage market) internal view returns (uint256) {
        return (market.maxRange - market.minRange) / market.step;
    }

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
}
