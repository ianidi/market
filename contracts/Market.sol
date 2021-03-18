// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

contract Market is Ownable {
    //TODO: add more info to events
    event Created(uint256 indexed marketID, uint256 _time);
    event Paused(uint256 indexed marketID, uint256 _time);
    event Resumed(uint256 indexed marketID, uint256 _time);
    event Closed(uint256 indexed marketID, uint256 _time);
    event Buy(uint256 indexed marketID, uint256 _time);
    event Redeem(
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
    mapping(address => uint256) public tokenToMarket;
    mapping(address => uint256) public winningTokenToMarket;
    mapping(uint256 => address) public baseCurrencyToChainlinkFeed;

    uint256 public currentMarketID = 0;
    address public manager;

    AggregatorV3Interface internal priceFeed;
    IERC20 public collateral;

    constructor() public {
        currentMarketID = uint256(1);
        baseCurrencyToChainlinkFeed[
            uint256(1)
        ] = 0x9326BFA02ADD2366b30bacB125260Af641031331; //Network: Kovan Aggregator: ETH/USD
    }

    /**
     * Returns the latest price
     */
    function getLatestPrice(AggregatorV3Interface feed)
        public
        view
        returns (int256)
    {
        (
            uint80 roundID,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = feed.latestRoundData();
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
    function getHistoricalPrice(AggregatorV3Interface feed, uint80 roundId)
        public
        view
        returns (int256)
    {
        (
            uint80 id,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = feed.getRoundData(roundId);
        require(timeStamp > 0, "Round not complete");
        return price;
    }

    function create(
        uint256 _baseCurrencyID,
        uint256 _duration,
        address _bearToken,
        address _bullToken
    ) public onlyOwner {
        require(
            baseCurrencyToChainlinkFeed[_baseCurrencyID] != address(0),
            "Invalid base currency"
        );
        require(
            _duration >= 600 seconds && _duration < 365 days,
            "Invalid duration"
        );
        require(
            tokenToMarket[_bearToken] == 0,
            "Bear token is already assigned to another market"
        );
        require(
            tokenToMarket[_bullToken] == 0,
            "Bull token is already assigned to another market"
        );

        //TODO: Contract factory for two ERC20 tokens
        //TODO: validate _bearToken is a valid ERC20 contract
        //TODO: validate _bullToken is a valid ERC20 contract
        //TODO: Contract factory for balancer contract

        //Get chainlink price feed by _baseCurrencyID
        address _chainlinkPriceFeed =
            baseCurrencyToChainlinkFeed[_baseCurrencyID];

        int256 _initialPrice =
            getLatestPrice(AggregatorV3Interface(_chainlinkPriceFeed));

        require(_initialPrice > 0, "Chainlink error");

        //TODO: accept _collateralToken as function parameter and validate is a valid ERC20 contract
        address _collateralToken = 0xdAC17F958D2ee523a2206206994597C13D831ec7; //USDT

        MarketStruct memory marketStruct =
            MarketStruct({
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

        //Assign bear and bull tokens to newly created market
        tokenToMarket[_bearToken] = currentMarketID;
        tokenToMarket[_bullToken] = currentMarketID;

        emit Created(currentMarketID, now);

        //Increment current market ID
        currentMarketID++;
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
            "Market has already been closed"
        );
        require(
            SafeMath.add(
                markets[_marketID].created,
                markets[_marketID].duration
            ) > now,
            "Market closing time hasn't yet arrived"
        );

        //Get chainlink price feed by _baseCurrencyID
        address _chainlinkPriceFeed =
            baseCurrencyToChainlinkFeed[_baseCurrencyID];

        //TODO: query chainlink by valid timestamp
        int256 _finalPrice =
            getLatestPrice(AggregatorV3Interface(_chainlinkPriceFeed));

        require(_initialPrice > 0, "Chainlink error");
        require(markets[_marketID].initialPrice != _finalPrice, "Price error");

        markets[_marketID].status = Status.Closed;
        markets[_marketID].finalPrice = _finalPrice;

        //TODO: push to winning tokens array => marketid

        emit Closed(_marketID, now);
    }

    // function transferToMe(
    //     address _owner,
    //     address _token,
    //     unit _amount
    // ) public {
    //     ERC20(_token).transferFrom(_owner, address(this), _amount);
    // }

    //Buy new token pair for collateral token
    function buy(
        uint256 _marketID // address token, // uint256 amount
    ) public {
        require(markets[_marketID].isExist, "Market doesn't exist");
        require(markets[_marketID].status == Status.Running, "Invalid status");

        //deposit collateral
        //mint tokens
        // uint256 totalSupply;
        //emit buy event
    }

    function redeem(
        uint256 _marketID,
        address token,
        uint256 amount
    ) public {
        //send collateral in accordance to markeetid collateral
        // uint256 totalRedemption;
        // pmSystem.safeTransferFrom(
        //     address(this),
        //     owner(),
        //     positionId,
        //     pmSystem.balanceOf(address(this), positionId),
        //     ""
        // );
        // require(
        //     collateralToken.transferFrom(
        //         msg.sender,
        //         address(this),
        //         uint256(fundingChange)
        //     ) &&
        //         collateralToken.approve(
        //             address(pmSystem),
        //             uint256(fundingChange)
        //         )
        // );
        // require(collateralToken.transfer(owner(), uint256(-fundingChange)));
    }

    //TODO: baseCurrencyToChainlinkFeed edit functions

    //TODO: market info read functions
    function viewMarketIsExist(uint256 _marketID) public view returns (bool) {
        return markets[_marketID].isExist;
    }
}
