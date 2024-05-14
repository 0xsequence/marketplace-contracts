// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import {SequenceMarket} from "contracts/SequenceMarket.sol";
import {SequenceMarketFactory} from "contracts/SequenceMarketFactory.sol";
import {ISequenceMarketSignals, ISequenceMarketStorage} from "contracts/interfaces/ISequenceMarket.sol";
import {ERC1155RoyaltyMock} from "./mocks/ERC1155RoyaltyMock.sol";
import {ERC721RoyaltyMock} from "./mocks/ERC721RoyaltyMock.sol";
import {ERC20TokenMock} from "./mocks/ERC20TokenMock.sol";
import {IERC1155TokenReceiver} from "0xsequence/erc-1155/src/contracts/interfaces/IERC1155TokenReceiver.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {IERC2981} from "contracts/interfaces/IERC2981.sol";
import {ERC1155MintBurnMock} from "@0xsequence/erc-1155/contracts/mocks/ERC1155MintBurnMock.sol";
import {ERC721Mock} from "./mocks/ERC721Mock.sol";

import {IERC721} from "contracts/interfaces/IERC721.sol";
import {IERC20} from "@0xsequence/erc-1155/contracts/interfaces/IERC20.sol";
import {IERC165} from "@0xsequence/erc-1155/contracts/interfaces/IERC165.sol";
import {IERC1155} from "@0xsequence/erc-1155/contracts/interfaces/IERC1155.sol";

import {Test, console, stdError} from "forge-std/Test.sol";

// solhint-disable not-rely-on-time

contract ERC1155ReentryAttacker is IERC1155TokenReceiver {
  address private immutable _market;

  uint256 private _requestId;
  uint256 private _quantity;
  bool private _hasAttacked;

  constructor(address market) {
    _market = market;
  }

  function acceptListing(uint256 requestId, uint256 quantity) external {
    _requestId = requestId;
    _quantity = quantity;
    SequenceMarket(_market).acceptRequest(_requestId, _quantity, address(this), new uint256[](0), new address[](0));
  }

  function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4) {
    if (_hasAttacked) {
      // Done
      _hasAttacked = false;
      return IERC1155TokenReceiver.onERC1155Received.selector;
    }
    // Attack the market
    _hasAttacked = true;
    SequenceMarket(_market).acceptRequest(_requestId, _quantity, address(this), new uint256[](0), new address[](0));
    return IERC1155TokenReceiver.onERC1155Received.selector;
  }

  function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
    external
    pure
    returns (bytes4)
  {
    return IERC1155TokenReceiver.onERC1155BatchReceived.selector;
  }
}

