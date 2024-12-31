// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract PredictionTokenFramework is ERC1155 {

    event MarketCreated (
        uint256 indexed marketId,
        address indexed creator,
        string indexed xUserId,
        uint256 followerGrowth,
        uint256 deadline
    );

    event SplitPosition (
        uint256 indexed marketId,
        address indexed holder,
        uint256 amounts
    );

    event MargePosition (
        uint256 indexed marketId,
        address indexed holder,
        uint256 amounts
    );

    event OracleReport (
        uint256 indexed marketId,
        Result result
    );

    struct Market {
        string xUserId;
        uint256 followerGrowth;
        uint256 deadline;
        Result result;
    }

    enum Result {
        Yet,
        Yes,
        No
    }

    address public oracle;
    uint256 public marketIdCounter;
    mapping(uint256 => Market) public markets;
    mapping(uint256 => uint256) public totalSupply;

    constructor(address _oracle) ERC1155("") {
        oracle = _oracle;
    }

    function createMarket(string memory xUserId, uint256 followerGrowth, uint256 marketDuration) external {
        marketIdCounter+=1;
        uint256 deadline = block.timestamp + marketDuration;
        markets[marketIdCounter] = Market(xUserId, followerGrowth, deadline, Result.Yet);

        emit MarketCreated(
            marketIdCounter, 
            msg.sender, 
            xUserId, 
            followerGrowth, 
            deadline
        );

    }

    function oracleReport(uint256 marketId ,Result result) external {
        require(result != Result.Yet, "invalid result");
        Market storage market = markets[marketId];
        require(market.deadline >= block.timestamp, "marketAlreadyEnd");
        require(market.result == Result.Yet, "already fullfilled");
        require(msg.sender == oracle, "only oracle contract");
        market.result = result;
        emit OracleReport(marketId, result);
    }

    function splitPosition(uint256 marketId) external payable {
        require(marketId <= marketIdCounter, "There is no market");
        Market memory market = markets[marketId];
        require(market.deadline >= block.timestamp, "marketAlreadyEnd");

        uint256[] memory positionIds = _getPositionIds(market);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = msg.value;

        _mintBatch(msg.sender, positionIds, amounts, "");
        
        emit SplitPosition(marketId, msg.sender, msg.value);
    }

    function mergePosition(uint256 marketId, uint256 amount) external {
        require(marketId <= marketIdCounter, "There is no market");
        Market memory market = markets[marketId];
        require(market.deadline >= block.timestamp, "marketAlreadyEnd");

        uint256[] memory positionIds = _getPositionIds(market);
        uint256[] memory amounts = new uint256[](2);

        amounts[0] = amount;
        amounts[1] = amount;

        _burnBatch(msg.sender, positionIds, amounts);
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "fail to send back");
    }

    function redeemPosition(uint256 marketId) external {
        require(marketId <= marketIdCounter, "There is no market");
        Market memory market = markets[marketId];
        require(market.result != Result.Yet, "marketAlreadyEnd");
        uint256[] memory positionIds = _getPositionIds(market);
        uint256 winnerPositionId = market.result == Result.Yes ? positionIds[0] : positionIds[1];
        //続き
    }

    function _getPositionIds(Market memory market) public pure returns (uint256[] memory positionIds) {
        positionIds = new uint256[](2);
        uint256 yesPositionId = uint256(
            keccak256(
                abi.encodePacked(market.xUserId, market.followerGrowth, market.deadline, ".yes")
            )
        );
        uint256 noPositionId = uint256(
            keccak256(
                abi.encodePacked(market.xUserId, market.followerGrowth, market.deadline, ".no")
            )
        );
        positionIds[0] = yesPositionId;
        positionIds[1] = noPositionId;
    }

}