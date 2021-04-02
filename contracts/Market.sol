// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "./balancer/BConst.sol";
import "./balancer/PoolManager.sol";
import "./ConditionalToken.sol";

contract Market is Ownable {
    //TODO: add more info to events
    event Created(uint indexed marketID, uint _time);
    event Paused(uint indexed marketID, uint _time);
    event Resumed(uint indexed marketID, uint _time);
    event Closed(uint indexed marketID, uint _time);
    event Buy(uint indexed marketID, uint _time);
    event Redeem(uint indexed marketID, uint _time);
    event NewBearToken(address indexed contractAddress, uint _time);
    event NewBullToken(address indexed contractAddress, uint _time);

    enum Status {Running, Paused, Closed}

    struct MarketStruct {
        bool exist;
        Status status;
        uint marketID;
        uint baseCurrencyID;
        uint80 initialRoundID;
        int256 initialPrice;
        int256 finalPrice;
        uint created;
        uint duration;
        uint totalDeposit;
        uint totalRedemption;
        uint collateralDecimals;
        address collateralToken;
        address bearToken;
        address bullToken;
        address pool;
    }

    mapping(uint => MarketStruct) public markets;
    mapping(uint => address) public baseCurrencyToChainlinkFeed;////////////////////////////////////////////////////////////////
    mapping(address => bool) public collateralList;

    AggregatorV3Interface internal priceFeed;

    address public poolManager;

    uint public currentMarketID = 1;
    uint public constant CONDITIONAL_TOKEN_WEIGHT = SafeMath.mul(10**18, uint(10));
    uint public constant COLLATERAL_TOKEN_WEIGHT  = SafeMath.mul(CONDITIONAL_TOKEN_WEIGHT, uint(2));

    constructor(address _poolManager) public {
        poolManager = _poolManager;
    }

    /**
     * Returns the latest price
     */
    function getLatestPrice(AggregatorV3Interface feed)
        public
        view
        returns (uint80, int256)
    {
        (
            uint80 roundID,
            int256 price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        return (roundID, price);
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
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = feed.getRoundData(roundId);
        require(timeStamp > 0, "Round not complete");
        return price;
    }

    function cloneBearToken() internal onlyOwner returns (ConditionalToken) {
        ConditionalToken bearToken = new ConditionalToken("Bear", "Bear");
        emit NewBearToken(address(bearToken), now);
        return bearToken;
    }

    function cloneBullToken() internal onlyOwner returns (ConditionalToken) {
        ConditionalToken bullToken = new ConditionalToken("Bull", "Bull");
        emit NewBullToken(address(bullToken), now);
        return bullToken;
    }

    function calcSwapFee(uint8 _decimals) public returns (uint) {
        return SafeMath.mul(uint(3), SafeMath.div((10 ** _decimals), uint(1000))); // 0.3%
    }

    function create(uint _baseCurrencyID, uint _duration, address _collateralToken, uint _collateralAmount)
        public
        onlyOwner
    {
        require(
            baseCurrencyToChainlinkFeed[_baseCurrencyID] != address(0),
            "Invalid base currency"
        );
        require(
            collateralList[_collateralToken] != false,
            "Invalid collateral"
        );
        require(
            _duration >= 600 seconds && _duration < 365 days,
            "Invalid duration"
        );

        uint8 _collateralDecimals = IERC20(_collateralToken).decimals();

        //Create two ERC20 tokens
        //TODO: title, decimals
        ConditionalToken _bearToken = cloneBearToken();
        ConditionalToken _bullToken = cloneBullToken();

        //Get chainlink price feed by _baseCurrencyID
        address _chainlinkPriceFeed =
            baseCurrencyToChainlinkFeed[_baseCurrencyID];

        (
            uint80 roundID,
            int256 price,
        ) = getLatestPrice(AggregatorV3Interface(_chainlinkPriceFeed));

        uint80 _initialRoundID = roundID;
        int256 _initialPrice = price;

        require(_initialPrice > 0, "Chainlink error");

        //Calculate conditional tokens amount
        uint _conditionalAmount = SafeMath.div(_collateralAmount, uint(2));

        //Create balancer pool
        BPool _pool = poolManager.createPool();

        //Mint both tokens
        _bearToken._mint(address(this), _conditionalAmount);
        _bullToken._mint(address(this), _conditionalAmount);

        //Deposit collateral token
        _collateralToken.transferFrom(msg.sender, address(this), _collateralAmount);

        //Approve tokens for binding by a pool
        poolManager.approveToken(_collateralToken, address(_pool), _collateralAmount);
        poolManager.approveToken(address(_bearToken), address(_pool), _conditionalAmount);
        poolManager.approveToken(address(_bullToken), address(_pool), _conditionalAmount);

        //Bind tokens to the pool
        poolManager.bindToken(address(_pool), _collateralToken, _collateralAmount, COLLATERAL_TOKEN_WEIGHT);
        poolManager.bindToken(address(_pool), address(_bearToken), _conditionalAmount, CONDITIONAL_TOKEN_WEIGHT);
        poolManager.bindToken(address(_pool), address(_bullToken), _conditionalAmount, CONDITIONAL_TOKEN_WEIGHT);

        //Calculate swap fee
        uint _swapFee = calcSwapFee(_collateralDecimals);

        //Set swap fee
        poolManager.setFee(address(_pool), _swapFee);

        //Release the pool and allow public swaps
        poolManager.setPublic(address(_pool), true);

        MarketStruct memory marketStruct =
            MarketStruct({
                exist: true,
                status: Status.Running,
                marketID: currentMarketID,
                baseCurrencyID: _baseCurrencyID,
                initialRoundID: _initialRoundID,
                initialPrice: _initialPrice,
                finalPrice: 0,
                created: now,
                duration: _duration,
                totalDeposit: 0,
                totalRedemption: 0,
                collateralToken: _collateralToken,
                bearToken: address(_bearToken),
                bullToken: address(_bullToken),
                pool: address(_pool)
            });

        markets[currentMarketID] = marketStruct;

        emit Created(currentMarketID, now);

        //Increment current market ID
        currentMarketID++;
    }

    function pause(uint _marketID) public onlyOwner {
        require(markets[_marketID].exist, "Market doesn't exist");
        require(markets[_marketID].status == Status.Running, "Invalid status");

        markets[_marketID].status = Status.Paused;

        emit Paused(_marketID, now);
    }

    function resume(uint _marketID) public onlyOwner {
        require(markets[_marketID].exist, "Market doesn't exist");
        require(markets[_marketID].status == Status.Paused, "Invalid status");

        markets[_marketID].status = Status.Running;

        emit Resumed(_marketID, now);
    }

    function close(uint _marketID) public onlyOwner {
        require(markets[_marketID].exist, "Market doesn't exist");
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
            baseCurrencyToChainlinkFeed[markets[_marketID].baseCurrencyID];

        //Query chainlink
        (
            uint80 roundID,
            int256 price,
        ) = getLatestPrice(AggregatorV3Interface(_chainlinkPriceFeed));

        uint80 _lastRoundID = roundID;
        int256 _finalPrice = price;

        require(_finalPrice > 0, "Chainlink error");
        require(markets[_marketID].initialRoundID != _lastRoundID, "Chainlink round ID didn't change");
        require(markets[_marketID].initialPrice != _finalPrice, "Price didn't change");

        markets[_marketID].status = Status.Closed;
        markets[_marketID].finalPrice = _finalPrice;

        emit Closed(_marketID, now);
    }

    //Buy new token pair for collateral token
    function buy(uint _marketID, uint _amount) external {
        require(markets[_marketID].exist, "Market doesn't exist");
        require(markets[_marketID].status == Status.Running, "Invalid status");
        require(_amount > 0, "Invalid amount");

        //Deposit collateral
        IERC20 collateral = IERC20(markets[_marketID].collateralToken);

        require(collateral.transferFrom(msg.sender, this, _amount));

        //Calculate conditional tokens amount
        uint _conditionalAmount = SafeMath.div(_amount, uint(2));

        //Mint both tokens for user
        ConditionalToken bearToken = ConditionalToken(markets[_marketID].bearToken);
        ConditionalToken bullToken = ConditionalToken(markets[_marketID].bullToken);

        require(bearToken._mint(msg.sender, _conditionalAmount));
        require(bullToken._mint(msg.sender, _conditionalAmount));

        //Increase total deposited collateral
        markets[_marketID].totalDeposit = SafeMath.add(
            markets[_marketID].totalDeposit,
            _amount
        );

        emit Buy(_marketID, now);
    }

    function redeem(uint _marketID, uint _amount) external {
        require(markets[_marketID].exist, "Market doesn't exist");
        require(markets[_marketID].status == Status.Closed, "Invalid status");
        require(_amount > 0, "Invalid amount");
        require(
            markets[_marketID].totalDeposit >=
                markets[_marketID].totalRedemption,
            "No collateral left"
        );

        //Determine winning token address
        address winningTokenAddress;

        if (markets[_marketID].finalPrice > markets[_marketID].initialPrice) {
            winningTokenAddress = markets[_marketID].bearToken;
        } else {
            winningTokenAddress = markets[_marketID].bullToken;
        }

        //Deposit winningToken
        ConditionalToken winningToken = ConditionalToken(winningTokenAddress);

        require(winningToken.transferFrom(msg.sender, this, _amount));

        //Burn winningToken
        require(winningToken._burn(this, _amount));

        //Send collateral to user
        IERC20 collateral = IERC20(markets[_marketID].collateralToken);

        require(collateral.transferFrom(this, msg.sender, _amount));

        //Increase total redemed collateral
        markets[_marketID].totalRedemption = SafeMath.add(
            markets[_marketID].totalRedemption,
            _amount
        );

        emit Redeem(_marketID, now);
    }

    function setBaseCurrencyToChainlinkFeed(
        uint _baseCurrencyID,
        address _chainlinkFeed
    ) public onlyOwner {
        baseCurrencyToChainlinkFeed[_baseCurrencyID] = _chainlinkFeed;
    }

    function setCollateralList(
        address _collateral,
        uint _value
    ) public onlyOwner {
        collateralList[_collateral] = _value;
    }

    function viewMarketExist(uint _marketID) public view returns (bool) {
        return markets[_marketID].exist;
    }
}