contract SequenceMarketTest is ISequenceMarketSignals, ISequenceMarketStorage, ReentrancyGuardUpgradeable, Test {
  SequenceMarketFactory private factory;
  SequenceMarket private market;
  ERC1155RoyaltyMock private erc1155;
  ERC721RoyaltyMock private erc721;
  ERC20TokenMock private erc20;

  uint256 private constant TOKEN_ID = 1;
  uint256 private constant TOKEN_QUANTITY = 100;
  uint256 private constant CURRENCY_QUANTITY = 1000 ether;

  uint256 private constant ROYALTY_FEE = 200; // 2%

  address private constant MARKET_OWNER = address(uint160(uint256(keccak256("market_owner"))));
  address private constant TOKEN_OWNER = address(uint160(uint256(keccak256("token_owner"))));
  address private constant CURRENCY_OWNER = address(uint160(uint256(keccak256("currency_owner"))));
  address private constant ROYALTY_RECIPIENT = address(uint160(uint256(keccak256("royalty_recipient"))));
  address private constant FEE_RECIPIENT = address(uint160(uint256(keccak256("fee_recipient"))));

  uint256[] private emptyFees;
  address[] private emptyFeeRecipients;

  uint256 private expectedNextRequestId;

  struct Balances {
    uint256 currency;
    uint256 tokenOwner;
    uint256 royal;
  }

  function setUp() external {
    factory = new SequenceMarketFactory();
    market = SequenceMarket(factory.deploy(0, MARKET_OWNER));

    erc1155 = new ERC1155RoyaltyMock();
    erc721 = new ERC721RoyaltyMock();
    erc20 = new ERC20TokenMock();

    vm.label(TOKEN_OWNER, "token_owner");
    vm.label(CURRENCY_OWNER, "currency_owner");

    expectedNextRequestId = 0;

    // Mint tokens
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = TOKEN_ID;
    uint256[] memory quantities = new uint256[](1);
    quantities[0] = TOKEN_QUANTITY;
    erc1155.batchMintMock(TOKEN_OWNER, tokenIds, quantities, "");

    erc721.mintMock(TOKEN_OWNER, TOKEN_QUANTITY);

    erc20.mockMint(CURRENCY_OWNER, CURRENCY_QUANTITY);
    vm.deal(CURRENCY_OWNER, CURRENCY_QUANTITY);

    // Approvals
    vm.startPrank(TOKEN_OWNER);
    erc1155.setApprovalForAll(address(market), true);
    erc721.setApprovalForAll(address(market), true);
    vm.stopPrank();
    vm.prank(CURRENCY_OWNER);
    erc20.approve(address(market), CURRENCY_QUANTITY);

    // Royalty
    erc1155.setFee(ROYALTY_FEE);
    erc1155.setFeeRecipient(ROYALTY_RECIPIENT);
    erc721.setFee(ROYALTY_FEE);
    erc721.setFeeRecipient(ROYALTY_RECIPIENT);
  }

  //
  // Common Create Request
  //
  function test_createRequest_interfaceInvalid(RequestParams memory request, address invalidAddr)
    external
  {
    _assumeNotPrecompile(invalidAddr);
    bool isERC1155 = request.isERC1155;
    _fixRequest(request, isERC1155);

    bytes4 expectedInterface;

    request.tokenContract = invalidAddr;
    expectedInterface = isERC1155 ? type(IERC1155).interfaceId : type(IERC721).interfaceId;

    // Must NOT support interface
    if (invalidAddr.code.length != 0) {
      try IERC165(invalidAddr).supportsInterface(expectedInterface) returns (bool result) {
        vm.assume(!result);
      } catch {}
    }

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(abi.encodeWithSelector(UnsupportedContractInterface.selector, invalidAddr, expectedInterface));
    market.createRequest(request);
  }

  //
  // Create Listing
  //

  // This is tested and fuzzed through internal calls
  function createListing(RequestParams memory request) internal returns (uint256 requestId) {
    _fixRequest(request, true);

    Request memory expected = Request({
      creator: TOKEN_OWNER,
      isListing: true,
      isERC1155: request.isERC1155,
      tokenContract: request.tokenContract,
      tokenId: request.tokenId,
      quantity: request.quantity,
      expiry: request.expiry,
      currency: request.currency,
      pricePerToken: request.pricePerToken
    });

    vm.expectEmit(true, true, true, true, address(market));
    emit RequestCreated(
      expectedNextRequestId,
      TOKEN_OWNER,
      expected.tokenContract,
      expected.tokenId,
      expected.isListing,
      expected.quantity,
      expected.currency,
      expected.pricePerToken,
      expected.expiry
    );
    vm.prank(TOKEN_OWNER);
    requestId = market.createRequest(request);
    expectedNextRequestId++;

    Request memory listing = market.getRequest(requestId);
    assertEq(listing.creator, expected.creator);
    assertEq(listing.isListing, expected.isListing);
    assertEq(listing.isERC1155, expected.isERC1155);
    assertEq(listing.creator, expected.creator);
    assertEq(listing.tokenContract, expected.tokenContract);
    assertEq(listing.tokenId, expected.tokenId);
    assertEq(listing.quantity, expected.quantity);
    assertEq(listing.currency, expected.currency);
    assertEq(listing.pricePerToken, expected.pricePerToken);
    assertEq(listing.expiry, expected.expiry);

    return requestId;
  }

  function test_createListing_invalidToken(RequestParams memory request, address badContract) external {
    vm.assume(badContract != address(erc1155) && badContract != address(erc721));
    _assumeNotPrecompile(badContract);
    _fixRequest(request, true);
    request.tokenContract = badContract;
    bytes4 expectedInterface = request.isERC1155 ? type(IERC1155).interfaceId : type(IERC721).interfaceId;

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(
      abi.encodeWithSelector(UnsupportedContractInterface.selector, badContract, expectedInterface)
    );
    market.createRequest(request);
  }

  function test_createListing_invalidExpiry(RequestParams memory request, uint96 expiry) external {
    vm.assume(expiry <= block.timestamp);
    _fixRequest(request, true);
    request.expiry = expiry;

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidExpiry.selector);
    market.createRequest(request);
  }

  function test_createListing_invalidQuantity_erc721(RequestParams memory request, uint256 quantity) external {
    vm.assume(quantity != 1);
    request.isERC1155 = false;
    _fixRequest(request, true);
    request.quantity = quantity;

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(
      abi.encodeWithSelector(InvalidTokenApproval.selector, address(erc721), TOKEN_ID, quantity, TOKEN_OWNER)
    );
    market.createRequest(request);
  }

  function test_createListing_invalidQuantity_erc1155(RequestParams memory request, uint256 quantity) external {
    vm.assume(quantity > TOKEN_QUANTITY || quantity == 0);
    request.isERC1155 = true;
    _fixRequest(request, true);
    request.quantity = quantity;

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(
      abi.encodeWithSelector(InvalidTokenApproval.selector, address(erc1155), TOKEN_ID, quantity, TOKEN_OWNER)
    );
    market.createRequest(request);
  }

  function test_createListing_invalidPrice(RequestParams memory request) external {
    _fixRequest(request, true);
    request.pricePerToken = 0;

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidPrice.selector);
    market.createRequest(request);
  }

  function test_createListing_erc1155_noToken(RequestParams memory request, uint256 tokenId) external {
    request.isERC1155 = true;
    _fixRequest(request, true);
    request.tokenId = tokenId;

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(
      abi.encodeWithSelector(InvalidTokenApproval.selector, address(erc1155), tokenId, request.quantity, CURRENCY_OWNER)
    );
    market.createRequest(request);
  }

  function test_createListing_erc1155_invalidApproval(RequestParams memory request) external {
    request.isERC1155 = true;
    _fixRequest(request, true);

    vm.prank(TOKEN_OWNER);
    erc1155.setApprovalForAll(address(market), false);

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(
      abi.encodeWithSelector(InvalidTokenApproval.selector, address(erc1155), TOKEN_ID, request.quantity, TOKEN_OWNER)
    );
    market.createRequest(request);
  }

  function test_createListing_erc721_noToken(RequestParams memory request, uint256 tokenId) external {
    request.isERC1155 = false;
    _fixRequest(request, true);
    request.tokenId = tokenId;

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidTokenApproval.selector, address(erc721), tokenId, 1, CURRENCY_OWNER));
    market.createRequest(request);
  }

  function test_createListing_erc721_invalidApproval(RequestParams memory request) external {
    request.isERC1155 = false;
    _fixRequest(request, true);

    vm.prank(TOKEN_OWNER);
    erc721.setApprovalForAll(address(market), false);

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidTokenApproval.selector, address(erc721), TOKEN_ID, 1, TOKEN_OWNER));
    market.createRequest(request);
  }

  //
  // Accept Listing
  //
  function acceptListing(RequestParams memory request, address recipient) internal returns (uint256 requestId) {
    _assumeNotPrecompile(recipient);
    vm.assume(recipient.code.length <= 2);

    requestId = createListing(request);

    uint256 totalPrice = request.pricePerToken * request.quantity;
    uint256 royalty = (totalPrice * ROYALTY_FEE) / 10_000;
    uint256 msgVal = request.currency == address(0) ? totalPrice + royalty : 0;

    Balances memory bals;
    if (msgVal != 0) {
      bals.currency = CURRENCY_OWNER.balance;
      bals.tokenOwner = TOKEN_OWNER.balance;
      bals.royal = ROYALTY_RECIPIENT.balance;
    } else {
      bals.currency = erc20.balanceOf(CURRENCY_OWNER);
      bals.tokenOwner = erc20.balanceOf(TOKEN_OWNER);
      bals.royal = erc20.balanceOf(ROYALTY_RECIPIENT);
    }

    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestId, CURRENCY_OWNER, request.tokenContract, recipient, request.quantity, 0);
    vm.prank(CURRENCY_OWNER);
    market.acceptRequest{value: msgVal}(requestId, request.quantity, recipient, emptyFees, emptyFeeRecipients);

    if (request.isERC1155) {
      assertEq(erc1155.balanceOf(recipient, TOKEN_ID), request.quantity);
    } else {
      assertEq(erc721.ownerOf(TOKEN_ID), recipient);
    }
    if (msgVal != 0) {
      assertEq(CURRENCY_OWNER.balance, bals.currency - totalPrice, "currency balance");
      assertEq(TOKEN_OWNER.balance, bals.tokenOwner + totalPrice - royalty, "token balance");
      assertEq(ROYALTY_RECIPIENT.balance, bals.royal + royalty, "royalty balance");
    } else {
      assertEq(erc20.balanceOf(CURRENCY_OWNER), bals.currency - totalPrice);
      assertEq(erc20.balanceOf(TOKEN_OWNER), bals.tokenOwner + totalPrice - royalty);
      assertEq(erc20.balanceOf(ROYALTY_RECIPIENT), bals.royal + royalty);
    }

    return requestId;
  }

  function test_acceptListing(RequestParams memory request, address recipient) external {
    acceptListing(request, recipient);
  }

  function test_acceptListing_additionalFees(RequestParams memory request, uint256[] memory additionalFees) external {
    _fixRequest(request, true);

    uint256 totalPrice = request.pricePerToken * request.quantity;
    uint256 royalty = (totalPrice * ROYALTY_FEE) / 10_000;

    if (additionalFees.length > 3) {
      // Cap at 3 fees
      assembly {
        mstore(additionalFees, 3)
      }
    }
    address[] memory additionalFeeRecipients = new address[](additionalFees.length);
    uint256 totalFees;
    for (uint256 i; i < additionalFees.length; i++) {
      additionalFeeRecipients[i] = FEE_RECIPIENT;
      additionalFees[i] = bound(additionalFees[i], 1, 0.2 ether);
      totalFees += additionalFees[i];
    }
    vm.assume((totalFees + royalty) < totalPrice);
    uint256 msgVal = request.currency == address(0) ? totalPrice + royalty + totalFees : 0;
    Balances memory bals;
    if (msgVal != 0) {
      bals.currency = CURRENCY_OWNER.balance;
      bals.tokenOwner = TOKEN_OWNER.balance;
      bals.royal = ROYALTY_RECIPIENT.balance;
    } else {
      bals.currency = erc20.balanceOf(CURRENCY_OWNER);
      bals.tokenOwner = erc20.balanceOf(TOKEN_OWNER);
      bals.royal = erc20.balanceOf(ROYALTY_RECIPIENT);
    }

    uint256 requestId = createListing(request);

    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestId, CURRENCY_OWNER, request.tokenContract, CURRENCY_OWNER, request.quantity, 0);
    vm.prank(CURRENCY_OWNER);
    market.acceptRequest{value: msgVal}(requestId, request.quantity, CURRENCY_OWNER, additionalFees, additionalFeeRecipients);

    if (request.isERC1155) {
      assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity);
    } else {
      assertEq(erc721.ownerOf(TOKEN_ID), CURRENCY_OWNER);
    }
    // Fees paid by taker
    if (msgVal != 0) {
      assertEq(CURRENCY_OWNER.balance, bals.currency - totalPrice - totalFees);
      assertEq(FEE_RECIPIENT.balance, totalFees); // Assume no starting value
      assertEq(TOKEN_OWNER.balance, bals.tokenOwner + totalPrice - royalty);
      assertEq(ROYALTY_RECIPIENT.balance, bals.royal + royalty);
    } else {
      assertEq(erc20.balanceOf(CURRENCY_OWNER), bals.currency - totalPrice - totalFees);
      assertEq(erc20.balanceOf(FEE_RECIPIENT), totalFees); // Assume no starting value
      assertEq(erc20.balanceOf(TOKEN_OWNER), bals.tokenOwner + totalPrice - royalty);
      assertEq(erc20.balanceOf(ROYALTY_RECIPIENT), bals.royal + royalty);
    }
  }

  function test_acceptListing_invalidAdditionalFees(RequestParams memory params) external {
    uint256 requestId = createListing(params);
    uint256 msgVal = params.currency == address(0) ? 100 ether : 0;

    // Zero fee
    uint256[] memory additionalFees = new uint256[](1);
    address[] memory additionalFeeRecipients = new address[](1);
    additionalFeeRecipients[0] = FEE_RECIPIENT;
    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidAdditionalFees.selector);
    market.acceptRequest{value: msgVal}(requestId, 1, CURRENCY_OWNER, additionalFees, additionalFeeRecipients);

    // Fee exceeds cost
    Request memory request = market.getRequest(requestId);
    additionalFees[0] = request.pricePerToken * request.quantity + 1;
    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidAdditionalFees.selector);
    market.acceptRequest{value: msgVal}(requestId, request.quantity, CURRENCY_OWNER, additionalFees, additionalFeeRecipients);

    // Zero address
    additionalFees[0] = 1 ether;
    additionalFeeRecipients[0] = address(0);
    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidAdditionalFees.selector);
    market.acceptRequest{value: msgVal}(requestId, 1, CURRENCY_OWNER, additionalFees, additionalFeeRecipients);

    // Invalid length (larger recipients)
    additionalFeeRecipients = new address[](2);
    additionalFeeRecipients[0] = FEE_RECIPIENT;
    additionalFeeRecipients[1] = FEE_RECIPIENT;
    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidAdditionalFees.selector);
    market.acceptRequest{value: msgVal}(requestId, 1, CURRENCY_OWNER, additionalFees, additionalFeeRecipients);

    // Invalid length (larger fees)
    additionalFees = new uint256[](3);
    additionalFees[0] = 1;
    additionalFees[1] = 2;
    additionalFees[2] = 3;
    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidAdditionalFees.selector);
    market.acceptRequest{value: msgVal}(requestId, 1, CURRENCY_OWNER, additionalFees, additionalFeeRecipients);
  }

  function test_acceptListing_invalidRoyalties(RequestParams memory request) external {
    _fixRequest(request, true);
    vm.assume(request.pricePerToken > 10_000); // Ensure rounding
    uint256 requestId = createListing(request);
    uint256 msgVal = request.currency == address(0) ? request.quantity * request.pricePerToken : 0;

    // >100%
    if (request.isERC1155) {
      erc1155.setFee(10_001);
    } else {
      erc721.setFee(10_001);
    }
    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(stdError.arithmeticError);
    market.acceptRequest{value: msgVal}(requestId, 1, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);

    // 100% is ok
    if (request.isERC1155) {
      erc1155.setFee(10_000);
    } else {
      erc721.setFee(10_000);
    }
    vm.prank(CURRENCY_OWNER);
    market.acceptRequest{value: msgVal}(requestId, 1, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);
  }

  function test_acceptListing_invalidQuantity_zero(RequestParams memory request) external {
    uint256 requestId = createListing(request);

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidQuantity.selector);
    market.acceptRequest(requestId, 0, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);
  }

  function test_acceptListing_invalidQuantity_tooHigh(RequestParams memory request) external {
    uint256 requestId = createListing(request);

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidQuantity.selector);
    market.acceptRequest(requestId, request.quantity + 1, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);
  }

  function test_acceptListing_invalidExpiry(RequestParams memory request, bool over) external {
    uint256 requestId = createListing(request);

    vm.warp(request.expiry + (over ? 1 : 0));

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidExpiry.selector);
    market.acceptRequest(requestId, request.quantity, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);
  }

  function test_acceptListing_invalidated(RequestParams memory params1, RequestParams memory params2) external {
    uint256 requestId1 = createListing(params1);
    uint256 requestId2 = createListing(params2);
    uint256 requestId3 = createOffer(params1);

    vm.prank(TOKEN_OWNER);
    market.invalidateRequests();

    (bool valid,) = market.isRequestValid(requestId1, 1);
    assertFalse(valid);
    (valid,) = market.isRequestValid(requestId2, 1);
    assertFalse(valid);
    (valid,) = market.isRequestValid(requestId3, 1);
    assertTrue(valid); // Unaffected

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(Invalidated.selector);
    market.acceptRequest(requestId1, 1, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);
    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(Invalidated.selector);
    market.acceptRequest(requestId2, 1, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);

    // Next request valid
    requestId1 = createListing(params1);
    uint256 msgVal = params1.currency == address(0) ? params1.pricePerToken : 0;
    vm.prank(CURRENCY_OWNER);
    market.acceptRequest{value: msgVal}(requestId1, 1, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);
  }

  function test_acceptListing_twice(RequestParams memory request) external {
    request.isERC1155 = true;
    _fixRequest(request, true);

    // Cater for rounding error with / 2 * 2
    request.quantity = (request.quantity / 2) * 2;
    if (request.quantity == 0) {
      request.quantity = 2;
    }
    uint256 totalPrice = request.pricePerToken * request.quantity;
    uint256 royalty = (totalPrice * ROYALTY_FEE) / 10_000 / 2 * 2;
    uint256 msgVal = request.currency == address(0) ? totalPrice + royalty : 0;

    Balances memory bals;
    if (msgVal != 0) {
      bals.currency = CURRENCY_OWNER.balance;
      bals.tokenOwner = TOKEN_OWNER.balance;
      bals.royal = ROYALTY_RECIPIENT.balance;
    } else {
      bals.currency = erc20.balanceOf(CURRENCY_OWNER);
      bals.tokenOwner = erc20.balanceOf(TOKEN_OWNER);
      bals.royal = erc20.balanceOf(ROYALTY_RECIPIENT);
    }

    uint256 requestId = createListing(request);

    vm.startPrank(CURRENCY_OWNER);
    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestId, CURRENCY_OWNER, address(erc1155), CURRENCY_OWNER, request.quantity / 2, request.quantity / 2);
    market.acceptRequest{value: msgVal}(requestId, request.quantity / 2, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);
    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestId, CURRENCY_OWNER, address(erc1155), CURRENCY_OWNER, request.quantity / 2, 0);
    market.acceptRequest{value: msgVal}(requestId, request.quantity / 2, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);
    vm.stopPrank();

    assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity);
    if (msgVal != 0) {
      assertEq(CURRENCY_OWNER.balance, bals.currency - totalPrice, "currency balance");
      assertEq(TOKEN_OWNER.balance, bals.tokenOwner + totalPrice - royalty, "token balance");
      assertEq(ROYALTY_RECIPIENT.balance, bals.royal + royalty, "royalty balance");
    } else {
      assertEq(erc20.balanceOf(CURRENCY_OWNER), bals.currency - totalPrice);
      assertEq(erc20.balanceOf(TOKEN_OWNER), bals.tokenOwner + totalPrice - royalty);
      assertEq(erc20.balanceOf(ROYALTY_RECIPIENT), bals.royal + royalty);
    }
  }

  function test_acceptListingBatch_repeat(RequestParams memory request) external {
    // Potential exploit of royalty rounding.
    request.isERC1155 = true;
    request.currency = address(1); // Not native
    _fixRequest(request, true);

    uint256 totalPrice = request.pricePerToken * request.quantity;
    uint256 royalty = ((request.pricePerToken * ROYALTY_FEE) / 10_000) * request.quantity;

    uint256 erc20BalCurrency = erc20.balanceOf(CURRENCY_OWNER);
    uint256 erc20BalTokenOwner = erc20.balanceOf(TOKEN_OWNER);
    uint256 erc20BalRoyal = erc20.balanceOf(ROYALTY_RECIPIENT);

    uint256 requestId = createListing(request);
    uint256[] memory requestIds = new uint256[](request.quantity);
    uint256[] memory quantities = new uint256[](request.quantity);
    address[] memory recipients = new address[](request.quantity);

    for (uint256 i; i < request.quantity; i++) {
      requestIds[i] = requestId;
      quantities[i] = 1;
      recipients[i] = CURRENCY_OWNER;
    }

    vm.prank(CURRENCY_OWNER);
    market.acceptRequestBatch(requestIds, quantities, recipients, emptyFees, emptyFeeRecipients);

    assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity);
    assertEq(erc20.balanceOf(CURRENCY_OWNER), erc20BalCurrency - totalPrice);
    assertEq(erc20.balanceOf(TOKEN_OWNER), erc20BalTokenOwner + totalPrice - royalty);
    assertEq(erc20.balanceOf(ROYALTY_RECIPIENT), erc20BalRoyal + royalty);
  }

  function test_acceptListing_twice_overQuantity(RequestParams memory request) external {
    request.isERC1155 = true;
    _fixRequest(request, true);

    uint256 requestId = acceptListing(request, CURRENCY_OWNER);
    uint256 msgVal = request.currency == address(0) ? request.quantity * request.pricePerToken : 0;

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidRequestId.selector, requestId));
    market.acceptRequest{value: msgVal}(requestId, 1, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);
  }

  function test_acceptListing_noFunds(RequestParams memory request) external {
    request.currency = address(1); // Not native
    uint256 requestId = createListing(request);

    uint256 bal = erc20.balanceOf(CURRENCY_OWNER);
    vm.prank(CURRENCY_OWNER);
    erc20.transfer(TOKEN_OWNER, bal);

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert("TransferHelper::transferFrom: transferFrom failed");
    market.acceptRequest(requestId, request.quantity, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);
  }

  function test_acceptListing_notEnoughNative(RequestParams memory request, address taker) external {
    vm.assume(taker.balance == 0);
    request.currency = address(0); // Native
    uint256 requestId = createListing(request);
    uint256 msgVal = request.quantity * request.pricePerToken;

    vm.prank(taker);
    vm.expectRevert();
    market.acceptRequest{value: msgVal}(requestId, request.quantity, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);
  }

  function test_acceptListing_invalidERC721Owner(RequestParams memory request) external {
    request.isERC1155 = false;
    _fixRequest(request, true);

    uint256 requestId = createListing(request);
    uint256 msgVal = request.currency == address(0) ? request.quantity * request.pricePerToken : 0;

    vm.prank(TOKEN_OWNER);
    erc721.transferFrom(TOKEN_OWNER, CURRENCY_OWNER, TOKEN_ID);

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert("ERC721: caller is not token owner or approved");
    market.acceptRequest{value: msgVal}(requestId, 1, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);
  }

  function test_acceptListing_reentry(RequestParams memory request) external {
    request.isERC1155 = true;

    uint256 requestId = createListing(request);

    ERC1155ReentryAttacker attacker = new ERC1155ReentryAttacker(address(market));
    erc20.mockMint(address(attacker), CURRENCY_QUANTITY);
    vm.prank(address(attacker));
    erc20.approve(address(market), CURRENCY_QUANTITY);

    if (request.currency == address(0)) {
      vm.expectRevert(); // No funds error
    } else {
      vm.expectRevert("ReentrancyGuard: reentrant call");
    }
    attacker.acceptListing(requestId, request.quantity);
  }

  //
  // Cancel Listing
  //
  function cancelListing(RequestParams memory request) internal returns (uint256 requestId) {
    requestId = createListing(request);
    uint256 msgVal = request.currency == address(0) ? request.quantity * request.pricePerToken : 0;

    // Fails invalid sender
    vm.expectRevert(abi.encodeWithSelector(InvalidRequestId.selector, requestId));
    market.cancelRequest(requestId);

    // Succeeds correct sender

    vm.expectEmit(true, true, true, true, address(market));
    emit RequestCancelled(requestId, request.tokenContract);
    vm.prank(TOKEN_OWNER);
    market.cancelRequest(requestId);

    Request memory listing = market.getRequest(requestId);
    // Zero'd
    assertEq(listing.creator, address(0));
    assertEq(listing.tokenContract, address(0));
    assertEq(listing.tokenId, 0);
    assertEq(listing.quantity, 0);
    assertEq(listing.currency, address(0));
    assertEq(listing.pricePerToken, 0);
    assertEq(listing.expiry, 0);

    // Accept fails
    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidRequestId.selector, requestId));
    market.acceptRequest{value: msgVal}(requestId, 1, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);

    return requestId;
  }

  function test_cancelListing(RequestParams memory request) external {
    cancelListing(request);
  }


  function test_cancelListing_partialFill(RequestParams memory request) external returns (uint256 requestId) {
    request.isERC1155 = true;
    _fixRequest(request, true);
    if (request.quantity == 1) {
      // Ensure multiple available
      request.quantity++;
      _fixRequest(request, true);
    }
    requestId = createListing(request);
    uint256 msgVal = request.currency == address(0) ? request.quantity * request.pricePerToken : 0;

    // Partial fill
    vm.prank(CURRENCY_OWNER);
    market.acceptRequest{value: msgVal}(requestId, 1, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);

    // Fails invalid sender
    vm.expectRevert(abi.encodeWithSelector(InvalidRequestId.selector, requestId));
    market.cancelRequest(requestId);

    // Succeeds correct sender

    vm.expectEmit(true, true, true, true, address(market));
    emit RequestCancelled(requestId, request.tokenContract);
    vm.prank(TOKEN_OWNER);
    market.cancelRequest(requestId);

    Request memory listing = market.getRequest(requestId);
    // Zero'd
    assertEq(listing.creator, address(0));
    assertEq(listing.tokenContract, address(0));
    assertEq(listing.tokenId, 0);
    assertEq(listing.quantity, 0);
    assertEq(listing.currency, address(0));
    assertEq(listing.pricePerToken, 0);
    assertEq(listing.expiry, 0);

    // Accept fails
    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidRequestId.selector, requestId));
    market.acceptRequest{value: msgVal}(requestId, 1, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);

    return requestId;
  }

  //
  // Create Offer
  //

  // This is tested and fuzzed through internal calls
  function createOffer(RequestParams memory request) internal returns (uint256 requestId) {
    _fixRequest(request, false);

    Request memory expected = Request({
      creator: CURRENCY_OWNER,
      isListing: false,
      isERC1155: request.isERC1155,
      tokenContract: request.tokenContract,
      tokenId: request.tokenId,
      quantity: request.quantity,
      currency: request.currency,
      pricePerToken: request.pricePerToken,
      expiry: request.expiry
    });

    vm.expectEmit(true, true, true, true, address(market));
    emit RequestCreated(
      expectedNextRequestId,
      CURRENCY_OWNER,
      expected.tokenContract,
      expected.tokenId,
      expected.isListing,
      expected.quantity,
      expected.currency,
      expected.pricePerToken,
      expected.expiry
    );
    vm.prank(CURRENCY_OWNER);
    requestId = market.createRequest(request);
    expectedNextRequestId++;

    Request memory offer = market.getRequest(requestId);
    assertEq(offer.creator, expected.creator);
    assertEq(offer.isListing, expected.isListing);
    assertEq(offer.isERC1155, expected.isERC1155);
    assertEq(offer.creator, expected.creator);
    assertEq(offer.tokenContract, expected.tokenContract);
    assertEq(offer.tokenId, expected.tokenId);
    assertEq(offer.quantity, expected.quantity);
    assertEq(offer.currency, expected.currency);
    assertEq(offer.pricePerToken, expected.pricePerToken);
    assertEq(offer.expiry, expected.expiry);

    return requestId;
  }

  function test_createOffer_invalidExpiry(RequestParams memory request, uint96 expiry) external {
    vm.assume(expiry <= block.timestamp);
    _fixRequest(request, false);
    request.expiry = expiry;

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidExpiry.selector);
    market.createRequest(request);
  }

  function test_createOffer_invalidQuantity(RequestParams memory request) external {
    _fixRequest(request, false);
    request.quantity = 0;

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidQuantity.selector);
    market.createRequest(request);
  }

  function test_createOffer_invalidPrice(RequestParams memory request) external {
    _fixRequest(request, false);
    request.pricePerToken = 0;

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidPrice.selector);
    market.createRequest(request);
  }

  function test_createOffer_invalidApproval(RequestParams memory request) external {
    _fixRequest(request, false);

    uint256 total = request.pricePerToken * request.quantity;
    uint256 royalty = (total * ROYALTY_FEE) / 10_000;
    total += royalty;

    vm.prank(CURRENCY_OWNER);
    erc20.approve(address(market), total - 1);

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidCurrencyApproval.selector, request.currency, total, CURRENCY_OWNER));
    market.createRequest(request);
  }

  //
  // Accept Offer
  //
  function acceptOffer(RequestParams memory request, address recipient) internal returns (uint256 requestId) {
    // Allow TOKEN_OWNER as recipient
    vm.assume(recipient != CURRENCY_OWNER);
    vm.assume(recipient != ROYALTY_RECIPIENT);
    _fixRequest(request, false);

    uint256 totalPrice = request.pricePerToken * request.quantity;
    uint256 royalty = (totalPrice * ROYALTY_FEE) / 10_000;

    Balances memory bals;
    bals.currency = erc20.balanceOf(CURRENCY_OWNER);
    bals.royal = erc20.balanceOf(ROYALTY_RECIPIENT);
    uint256 balRecipient = erc20.balanceOf(recipient);

    requestId = createOffer(request);

    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestId, TOKEN_OWNER, request.tokenContract, recipient, request.quantity, 0);
    vm.prank(TOKEN_OWNER);
    market.acceptRequest(requestId, request.quantity, recipient, emptyFees, emptyFeeRecipients);

    if (request.isERC1155) {
      assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity);
    } else {
      assertEq(erc721.ownerOf(TOKEN_ID), CURRENCY_OWNER);
    }
    assertEq(erc20.balanceOf(CURRENCY_OWNER), bals.currency - totalPrice - royalty, "currency");
    assertEq(erc20.balanceOf(recipient), balRecipient + totalPrice, "recipient");
    assertEq(erc20.balanceOf(ROYALTY_RECIPIENT), bals.royal + royalty, "royalty");

    return requestId;
  }

  function test_acceptOffer(RequestParams memory request, address recipient) external {
    acceptOffer(request, recipient);
  }

  function test_acceptOffer_additionalFees(RequestParams memory request, uint256[] memory additionalFees) external {
    _fixRequest(request, false);

    uint256 totalPrice = request.pricePerToken * request.quantity;
    uint256 royalty = (totalPrice * ROYALTY_FEE) / 10_000;

    if (additionalFees.length > 3) {
      // Cap at 3 fees
      assembly {
        mstore(additionalFees, 3)
      }
    }
    address[] memory additionalFeeRecipients = new address[](additionalFees.length);
    uint256 totalFees;
    for (uint256 i; i < additionalFees.length; i++) {
      additionalFeeRecipients[i] = FEE_RECIPIENT;
      additionalFees[i] = bound(additionalFees[i], 1, 0.2 ether);
      totalFees += additionalFees[i];
    }
    vm.assume((totalFees + royalty) < totalPrice);

    uint256 erc20BalCurrency = erc20.balanceOf(CURRENCY_OWNER);
    uint256 erc20BalTokenOwner = erc20.balanceOf(TOKEN_OWNER);
    uint256 erc20BalRoyal = erc20.balanceOf(ROYALTY_RECIPIENT);

    uint256 requestId = createOffer(request);

    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestId, TOKEN_OWNER, request.tokenContract, TOKEN_OWNER, request.quantity, 0);
    vm.prank(TOKEN_OWNER);
    market.acceptRequest(requestId, request.quantity, TOKEN_OWNER, additionalFees, additionalFeeRecipients);

    if (request.isERC1155) {
      assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity);
    } else {
      assertEq(erc721.ownerOf(TOKEN_ID), CURRENCY_OWNER);
    }
    assertEq(erc20.balanceOf(CURRENCY_OWNER), erc20BalCurrency - totalPrice - royalty);
    assertEq(erc20.balanceOf(FEE_RECIPIENT), totalFees); // Assume no starting value
    // Fees paid by taker
    assertEq(erc20.balanceOf(TOKEN_OWNER), erc20BalTokenOwner + totalPrice - totalFees);
    assertEq(erc20.balanceOf(ROYALTY_RECIPIENT), erc20BalRoyal + royalty);
  }

  function test_acceptOffer_invalidAdditionalFees(RequestParams memory params) external {
    uint256 requestId = createOffer(params);

    // Zero fee
    uint256[] memory additionalFees = new uint256[](1);
    address[] memory additionalFeeRecipients = new address[](1);
    additionalFeeRecipients[0] = FEE_RECIPIENT;
    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidAdditionalFees.selector);
    market.acceptRequest(requestId, 1, TOKEN_OWNER, additionalFees, additionalFeeRecipients);

    // Fee exceeds cost
    Request memory request = market.getRequest(requestId);
    additionalFees[0] = request.pricePerToken * request.quantity + 1;
    vm.prank(TOKEN_OWNER);
    vm.expectRevert(stdError.arithmeticError);
    market.acceptRequest(requestId, request.quantity, TOKEN_OWNER, additionalFees, additionalFeeRecipients);

    // Zero address
    additionalFees[0] = 1 ether;
    additionalFeeRecipients[0] = address(0);
    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidAdditionalFees.selector);
    market.acceptRequest(requestId, 1, TOKEN_OWNER, additionalFees, additionalFeeRecipients);

    // Invalid length (larger recipients)
    additionalFeeRecipients = new address[](2);
    additionalFeeRecipients[0] = FEE_RECIPIENT;
    additionalFeeRecipients[1] = FEE_RECIPIENT;
    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidAdditionalFees.selector);
    market.acceptRequest(requestId, 1, TOKEN_OWNER, additionalFees, additionalFeeRecipients);

    // Invalid length (larger fees)
    additionalFees = new uint256[](3);
    additionalFees[0] = 1;
    additionalFees[1] = 2;
    additionalFees[2] = 3;
    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidAdditionalFees.selector);
    market.acceptRequest(requestId, 1, TOKEN_OWNER, additionalFees, additionalFeeRecipients);
  }

  function test_acceptOffer_invalidRoyalties(RequestParams memory request) external {
    _fixRequest(request, false);
    vm.assume(request.pricePerToken > 10_000); // Ensure rounding
    uint256 requestId = createOffer(request);

    // >100%
    if (request.isERC1155) {
      erc1155.setFee(10_001);
    } else {
      erc721.setFee(10_001);
    }
    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidRoyalty.selector);
    market.acceptRequest(requestId, 1, TOKEN_OWNER, emptyFees, emptyFeeRecipients);

    // 100% is ok
    if (request.isERC1155) {
      erc1155.setFee(10_000);
    } else {
      erc721.setFee(10_000);
    }
    vm.prank(TOKEN_OWNER);
    market.acceptRequest(requestId, 1, TOKEN_OWNER, emptyFees, emptyFeeRecipients);
  }

  function test_acceptOffer_invalidQuantity_zero(RequestParams memory request) external {
    uint256 requestId = createOffer(request);

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidQuantity.selector);
    market.acceptRequest(requestId, 0, TOKEN_OWNER, emptyFees, emptyFeeRecipients);
  }

  function test_acceptOffer_invalidQuantity_tooHigh(RequestParams memory request) external {
    uint256 requestId = createOffer(request);

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidQuantity.selector);
    market.acceptRequest(requestId, request.quantity + 1, TOKEN_OWNER, emptyFees, emptyFeeRecipients);
  }

  function test_acceptOffer_invalidExpiry(RequestParams memory request, bool over) external {
    uint256 requestId = createOffer(request);

    vm.warp(request.expiry + (over ? 1 : 0));

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidExpiry.selector);
    market.acceptRequest(requestId, request.quantity, TOKEN_OWNER, emptyFees, emptyFeeRecipients);
  }

  function test_acceptOffer_invalidated(RequestParams memory params1, RequestParams memory params2) external {
    uint256 requestId1 = createOffer(params1);
    uint256 requestId2 = createOffer(params2);
    uint256 requestId3 = createListing(params1);

    vm.prank(CURRENCY_OWNER);
    market.invalidateRequests();

    (bool valid,) = market.isRequestValid(requestId1, 1);
    assertFalse(valid);
    (valid,) = market.isRequestValid(requestId2, 1);
    assertFalse(valid);
    (valid,) = market.isRequestValid(requestId3, 1);
    assertTrue(valid); // Unaffected

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(Invalidated.selector);
    market.acceptRequest(requestId1, 1, TOKEN_OWNER, emptyFees, emptyFeeRecipients);
    vm.prank(TOKEN_OWNER);
    vm.expectRevert(Invalidated.selector);
    market.acceptRequest(requestId2, 1, TOKEN_OWNER, emptyFees, emptyFeeRecipients);

    // Next request valid
    requestId1 = createOffer(params1);
    uint256 msgVal = params1.currency == address(0) ? params1.pricePerToken : 0;
    vm.prank(TOKEN_OWNER);
    market.acceptRequest{value: msgVal}(requestId1, 1, TOKEN_OWNER, emptyFees, emptyFeeRecipients);
  }

  function test_acceptOffer_twice(RequestParams memory request) external {
    request.isERC1155 = true;
    _fixRequest(request, false);

    // Cater for rounding error with / 2 * 2
    request.quantity = (request.quantity / 2) * 2;
    if (request.quantity == 0) {
      request.quantity = 2;
    }
    uint256 totalPrice = request.pricePerToken * request.quantity;
    uint256 royalty = (totalPrice * ROYALTY_FEE) / 10_000 / 2 * 2;

    uint256 erc20BalCurrency = erc20.balanceOf(CURRENCY_OWNER);
    uint256 erc20BalTokenOwner = erc20.balanceOf(TOKEN_OWNER);
    uint256 erc20BalRoyal = erc20.balanceOf(ROYALTY_RECIPIENT);

    uint256 requestId = createOffer(request);

    vm.startPrank(TOKEN_OWNER);
    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestId, TOKEN_OWNER, address(erc1155), TOKEN_OWNER, request.quantity / 2, request.quantity / 2);
    market.acceptRequest(requestId, request.quantity / 2, TOKEN_OWNER, emptyFees, emptyFeeRecipients);
    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestId, TOKEN_OWNER, address(erc1155), TOKEN_OWNER, request.quantity / 2, 0);
    market.acceptRequest(requestId, request.quantity / 2, TOKEN_OWNER, emptyFees, emptyFeeRecipients);
    vm.stopPrank();

    assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity);
    assertEq(erc20.balanceOf(CURRENCY_OWNER), erc20BalCurrency - totalPrice - royalty);
    assertEq(erc20.balanceOf(TOKEN_OWNER), erc20BalTokenOwner + totalPrice);
    assertEq(erc20.balanceOf(ROYALTY_RECIPIENT), erc20BalRoyal + royalty);
  }

  function test_acceptOfferBatch_repeat(RequestParams memory request) external {
    // Potential exploit of royalty rounding.
    request.isERC1155 = true;
    _fixRequest(request, true);

    uint256 totalPrice = request.pricePerToken * request.quantity;
    uint256 royalty = ((request.pricePerToken * ROYALTY_FEE) / 10_000) * request.quantity;

    uint256 erc20BalCurrency = erc20.balanceOf(CURRENCY_OWNER);
    uint256 erc20BalTokenOwner = erc20.balanceOf(TOKEN_OWNER);
    uint256 erc20BalRoyal = erc20.balanceOf(ROYALTY_RECIPIENT);

    uint256 requestId = createOffer(request);
    uint256[] memory requestIds = new uint256[](request.quantity);
    uint256[] memory quantities = new uint256[](request.quantity);
    address[] memory recipients = new address[](request.quantity);

    for (uint256 i; i < request.quantity; i++) {
      requestIds[i] = requestId;
      quantities[i] = 1;
      recipients[i] = TOKEN_OWNER;
    }

    vm.prank(TOKEN_OWNER);
    market.acceptRequestBatch(requestIds, quantities, recipients, emptyFees, emptyFeeRecipients);

    assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity);
    assertEq(erc20.balanceOf(CURRENCY_OWNER), erc20BalCurrency - totalPrice - royalty);
    assertEq(erc20.balanceOf(TOKEN_OWNER), erc20BalTokenOwner + totalPrice);
    assertEq(erc20.balanceOf(ROYALTY_RECIPIENT), erc20BalRoyal + royalty);
  }

  function test_acceptOffer_twice_overQuantity(RequestParams memory request) external {
    request.isERC1155 = true;

    uint256 requestId = acceptOffer(request, TOKEN_OWNER);

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidRequestId.selector, requestId));
    market.acceptRequest(requestId, 1, TOKEN_OWNER, emptyFees, emptyFeeRecipients);
  }

  function test_acceptOffer_noFunds(RequestParams memory request) external {
    uint256 requestId = createOffer(request);

    uint256 bal = erc20.balanceOf(CURRENCY_OWNER);
    vm.prank(CURRENCY_OWNER);
    erc20.transfer(TOKEN_OWNER, bal);

    vm.prank(TOKEN_OWNER);
    vm.expectRevert("TransferHelper::transferFrom: transferFrom failed");
    market.acceptRequest(requestId, request.quantity, TOKEN_OWNER, emptyFees, emptyFeeRecipients);
  }

  function test_acceptOffer_invalidERC721Owner(RequestParams memory request) external {
    request.isERC1155 = false;

    uint256 requestId = createOffer(request);

    vm.prank(TOKEN_OWNER);
    erc721.transferFrom(TOKEN_OWNER, CURRENCY_OWNER, TOKEN_ID);

    vm.prank(TOKEN_OWNER);
    vm.expectRevert("ERC721: caller is not token owner or approved");
    market.acceptRequest(requestId, 1, TOKEN_OWNER, emptyFees, emptyFeeRecipients);
  }

  //
  // Cancel Offer
  //
  function cancelOffer(RequestParams memory request) internal returns (uint256 requestId) {
    requestId = createOffer(request);

    // Fails invalid sender
    vm.expectRevert(abi.encodeWithSelector(InvalidRequestId.selector, requestId));
    market.cancelRequest(requestId);

    // Succeeds correct sender
    vm.expectEmit(true, true, true, true, address(market));
    emit RequestCancelled(requestId, request.tokenContract);
    vm.prank(CURRENCY_OWNER);
    market.cancelRequest(requestId);

    Request memory offer = market.getRequest(requestId);
    // Zero'd
    assertEq(offer.creator, address(0));
    assertEq(offer.tokenContract, address(0));
    assertEq(offer.tokenId, 0);
    assertEq(offer.quantity, 0);
    assertEq(offer.currency, address(0));
    assertEq(offer.pricePerToken, 0);
    assertEq(offer.expiry, 0);

    // Accept fails
    vm.prank(TOKEN_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidRequestId.selector, requestId));
    market.acceptRequest(requestId, 1, TOKEN_OWNER, emptyFees, emptyFeeRecipients);

    return requestId;
  }

  function test_cancelOffer(RequestParams memory request) external {
    cancelOffer(request);
  }

  function test_cancelOffer_partialFill(RequestParams memory request) external returns (uint256 requestId) {
    request.isERC1155 = true;
    _fixRequest(request, false);
    if (request.quantity == 1) {
      // Ensure multiple available
      request.quantity++;
      _fixRequest(request, false);
    }
    requestId = createOffer(request);

    // Partial fill
    vm.prank(TOKEN_OWNER);
    market.acceptRequest(requestId, 1, TOKEN_OWNER, emptyFees, emptyFeeRecipients);

    // Succeeds correct sender
    vm.expectEmit(true, true, true, true, address(market));
    emit RequestCancelled(requestId, request.tokenContract);
    vm.prank(CURRENCY_OWNER);
    market.cancelRequest(requestId);

    Request memory offer = market.getRequest(requestId);
    // Zero'd
    assertEq(offer.creator, address(0));
    assertEq(offer.tokenContract, address(0));
    assertEq(offer.tokenId, 0);
    assertEq(offer.quantity, 0);
    assertEq(offer.currency, address(0));
    assertEq(offer.pricePerToken, 0);
    assertEq(offer.expiry, 0);

    // Accept fails
    vm.prank(TOKEN_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidRequestId.selector, requestId));
    market.acceptRequest(requestId, 1, TOKEN_OWNER, emptyFees, emptyFeeRecipients);

    return requestId;
  }

  //
  // Create Request Batch
  //
  function createRequestBatch(uint8 count, RequestParams[] memory input) internal returns (uint256[] memory requestIds) {
    count = count > 4 ? 4 : count;
    vm.assume(input.length >= count);
    RequestParams[] memory params = new RequestParams[](count);

    for (uint8 i; i < count; i++) {
      RequestParams memory request = input[i];
      _fixRequest(request, request.isListing);
      params[i] = request;
    }

    // Given token holder some currency so it can submit offers too
    erc20.mockMint(TOKEN_OWNER, CURRENCY_QUANTITY);
    vm.prank(TOKEN_OWNER);
    erc20.approve(address(market), CURRENCY_QUANTITY);

    // Emits
    for (uint256 i; i < count; i++) {
      vm.expectEmit(true, true, true, true, address(market));
      RequestParams memory request = params[i];
      emit RequestCreated(
        expectedNextRequestId,
        TOKEN_OWNER,
        request.tokenContract,
        request.tokenId,
        request.isListing,
        request.quantity,
        request.currency,
        request.pricePerToken,
        request.expiry
      );
      expectedNextRequestId++;
    }

    vm.prank(TOKEN_OWNER);
    requestIds = market.createRequestBatch(params);

    assertEq(requestIds.length, count);

    // Check requests
    Request[] memory requests = market.getRequestBatch(requestIds);
    assertEq(requests.length, count);
    for (uint256 i; i < count; i++) {
      Request memory request = requests[i];
      RequestParams memory param = params[i];
      assertEq(request.creator, TOKEN_OWNER);
      assertEq(request.isListing, param.isListing);
      assertEq(request.isERC1155, param.isERC1155);
      assertEq(request.tokenContract, param.tokenContract);
      assertEq(request.tokenId, param.tokenId);
      assertEq(request.quantity, param.quantity);
      assertEq(request.expiry, param.expiry);
      assertEq(request.currency, param.currency);
      assertEq(request.pricePerToken, param.pricePerToken);
    }

    return requestIds;
  }


  function test_createRequestBatch(uint8 count, RequestParams[] memory input) external {
    createRequestBatch(count, input);
  }

  //
  // Accept Request Batch
  //
  function test_acceptRequestBatch_fixed() external {
    erc20.mockMint(TOKEN_OWNER, CURRENCY_QUANTITY);
    vm.prank(TOKEN_OWNER);
    erc20.approve(address(market), CURRENCY_QUANTITY);

    RequestParams memory request = RequestParams({
      isListing: true,
      isERC1155: true,
      tokenContract: address(erc1155),
      tokenId: TOKEN_ID,
      quantity: 1,
      currency: address(erc20),
      pricePerToken: 1,
      expiry: uint96(block.timestamp)
    });

    uint256[] memory requestIds = new uint256[](4);
    request.isERC1155 = true;
    requestIds[0] = createListing(request);
    request.isERC1155 = false;
    requestIds[1] = createListing(request);
    request.isERC1155 = true;
    requestIds[2] = createOffer(request);
    request.isERC1155 = false;
    requestIds[3] = createOffer(request);

    uint256[] memory quantities = new uint256[](4);
    address[] memory recipients = new address[](4);
    for (uint256 i = 0; i < 4; i++) {
      quantities[i] = 1;
      recipients[i] = TOKEN_OWNER;
    }

    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestIds[0], TOKEN_OWNER, address(erc1155), TOKEN_OWNER, 1, 0);
    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestIds[1], TOKEN_OWNER, address(erc721), TOKEN_OWNER, 1, 0);
    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestIds[2], TOKEN_OWNER, address(erc1155), TOKEN_OWNER, 1, 0);
    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestIds[3], TOKEN_OWNER, address(erc721), TOKEN_OWNER, 1, 0);
    vm.prank(TOKEN_OWNER);
    market.acceptRequestBatch(requestIds, quantities, recipients, emptyFees, emptyFeeRecipients);
  }

  function test_acceptRequestBatch_fuzz(uint8 count, RequestParams[] memory input, uint8[] memory quantities) external {
    uint256[] memory requestIds = createRequestBatch(count, input);
    uint256 requestCount = requestIds.length;
    assembly {
      // Ensure array size is sufficient. 0s will be bound
      mstore(quantities, requestCount)
    }

    vm.startPrank(CURRENCY_OWNER);
    erc1155.setApprovalForAll(address(market), true);
    erc721.setApprovalForAll(address(market), true);
    erc20.approve(address(market), type(uint256).max);
    vm.stopPrank();

    for (uint256 i; i < requestCount; i++) {
      (bool valid, Request memory request) = market.isRequestValid(requestIds[i], 0);
      if (valid) {
        uint256 requestQuantity = request.quantity;

        // Check can accept
        if (request.isListing) {
          // Give enough currency to accept
          uint256 required = request.quantity * request.pricePerToken;
          erc20.mockMint(CURRENCY_OWNER, required);
        } else if (request.isERC1155) {
          // Give enough tokens to accept
          uint256[] memory tokenIds = new uint256[](1);
          tokenIds[0] = request.tokenId;
          uint256[] memory required = new uint256[](1);
          required[0] = request.quantity;
          erc1155.batchMintMock(CURRENCY_OWNER, tokenIds, required, "");
        } else if (erc721.ownerOf(request.tokenId) != CURRENCY_OWNER) {
          // Skip this. We don't fix it
          continue;
        }

        // Random valid quantity
        uint256 quantity = _bound(quantities[i], 1, request.quantity);

        vm.expectEmit(true, true, true, true, address(market));
        emit RequestAccepted(requestIds[i], CURRENCY_OWNER, request.tokenContract, CURRENCY_OWNER, quantity, requestQuantity - quantity);
        vm.prank(CURRENCY_OWNER);
        market.acceptRequest(requestIds[i], quantity, CURRENCY_OWNER, emptyFees, emptyFeeRecipients);
      }
    }
  }

  function test_acceptListingBatch(RequestParams memory request, address[] memory recipients) external {
    vm.assume(recipients.length > 1);
    vm.assume(recipients[0] != recipients[1]);
    assembly {
      mstore(recipients, 2)
    }
    _assumeNotPrecompile(recipients[0]);
    _assumeNotPrecompile(recipients[1]);
    vm.assume(erc1155.balanceOf(recipients[0], TOKEN_ID) == 0);
    vm.assume(erc1155.balanceOf(recipients[1], TOKEN_ID) == 0);

    request.isERC1155 = true;
    _fixRequest(request, false);

    // Prevent overflow
    request.pricePerToken /= 2;
    request.quantity /= 2;
    _fixRequest(request, false); // Fix values too low

    uint256 totalPrice2 = request.pricePerToken * request.quantity * 2;
    uint256 erc20BalCurrency = erc20.balanceOf(CURRENCY_OWNER);
    uint256 erc20BalTokenOwner = erc20.balanceOf(TOKEN_OWNER);
    uint256 erc20BalRoyal = erc20.balanceOf(ROYALTY_RECIPIENT);

    uint256[] memory requestIds = new uint256[](2);
    requestIds[0] = createListing(request);
    request.expiry++;
    requestIds[1] = createListing(request);

    uint256[] memory quantities = new uint256[](2);
    quantities[0] = request.quantity;
    quantities[1] = request.quantity;

    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestIds[0], CURRENCY_OWNER, address(erc1155), recipients[0], request.quantity, 0);
    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestIds[1], CURRENCY_OWNER, address(erc1155), recipients[1], request.quantity, 0);
    vm.startPrank(CURRENCY_OWNER);
    market.acceptRequestBatch(requestIds, quantities, recipients, emptyFees, emptyFeeRecipients);
    vm.stopPrank();

    uint256 royalty2 = (((totalPrice2 / 2) * ROYALTY_FEE) / 10_000) * 2; // Cater for rounding error

    assertEq(erc1155.balanceOf(recipients[0], TOKEN_ID), request.quantity);
    assertEq(erc1155.balanceOf(recipients[1], TOKEN_ID), request.quantity);
    assertEq(erc20.balanceOf(CURRENCY_OWNER), erc20BalCurrency - totalPrice2);
    assertEq(erc20.balanceOf(TOKEN_OWNER), erc20BalTokenOwner + totalPrice2 - royalty2);
    assertEq(erc20.balanceOf(ROYALTY_RECIPIENT), erc20BalRoyal + royalty2);
  }

  function test_acceptOfferBatch(RequestParams memory request, address[] memory recipients) external {
    vm.assume(recipients.length > 1);
    vm.assume(recipients[0] != recipients[1]);
    vm.assume(recipients[0] != CURRENCY_OWNER);
    vm.assume(recipients[0] != ROYALTY_RECIPIENT);
    vm.assume(recipients[1] != CURRENCY_OWNER);
    vm.assume(recipients[1] != ROYALTY_RECIPIENT);
    assembly {
      mstore(recipients, 2)
    }
    _assumeNotPrecompile(recipients[0]);
    _assumeNotPrecompile(recipients[1]);

    request.isERC1155 = true;
    _fixRequest(request, false);

    // Prevent overflow
    request.pricePerToken /= 2;
    request.quantity /= 2;
    _fixRequest(request, false); // Fix values too low

    uint256 totalPrice = request.pricePerToken * request.quantity;
    uint256 erc20BalCurrency = erc20.balanceOf(CURRENCY_OWNER);
    uint256 erc20BalTokenOwner = erc20.balanceOf(TOKEN_OWNER);
    uint256 erc20BalRoyal = erc20.balanceOf(ROYALTY_RECIPIENT);

    uint256[] memory requestIds = new uint256[](2);
    requestIds[0] = createOffer(request);
    request.expiry++;
    requestIds[1] = createOffer(request);

    uint256[] memory quantities = new uint256[](2);
    quantities[0] = request.quantity;
    quantities[1] = request.quantity;

    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestIds[0], TOKEN_OWNER, address(erc1155), recipients[0], request.quantity, 0);
    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestIds[1], TOKEN_OWNER, address(erc1155), recipients[1], request.quantity, 0);
    vm.startPrank(TOKEN_OWNER);
    market.acceptRequestBatch(requestIds, quantities, recipients, emptyFees, emptyFeeRecipients);
    vm.stopPrank();

    uint256 royalty2 = (totalPrice * ROYALTY_FEE) / 10_000 * 2;

    assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity * 2);
    assertEq(erc20.balanceOf(CURRENCY_OWNER), erc20BalCurrency - (totalPrice * 2) - royalty2);
    assertEq(erc20.balanceOf(recipients[0]), erc20BalTokenOwner + totalPrice);
    assertEq(erc20.balanceOf(recipients[1]), erc20BalTokenOwner + totalPrice);
    assertEq(erc20.balanceOf(ROYALTY_RECIPIENT), erc20BalRoyal + royalty2);
  }

  function test_acceptRequestBatch_invalidLengths(uint8 count, RequestParams[] memory input, uint256[] memory quantities, address[] memory recipients)
    external
  {
    count = count > 4 ? 4 : count;
    vm.assume(quantities.length != count);
    uint256[] memory requestIds = createRequestBatch(count, input);
    vm.assume(quantities.length != requestIds.length || recipients.length != requestIds.length);

    vm.expectRevert(InvalidBatchRequest.selector);
    market.acceptRequestBatch(requestIds, quantities, recipients, emptyFees, emptyFeeRecipients);
  }

  //
  // Cancel Request Batch
  //
  function test_cancelRequestBatch(uint8 count, RequestParams[] memory input) external {
    uint256[] memory requestIds = createRequestBatch(count, input);

    for (uint256 i; i < requestIds.length; i++) {
      Request memory request = market.getRequest(requestIds[i]);
      vm.expectEmit(true, true, true, true, address(market));
      emit RequestCancelled(requestIds[i], request.tokenContract);
    }

    vm.prank(TOKEN_OWNER);
    market.cancelRequestBatch(requestIds);

    for (uint256 i; i < requestIds.length; i++) {
      (bool valid, Request memory request) = market.isRequestValid(requestIds[i], 0);
      assertEq(request.creator, address(0));
      assertEq(request.tokenContract, address(0));
      assertEq(request.tokenId, 0);
      assertEq(request.quantity, 0);
      assertEq(request.currency, address(0));
      assertEq(request.pricePerToken, 0);
      assertEq(request.expiry, 0);
      assertEq(valid, false);
    }
  }

  function test_cancelRequestBatch_invalidCaller(uint8 count, RequestParams[] memory input) external {
    vm.assume(count > 1 && input.length > 1);
    uint256[] memory requestIds = createRequestBatch(count, input);

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidRequestId.selector, requestIds[0]));
    market.cancelRequestBatch(requestIds);

    // Created by CURRENCY_OWNER
    uint256 currencyRequestId = createOffer(input[0]);

    requestIds[1] = currencyRequestId;

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidRequestId.selector, currencyRequestId));
    market.cancelRequestBatch(requestIds);
  }

  //
  // Validity
  //
  function test_isRequestValid_expired() external {
    RequestParams memory request = RequestParams({
      isListing: true,
      isERC1155: true,
      tokenContract: address(erc1155),
      tokenId: TOKEN_ID,
      quantity: 1,
      currency: address(erc20),
      pricePerToken: 1 ether,
      expiry: uint96(block.timestamp + 1)
    });

    uint256[] memory requestIds = new uint256[](4);
    uint256[] memory quantities = new uint256[](4);

    requestIds[0] = createListing(request);

    request.isERC1155 = false;
    _fixRequest(request, true);
    requestIds[1] = createListing(request);

    _fixRequest(request, false);
    requestIds[2] = createOffer(request);

    request.isERC1155 = true;
    _fixRequest(request, false);
    requestIds[3] = createOffer(request);

    vm.warp(request.expiry + 5);

    bool[] memory valid;
    (valid,) = market.isRequestValidBatch(requestIds, quantities);
    for (uint256 i; i < 4; i++) {
      assertEq(valid[i], false);
    }
  }

  function test_isRequestValid_invalidApproval() external {
    RequestParams memory request = RequestParams({
      isListing: true,
      isERC1155: true,
      tokenContract: address(erc1155),
      tokenId: TOKEN_ID,
      quantity: 1,
      currency: address(erc20),
      pricePerToken: 1 ether,
      expiry: uint96(block.timestamp + 1)
    });

    uint256[] memory requestIds = new uint256[](4);
    uint256[] memory quantities = new uint256[](4);

    requestIds[0] = createListing(request);

    request.isERC1155 = false;
    _fixRequest(request, true);
    requestIds[1] = createListing(request);

    _fixRequest(request, false);
    requestIds[2] = createOffer(request);

    request.isERC1155 = true;
    _fixRequest(request, false);
    requestIds[3] = createOffer(request);

    vm.startPrank(TOKEN_OWNER);
    erc1155.setApprovalForAll(address(market), false);
    erc721.setApprovalForAll(address(market), false);
    vm.stopPrank();
    vm.prank(CURRENCY_OWNER);
    erc20.approve(address(market), 0);

    (bool[] memory valid,) = market.isRequestValidBatch(requestIds, quantities);
    for (uint256 i; i < 4; i++) {
      assertEq(valid[i], false);
    }
  }

  function test_isRequestValid_partialValidity() external {
    RequestParams memory request = RequestParams({
      isListing: false,
      isERC1155: true,
      tokenContract: address(erc1155),
      tokenId: TOKEN_ID,
      quantity: 10,
      currency: address(erc20),
      pricePerToken: 1 ether,
      expiry: uint96(block.timestamp + 1)
    });

    vm.prank(CURRENCY_OWNER);
    uint256 requestId = market.createRequest(request);

    vm.prank(CURRENCY_OWNER);
    erc20.approve(address(market), 2 ether);

    erc1155.setFee(0); // Ignore royalty

    (bool valid,) = market.isRequestValid(requestId, 0);
    assertEq(valid, false); // Not valid for all tokens

    (valid,) = market.isRequestValid(requestId, 1);
    assertEq(valid, true);
    (valid,) = market.isRequestValid(requestId, 2);
    assertEq(valid, true);
    for (uint256 i = 3; i < 15; i++) {
      // Invalid due to approval or over quantity
      (valid,) = market.isRequestValid(requestId, i);
      assertEq(valid, false);
    }
  }

  function test_isRequestValid_royaltyInvalid() external {
    RequestParams memory request = RequestParams({
      isListing: false,
      isERC1155: true,
      tokenContract: address(erc1155),
      tokenId: TOKEN_ID,
      quantity: 10,
      currency: address(erc20),
      pricePerToken: 1 ether,
      expiry: uint96(block.timestamp + 1)
    });

    vm.prank(CURRENCY_OWNER);
    uint256 requestId = market.createRequest(request);

    vm.prank(CURRENCY_OWNER);
    erc20.approve(address(market), request.pricePerToken * request.quantity); // Exact amount
    erc1155.setFee(10_000); // 100% royalty. Now half will be valid due to royalty fee

    (bool valid,) = market.isRequestValid(requestId, 0);
    assertEq(valid, false);
    for (uint256 i = 1; i < 6; i++) {
      (valid,) = market.isRequestValid(requestId, i);
      assertEq(valid, true);
    }
    for (uint256 i = 6; i < 11; i++) {
      (valid,) = market.isRequestValid(requestId, i);
      assertEq(valid, false);
    }
  }

  function test_isRequestValid_invalidBalance() external {
    RequestParams memory request = RequestParams({
      isListing: true,
      isERC1155: true,
      tokenContract: address(erc1155),
      tokenId: TOKEN_ID,
      quantity: 1,
      currency: address(erc20),
      pricePerToken: 1 ether,
      expiry: uint96(block.timestamp + 1)
    });

    uint256[] memory requestIds = new uint256[](4);
    uint256[] memory quantities = new uint256[](4);

    requestIds[0] = createListing(request);

    request.isERC1155 = false;
    _fixRequest(request, true);
    requestIds[1] = createListing(request);

    _fixRequest(request, false);
    requestIds[2] = createOffer(request);

    request.isERC1155 = true;
    _fixRequest(request, false);
    requestIds[3] = createOffer(request);

    // Use fee recipient as a "random" address
    vm.startPrank(TOKEN_OWNER);
    erc1155.safeTransferFrom(TOKEN_OWNER, FEE_RECIPIENT, TOKEN_ID, erc1155.balanceOf(TOKEN_OWNER, TOKEN_ID), "");
    erc721.transferFrom(TOKEN_OWNER, FEE_RECIPIENT, TOKEN_ID);
    vm.stopPrank();
    vm.startPrank(CURRENCY_OWNER);
    erc20.transfer(FEE_RECIPIENT, CURRENCY_QUANTITY);
    assertEq(erc20.balanceOf(CURRENCY_OWNER), 0);
    vm.stopPrank();

    (bool[] memory valid,) = market.isRequestValidBatch(requestIds, quantities);
    for (uint256 i; i < 4; i++) {
      assertEq(valid[i], false);
    }
  }

  function test_isRequestValid_bulk(uint8 count, RequestParams[] memory requests, bool[] memory expectValid) external {
    count = count > 4 ? 4 : count;
    vm.assume(requests.length >= count);
    assembly {
      // Bound sizes (default to false when array is smaller)
      mstore(expectValid, count)
    }

    uint256[] memory requestIds = new uint256[](count);
    uint256[] memory quantities = new uint256[](count);
    for (uint8 i; i < count; i++) {
      RequestParams memory request = requests[i];
      _fixRequest(request, request.isListing);
      if (request.isListing) {
        requestIds[i] = expectValid[i] ? createListing(request) : cancelListing(request);
      } else {
        requestIds[i] = expectValid[i] ? createOffer(request) : cancelOffer(request);
      }
    }

    (bool[] memory valid,) = market.isRequestValidBatch(requestIds, quantities);
    assertEq(valid.length, count);
    for (uint256 i; i < count; i++) {
      assertEq(valid[i], expectValid[i]);
    }
  }

  //
  // Royalty
  //
  function test_getRoyaltyInfo_defaultZero() external {
    // New erc721 that doesn't have royalties
    ERC721Mock erc721Mock = new ERC721Mock();

    (address recipient, uint256 royalty) = market.getRoyaltyInfo(address(erc721Mock), 1, 1 ether);

    assertEq(recipient, address(0));
    assertEq(royalty, 0);
  }

  function test_getRoyaltyInfo_overridden(bool isERC1155, uint96 fee, address recipient) external {
    address tokenContract;
    // These do not support ERC-2981
    if (isERC1155) {
      tokenContract = address(new ERC1155MintBurnMock("", ""));
    } else {
      tokenContract = address(new ERC721Mock());
    }
    fee = uint96(_bound(fee, 1, 10000));

    vm.expectEmit();
    emit CustomRoyaltyChanged(tokenContract, recipient, fee);
    vm.prank(MARKET_OWNER);
    market.setRoyaltyInfo(tokenContract, recipient, fee);

    (address actualR, uint256 actualF) = market.getRoyaltyInfo(tokenContract, 1, 10000);

    assertEq(actualR, recipient);
    assertEq(actualF, uint256(fee));
  }

  function test_getRoyaltyInfo_notOverridden(bool isERC1155, uint96 fee, address recipient) external {
    // Not overriden when the contract supports ERC-2981
    address tokenContract = isERC1155 ? address(erc1155) : address(erc721);
    fee = uint96(_bound(fee, 1, 10000));

    // This still emits
    vm.expectEmit();
    emit CustomRoyaltyChanged(tokenContract, recipient, fee);
    vm.prank(MARKET_OWNER);
    market.setRoyaltyInfo(tokenContract, recipient, fee);

    (address actualR, uint256 actualF) = market.getRoyaltyInfo(tokenContract, 1, 10000);

    // Expect token royalty values set above
    (address expectedR, uint256 expectedF) = IERC2981(tokenContract).royaltyInfo(1, 10000);
    assertEq(actualR, expectedR);
    assertEq(actualF, expectedF);
  }

  function test_setRoyaltyInfo_invalidCaller(address caller, address tokenContract, uint96 fee, address recipient) external {
    vm.assume(caller != MARKET_OWNER);

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(caller);
    market.setRoyaltyInfo(tokenContract, recipient, fee);
  }

  //
  // Helpers
  //

  function _fixRequest(RequestParams memory request, bool isListing) private view {
    request.isListing = isListing;
    request.tokenContract = request.isERC1155 ? address(erc1155) : address(erc721);
    request.tokenId = TOKEN_ID;
    request.currency = isListing && request.currency == address(0) ? address(0) : address(erc20);
    request.pricePerToken = _bound(request.pricePerToken, 1, 1 ether);
    request.expiry = uint96(_bound(uint256(request.expiry), block.timestamp + 1, type(uint96).max - 100));

    if (request.isERC1155) {
      request.quantity = _bound(request.quantity, 1, TOKEN_QUANTITY);
    } else {
      request.quantity = 1;
    }

    vm.assume((request.quantity * request.pricePerToken) <= CURRENCY_QUANTITY / 10);
  }

  function _assumeNotPrecompile(address addr) internal view {
    vm.assume(addr != address(0));
    vm.assume(addr.code.length <= 2);
    assumeNotPrecompile(addr);
    assumeNotForgeAddress(addr);
  }
}
