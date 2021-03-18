// contracts/ERC20.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
    event Redemption(
        uint256 indexed marketID,
        uint256 indexed memberID,
        uint256 _time
    );

    enum Status {Running, Paused, Closed}

    struct MarketStruct {
        bool isExist;
        Status status;
        uint256 marketID;
        uint256 baseCurrencyID;
        int256 initialPrice;
        int256 finalPrice;
        uint256 created;
        uint256 duration;
        uint256 totalSupply;
        uint256 totalRedemption;
        address collateralToken;
        address bearToken;
        address bullToken;
    }

    mapping(uint256 => MarketStruct) public markets;
    mapping(address => uint256) public tokenToMarketList;
    mapping(uint256 => address) public baseCurrencyToChainlinkFeed;

    uint256 public currentMarketID = 0;
    address public manager;

    AggregatorV3Interface internal priceFeed;
    IERC20 public collateral;

    constructor() public {
        MarketStruct memory marketStruct;
        currentMarketID++;
    }

    // modifier onlyWhitelisted() {
    //   require(whitelist == Whitelist(0) || whitelist.isWhitelisted(msg.sender), "only whitelisted users may call this function");
    //   _;
    // }

    /**
     * Returns the latest price
     */
    function getLatestPrice() public view returns (int256) {
        (
            uint80 roundID,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
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
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = priceFeed.getRoundData(roundId);
        require(timeStamp > 0, "Round not complete");
        return price;
    }

    //TODO: Whitelist modifier baseCurrency chainlink
    function createMarket(
        uint256 _baseCurrencyID,
        uint256 _duration,
        address _bearToken,
        address _bullToken
    ) public onlyOwner {
        //TODO: contract factory (ERC20)

        //TODO: validate _duration
        //TODO: validate _bearToken
        //TODO: validate _bullToken

        int256 _initialPrice;
        address _chainlinkPriceFeed;

        //TODO: get chainlink price feed by _baseCurrencyID
        _chainlinkPriceFeed = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;

        //TODO: throw on chainlink error
        _initialPrice = getLatestPrice(
            AggregatorV3Interface(_chainlinkPriceFeed)
        );

        //TODO: accept _collateralToken as function parameter
        address _collateralToken = 0xdac17f958d2ee523a2206206994597c13d831ec7; //USDT

        marketStruct = MarketStruct({
            isExist: true,
            status: Status.Running,
            marketID: currentMarketID,
            baseCurrencyID: _baseCurrencyID,
            initialPrice: _initialPrice,
            finalPrice: 0,
            created: now,
            duration: _duration,
            totalSupply: 0,
            totalRedemption: 0,
            collateralToken: _collateralToken,
            bearToken: _bearToken,
            bullToken: _bullToken
        });

        markets[currentMarketID] = marketStruct;

        emit Created(currentMarketID, now);

        //Increment current market ID
        currentMarketID++;

        //TODO: call balancer
    }

    function pause(uint256 _marketID) public onlyOwner {
        require(markets[_marketID].isExist, "Market doesn't exist");
        require(markets[_marketID].status == Status.Running, "Invalid status");

        markets[_marketID].status = Status.Paused;

        emit Paused(_marketID, now);
    }

    function resume(uint256 _marketID) public onlyOwner {
        require(markets[_marketID].isExist, "Market doesn't exist");
        require(markets[_marketID].status == Status.Paused, "Invalid status");

        markets[_marketID].status = Status.Running;

        emit Resumed(_marketID, now);
    }

    function close(uint256 _marketID) public onlyOwner {
        require(markets[_marketID].isExist, "Market doesn't exist");
        require(
            markets[_marketID].status == Status.Running ||
                markets[_marketID].status == Status.Paused,
            "This market has already been closed"
        );

        markets[_marketID].status = Status.Closed;

        emit Closed(_marketID, now);
    }

    function transferToMe(
        address _owner,
        address _token,
        unit _amount
    ) public {
        ERC20(_token).transferFrom(_owner, address(this), _amount);
    }

    //Buy new token pair for collateral token
    function buy(
        uint256 _marketID,
        address token,
        uint256 amount
    ) public {
        //mint tokens
        //call balancer
    }

    function redeem(
        uint256 _marketID,
        address token,
        uint256 amount
    ) public {
        //call balancer

        pmSystem.safeTransferFrom(
            address(this),
            owner(),
            positionId,
            pmSystem.balanceOf(address(this), positionId),
            ""
        );

        require(
            collateralToken.transferFrom(
                msg.sender,
                address(this),
                uint256(fundingChange)
            ) &&
                collateralToken.approve(
                    address(pmSystem),
                    uint256(fundingChange)
                )
        );

        require(collateralToken.transfer(owner(), uint256(-fundingChange)));
    }

    //TODO: market info read functions
    function viewMarketIsExist(uint256 _marketID) public view returns (bool) {
        return markets[_marketID].isExist;
    }
}
