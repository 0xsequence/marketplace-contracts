// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import {Orderbook} from "contracts/Orderbook.sol";
import {IOrderbookSignals, IOrderbookStorage} from "contracts/interfaces/IOrderbook.sol";
import {ERC1155RoyaltyMock} from "./mocks/ERC1155RoyaltyMock.sol";
import {ERC721RoyaltyMock} from "./mocks/ERC721RoyaltyMock.sol";
import {ERC20TokenMock} from "./mocks/ERC20TokenMock.sol";
import {IERC1155TokenReceiver} from "0xsequence/erc-1155/src/contracts/interfaces/IERC1155TokenReceiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

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
  address private immutable _orderbook;

  uint256 private _orderId;
  uint256 private _quantity;
  bool private _hasAttacked;

  constructor(address orderbook) {
    _orderbook = orderbook;
  }

  function acceptListing(uint256 orderId, uint256 quantity) external {
    _orderId = orderId;
    _quantity = quantity;
    Orderbook(_orderbook).acceptOrder(_orderId, _quantity, new uint256[](0), new address[](0));
  }

  function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4) {
    if (_hasAttacked) {
      // Done
      _hasAttacked = false;
      return IERC1155TokenReceiver.onERC1155Received.selector;
    }
    // Attack the orderbook
    _hasAttacked = true;
    Orderbook(_orderbook).acceptOrder(_orderId, _quantity, new uint256[](0), new address[](0));
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

contract OrderbookTest is IOrderbookSignals, IOrderbookStorage, ReentrancyGuard, Test {
  Orderbook private orderbook;
  ERC1155RoyaltyMock private erc1155;
  ERC721RoyaltyMock private erc721;
  ERC20TokenMock private erc20;

  uint256 private constant TOKEN_ID = 1;
  uint256 private constant TOKEN_QUANTITY = 100;
  uint256 private constant CURRENCY_QUANTITY = 1000 ether;

  uint256 private constant ROYALTY_FEE = 200; // 2%

  address private constant ORDERBOOK_OWNER = address(uint160(uint256(keccak256("orderbook_owner"))));
  address private constant TOKEN_OWNER = address(uint160(uint256(keccak256("token_owner"))));
  address private constant CURRENCY_OWNER = address(uint160(uint256(keccak256("currency_owner"))));
  address private constant ROYALTY_RECEIVER = address(uint160(uint256(keccak256("royalty_receiver"))));
  address private constant FEE_RECEIVER = address(uint160(uint256(keccak256("fee_receiver"))));

  uint256[] private emptyFees;
  address[] private emptyFeeReceivers;

  uint256 private expectedNextOrderId;

  function setUp() external {
    orderbook = new Orderbook(ORDERBOOK_OWNER);
    erc1155 = new ERC1155RoyaltyMock();
    erc721 = new ERC721RoyaltyMock();
    erc20 = new ERC20TokenMock();

    vm.label(TOKEN_OWNER, "token_owner");
    vm.label(CURRENCY_OWNER, "currency_owner");

    expectedNextOrderId = 0;

    // Mint tokens
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = TOKEN_ID;
    uint256[] memory quantities = new uint256[](1);
    quantities[0] = TOKEN_QUANTITY;
    erc1155.batchMintMock(TOKEN_OWNER, tokenIds, quantities, "");

    erc721.mintMock(TOKEN_OWNER, TOKEN_QUANTITY);

    erc20.mockMint(CURRENCY_OWNER, CURRENCY_QUANTITY);

    // Approvals
    vm.startPrank(TOKEN_OWNER);
    erc1155.setApprovalForAll(address(orderbook), true);
    erc721.setApprovalForAll(address(orderbook), true);
    vm.stopPrank();
    vm.prank(CURRENCY_OWNER);
    erc20.approve(address(orderbook), CURRENCY_QUANTITY);

    // Royalty
    erc1155.setFee(ROYALTY_FEE);
    erc1155.setFeeRecipient(ROYALTY_RECEIVER);
    erc721.setFee(ROYALTY_FEE);
    erc721.setFeeRecipient(ROYALTY_RECEIVER);
  }

  //
  // Common Create Order
  //
  function test_createOrder_interfaceInvalid(OrderRequest memory request, address invalidAddr)
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
    orderbook.createOrder(request);
  }

  //
  // Create Listing
  //

  // This is tested and fuzzed through internal calls
  function test_createListing(OrderRequest memory request) internal returns (uint256 orderId) {
    _fixRequest(request, true);

    Order memory expected = Order({
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

    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderCreated(
      expectedNextOrderId,
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
    orderId = orderbook.createOrder(request);
    expectedNextOrderId++;

    Order memory listing = orderbook.getOrder(orderId);
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

    return orderId;
  }

  function test_createListing_invalidToken(OrderRequest memory request, address badContract) external {
    vm.assume(badContract != address(erc1155) && badContract != address(erc721));
    _assumeNotPrecompile(badContract);
    _fixRequest(request, true);
    request.tokenContract = badContract;

    vm.prank(TOKEN_OWNER);
    vm.expectRevert();
    orderbook.createOrder(request);
  }

  function test_createListing_invalidExpiry(OrderRequest memory request, uint96 expiry) external {
    vm.assume(expiry <= block.timestamp);
    _fixRequest(request, true);
    request.expiry = expiry;

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidExpiry.selector);
    orderbook.createOrder(request);
  }

  function test_createListing_invalidQuantity_erc721(OrderRequest memory request, uint256 quantity) external {
    vm.assume(quantity != 1);
    request.isERC1155 = false;
    _fixRequest(request, true);
    request.quantity = quantity;

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(
      abi.encodeWithSelector(InvalidTokenApproval.selector, address(erc721), TOKEN_ID, quantity, TOKEN_OWNER)
    );
    orderbook.createOrder(request);
  }

  function test_createListing_invalidQuantity_erc1155(OrderRequest memory request, uint256 quantity) external {
    vm.assume(quantity > TOKEN_QUANTITY || quantity == 0);
    request.isERC1155 = true;
    _fixRequest(request, true);
    request.quantity = quantity;

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(
      abi.encodeWithSelector(InvalidTokenApproval.selector, address(erc1155), TOKEN_ID, quantity, TOKEN_OWNER)
    );
    orderbook.createOrder(request);
  }

  function test_createListing_invalidPrice(OrderRequest memory request) external {
    _fixRequest(request, true);
    request.pricePerToken = 0;

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidPrice.selector);
    orderbook.createOrder(request);
  }

  function test_createListing_erc1155_noToken(OrderRequest memory request, uint256 tokenId) external {
    request.isERC1155 = true;
    _fixRequest(request, true);
    request.tokenId = tokenId;

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(
      abi.encodeWithSelector(InvalidTokenApproval.selector, address(erc1155), tokenId, request.quantity, CURRENCY_OWNER)
    );
    orderbook.createOrder(request);
  }

  function test_createListing_erc1155_invalidApproval(OrderRequest memory request) external {
    request.isERC1155 = true;
    _fixRequest(request, true);

    vm.prank(TOKEN_OWNER);
    erc1155.setApprovalForAll(address(orderbook), false);

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(
      abi.encodeWithSelector(InvalidTokenApproval.selector, address(erc1155), TOKEN_ID, request.quantity, TOKEN_OWNER)
    );
    orderbook.createOrder(request);
  }

  function test_createListing_erc721_noToken(OrderRequest memory request, uint256 tokenId) external {
    request.isERC1155 = false;
    _fixRequest(request, true);
    request.tokenId = tokenId;

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidTokenApproval.selector, address(erc721), tokenId, 1, CURRENCY_OWNER));
    orderbook.createOrder(request);
  }

  function test_createListing_erc721_invalidApproval(OrderRequest memory request) external {
    request.isERC1155 = false;
    _fixRequest(request, true);

    vm.prank(TOKEN_OWNER);
    erc721.setApprovalForAll(address(orderbook), false);

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidTokenApproval.selector, address(erc721), TOKEN_ID, 1, TOKEN_OWNER));
    orderbook.createOrder(request);
  }

  //
  // Accept Listing
  //
  function test_acceptListing(OrderRequest memory request) public returns (uint256 orderId) {
    uint256 erc20BalCurrency = erc20.balanceOf(CURRENCY_OWNER);
    uint256 erc20BalTokenOwner = erc20.balanceOf(TOKEN_OWNER);
    uint256 erc20BalRoyal = erc20.balanceOf(ROYALTY_RECEIVER);

    orderId = test_createListing(request);

    uint256 totalPrice = request.pricePerToken * request.quantity;
    uint256 royalty = (totalPrice * ROYALTY_FEE) / 10_000;

    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderAccepted(orderId, CURRENCY_OWNER, request.tokenContract, request.quantity, 0);
    vm.prank(CURRENCY_OWNER);
    orderbook.acceptOrder(orderId, request.quantity, emptyFees, emptyFeeReceivers);

    if (request.isERC1155) {
      assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity);
    } else {
      assertEq(erc721.ownerOf(TOKEN_ID), CURRENCY_OWNER);
    }
    assertEq(erc20.balanceOf(CURRENCY_OWNER), erc20BalCurrency - totalPrice);
    assertEq(erc20.balanceOf(TOKEN_OWNER), erc20BalTokenOwner + totalPrice - royalty);
    assertEq(erc20.balanceOf(ROYALTY_RECEIVER), erc20BalRoyal + royalty);

    return orderId;
  }

  function test_acceptListing_additionalFees(OrderRequest memory request, uint256[] memory additionalFees) public {
    _fixRequest(request, true);

    uint256 totalPrice = request.pricePerToken * request.quantity;
    uint256 royalty = (totalPrice * ROYALTY_FEE) / 10_000;

    if (additionalFees.length > 3) {
      // Cap at 3 fees
      assembly {
        mstore(additionalFees, 3)
      }
    }
    address[] memory additionalFeeReceivers = new address[](additionalFees.length);
    uint256 totalFees;
    for (uint256 i; i < additionalFees.length; i++) {
      additionalFeeReceivers[i] = FEE_RECEIVER;
      additionalFees[i] = bound(additionalFees[i], 1, 0.2 ether);
      totalFees += additionalFees[i];
    }
    vm.assume((totalFees + royalty) < totalPrice);

    uint256 erc20BalCurrency = erc20.balanceOf(CURRENCY_OWNER);
    uint256 erc20BalTokenOwner = erc20.balanceOf(TOKEN_OWNER);
    uint256 erc20BalRoyal = erc20.balanceOf(ROYALTY_RECEIVER);

    uint256 orderId = test_createListing(request);

    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderAccepted(orderId, CURRENCY_OWNER, request.tokenContract, request.quantity, 0);
    vm.prank(CURRENCY_OWNER);
    orderbook.acceptOrder(orderId, request.quantity, additionalFees, additionalFeeReceivers);

    if (request.isERC1155) {
      assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity);
    } else {
      assertEq(erc721.ownerOf(TOKEN_ID), CURRENCY_OWNER);
    }
    // Fees paid by taker
    assertEq(erc20.balanceOf(CURRENCY_OWNER), erc20BalCurrency - totalPrice - totalFees);
    assertEq(erc20.balanceOf(FEE_RECEIVER), totalFees); // Assume no starting value
    assertEq(erc20.balanceOf(TOKEN_OWNER), erc20BalTokenOwner + totalPrice - royalty);
    assertEq(erc20.balanceOf(ROYALTY_RECEIVER), erc20BalRoyal + royalty);
  }

  function test_acceptListing_invalidAdditionalFees(OrderRequest memory request) external {
    uint256 orderId = test_createListing(request);

    // Zero fee
    uint256[] memory additionalFees = new uint256[](1);
    address[] memory additionalFeeReceivers = new address[](1);
    additionalFeeReceivers[0] = FEE_RECEIVER;
    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidAdditionalFees.selector);
    orderbook.acceptOrder(orderId, 1, additionalFees, additionalFeeReceivers);

    // Fee exceeds cost
    Order memory order = orderbook.getOrder(orderId);
    additionalFees[0] = order.pricePerToken * order.quantity + 1;
    vm.expectRevert(InvalidAdditionalFees.selector);
    vm.prank(CURRENCY_OWNER);
    orderbook.acceptOrder(orderId, order.quantity, additionalFees, additionalFeeReceivers);

    // Zero address
    additionalFees[0] = 1 ether;
    additionalFeeReceivers[0] = address(0);
    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidAdditionalFees.selector);
    orderbook.acceptOrder(orderId, 1, additionalFees, additionalFeeReceivers);

    // Invalid length (larger receivers)
    additionalFeeReceivers = new address[](2);
    additionalFeeReceivers[0] = FEE_RECEIVER;
    additionalFeeReceivers[1] = FEE_RECEIVER;
    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidAdditionalFees.selector);
    orderbook.acceptOrder(orderId, 1, additionalFees, additionalFeeReceivers);

    // Invalid length (larger fees)
    additionalFees = new uint256[](3);
    additionalFees[0] = 1;
    additionalFees[1] = 2;
    additionalFees[2] = 3;
    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidAdditionalFees.selector);
    orderbook.acceptOrder(orderId, 1, additionalFees, additionalFeeReceivers);
  }

  function test_acceptListing_invalidRoyalties(OrderRequest memory request) external {
    _fixRequest(request, true);
    vm.assume(request.pricePerToken > 10_000); // Ensure rounding
    uint256 orderId = test_createListing(request);

    // >100%
    if (request.isERC1155) {
      erc1155.setFee(10_001);
    } else {
      erc721.setFee(10_001);
    }
    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(stdError.arithmeticError);
    orderbook.acceptOrder(orderId, 1, emptyFees, emptyFeeReceivers);

    // 100% is ok
    if (request.isERC1155) {
      erc1155.setFee(10_000);
    } else {
      erc721.setFee(10_000);
    }
    vm.prank(CURRENCY_OWNER);
    orderbook.acceptOrder(orderId, 1, emptyFees, emptyFeeReceivers);
  }

  function test_acceptListing_invalidQuantity_zero(OrderRequest memory request) external {
    uint256 orderId = test_createListing(request);

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidQuantity.selector);
    orderbook.acceptOrder(orderId, 0, emptyFees, emptyFeeReceivers);
  }

  function test_acceptListing_invalidQuantity_tooHigh(OrderRequest memory request) external {
    uint256 orderId = test_createListing(request);

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidQuantity.selector);
    orderbook.acceptOrder(orderId, request.quantity + 1, emptyFees, emptyFeeReceivers);
  }

  function test_acceptListing_invalidExpiry(OrderRequest memory request, bool over) external {
    uint256 orderId = test_createListing(request);

    vm.warp(request.expiry + (over ? 1 : 0));

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidExpiry.selector);
    orderbook.acceptOrder(orderId, request.quantity, emptyFees, emptyFeeReceivers);
  }

  function test_acceptListing_twice(OrderRequest memory request) external {
    request.isERC1155 = true;
    _fixRequest(request, true);

    // Cater for rounding error with / 2 * 2
    request.quantity = (request.quantity / 2) * 2;
    if (request.quantity == 0) {
      request.quantity = 2;
    }
    uint256 totalPrice = request.pricePerToken * request.quantity;
    uint256 royalty = (totalPrice * ROYALTY_FEE) / 10_000 / 2 * 2;

    uint256 erc20BalCurrency = erc20.balanceOf(CURRENCY_OWNER);
    uint256 erc20BalTokenOwner = erc20.balanceOf(TOKEN_OWNER);
    uint256 erc20BalRoyal = erc20.balanceOf(ROYALTY_RECEIVER);

    uint256 orderId = test_createListing(request);

    vm.startPrank(CURRENCY_OWNER);
    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderAccepted(orderId, CURRENCY_OWNER, address(erc1155), request.quantity / 2, request.quantity / 2);
    orderbook.acceptOrder(orderId, request.quantity / 2, emptyFees, emptyFeeReceivers);
    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderAccepted(orderId, CURRENCY_OWNER, address(erc1155), request.quantity / 2, 0);
    orderbook.acceptOrder(orderId, request.quantity / 2, emptyFees, emptyFeeReceivers);
    vm.stopPrank();

    assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity);
    assertEq(erc20.balanceOf(CURRENCY_OWNER), erc20BalCurrency - totalPrice);
    assertEq(erc20.balanceOf(TOKEN_OWNER), erc20BalTokenOwner + totalPrice - royalty);
    assertEq(erc20.balanceOf(ROYALTY_RECEIVER), erc20BalRoyal + royalty);
  }

  function test_acceptListingBatch_repeat(OrderRequest memory request) external {
    // Potential exploit of royalty rounding.
    request.isERC1155 = true;
    _fixRequest(request, true);

    uint256 totalPrice = request.pricePerToken * request.quantity;
    uint256 royalty = ((request.pricePerToken * ROYALTY_FEE) / 10_000) * request.quantity;

    uint256 erc20BalCurrency = erc20.balanceOf(CURRENCY_OWNER);
    uint256 erc20BalTokenOwner = erc20.balanceOf(TOKEN_OWNER);
    uint256 erc20BalRoyal = erc20.balanceOf(ROYALTY_RECEIVER);

    uint256 orderId = test_createListing(request);
    uint256[] memory orderIds = new uint256[](request.quantity);
    uint256[] memory quantities = new uint256[](request.quantity);

    for (uint256 i; i < request.quantity; i++) {
      orderIds[i] = orderId;
      quantities[i] = 1;
    }

    vm.prank(CURRENCY_OWNER);
    orderbook.acceptOrderBatch(orderIds, quantities, emptyFees, emptyFeeReceivers);

    assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity);
    assertEq(erc20.balanceOf(CURRENCY_OWNER), erc20BalCurrency - totalPrice);
    assertEq(erc20.balanceOf(TOKEN_OWNER), erc20BalTokenOwner + totalPrice - royalty);
    assertEq(erc20.balanceOf(ROYALTY_RECEIVER), erc20BalRoyal + royalty);
  }

  function test_acceptListing_twice_overQuantity(OrderRequest memory request) external {
    request.isERC1155 = true;

    uint256 orderId = test_acceptListing(request);

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidOrderId.selector, orderId));
    orderbook.acceptOrder(orderId, 1, emptyFees, emptyFeeReceivers);
  }

  function test_acceptListing_noFunds(OrderRequest memory request) external {
    uint256 orderId = test_createListing(request);

    uint256 bal = erc20.balanceOf(CURRENCY_OWNER);
    vm.prank(CURRENCY_OWNER);
    erc20.transfer(TOKEN_OWNER, bal);

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert("TransferHelper::transferFrom: transferFrom failed");
    orderbook.acceptOrder(orderId, request.quantity, emptyFees, emptyFeeReceivers);
  }

  function test_acceptListing_invalidERC721Owner(OrderRequest memory request) external {
    request.isERC1155 = false;

    uint256 orderId = test_createListing(request);

    vm.prank(TOKEN_OWNER);
    erc721.transferFrom(TOKEN_OWNER, CURRENCY_OWNER, TOKEN_ID);

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert("ERC721: caller is not token owner or approved");
    orderbook.acceptOrder(orderId, 1, emptyFees, emptyFeeReceivers);
  }

  function test_acceptListing_reentry(OrderRequest memory request) external {
    request.isERC1155 = true;

    uint256 orderId = test_createListing(request);

    ERC1155ReentryAttacker attacker = new ERC1155ReentryAttacker(address(orderbook));
    erc20.mockMint(address(attacker), CURRENCY_QUANTITY);
    vm.prank(address(attacker));
    erc20.approve(address(orderbook), CURRENCY_QUANTITY);

    vm.expectRevert("ReentrancyGuard: reentrant call");
    attacker.acceptListing(orderId, request.quantity);
  }

  //
  // Cancel Listing
  //
  function test_cancelListing(OrderRequest memory request) public returns (uint256 orderId) {
    orderId = test_createListing(request);

    // Fails invalid sender
    vm.expectRevert(abi.encodeWithSelector(InvalidOrderId.selector, orderId));
    orderbook.cancelOrder(orderId);

    // Succeeds correct sender

    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderCancelled(orderId, request.tokenContract);
    vm.prank(TOKEN_OWNER);
    orderbook.cancelOrder(orderId);

    Order memory listing = orderbook.getOrder(orderId);
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
    vm.expectRevert(abi.encodeWithSelector(InvalidOrderId.selector, orderId));
    orderbook.acceptOrder(orderId, 1, emptyFees, emptyFeeReceivers);

    return orderId;
  }

  function test_cancelListing_partialFill(OrderRequest memory request) public returns (uint256 orderId) {
    request.isERC1155 = true;
    _fixRequest(request, true);
    if (request.quantity == 1) {
      // Ensure multiple available
      request.quantity++;
      _fixRequest(request, true);
    }
    orderId = test_createListing(request);

    // Partial fill
    vm.prank(CURRENCY_OWNER);
    orderbook.acceptOrder(orderId, 1, emptyFees, emptyFeeReceivers);

    // Fails invalid sender
    vm.expectRevert(abi.encodeWithSelector(InvalidOrderId.selector, orderId));
    orderbook.cancelOrder(orderId);

    // Succeeds correct sender

    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderCancelled(orderId, request.tokenContract);
    vm.prank(TOKEN_OWNER);
    orderbook.cancelOrder(orderId);

    Order memory listing = orderbook.getOrder(orderId);
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
    vm.expectRevert(abi.encodeWithSelector(InvalidOrderId.selector, orderId));
    orderbook.acceptOrder(orderId, 1, emptyFees, emptyFeeReceivers);

    return orderId;
  }

  //
  // Create Offer
  //

  // This is tested and fuzzed through internal calls
  function test_createOffer(OrderRequest memory request) internal returns (uint256 orderId) {
    _fixRequest(request, false);

    Order memory expected = Order({
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

    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderCreated(
      expectedNextOrderId,
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
    orderId = orderbook.createOrder(request);
    expectedNextOrderId++;

    Order memory offer = orderbook.getOrder(orderId);
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

    return orderId;
  }

  function test_createOffer_invalidExpiry(OrderRequest memory request, uint96 expiry) external {
    vm.assume(expiry <= block.timestamp);
    _fixRequest(request, false);
    request.expiry = expiry;

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidExpiry.selector);
    orderbook.createOrder(request);
  }

  function test_createOffer_invalidQuantity(OrderRequest memory request) external {
    _fixRequest(request, false);
    request.quantity = 0;

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidQuantity.selector);
    orderbook.createOrder(request);
  }

  function test_createOffer_invalidPrice(OrderRequest memory request) external {
    _fixRequest(request, false);
    request.pricePerToken = 0;

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(InvalidPrice.selector);
    orderbook.createOrder(request);
  }

  function test_createOffer_invalidApproval(OrderRequest memory request) external {
    _fixRequest(request, false);

    uint256 total = request.pricePerToken * request.quantity;
    uint256 royalty = (total * ROYALTY_FEE) / 10_000;
    total += royalty;

    vm.prank(CURRENCY_OWNER);
    erc20.approve(address(orderbook), total - 1);

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidCurrencyApproval.selector, request.currency, total, CURRENCY_OWNER));
    orderbook.createOrder(request);
  }

  //
  // Accept Offer
  //
  function test_acceptOffer(OrderRequest memory request) public returns (uint256 orderId) {
    _fixRequest(request, false);

    uint256 totalPrice = request.pricePerToken * request.quantity;
    uint256 royalty = (totalPrice * ROYALTY_FEE) / 10_000;

    uint256 erc20BalCurrency = erc20.balanceOf(CURRENCY_OWNER);
    uint256 erc20BalTokenOwner = erc20.balanceOf(TOKEN_OWNER);
    uint256 erc20BalRoyal = erc20.balanceOf(ROYALTY_RECEIVER);

    orderId = test_createOffer(request);

    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderAccepted(orderId, TOKEN_OWNER, request.tokenContract, request.quantity, 0);
    vm.prank(TOKEN_OWNER);
    orderbook.acceptOrder(orderId, request.quantity, emptyFees, emptyFeeReceivers);

    if (request.isERC1155) {
      assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity);
    } else {
      assertEq(erc721.ownerOf(TOKEN_ID), CURRENCY_OWNER);
    }
    assertEq(erc20.balanceOf(CURRENCY_OWNER), erc20BalCurrency - totalPrice - royalty);
    assertEq(erc20.balanceOf(TOKEN_OWNER), erc20BalTokenOwner + totalPrice);
    assertEq(erc20.balanceOf(ROYALTY_RECEIVER), erc20BalRoyal + royalty);

    return orderId;
  }

  function test_acceptOffer_additionalFees(OrderRequest memory request, uint256[] memory additionalFees) public {
    _fixRequest(request, false);

    uint256 totalPrice = request.pricePerToken * request.quantity;
    uint256 royalty = (totalPrice * ROYALTY_FEE) / 10_000;

    if (additionalFees.length > 3) {
      // Cap at 3 fees
      assembly {
        mstore(additionalFees, 3)
      }
    }
    address[] memory additionalFeeReceivers = new address[](additionalFees.length);
    uint256 totalFees;
    for (uint256 i; i < additionalFees.length; i++) {
      additionalFeeReceivers[i] = FEE_RECEIVER;
      additionalFees[i] = bound(additionalFees[i], 1, 0.2 ether);
      totalFees += additionalFees[i];
    }
    vm.assume((totalFees + royalty) < totalPrice);

    uint256 erc20BalCurrency = erc20.balanceOf(CURRENCY_OWNER);
    uint256 erc20BalTokenOwner = erc20.balanceOf(TOKEN_OWNER);
    uint256 erc20BalRoyal = erc20.balanceOf(ROYALTY_RECEIVER);

    uint256 orderId = test_createOffer(request);

    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderAccepted(orderId, TOKEN_OWNER, request.tokenContract, request.quantity, 0);
    vm.prank(TOKEN_OWNER);
    orderbook.acceptOrder(orderId, request.quantity, additionalFees, additionalFeeReceivers);

    if (request.isERC1155) {
      assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity);
    } else {
      assertEq(erc721.ownerOf(TOKEN_ID), CURRENCY_OWNER);
    }
    assertEq(erc20.balanceOf(CURRENCY_OWNER), erc20BalCurrency - totalPrice - royalty);
    assertEq(erc20.balanceOf(FEE_RECEIVER), totalFees); // Assume no starting value
    // Fees paid by taker
    assertEq(erc20.balanceOf(TOKEN_OWNER), erc20BalTokenOwner + totalPrice - totalFees);
    assertEq(erc20.balanceOf(ROYALTY_RECEIVER), erc20BalRoyal + royalty);
  }

  function test_acceptOffer_invalidAdditionalFees(OrderRequest memory request) external {
    uint256 orderId = test_createOffer(request);

    // Zero fee
    uint256[] memory additionalFees = new uint256[](1);
    address[] memory additionalFeeReceivers = new address[](1);
    additionalFeeReceivers[0] = FEE_RECEIVER;
    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidAdditionalFees.selector);
    orderbook.acceptOrder(orderId, 1, additionalFees, additionalFeeReceivers);

    // Fee exceeds cost
    Order memory order = orderbook.getOrder(orderId);
    additionalFees[0] = order.pricePerToken * order.quantity + 1;
    vm.prank(TOKEN_OWNER);
    vm.expectRevert(stdError.arithmeticError);
    orderbook.acceptOrder(orderId, order.quantity, additionalFees, additionalFeeReceivers);

    // Zero address
    additionalFees[0] = 1 ether;
    additionalFeeReceivers[0] = address(0);
    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidAdditionalFees.selector);
    orderbook.acceptOrder(orderId, 1, additionalFees, additionalFeeReceivers);

    // Invalid length (larger receivers)
    additionalFeeReceivers = new address[](2);
    additionalFeeReceivers[0] = FEE_RECEIVER;
    additionalFeeReceivers[1] = FEE_RECEIVER;
    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidAdditionalFees.selector);
    orderbook.acceptOrder(orderId, 1, additionalFees, additionalFeeReceivers);

    // Invalid length (larger fees)
    additionalFees = new uint256[](3);
    additionalFees[0] = 1;
    additionalFees[1] = 2;
    additionalFees[2] = 3;
    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidAdditionalFees.selector);
    orderbook.acceptOrder(orderId, 1, additionalFees, additionalFeeReceivers);
  }

  function test_acceptOffer_invalidRoyalties(OrderRequest memory request) external {
    _fixRequest(request, false);
    vm.assume(request.pricePerToken > 10_000); // Ensure rounding
    uint256 orderId = test_createOffer(request);

    // >100%
    if (request.isERC1155) {
      erc1155.setFee(10_001);
    } else {
      erc721.setFee(10_001);
    }
    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidRoyalty.selector);
    orderbook.acceptOrder(orderId, 1, emptyFees, emptyFeeReceivers);

    // 100% is ok
    if (request.isERC1155) {
      erc1155.setFee(10_000);
    } else {
      erc721.setFee(10_000);
    }
    vm.prank(TOKEN_OWNER);
    orderbook.acceptOrder(orderId, 1, emptyFees, emptyFeeReceivers);
  }

  function test_acceptOffer_invalidQuantity_zero(OrderRequest memory request) external {
    uint256 orderId = test_createOffer(request);

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidQuantity.selector);
    orderbook.acceptOrder(orderId, 0, emptyFees, emptyFeeReceivers);
  }

  function test_acceptOffer_invalidQuantity_tooHigh(OrderRequest memory request) external {
    uint256 orderId = test_createOffer(request);

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidQuantity.selector);
    orderbook.acceptOrder(orderId, request.quantity + 1, emptyFees, emptyFeeReceivers);
  }

  function test_acceptOffer_invalidExpiry(OrderRequest memory request, bool over) external {
    uint256 orderId = test_createOffer(request);

    vm.warp(request.expiry + (over ? 1 : 0));

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(InvalidExpiry.selector);
    orderbook.acceptOrder(orderId, request.quantity, emptyFees, emptyFeeReceivers);
  }

  function test_acceptOffer_twice(OrderRequest memory request) external {
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
    uint256 erc20BalRoyal = erc20.balanceOf(ROYALTY_RECEIVER);

    uint256 orderId = test_createOffer(request);

    vm.startPrank(TOKEN_OWNER);
    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderAccepted(orderId, TOKEN_OWNER, address(erc1155), request.quantity / 2, request.quantity / 2);
    orderbook.acceptOrder(orderId, request.quantity / 2, emptyFees, emptyFeeReceivers);
    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderAccepted(orderId, TOKEN_OWNER, address(erc1155), request.quantity / 2, 0);
    orderbook.acceptOrder(orderId, request.quantity / 2, emptyFees, emptyFeeReceivers);
    vm.stopPrank();

    assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity);
    assertEq(erc20.balanceOf(CURRENCY_OWNER), erc20BalCurrency - totalPrice - royalty);
    assertEq(erc20.balanceOf(TOKEN_OWNER), erc20BalTokenOwner + totalPrice);
    assertEq(erc20.balanceOf(ROYALTY_RECEIVER), erc20BalRoyal + royalty);
  }

  function test_acceptOfferBatch_repeat(OrderRequest memory request) external {
    // Potential exploit of royalty rounding.
    request.isERC1155 = true;
    _fixRequest(request, true);

    uint256 totalPrice = request.pricePerToken * request.quantity;
    uint256 royalty = ((request.pricePerToken * ROYALTY_FEE) / 10_000) * request.quantity;

    uint256 erc20BalCurrency = erc20.balanceOf(CURRENCY_OWNER);
    uint256 erc20BalTokenOwner = erc20.balanceOf(TOKEN_OWNER);
    uint256 erc20BalRoyal = erc20.balanceOf(ROYALTY_RECEIVER);

    uint256 orderId = test_createOffer(request);
    uint256[] memory orderIds = new uint256[](request.quantity);
    uint256[] memory quantities = new uint256[](request.quantity);

    for (uint256 i; i < request.quantity; i++) {
      orderIds[i] = orderId;
      quantities[i] = 1;
    }

    vm.prank(TOKEN_OWNER);
    orderbook.acceptOrderBatch(orderIds, quantities, emptyFees, emptyFeeReceivers);

    assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity);
    assertEq(erc20.balanceOf(CURRENCY_OWNER), erc20BalCurrency - totalPrice - royalty);
    assertEq(erc20.balanceOf(TOKEN_OWNER), erc20BalTokenOwner + totalPrice);
    assertEq(erc20.balanceOf(ROYALTY_RECEIVER), erc20BalRoyal + royalty);
  }

  function test_acceptOffer_twice_overQuantity(OrderRequest memory request) external {
    request.isERC1155 = true;

    uint256 orderId = test_acceptOffer(request);

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidOrderId.selector, orderId));
    orderbook.acceptOrder(orderId, 1, emptyFees, emptyFeeReceivers);
  }

  function test_acceptOffer_noFunds(OrderRequest memory request) external {
    uint256 orderId = test_createOffer(request);

    uint256 bal = erc20.balanceOf(CURRENCY_OWNER);
    vm.prank(CURRENCY_OWNER);
    erc20.transfer(TOKEN_OWNER, bal);

    vm.prank(TOKEN_OWNER);
    vm.expectRevert("TransferHelper::transferFrom: transferFrom failed");
    orderbook.acceptOrder(orderId, request.quantity, emptyFees, emptyFeeReceivers);
  }

  function test_acceptOffer_invalidERC721Owner(OrderRequest memory request) external {
    request.isERC1155 = false;

    uint256 orderId = test_createOffer(request);

    vm.prank(TOKEN_OWNER);
    erc721.transferFrom(TOKEN_OWNER, CURRENCY_OWNER, TOKEN_ID);

    vm.prank(TOKEN_OWNER);
    vm.expectRevert("ERC721: caller is not token owner or approved");
    orderbook.acceptOrder(orderId, 1, emptyFees, emptyFeeReceivers);
  }

  //
  // Cancel Offer
  //
  function test_cancelOffer(OrderRequest memory request) public returns (uint256 orderId) {
    orderId = test_createOffer(request);

    // Fails invalid sender
    vm.expectRevert(abi.encodeWithSelector(InvalidOrderId.selector, orderId));
    orderbook.cancelOrder(orderId);

    // Succeeds correct sender
    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderCancelled(orderId, request.tokenContract);
    vm.prank(CURRENCY_OWNER);
    orderbook.cancelOrder(orderId);

    Order memory offer = orderbook.getOrder(orderId);
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
    vm.expectRevert(abi.encodeWithSelector(InvalidOrderId.selector, orderId));
    orderbook.acceptOrder(orderId, 1, emptyFees, emptyFeeReceivers);

    return orderId;
  }

  function test_cancelOffer_partialFill(OrderRequest memory request) external returns (uint256 orderId) {
    request.isERC1155 = true;
    _fixRequest(request, false);
    if (request.quantity == 1) {
      // Ensure multiple available
      request.quantity++;
      _fixRequest(request, false);
    }
    orderId = test_createOffer(request);

    // Partial fill
    vm.prank(TOKEN_OWNER);
    orderbook.acceptOrder(orderId, 1, emptyFees, emptyFeeReceivers);

    // Succeeds correct sender
    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderCancelled(orderId, request.tokenContract);
    vm.prank(CURRENCY_OWNER);
    orderbook.cancelOrder(orderId);

    Order memory offer = orderbook.getOrder(orderId);
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
    vm.expectRevert(abi.encodeWithSelector(InvalidOrderId.selector, orderId));
    orderbook.acceptOrder(orderId, 1, emptyFees, emptyFeeReceivers);

    return orderId;
  }

  //
  // Create Order Batch
  //
  function test_createOrderBatch(uint8 count, OrderRequest[] memory input) public returns (uint256[] memory orderIds) {
    count = count > 4 ? 4 : count;
    vm.assume(input.length >= count);
    OrderRequest[] memory requests = new OrderRequest[](count);

    for (uint8 i; i < count; i++) {
      OrderRequest memory request = input[i];
      _fixRequest(request, request.isListing);
      requests[i] = request;
    }

    // Given token holder some currency so it can submit offers too
    erc20.mockMint(TOKEN_OWNER, CURRENCY_QUANTITY);
    vm.prank(TOKEN_OWNER);
    erc20.approve(address(orderbook), CURRENCY_QUANTITY);

    // Emits
    for (uint256 i; i < count; i++) {
      vm.expectEmit(true, true, true, true, address(orderbook));
      OrderRequest memory request = requests[i];
      emit OrderCreated(
        expectedNextOrderId,
        TOKEN_OWNER,
        request.tokenContract,
        request.tokenId,
        request.isListing,
        request.quantity,
        request.currency,
        request.pricePerToken,
        request.expiry
      );
      expectedNextOrderId++;
    }

    vm.prank(TOKEN_OWNER);
    orderIds = orderbook.createOrderBatch(requests);

    assertEq(orderIds.length, count);

    // Check orders
    Order[] memory orders = orderbook.getOrderBatch(orderIds);
    assertEq(orders.length, count);
    for (uint256 i; i < count; i++) {
      Order memory order = orders[i];
      OrderRequest memory request = requests[i];
      assertEq(order.creator, TOKEN_OWNER);
      assertEq(order.isListing, request.isListing);
      assertEq(order.isERC1155, request.isERC1155);
      assertEq(order.tokenContract, request.tokenContract);
      assertEq(order.tokenId, request.tokenId);
      assertEq(order.quantity, request.quantity);
      assertEq(order.expiry, request.expiry);
      assertEq(order.currency, request.currency);
      assertEq(order.pricePerToken, request.pricePerToken);
    }

    return orderIds;
  }

  //
  // Accept Order Batch
  //
  function test_acceptOrderBatch_fixed() external {
    erc20.mockMint(TOKEN_OWNER, CURRENCY_QUANTITY);
    vm.prank(TOKEN_OWNER);
    erc20.approve(address(orderbook), CURRENCY_QUANTITY);

    OrderRequest memory request = OrderRequest({
      isListing: true,
      isERC1155: true,
      tokenContract: address(erc1155),
      tokenId: TOKEN_ID,
      quantity: 1,
      currency: address(erc20),
      pricePerToken: 1,
      expiry: uint96(block.timestamp)
    });

    uint256[] memory orderIds = new uint256[](4);
    request.isERC1155 = true;
    orderIds[0] = test_createListing(request);
    request.isERC1155 = false;
    orderIds[1] = test_createListing(request);
    request.isERC1155 = true;
    orderIds[2] = test_createOffer(request);
    request.isERC1155 = false;
    orderIds[3] = test_createOffer(request);

    uint256[] memory quantities = new uint256[](4);
    quantities[0] = 1;
    quantities[1] = 1;
    quantities[2] = 1;
    quantities[3] = 1;

    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderAccepted(orderIds[0], TOKEN_OWNER, address(erc1155), 1, 0);
    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderAccepted(orderIds[1], TOKEN_OWNER, address(erc721), 1, 0);
    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderAccepted(orderIds[2], TOKEN_OWNER, address(erc1155), 1, 0);
    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderAccepted(orderIds[3], TOKEN_OWNER, address(erc721), 1, 0);
    vm.prank(TOKEN_OWNER);
    orderbook.acceptOrderBatch(orderIds, quantities, emptyFees, emptyFeeReceivers);
  }

  function test_acceptOrderBatch_fuzz(uint8 count, OrderRequest[] memory input, uint8[] memory quantities) external {
    uint256[] memory orderIds = test_createOrderBatch(count, input);
    uint256 orderCount = orderIds.length;
    assembly {
      // Ensure array size is sufficient. 0s will be bound
      mstore(quantities, orderCount)
    }

    vm.startPrank(CURRENCY_OWNER);
    erc1155.setApprovalForAll(address(orderbook), true);
    erc721.setApprovalForAll(address(orderbook), true);
    erc20.approve(address(orderbook), type(uint256).max);
    vm.stopPrank();

    for (uint256 i; i < orderCount; i++) {
      (bool valid, Order memory order) = orderbook.isOrderValid(orderIds[i], 0);
      if (valid) {
        uint256 orderQuantity = order.quantity;

        // Check can accept
        if (order.isListing) {
          // Give enough currency to accept
          uint256 required = order.quantity * order.pricePerToken;
          erc20.mockMint(CURRENCY_OWNER, required);
        } else if (order.isERC1155) {
          // Give enough tokens to accept
          uint256[] memory tokenIds = new uint256[](1);
          tokenIds[0] = order.tokenId;
          uint256[] memory required = new uint256[](1);
          required[0] = order.quantity;
          erc1155.batchMintMock(CURRENCY_OWNER, tokenIds, required, "");
        } else if (erc721.ownerOf(order.tokenId) != CURRENCY_OWNER) {
          // Skip this. We don't fix it
          continue;
        }

        // Random valid quantity
        uint256 quantity = _bound(quantities[i], 1, order.quantity);

        vm.expectEmit(true, true, true, true, address(orderbook));
        emit OrderAccepted(orderIds[i], CURRENCY_OWNER, order.tokenContract, quantity, orderQuantity - quantity);
        vm.prank(CURRENCY_OWNER);
        orderbook.acceptOrder(orderIds[i], quantity, emptyFees, emptyFeeReceivers);
      }
    }
  }

  function test_acceptListingBatch(OrderRequest memory request) external {
    request.isERC1155 = true;
    _fixRequest(request, false);

    // Prevent overflow
    request.pricePerToken /= 2;
    request.quantity /= 2;
    _fixRequest(request, false); // Fix values too low

    uint256 totalPrice2 = request.pricePerToken * request.quantity * 2;
    uint256 erc20BalCurrency = erc20.balanceOf(CURRENCY_OWNER);
    uint256 erc20BalTokenOwner = erc20.balanceOf(TOKEN_OWNER);
    uint256 erc20BalRoyal = erc20.balanceOf(ROYALTY_RECEIVER);

    uint256[] memory orderIds = new uint256[](2);
    orderIds[0] = test_createListing(request);
    request.expiry++;
    orderIds[1] = test_createListing(request);
    uint256[] memory quantities = new uint256[](2);
    quantities[0] = request.quantity;
    quantities[1] = request.quantity;

    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderAccepted(orderIds[0], CURRENCY_OWNER, address(erc1155), request.quantity, 0);
    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderAccepted(orderIds[1], CURRENCY_OWNER, address(erc1155), request.quantity, 0);
    vm.startPrank(CURRENCY_OWNER);
    orderbook.acceptOrderBatch(orderIds, quantities, emptyFees, emptyFeeReceivers);
    vm.stopPrank();

    uint256 royalty2 = (((totalPrice2 / 2) * ROYALTY_FEE) / 10_000) * 2; // Cater for rounding error

    assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity * 2);
    assertEq(erc20.balanceOf(CURRENCY_OWNER), erc20BalCurrency - totalPrice2);
    assertEq(erc20.balanceOf(TOKEN_OWNER), erc20BalTokenOwner + totalPrice2 - royalty2);
    assertEq(erc20.balanceOf(ROYALTY_RECEIVER), erc20BalRoyal + royalty2);
  }

  function test_acceptOfferBatch(OrderRequest memory request) external {
    request.isERC1155 = true;
    _fixRequest(request, false);

    // Prevent overflow
    request.pricePerToken /= 2;
    request.quantity /= 2;
    _fixRequest(request, false); // Fix values too low

    uint256 totalPrice2 = request.pricePerToken * request.quantity * 2;
    uint256 erc20BalCurrency = erc20.balanceOf(CURRENCY_OWNER);
    uint256 erc20BalTokenOwner = erc20.balanceOf(TOKEN_OWNER);
    uint256 erc20BalRoyal = erc20.balanceOf(ROYALTY_RECEIVER);

    uint256[] memory orderIds = new uint256[](2);
    orderIds[0] = test_createOffer(request);
    request.expiry++;
    orderIds[1] = test_createOffer(request);

    uint256[] memory quantities = new uint256[](2);
    quantities[0] = request.quantity;
    quantities[1] = request.quantity;

    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderAccepted(orderIds[0], TOKEN_OWNER, address(erc1155), request.quantity, 0);
    vm.expectEmit(true, true, true, true, address(orderbook));
    emit OrderAccepted(orderIds[1], TOKEN_OWNER, address(erc1155), request.quantity, 0);
    vm.startPrank(TOKEN_OWNER);
    orderbook.acceptOrderBatch(orderIds, quantities, emptyFees, emptyFeeReceivers);
    vm.stopPrank();

    uint256 royalty2 = (((totalPrice2 / 2) * ROYALTY_FEE) / 10_000) * 2; // Cater for rounding error

    assertEq(erc1155.balanceOf(CURRENCY_OWNER, TOKEN_ID), request.quantity * 2);
    assertEq(erc20.balanceOf(CURRENCY_OWNER), erc20BalCurrency - totalPrice2 - royalty2);
    assertEq(erc20.balanceOf(TOKEN_OWNER), erc20BalTokenOwner + totalPrice2);
    assertEq(erc20.balanceOf(ROYALTY_RECEIVER), erc20BalRoyal + royalty2);
  }

  function test_acceptOrderBatch_invalidLengths(uint8 count, OrderRequest[] memory input, uint256[] memory quantities)
    external
  {
    count = count > 4 ? 4 : count;
    vm.assume(quantities.length != count);
    uint256[] memory orderIds = test_createOrderBatch(count, input);
    vm.assume(quantities.length != orderIds.length);

    vm.expectRevert(InvalidBatchRequest.selector);
    orderbook.acceptOrderBatch(orderIds, quantities, emptyFees, emptyFeeReceivers);
  }

  //
  // Cancel Order Batch
  //
  function test_cancelOrderBatch(uint8 count, OrderRequest[] memory input) external {
    uint256[] memory orderIds = test_createOrderBatch(count, input);

    for (uint256 i; i < orderIds.length; i++) {
      Order memory order = orderbook.getOrder(orderIds[i]);
      vm.expectEmit(true, true, true, true, address(orderbook));
      emit OrderCancelled(orderIds[i], order.tokenContract);
    }

    vm.prank(TOKEN_OWNER);
    orderbook.cancelOrderBatch(orderIds);

    for (uint256 i; i < orderIds.length; i++) {
      (bool valid, Order memory order) = orderbook.isOrderValid(orderIds[i], 0);
      assertEq(order.creator, address(0));
      assertEq(order.tokenContract, address(0));
      assertEq(order.tokenId, 0);
      assertEq(order.quantity, 0);
      assertEq(order.currency, address(0));
      assertEq(order.pricePerToken, 0);
      assertEq(order.expiry, 0);
      assertEq(valid, false);
    }
  }

  function test_cancelOrderBatch_invalidCaller(uint8 count, OrderRequest[] memory input) external {
    vm.assume(count > 1 && input.length > 1);
    uint256[] memory orderIds = test_createOrderBatch(count, input);

    vm.prank(CURRENCY_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidOrderId.selector, orderIds[0]));
    orderbook.cancelOrderBatch(orderIds);

    // Created by CURRENCY_OWNER
    uint256 currencyOrderId = test_createOffer(input[0]);

    orderIds[1] = currencyOrderId;

    vm.prank(TOKEN_OWNER);
    vm.expectRevert(abi.encodeWithSelector(InvalidOrderId.selector, currencyOrderId));
    orderbook.cancelOrderBatch(orderIds);
  }

  //
  // Validity
  //
  function test_isOrderValid_expired() external {
    OrderRequest memory request = OrderRequest({
      isListing: true,
      isERC1155: true,
      tokenContract: address(erc1155),
      tokenId: TOKEN_ID,
      quantity: 1,
      currency: address(erc20),
      pricePerToken: 1 ether,
      expiry: uint96(block.timestamp + 1)
    });

    uint256[] memory orderIds = new uint256[](4);
    uint256[] memory quantities = new uint256[](4);

    orderIds[0] = test_createListing(request);

    request.isERC1155 = false;
    _fixRequest(request, true);
    orderIds[1] = test_createListing(request);

    _fixRequest(request, false);
    orderIds[2] = test_createOffer(request);

    request.isERC1155 = true;
    _fixRequest(request, false);
    orderIds[3] = test_createOffer(request);

    vm.warp(request.expiry + 5);

    bool[] memory valid;
    (valid,) = orderbook.isOrderValidBatch(orderIds, quantities);
    for (uint256 i; i < 4; i++) {
      assertEq(valid[i], false);
    }
  }

  function test_isOrderValid_invalidApproval() external {
    OrderRequest memory request = OrderRequest({
      isListing: true,
      isERC1155: true,
      tokenContract: address(erc1155),
      tokenId: TOKEN_ID,
      quantity: 1,
      currency: address(erc20),
      pricePerToken: 1 ether,
      expiry: uint96(block.timestamp + 1)
    });

    uint256[] memory orderIds = new uint256[](4);
    uint256[] memory quantities = new uint256[](4);

    orderIds[0] = test_createListing(request);

    request.isERC1155 = false;
    _fixRequest(request, true);
    orderIds[1] = test_createListing(request);

    _fixRequest(request, false);
    orderIds[2] = test_createOffer(request);

    request.isERC1155 = true;
    _fixRequest(request, false);
    orderIds[3] = test_createOffer(request);

    vm.startPrank(TOKEN_OWNER);
    erc1155.setApprovalForAll(address(orderbook), false);
    erc721.setApprovalForAll(address(orderbook), false);
    vm.stopPrank();
    vm.prank(CURRENCY_OWNER);
    erc20.approve(address(orderbook), 0);

    (bool[] memory valid,) = orderbook.isOrderValidBatch(orderIds, quantities);
    for (uint256 i; i < 4; i++) {
      assertEq(valid[i], false);
    }
  }

  function test_isOrderValid_partialValidity() external {
    OrderRequest memory request = OrderRequest({
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
    uint256 orderId = orderbook.createOrder(request);

    vm.prank(CURRENCY_OWNER);
    erc20.approve(address(orderbook), 2 ether);

    erc1155.setFee(0); // Ignore royalty

    (bool valid,) = orderbook.isOrderValid(orderId, 0);
    assertEq(valid, false); // Not valid for all tokens

    (valid,) = orderbook.isOrderValid(orderId, 1);
    assertEq(valid, true);
    (valid,) = orderbook.isOrderValid(orderId, 2);
    assertEq(valid, true);
    for (uint256 i = 3; i < 15; i++) {
      // Invalid due to approval or over quantity
      (valid,) = orderbook.isOrderValid(orderId, i);
      assertEq(valid, false);
    }
  }

  function test_isOrderValid_royaltyInvalid() external {
    OrderRequest memory request = OrderRequest({
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
    uint256 orderId = orderbook.createOrder(request);

    vm.prank(CURRENCY_OWNER);
    erc20.approve(address(orderbook), request.pricePerToken * request.quantity); // Exact amount
    erc1155.setFee(10_000); // 100% royalty. Now half will be valid due to royalty fee

    (bool valid,) = orderbook.isOrderValid(orderId, 0);
    assertEq(valid, false);
    for (uint256 i = 1; i < 6; i++) {
      (valid,) = orderbook.isOrderValid(orderId, i);
      assertEq(valid, true);
    }
    for (uint256 i = 6; i < 11; i++) {
      (valid,) = orderbook.isOrderValid(orderId, i);
      assertEq(valid, false);
    }
  }

  function test_isOrderValid_invalidBalance() external {
    OrderRequest memory request = OrderRequest({
      isListing: true,
      isERC1155: true,
      tokenContract: address(erc1155),
      tokenId: TOKEN_ID,
      quantity: 1,
      currency: address(erc20),
      pricePerToken: 1 ether,
      expiry: uint96(block.timestamp + 1)
    });

    uint256[] memory orderIds = new uint256[](4);
    uint256[] memory quantities = new uint256[](4);

    orderIds[0] = test_createListing(request);

    request.isERC1155 = false;
    _fixRequest(request, true);
    orderIds[1] = test_createListing(request);

    _fixRequest(request, false);
    orderIds[2] = test_createOffer(request);

    request.isERC1155 = true;
    _fixRequest(request, false);
    orderIds[3] = test_createOffer(request);

    // Use fee receiver as a "random" address
    vm.startPrank(TOKEN_OWNER);
    erc1155.safeTransferFrom(TOKEN_OWNER, FEE_RECEIVER, TOKEN_ID, erc1155.balanceOf(TOKEN_OWNER, TOKEN_ID), "");
    erc721.transferFrom(TOKEN_OWNER, FEE_RECEIVER, TOKEN_ID);
    vm.stopPrank();
    vm.startPrank(CURRENCY_OWNER);
    erc20.transfer(FEE_RECEIVER, CURRENCY_QUANTITY);
    assertEq(erc20.balanceOf(CURRENCY_OWNER), 0);
    vm.stopPrank();

    (bool[] memory valid,) = orderbook.isOrderValidBatch(orderIds, quantities);
    for (uint256 i; i < 4; i++) {
      assertEq(valid[i], false);
    }
  }

  function test_isOrderValid_bulk(uint8 count, OrderRequest[] memory requests, bool[] memory expectValid) external {
    count = count > 4 ? 4 : count;
    vm.assume(requests.length >= count);
    assembly {
      // Bound sizes (default to false when array is smaller)
      mstore(expectValid, count)
    }

    uint256[] memory orderIds = new uint256[](count);
    uint256[] memory quantities = new uint256[](count);
    for (uint8 i; i < count; i++) {
      OrderRequest memory request = requests[i];
      _fixRequest(request, request.isListing);
      if (request.isListing) {
        orderIds[i] = expectValid[i] ? test_createListing(request) : test_cancelListing(request);
      } else {
        orderIds[i] = expectValid[i] ? test_createOffer(request) : test_cancelOffer(request);
      }
    }

    (bool[] memory valid,) = orderbook.isOrderValidBatch(orderIds, quantities);
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

    (address recipient, uint256 royalty) = orderbook.getRoyaltyInfo(address(erc721Mock), 1, 1 ether);

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
    vm.prank(ORDERBOOK_OWNER);
    orderbook.setRoyaltyInfo(tokenContract, recipient, fee);

    (address actualR, uint256 actualF) = orderbook.getRoyaltyInfo(tokenContract, 1, 10000);

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
    vm.prank(ORDERBOOK_OWNER);
    orderbook.setRoyaltyInfo(tokenContract, recipient, fee);

    (address actualR, uint256 actualF) = orderbook.getRoyaltyInfo(tokenContract, 1, 10000);

    // Expect token royalty values set above
    (address expectedR, uint256 expectedF) = IERC2981(tokenContract).royaltyInfo(1, 10000);
    assertEq(actualR, expectedR);
    assertEq(actualF, expectedF);
  }

  function test_setRoyaltyInfo_invalidCaller(address caller, address tokenContract, uint96 fee, address recipient) external {
    vm.assume(caller != ORDERBOOK_OWNER);

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(caller);
    orderbook.setRoyaltyInfo(tokenContract, recipient, fee);
  }

  //
  // Helpers
  //

  /**
   * Skip a test.
   */
  modifier skipTest() {
    // solhint-disable-next-line no-console
    console.log("Test skipped");
    if (false) {
      // Required for compiler
      _;
    }
  }

  function _fixRequest(OrderRequest memory request, bool isListing) private view {
    request.isListing = isListing;
    request.tokenContract = request.isERC1155 ? address(erc1155) : address(erc721);
    request.tokenId = TOKEN_ID;
    request.currency = address(erc20);
    request.pricePerToken = _bound(request.pricePerToken, 1, 1 ether);
    request.expiry = uint96(_bound(uint256(request.expiry), block.timestamp + 1, type(uint96).max - 100));

    if (request.isERC1155) {
      request.quantity = _bound(request.quantity, 1, TOKEN_QUANTITY);
    } else {
      request.quantity = 1;
    }

    vm.assume((request.quantity * request.pricePerToken) <= CURRENCY_QUANTITY / 10);
  }

  function _assumeNotPrecompile(address addr) internal pure {
      // vm.assume(addr != address(0));
      assumeNotPrecompile(addr);
      assumeNotForgeAddress(addr);
  }
}
