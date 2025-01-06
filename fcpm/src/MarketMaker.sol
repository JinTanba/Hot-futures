// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/* 
 * If you’re using Foundry (forge), you can keep this import for debugging logs:
 *    import "forge-std/console.sol";
 * Otherwise, remove or comment out references to console.
 */
// import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RangeScalarMarketNoState
 * @notice Your original scalar market contract that creates Short/Long tokens
 *         (ERC1155) for each subrange.
 */
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

    /**
     * @notice Creates a new scalar market, only callable by `oracle`.
     */
    function createMarket(
        string memory targetAccountId,
        uint256 currentAccountFollowerCount,
        uint256 minRange,
        uint256 maxRange,
        uint256 step,
        bytes32 oracleProviderHash,
        uint256 duration
    )
        external
    {
        require(msg.sender == oracle, "Only oracle can create");
        require(minRange < maxRange, "minRange < maxRange");
        require(step > 0, "step > 0");
        require((maxRange - minRange) % step == 0, "Range must be divisible by step");

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
            deadline: block.timestamp + duration // Market closing time
        });
    }

    /**
     * @notice Splits collateral into outcome tokens (Short/Long) for each subrange.
     *         You must send ETH as collateral in msg.value.
     */
    function split(uint256 marketId) external payable {
        // console.log("-------   Token:split -------------");
        Market storage market = markets[marketId];
        require(!market.resolved, "Market resolved");
        require(block.timestamp < market.deadline, "Cannot split after deadline"); 
        require(msg.value > 0, "No collateral sent");

        uint256 numRanges = _getNumRanges(market);

        // console.log("numRanges", numRanges);

        uint256[] memory tokenIds = new uint256[](numRanges * 2);
        uint256[] memory amounts  = new uint256[](numRanges * 2);

        for (uint256 i = 0; i < numRanges; i++) {
            uint256 shortId = _encodeTokenId(marketId, i, true);
            uint256 longId  = _encodeTokenId(marketId, i, false);

            tokenIds[2 * i]     = shortId;
            tokenIds[2 * i + 1] = longId;

            // Each subrange pair gets the same share of collateral
            amounts[2 * i]     = msg.value; 
            amounts[2 * i + 1] = msg.value; 
        }

        // Mint the Short/Long tokens to the user
        _mintBatch(msg.sender, tokenIds, amounts, "");
    }

    /**
     * @notice Merge Short/Long tokens back into collateral (reverse of split).
     *         Burns the user's Short/Long tokens and returns the ETH collateral.
     */
    function merge(uint256 marketId, uint256 amount) external {
        Market storage market = markets[marketId];
        require(!market.resolved, "Cannot merge after resolution");
        // Optionally, if you want to forbid merges after deadline:
        // require(block.timestamp < market.deadline, "Cannot merge after deadline"); 

        (uint256[] memory tokenIds, uint256[] memory amounts) = _getTokenIdsAndAmounts(marketId, amount);

        // Burns the user's outcome tokens
        _burnBatch(msg.sender, tokenIds, amounts);

        // Refund the user in ETH
        payable(msg.sender).transfer(amount);
    }

    /**
     * @notice Resolves the market. Only the oracle can do this, after the outcome is known.
     */
    function resolveMarket(uint256 marketId, uint256 currentFolloweCount) external {
        // console.log("--------Token:resolveMarket--------");
        require(msg.sender == oracle, "Only oracle can resolve");
        Market storage market = markets[marketId];
        // require(market.deadline < block.timestamp, "market is not over");

        require(!market.resolved, "Already resolved");
        market.resolved = true;
        // finalValue is the *change* in follower count from the time of creation
        market.finalValue = currentFolloweCount - market.currentAccountFollowerCount;
        // console.log("Market final value:", market.finalValue);
    }

    /**
     * @notice Redeems winning outcome tokens for collateral, after the market is resolved.
     */
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

            // If the subrange matches the final outcome subrange, 
            // those tokens can be redeemed for a share of collateral
            if (found && i == subrangeIndex) {
                // Short payout
                if (shortBalance > 0) {
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
                }

                // Long payout
                if (longBalance > 0) {
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
                }
            } else {
                // Subrange is not the winning range, or user doesn't hold tokens
                burnTokenIds[2 * i]     = shortId;
                burnTokenIds[2 * i + 1] = longId;
                burnAmounts[2 * i]      = 0;
                burnAmounts[2 * i + 1]  = 0;
            }
        }

        // Burn the redeemed tokens
        _burnBatch(msg.sender, burnTokenIds, burnAmounts);

        // Send the user their winnings in ETH
        if (totalPayout > 0) {
            payable(msg.sender).transfer(totalPayout);
        }
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

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
            // The Short token pays out proportionally if x is in [subrangeMin, subrangeMax).
            // Payout = fraction of subrange that is "above x".
            // e.g. if x = subrangeMid, short gets half. 
            // This is the formula used in Gnosis' Scalar setup.
            uint256 numerator = (subrangeMax > x) ? (subrangeMax - x) : 0;
            uint256 denominator = market.step;
            return (amount * numerator) / denominator;
        } else {
            // The Long token pays the fraction of subrange "below x".
            // e.g. if x = subrangeMid, long gets half.
            uint256 numerator = (x > subrangeMin) ? (x - subrangeMin) : 0;
            uint256 denominator = market.step;
            return (amount * numerator) / denominator;
        }
    }

    function _getNumRanges(Market storage market) internal view returns (uint256) {
        return (market.maxRange - market.minRange) / market.step;
    }

    /**
     * @dev Token ID encoding:
     *      [upper 128 bits: marketId | next 127 bits: rangeIndex | last 1 bit: isShort (bool) ]
     */
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

    /**
     * @dev For merges, we need the array of all Short/Long token IDs for a given `amount`.
     */
    function _getTokenIdsAndAmounts(
        uint256 _marketId,
        uint256 baseAmount
    )
        internal
        view
        returns (uint256[] memory tokenIds, uint256[] memory amounts)
    {
        Market storage market = markets[_marketId];
        uint256 numRanges = _getNumRanges(market);

        tokenIds = new uint256[](numRanges * 2);
        amounts  = new uint256[](numRanges * 2);

        for (uint256 i = 0; i < numRanges; i++) {
            uint256 shortId = _encodeTokenId(_marketId, i, true);
            uint256 longId  = _encodeTokenId(_marketId, i, false);

            tokenIds[2 * i]     = shortId;
            tokenIds[2 * i + 1] = longId;

            // Each short/long pair is allocated the same baseAmount
            amounts[2 * i]     = baseAmount;
            amounts[2 * i + 1] = baseAmount;
        }

        return (tokenIds, amounts);
    }

    // View function to retrieve a Market struct
    function getMarket(uint256 marketId) external view returns(Market memory) {
        return markets[marketId];
    }
}

