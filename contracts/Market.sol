// contracts/ERC20.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

// SafeMath.sub

contract Market is Ownable {
    //TODO: add events
    event Created(uint256 indexed marketID, uint256 _time);
    event Paused(uint256 indexed marketID, uint256 _time);
    event Resumed(uint256 indexed marketID, uint256 _time);
    event Closed(uint256 indexed marketID, uint256 _time);
    event Redemption(uint256 indexed marketID, uint256 indexed memberID, uint256 _time);

    enum Status {Running, Paused, Closed}

    struct MarketStruct {
        bool isExist;
        Status public status;
        uint256 public marketID;
        uint256 public baseCurrencyID;
        int256 public initialPrice;
        int256 public finalPrice;
        uint256 public created;
        uint256 public duration;
        uint256 public totalSupply;
        uint256 public totalRedemption;
        address public collateralToken;
        address public bearToken;
        address public bullToken;
    }

    mapping(uint256 => MarketStruct) public markets;
    mapping(address => uint256) public tokenToMarketList;
    mapping(uint256 => address) public baseCurrencyToChainlinkFeed;

    uint256 public currentMarketID = 0;
    address public manager;

    AggregatorV3Interface internal priceFeed;

    constructor() public {
        MarketStruct memory marketStruct;
        currentMarketID++;
    }

    /**
     * Returns the latest price
     */
    function getLatestPrice() public view returns (int) {
        (
            uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        return price;
    }

    /**
     * Returns historical price for a round id.
     * roundId is NOT incremental. Not all roundIds are valid.
     * You must know a valid roundId before consuming historical data.
     *
     * ROUNDID VALUES:
     *    InValid:      18446744073709562300
     *    Valid:        18446744073709562301
     *    
     * @dev A timestamp with zero value means the round is not complete and should not be used.
     */
    function getHistoricalPrice(uint80 roundId) public view returns (int256) {
        (
            uint80 id, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.getRoundData(roundId);
        require(timeStamp > 0, "Round not complete");
        return price;
    }

    function createMarket(address _ownerWallet) public onlyOwner {
      
    }

    function pauseMarket(uint256 _marketID) public onlyOwner {
      
    }

    function resumeMarket(uint256 _marketID) public onlyOwner {
      
    }

    function closeMarket(uint256 _marketID) public onlyOwner {
      
    }

    //TODO: change market duration


    function redeem(uint256 _marketID, address token, uint256 amount) public {
      
    }
}

        userStruct = MarketStruct({
            isExist: true,
            id: currUserID,
            referrerID: _referrerID,
            referrerIDInitial: _referrerIDInitial,
            referral: new address[](0)
        });

        users[msg.sender] = userStruct;
        userList[currUserID] = msg.sender;

market info read functions
    function viewUserStarExpired(address _user, uint256 _star)
        public
        view
        returns (uint256)
    {
        return users[_user].starExpired[_star];
    }


marketid++

Whitelist baseCurrency chainlink

    

    modifier atStage(Stage _stage) {
        // Contract has to be in given stage
        require(stage == _stage);
        _;
    }

    modifier onlyWhitelisted() {
        require(
            whitelist == Whitelist(0) || whitelist.isWhitelisted(msg.sender),
            "only whitelisted users may call this function"
        );
        _;
    }



    
    mapping(address => uint256) withdrawnFees;



buy
    mint tokens



    call balancer


contract factory



    function close() public onlyOwner {
        require(
            stage == Stage.Running || stage == Stage.Paused,
            "This Market has already been closed"
        );
        for (uint256 i = 0; i < atomicOutcomeSlotCount; i++) {
            uint256 positionId = generateAtomicPositionId(i);
            pmSystem.safeTransferFrom(
                address(this),
                owner(),
                positionId,
                pmSystem.balanceOf(address(this), positionId),
                ""
            );
        }
        stage = Stage.Closed;
        emit Closed();
    }