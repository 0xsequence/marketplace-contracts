// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import {ISequenceMarketSignals, ISequenceMarketStorage} from "contracts/interfaces/ISequenceMarket.sol";
import {SequenceMarketFactory, SequenceMarket} from "contracts/SequenceMarketFactory.sol";

import {ERC721RoyaltyMock} from "./mocks/ERC721RoyaltyMock.sol";
import {ERC20TokenMock} from "./mocks/ERC20TokenMock.sol";

import {Test, console, stdError} from "forge-std/Test.sol";

// solhint-disable not-rely-on-time

contract MarketV2 is SequenceMarket {
  function cancelRequestOwner(uint256 requestId) public onlyOwner {
    Request storage request = _requests[requestId];
    address tokenContract = request.tokenContract;
    delete _requests[requestId];
    emit RequestCancelled(requestId, tokenContract);
  }

  function version() public pure returns (uint256) {
    return 2;
  }
}

contract UpgradeabilityTest is ISequenceMarketStorage, Test {
  SequenceMarketFactory private factory;
  SequenceMarket private market;

  function setUp() internal {
    factory = new SequenceMarketFactory();
  }

  modifier withMarket(address owner) {
    setUp();
    market = SequenceMarket(factory.deploy(0, owner));
    vm.label(address(market), "MarketProxy");
    market.getRequest(0);
    _;
  }

  function test_upgrades(address owner, address maker) external withMarket(owner) {
    _assumeNotPrecompile(owner);
    _assumeNotPrecompile(maker);

    ERC20TokenMock erc20 = new ERC20TokenMock();
    ERC721RoyaltyMock erc721 = new ERC721RoyaltyMock();
    erc721.mintMock(maker, 5);
    vm.prank(maker);
    erc721.setApprovalForAll(address(market), true);

    RequestParams memory req = RequestParams({
      isListing: true,
      isERC1155: false,
      tokenContract: address(erc721),
      tokenId: 1,
      quantity: 1,
      expiry: uint96(block.timestamp + 1000),
      currency: address(erc20),
      pricePerToken: 1
    });

    vm.prank(maker);
    uint256 requestId = market.createRequest(req);

    // Do upgrade
    MarketV2 marketV2 = new MarketV2();
    vm.prank(owner, owner);
    market.upgradeTo(address(marketV2));

    // Check that the request is still there
    (bool valid,) = market.isRequestValid(requestId, 1);
    assertTrue(valid);
    Request memory listing = market.getRequest(requestId);
    assertEq(listing.creator, maker);

    // Check that the version is updated
    assertEq(MarketV2(address(market)).version(), 2);

    // Check that the owner can cancel the request
    vm.prank(owner);
    MarketV2(address(market)).cancelRequestOwner(requestId);
    (valid,) = market.isRequestValid(requestId, 1);
    assertFalse(valid);
  }

  function test_nonAdminNoUpgrade(address owner, address nonowner) external withMarket(owner) {
    vm.assume(owner != nonowner);

    MarketV2 marketV2 = new MarketV2();

    vm.expectRevert();
    vm.prank(nonowner, nonowner);
    market.upgradeTo(address(marketV2));
  }

  //
  // Helpers
  //
  function _assumeNotPrecompile(address addr) internal view {
    vm.assume(addr != address(0));
    vm.assume(addr.code.length <= 2);
    assumeNotPrecompile(addr);
    assumeNotForgeAddress(addr);
  }
}
