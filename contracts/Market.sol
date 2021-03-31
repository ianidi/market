// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "./balancer/BPool.sol";
import "./balancer/BFactory.sol";
import "./ConditionalToken.sol";

contract Market is BPool, Ownable {
    //TODO: add more info to events
    event Created(uint256 indexed marketID, uint256 _time);
    event Paused(uint256 indexed marketID, uint256 _time);
    event Resumed(uint256 indexed marketID, uint256 _time);
    event Closed(uint256 indexed marketID, uint256 _time);
    event Buy(uint256 indexed marketID, uint256 _time);
    event Redeem(uint256 indexed marketID, uint256 _time);
    event NewBearToken(address indexed contractAddress, uint256 _time);
    event NewBullToken(address indexed contractAddress, uint256 _time);

    enum Status {Running, Paused, Closed}

    struct MarketStruct {
        bool exist;
        Status status;
        uint256 marketID;
        uint256 baseCurrencyID;
        int256 initialPrice;
        int256 finalPrice;
        uint256 created;
        uint256 duration;
        uint256 totalDeposit;
        uint256 totalRedemption;
        uint256 collateralDecimals;
        address collateralToken;
        address bearToken;
        address bullToken;
        BPool pool;
    }

    mapping(uint256 => MarketStruct) public markets;
    mapping(uint256 => address) public baseCurrencyToChainlinkFeed;
    mapping(address => bool) public collateralList;

    uint256 public currentMarketID = 1;
    BFactory private factory;

    //Constants
    uint256 public constant CONDITIONAL_TOKEN_WEIGHT = 10.mul(BPool.BONE);
    uint256 public constant COLLATERAL_TOKEN_WEIGHT  = CONDITIONAL_TOKEN_WEIGHT.mul(2);

    AggregatorV3Interface internal priceFeed;
    IERC20 public collateral;

    constructor() public {
        BFactory factory = BFactory(_factory);

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

    function cloneBearToken() internal onlyOwner returns (BearToken) {
        ConditionalToken bearToken = new ConditionalToken("Bear", "Bear");
        emit NewBearToken(address(bearToken), now);
        return bearToken;
    }

    function cloneBullToken() internal onlyOwner returns (BullToken) {
        ConditionalToken bullToken = new ConditionalToken("Bull", "Bull");
        emit NewBullToken(address(bullToken), now);
        return bullToken;
    }

    function addConditionalToken(BPool _pool, ConditionalToken _conditionalToken, uint256 _conditionalBalance)
        internal
    {
        //Mint bear and bull tokens
        _conditionalToken.mint(address(this), _conditionalBalance);

        addToken(_pool, _conditionalToken, _conditionalBalance, CONDITIONAL_TOKEN_WEIGHT);
    }

    function addCollateralToken(BPool _pool, IERC20 _collateralToken, uint256 _collateralBalance)
        internal
    {
        //Pull collateral tokens from sender
        //TODO: try to make the transfer to the pool directly
        _collateralToken.transferFrom(msg.sender, address(this), _collateralBalance);

        addToken(_pool, _collateralToken, _collateralBalance, COLLATERAL_TOKEN_WEIGHT);
    }

    function calcSwapFee(uint8 _decimals) public returns (uint8) {
        return (10 ** _decimals).div(1000).mul(3); // 0.3%
    }

    function create(uint256 _baseCurrencyID, uint256 _duration, address _collateralToken, uint256 _approvedBalance)
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

        //Create two ERC20 tokens
        address _bearToken = address(cloneBearToken());
        address _bullToken = address(cloneBullToken());

        //Get chainlink price feed by _baseCurrencyID
        address _chainlinkPriceFeed =
            baseCurrencyToChainlinkFeed[_baseCurrencyID];

        int256 _initialPrice =
            getLatestPrice(AggregatorV3Interface(_chainlinkPriceFeed));

        require(_initialPrice > 0, "Chainlink error");

        uint8 _collateralDecimals = IERC20(_collateralToken).decimals();

        //Create balancer pool
        BPool _pool = factory.newBPool();

        //Estamate balance tokens
        uint256 _initialBalance = _approvedBalance.div(2);

        //Calculate swap fee
        uint256 _swapFee = calcSwapFee(_collateralDecimals);

        //Add conditional and collateral tokens to the pool
        addConditionalToken(_pool, _bearToken, _initialBalance);
        addConditionalToken(_pool, _bullToken, _initialBalance);
        addCollateralToken(_pool, IERC20(_collateralToken), _initialBalance);

        //Set the swap fee
        _pool.setSwapFee(_swapFee);

        //Release the pool and allow public swaps
        _pool.release();

        MarketStruct memory marketStruct =
            MarketStruct({
                exist: true,
                status: Status.Running,
                marketID: currentMarketID,
                baseCurrencyID: _baseCurrencyID,
                initialPrice: _initialPrice,
                finalPrice: 0,
                created: now,
                duration: _duration,
                totalDeposit: 0,
                totalRedemption: 0,
                collateralDecimals: _collateralDecimals,
                collateralToken: _collateralToken,
                bearToken: _bearToken,
                bullToken: _bullToken
            });

        markets[currentMarketID] = marketStruct;

        emit Created(currentMarketID, now);

        //Increment current market ID
        currentMarketID++;
    }

    function pause(uint256 _marketID) public onlyOwner {
        require(markets[_marketID].exist, "Market doesn't exist");
        require(markets[_marketID].status == Status.Running, "Invalid status");

        markets[_marketID].status = Status.Paused;

        emit Paused(_marketID, now);
    }

    function resume(uint256 _marketID) public onlyOwner {
        require(markets[_marketID].exist, "Market doesn't exist");
        require(markets[_marketID].status == Status.Paused, "Invalid status");

        markets[_marketID].status = Status.Running;

        emit Resumed(_marketID, now);
    }

    function close(uint256 _marketID) public onlyOwner {
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

        //TODO: query chainlink by valid timestamp
        int256 _finalPrice =
            getLatestPrice(AggregatorV3Interface(_chainlinkPriceFeed));

        require(_finalPrice > 0, "Chainlink error");
        //TODO: require(markets[_marketID].initialPrice != _finalPrice, "Price didn't change");

        markets[_marketID].status = Status.Closed;
        markets[_marketID].finalPrice = _finalPrice;

        emit Closed(_marketID, now);
    }

    //Buy new token pair for collateral token
    function buy(uint256 _marketID, uint256 _amount) external {
        require(markets[_marketID].exist, "Market doesn't exist");
        require(markets[_marketID].status == Status.Running, "Invalid status");
        require(_amount > 0, "Invalid amount");

        //TODO: deposit collateral in accordance to markeetid collateral. require(token.transferFrom(msg.sender, this, _amount));
        //TODO: mint both tokens. _mint(msg.sender, supply);
        //TODO: approve both tokens
        //TODO: send both tokens to user. require(token.transferFrom(msg.sender, this, _amount));

        //Increase total deposited collateral
        markets[_marketID].totalDeposit = SafeMath.add(
            markets[_marketID].totalDeposit,
            _amount
        );

        emit Buy(_marketID, now);
    }

    function redeem(uint256 _marketID, uint256 _amount) external {
        require(markets[_marketID].exist, "Market doesn't exist");
        require(markets[_marketID].status == Status.Closed, "Invalid status");
        require(_amount > 0, "Invalid amount");
        require(
            markets[_marketID].totalDeposit >
                markets[_marketID].totalRedemption,
            "No collateral left"
        );

        //Determine winning token address
        address winningToken;

        if (markets[_marketID].finalPrice > markets[_marketID].initialPrice) {
            winningToken = markets[_marketID].bearToken;
        } else {
            winningToken = markets[_marketID].bullToken;
        }

        //TODO: deposit winningToken _amount. require(token.transferFrom(msg.sender, this, _amount));
        //TODO: send collateral to user in accordance to markeetid collateral. 1 token = 1 collateral

        //Increase total redemed collateral
        markets[_marketID].totalRedemption = SafeMath.add(
            markets[_marketID].totalRedemption,
            _amount
        );

        emit Redeem(_marketID, now);
    }

    function setBaseCurrencyToChainlinkFeed(
        uint256 _baseCurrencyID,
        address _chainlinkFeed
    ) public onlyOwner {
        baseCurrencyToChainlinkFeed[_baseCurrencyID] = _chainlinkFeed;
    }

    function setCollateralList(
        address _collateral,
        uint256 _value
    ) public onlyOwner {
        collateralList[_collateral] = _value;
    }

    function viewMarketExist(uint256 _marketID) public view returns (bool) {
        return markets[_marketID].exist;
    }
}
