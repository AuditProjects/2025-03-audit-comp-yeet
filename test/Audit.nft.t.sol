import "./Yeet.Test.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// nft approve 之后余额
contract NFTTest is Test, YeetBaseTest {
    MyNFT public myNft;
    address user;
    address others;

    function setUp() public override {
        super.setUp();

        user = makeAddr("user");
        others = makeAddr("others");
        myNft = new MyNFT();

        vm.prank(user);
        myNft.mint(user, 1);
        myNft.mint(user, 2);
        myNft.mint(user, 3);

    }

    function test_NFTApprove() public {
        uint256 targetNFT = 1;

        vm.prank(user);
        myNft.approve(others, targetNFT);


        assertEq(myNft.ownerOf(1), user);
        assertEq(myNft.balanceOf(user), 3);
        assertEq(myNft.balanceOf(others), 0);

        vm.prank(others);
        myNft.transferFrom(user, others, targetNFT);
        
        assertEq(myNft.ownerOf(1), others);
        assertEq(myNft.balanceOf(user), 2);
        assertEq(myNft.balanceOf(others), 1);

    }

    // function test_NFTBoost_ToManyIds() public {
    //     nft.mintAmount(address(0x1), 1);
    //     uint256[] memory ids = new uint256[](27);
    //     for (uint256 i = 0; i < ids.length; i++) {
    //         ids[i] = 1;
    //     }

    //     vm.expectRevert(abi.encodeWithSelector(Yeet.ToManyTokenIds.selector, 27));
    //     yeet.yeet(ids);
    // }
}

contract MyNFT is ERC721 {
    constructor() ERC721("MyNFT", "NFT") {}

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }

    function burn(address to, uint256 tokenId) public {
        _burn(tokenId);
    }
}

