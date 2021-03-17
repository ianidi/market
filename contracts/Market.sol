
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

contract Market is SafeMath {
    // constructor() ERC721("MyCollectible", "MCO") {
    // }
}




        address indexed manager,


    AggregatorV3Interface internal priceFeed;

        constructor() public {
          
    }

marketid++

Whitelist baseCurrency chainlink

    enum Stage {Running, Paused, Closed}

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

IERC20 public collateralToken;

bear address
bull address

    int256 public initialPrice;
    uint256 public created;
    uint256 public duration;
    int256 public baseCurrency;
    status
    

    totalsupply

    totalRedeem

    
    mapping(address => uint256) withdrawnFees;



buy
    mint tokens



    call balancer


    /**
     * Returns the latest price
     */
    function getLatestPrice(AggregatorV3Interface feed) public view returns (int256) {
        (
            uint80 roundID,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        return price;
    }



contract factory


market info read functions


events



pause
resume
changeduration
close


redeem



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
        emit AMMClosed();
    }