/**
 * @title RangeScalarFPMM
 * @notice Minimal example of an FPMM-style AMM that can trade the Short/Long outcome
 *         tokens minted by RangeScalarMarketNoState (ERC1155).
 *
 *         NOT FOR PRODUCTION. Math is simplified. Collateral handling is omitted.
 */
contract RangeScalarFPMM is ERC20, Ownable {
    /**
     * @dev Interface to the RangeScalarMarketNoState (ERC1155) 
     *      so we can call `safeTransferFrom`, etc.
     */
    RangeScalarMarketNoState public rangeMarket;

    /**
     * @dev The specific marketId in RangeScalarMarketNoState that this AMM supports.
     */
    uint256 public marketId;

    /**
     * @dev A list of outcome token IDs. For scalar markets, 
     *      each subrange has 2 IDs: shortId and longId.
     *      This array might look like: [short_0, long_0, short_1, long_1, ...].
     */
    uint256[] public outcomeTokenIds;

    /**
     * @dev Pool balance of each outcome token ID (how many tokens the AMM holds).
     */
    mapping(uint256 => uint256) public poolBalances;

    /**
     * @dev Number of different outcome tokens (should match outcomeTokenIds.length).
     */
    uint256 public numOutcomes;

    // -------------------------------------------------
    // Events
    // -------------------------------------------------

    event LiquidityAdded(address indexed provider, uint256 collateralAdded, uint256 lpTokensMinted);
    event LiquidityRemoved(address indexed provider, uint256 lpTokensBurned);
    event Bought(address indexed buyer, uint256 indexed outcomeTokenId, uint256 collateralIn, uint256 tokensOut);
    event Sold(address indexed seller, uint256 indexed outcomeTokenId, uint256 tokensIn, uint256 collateralOut);

    // -------------------------------------------------
    // Constructor
    // -------------------------------------------------

    /**
     * @param _rangeMarket  Address of the RangeScalarMarketNoState contract.
     * @param _marketId     MarketId for which this AMM will provide liquidity.
     * @param _name         Name of the LP token for this AMM.
     * @param _symbol       Symbol of the LP token for this AMM.
     */
    constructor(
        address _rangeMarket,
        uint256 _marketId,
        string memory _name,
        string memory _symbol
    )
        ERC20(_name, _symbol)
    {
        require(_rangeMarket != address(0), "Invalid market address");
        rangeMarket = RangeScalarMarketNoState(_rangeMarket);
        marketId = _marketId;
    }

    // -------------------------------------------------
    // Pool Initialization
    // -------------------------------------------------

    /**
     * @notice Initialize the pool with a set of outcome token IDs and amounts.
     *         Typically, you must have already `split()` in RangeScalarMarketNoState
     *         to obtain these outcome tokens, and approve this contract.
     *
     * @param _outcomeTokenIds  Array of token IDs (short_0, long_0, short_1, long_1, etc.)
     * @param _initialAmounts   How many of each outcome token the AMM will hold
     * @param _lpReceiver       Address to receive the newly minted LP shares
     */
    function initializePool(
        uint256[] calldata _outcomeTokenIds,
        uint256[] calldata _initialAmounts,
        address _lpReceiver
    )
        external
        onlyOwner
    {
        require(outcomeTokenIds.length == 0, "Pool already initialized");
        require(_outcomeTokenIds.length == _initialAmounts.length, "Lengths mismatch");
        require(_outcomeTokenIds.length > 0, "No outcome tokens");

        outcomeTokenIds = _outcomeTokenIds;
        numOutcomes = outcomeTokenIds.length;

        // Transfer outcome tokens from msg.sender to this AMM contract
        for (uint256 i = 0; i < numOutcomes; i++) {
            uint256 tokenId = outcomeTokenIds[i];
            uint256 amount = _initialAmounts[i];

            // user must have setApprovalForAll(this, true) on the RangeScalarMarketNoState
            rangeMarket.safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
            poolBalances[tokenId] = amount;
        }

        // Mint LP shares. For demo: initial supply = sum of initial outcome tokens
        uint256 sumAmounts = 0;
        for (uint256 i = 0; i < numOutcomes; i++) {
            sumAmounts += _initialAmounts[i];
        }
        _mint(_lpReceiver, sumAmounts);

        emit LiquidityAdded(_lpReceiver, sumAmounts, sumAmounts);
    }

    // -------------------------------------------------
    // Buying / Selling
    // -------------------------------------------------

    /**
     * @notice Buy a specific outcome from this AMM.
     *         (Naive math: not real constant-product.)
     *
     * @param outcomeTokenId   The token ID of the outcome to buy
     * @param collateralAmount The "collateral" user pays (conceptually)
     * @param minOutcomeTokens The minimum amount of outcome tokens desired
     */
    function buy(
        uint256 outcomeTokenId,
        uint256 collateralAmount,
        uint256 minOutcomeTokens
    )
        external
        returns (uint256 outcomeTokensBought)
    {
        require(poolBalances[outcomeTokenId] > 0, "Unknown tokenId");

        // "virtualCollateral" = sum of all outcome token balances in the pool
        uint256 virtualCollateral = 0;
        for (uint256 i = 0; i < numOutcomes; i++) {
            virtualCollateral += poolBalances[outcomeTokenIds[i]];
        }

        // Naive formula (for demonstration):
        // outcomeTokensBought = (collateralAmount * poolBalances[outcomeTokenId]) / virtualCollateral
        outcomeTokensBought =
            (collateralAmount * poolBalances[outcomeTokenId]) /
            virtualCollateral;

        require(outcomeTokensBought >= minOutcomeTokens, "Slippage: not enough tokens");

        // Decrease the pool balance
        poolBalances[outcomeTokenId] -= outcomeTokensBought;

        // Transfer outcome tokens from the AMM to buyer
        rangeMarket.safeTransferFrom(address(this), msg.sender, outcomeTokenId, outcomeTokensBought, "");

        emit Bought(msg.sender, outcomeTokenId, collateralAmount, outcomeTokensBought);
    }

    /**
     * @notice Sell outcome tokens back to the AMM.
     *         (Naive math: not real constant-product.)
     *
     * @param outcomeTokenId   The token ID of the outcome to sell
     * @param outcomeTokenAmt  Amount of outcome tokens you’re selling
     * @param minCollateralOut The minimum "collateral" you expect to get
     */
    function sell(
        uint256 outcomeTokenId,
        uint256 outcomeTokenAmt,
        uint256 minCollateralOut
    )
        external
        returns (uint256 collateralOut)
    {
        require(poolBalances[outcomeTokenId] > 0, "Unknown tokenId");

        // "virtualCollateral" = sum of all outcome balances
        uint256 virtualCollateral = 0;
        for (uint256 i = 0; i < numOutcomes; i++) {
            virtualCollateral += poolBalances[outcomeTokenIds[i]];
        }

        // Naive formula:
        // collateralOut = (outcomeTokenAmt * virtualCollateral) / poolBalances[outcomeTokenId]
        collateralOut =
            (outcomeTokenAmt * virtualCollateral) /
            poolBalances[outcomeTokenId];

        require(collateralOut >= minCollateralOut, "Slippage: not enough collateral out");

        // Transfer user’s outcome tokens to the AMM
        rangeMarket.safeTransferFrom(msg.sender, address(this), outcomeTokenId, outcomeTokenAmt, "");

        // Increase the pool's balance
        poolBalances[outcomeTokenId] += outcomeTokenAmt;

        emit Sold(msg.sender, outcomeTokenId, outcomeTokenAmt, collateralOut);
    }

    // -------------------------------------------------
    // Liquidity Management
    // -------------------------------------------------

    /**
     * @notice Add liquidity by depositing outcome tokens in the same ratio 
     *         as the existing pool. (Naive check in real code.)
     *
     * @param additionalAmounts The amounts of each outcome token to deposit
     */
    function addLiquidity(uint256[] calldata additionalAmounts) external {
        require(additionalAmounts.length == numOutcomes, "Mismatched length");

        // Transfer outcome tokens to the AMM
        for (uint256 i = 0; i < numOutcomes; i++) {
            uint256 tokenId = outcomeTokenIds[i];
            uint256 amount = additionalAmounts[i];

            rangeMarket.safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
        }

        // Update balances and compute total deposit
        uint256 sumAdditional = 0;
        for (uint256 i = 0; i < numOutcomes; i++) {
            poolBalances[outcomeTokenIds[i]] += additionalAmounts[i];
            sumAdditional += additionalAmounts[i];
        }

        // Mint LP tokens. For demonstration, we do 1:1 with sum.
        _mint(msg.sender, sumAdditional);

        emit LiquidityAdded(msg.sender, sumAdditional, sumAdditional);
    }

    /**
     * @notice Remove liquidity (burn LP) to withdraw a proportional share
     *         of all outcome tokens from the pool.
     *
     * @param lpTokenAmount The amount of LP tokens to burn
     */
    function removeLiquidity(uint256 lpTokenAmount) external {
        require(balanceOf(msg.sender) >= lpTokenAmount, "Insufficient LP");

        uint256 totalLP = totalSupply();

        // Burn the user's LP
        _burn(msg.sender, lpTokenAmount);

        // Return the proportional share of outcome tokens
        for (uint256 i = 0; i < numOutcomes; i++) {
            uint256 tokenId = outcomeTokenIds[i];

            uint256 userShare = (poolBalances[tokenId] * lpTokenAmount) / totalLP;

            if (userShare > 0) {
                poolBalances[tokenId] -= userShare;
                rangeMarket.safeTransferFrom(address(this), msg.sender, tokenId, userShare, "");
            }
        }

        emit LiquidityRemoved(msg.sender, lpTokenAmount);
    }

    // -------------------------------------------------
    // ERC1155 Receiver Hooks
    // -------------------------------------------------

    function onERC1155Received(
        address /* operator */,
        address /* from */,
        uint256 /* id */,
        uint256 /* value */,
        bytes calldata /* data */
    ) external pure returns (bytes4) {
        // Must return this magic value to accept single ERC1155 transfers
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address /* operator */,
        address /* from */,
        uint256[] calldata /* ids */,
        uint256[] calldata /* values */,
        bytes calldata /* data */
    ) external pure returns (bytes4) {
        // Must return this magic value to accept batch ERC1155 transfers
        return this.onERC1155BatchReceived.selector;
    }
}
