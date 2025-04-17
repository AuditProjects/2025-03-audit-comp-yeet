import "./StakeV2.test.sol";

contract StakeV2_PoCTest is Test, StakeV2_BaseTest {

    function setUp() override public {
        super.setUp();
    }

    // @poc-m1-done
    function test_FundsPermanentlyLocked() public {
        // 1. call deposdepositRewardit -> Recorded correctly
        stakeV2.depositReward{value: 1 ether}();
        assertEq(address(stakeV2).balance, stakeV2.accumulatedRewards(), "StakeV2 balance should equal accumulatedRewards");
        
        // 2. call depositWBERA -> Recorded correctly
        wbera.deposit{
            value: 2 ether
        }();
        wbera.transfer(address(stakeV2), 2 ether);
        stakeV2.depositWBERA(2 ether);
        assertEq(address(stakeV2).balance, stakeV2.accumulatedRewards(), "StakeV2 balance should equal accumulatedRewards");

        // 3. transfer BERA to stakeV2  (receive unexpected BERA)  -> Not recorded!
        payable(address(stakeV2)).call{value: 100 ether}("");
        assertNotEq(address(stakeV2).balance, stakeV2.accumulatedRewards(), "StakeV2 balance should not equal accumulatedRewards");

        // 4. call executeRewardDistribution -> Balance still not empty, funds are stuck
        token.mint(address(this), 10 ether);
        token.approve(address(stakeV2), 10 ether);
        stakeV2.stake(10 ether);
        uint256 expectedIslandTokens = 0 ether;
        uint256 expectedShares = 50 ether;
        mockZapper.setReturnValues(expectedIslandTokens, expectedShares);
        stakeV2.executeRewardDistribution(
            IZapper.SingleTokenSwap(0, 0, 0, address(0), ""),
            IZapper.SingleTokenSwap(0, 0, 0, address(0), ""),
            IZapper.KodiakVaultStakingParams(address(0), 0, 0, 0, 0, 0, address(0)),
            IZapper.VaultDepositParams(address(0), address(0), 0)
        );
        assertNotEq(address(stakeV2).balance, stakeV2.accumulatedRewards(), "StakeV2 balance should not equal accumulatedRewards");
        
        assertEq(stakeV2.accumulatedRewards(), 0, "AccumulatedRewards should be reset to 0");
        assertEq(address(stakeV2).balance, 100 ether, "StakeV2 balance should 100 ether");
    }
}
