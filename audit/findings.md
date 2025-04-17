

# Directly sent funds to the StakeV2 become permanently locked

**1. Title**



**2. Description**

## Brief/Intro

The funds sent by an address directly to the `StakeV2` contract will be permanently locked with no way to withdraw them. 


## Vulnerability Details

In the `StakeV2` contract, deposits are primarily handled through these two functions:

`depositWBERA()` function: Unwraps WBERA into BERA and sends it to the contract through `depositReward()`.


```solidity
    function depositWBERA(uint256 amount) external {
        wbera.withdraw(amount); // wbera -> 合约
@>      this.depositReward{     // 合约   -> bera 
            value: amount
        }();
    }
```

`depositReward()` function: Records all rewards in the contract, the deposited funds are recorded in `accumulatedRewards`.

```solidity
    function depositReward() public payable {
        require(msg.value > 0, "Must send value");
@>      accumulatedRewards += msg.value;
        emit RewardDeposited(msg.sender, msg.value);
    }
```

The `executeRewardDistributionYeet` function transfers all accumulated BERA rewards from `accumulatedRewards` to another contract (`zapper`).

```solidity
    function executeRewardDistribution(
        IZapper.SingleTokenSwap calldata swap0,
        IZapper.SingleTokenSwap calldata swap1,
        IZapper.KodiakVaultStakingParams calldata stakingParams,
        IZapper.VaultDepositParams calldata vaultParams
    ) external onlyManager nonReentrant {
        require(accumulatedRewards > 0, "No rewards to distribute");

        // take all wrapper BERA

        uint256 amountToDistribute = accumulatedRewards;
        accumulatedRewards = 0;

        // Use Zapper to swap accumulated BERA and deposit into vault
        (uint256 _islandTokens, uint256 vaultSharesMinted) =
@>                          zapper.zapInNative{value: amountToDistribute}(swap0, swap1, stakingParams, vaultParams);

        _handleVaultShares(vaultSharesMinted);
        emit RewardsDistributed(amountToDistribute, rewardIndex);
    }
```

However, the `StakeV2` contract has a fallback function that allows it to receive BERA directly:

```solidity
@>      fallback() external payable {}
```

Funds received this way are not recorded in `accumulatedRewards`, meaning they cannot be distributed. Additionally, since there is no withdrawal function, these funds will be permanently frozen.


## Impact Details
- If users accidentally send BERA to `StakeV2` contract, they will never be able to get it back. 
- If other contracts interact with `StakeV2` in the future (e.g., a contract upgrade), they might accidentally send BERA directly to it.
- Even though this issue might not seem critical initially, as more transactions occur, trapped funds will increase, leading to significant losses.

## References
- [StakeV2.sol#L136](https://github.com/immunefi-team/audit-comp-yeet/blob/da15231cdefd8f385fcdb85c27258b5f0d0cc270/src/StakeV2.sol#L136)
- [StakeV2.sol#L182-L201](https://github.com/immunefi-team/audit-comp-yeet/blob/da15231cdefd8f385fcdb85c27258b5f0d0cc270/src/StakeV2.sol#L182-L201)


**3. Proof of Concept**


## Proof of Concept

Here’s a Foundry test script. In the `test` folder, create a test contract named `StakeV2_PoCTest`, which inherits from the base contract `StakeV2_BaseTest`:

```solidity
import "./StakeV2.test.sol";

contract StakeV2_PoCTest is Test, StakeV2_BaseTest {

    function setUp() override public {
        super.setUp();
    }

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
```

Run the Foundry test script:
```
forge test --mt test_FundsPermanentlyLocked
```

It can be proven that in certain cases, the BERA held by `stakeV2` does not match the value of `accumulatedRewards`.

The mitigation is to add a `withdraw` function that allows the remaining funds in the contract to be transferred to a designated recipient, such as the admin. This makes the contract more flexible and capable of handling a wider range of scenarios.


# Claim fails when the Reward contract lacks sufficient tokens

**1. Title**
Claim fails when the Reward contract lacks sufficient tokens

**2. Description**

## Brief/Intro

Users might not be able to claim their rewards if the Reward contract doesn’t have enough tokens. Since the tokens are minted by an external party and not by the contract itself, this can prevent users from getting the rewards they’ve earned.


## Vulnerability Details

In the `Reward.sol`, when a user calls `claim`, The contract calculates the claimable reward using `getClaimableAmount` function, and then checks whether `token.balanceOf(address(this)) >= amountEarned`.

If the contract doesn’t have enough tokens, the call reverts.

```solidity
    function claim() external {
@>      uint256 amountEarned = getClaimableAmount(msg.sender);
        require(amountEarned != 0, "Nothing to claim");
@>      require(token.balanceOf(address(this)) >= amountEarned, "Not enough tokens in contract");

        lastClaimedForEpoch[msg.sender] = currentEpoch - 1; // This should be the fix.
        token.transfer(msg.sender, amountEarned);
        emit Rewarded(msg.sender, amountEarned, block.timestamp);
    }
```

This means users must wait until an external party mints and sends more tokens to the contract before they can claim.

By the way, In `Yeet.sol`, the `yeetTokenAddress` is declared but never used, which may indicate a logic flaw or unused variable:

```solidity
@> address public yeetTokenAddress;
```


## Impact Details
- If the `Reward.sol` doesn’t hold enough tokens, any user trying to claim their reward will fail.
- This could block all users from claiming rewards for an unknown period of time, leading to frustration, loss of trust, or even abandonment of the protocol.

## References
- https://github.com/immunefi-team/audit-comp-yeet/blob/da15231cdefd8f385fcdb85c27258b5f0d0cc270/src/Reward.sol#L132-L140
- https://github.com/immunefi-team/audit-comp-yeet/blob/da15231cdefd8f385fcdb85c27258b5f0d0cc270/src/Yeet.sol#L111


**3. Proof of Concept**

## Proof of Concept

Here’s a simple test that demonstrates the issue: when not enough tokens have been minted, attempting to claim will revert.

```solidity
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

```





# Claiming rewards after skipping many rounds can lead to denial of service (DoS)

**1. Title**
## 

**2. Description**

## Brief/Intro
Users who haven’t claimed rewards for many rounds may face excessive gas costs when calling the `claim` function due to the loop inside `getClaimableAmount` function. As time passes, the gas required continues to grow, and eventually, `claim` may never succeed for these users.

## Vulnerability Details

When a user calls `claim`, the contract first calls `getClaimableAmount` to calculate the reward.
within this function, there’s a for loop that iterates over every unclaimed epoch:

```solidity
    function getClaimableAmount(address user) public view returns (uint256) {
        uint256 totalClaimable;

        // Fixed-point arithmetic for more precision
        uint256 scalingFactor = 1e18;

@>      for (uint256 epoch = lastClaimedForEpoch[user] + 1; epoch < currentEpoch; epoch++) {
            if (totalYeetVolume[epoch] == 0) continue; // Avoid division by zero

            uint256 userVolume = userYeetVolume[epoch][user];
            uint256 totalVolume = totalYeetVolume[epoch];

            uint256 userShare = (userVolume * scalingFactor) / totalVolume;

            uint256 maxClaimable = (epochRewards[epoch] / rewardsSettings.MAX_CAP_PER_WALLET_PER_EPOCH_FACTOR());
            uint256 claimable = (userShare * epochRewards[epoch]) / scalingFactor;

            if (claimable > maxClaimable) {
                claimable = maxClaimable;
            }

            totalClaimable += claimable;
        }

        return totalClaimable;
    }
```
Each iteration involves multiple reads, divisions, and conditionals. As the number of unclaimed rounds increases for a user, the loop runs more times, causing gas consumption to rise sharply.

Eventually, the function may consume more gas than the block gas limit allows. In this case, the `claim` call will always revert, and the user will be permanently unable to claim rewards.

## Impact Details
- Affected users cannot claim any of their earned rewards, no matter how large.
- Tokens meant for these users remain stuck in the contract, which may inflate the protocol’s liabilities or distort token economics.

## References
- https://github.com/immunefi-team/audit-comp-yeet/blob/da15231cdefd8f385fcdb85c27258b5f0d0cc270/src/Reward.sol#L133
- https://github.com/immunefi-team/audit-comp-yeet/blob/da15231cdefd8f385fcdb85c27258b5f0d0cc270/src/Reward.sol#L173-L198

**3. Proof of Concept**

## Proof of Concept

Here’s a Foundry test script. In the `test` folder, create a test contract named `PoCTest`:

```solidity
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

        // Assuming enough tokens are minted
        token.mint(address(reward), reward.getClaimableAmount(claimer));
        // It will consume an excessive amount of gas!
        reward.claim();
        vm.stopPrank();
    }

    receive() external payable {}
}

```

Run the Foundry test script:
```
forge test --mt test_GetClaimableAmountDoS --gas-report
```

A detailed snapshot of the test results is provided in the attachment.

Based on Berachain’s estimated block gas limit (for example, 5,000,000 — though this value can vary), setting `ROUND_LIMIT` to 600 can easily exceed the available gas, potentially causing subsequent `claim` calls to consistently fail.