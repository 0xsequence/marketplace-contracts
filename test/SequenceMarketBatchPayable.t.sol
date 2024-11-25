// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import {SequenceMarketTest} from "./SequenceMarket.t.sol";
import {SequenceMarketBatchPayable} from "contracts/SequenceMarketBatchPayable.sol";
import {SequenceMarket} from "contracts/SequenceMarket.sol";
import {SequenceMarketFactory} from "contracts/SequenceMarketFactory.sol";
import {SequenceMarketBatchPayableFactory} from "contracts/SequenceMarketBatchPayableFactory.sol";
import {ISequenceMarketSignals, ISequenceMarketStorage} from "contracts/interfaces/ISequenceMarket.sol";
import {ISequenceMarketBatchPayable} from "contracts/interfaces/ISequenceMarketBatchPayable.sol";
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

import {console, stdError} from "forge-std/Test.sol";

// solhint-disable not-rely-on-time

contract SequenceMarketBatchPayableTest is SequenceMarketTest {

  SequenceMarketBatchPayable internal marketB;

  function setUp() override external {
    // Deploy original market and upgrade to batch payable
    factory = new SequenceMarketFactory();
    market = SequenceMarket(factory.deploy(0, MARKET_OWNER));
    SequenceMarketBatchPayableFactory payableFactory = new SequenceMarketBatchPayableFactory();

    // Upgrade to batch payable
    address payableImplementation = payableFactory.implementation();
    vm.prank(MARKET_OWNER);
    market.upgradeTo(payableImplementation);
    marketB = SequenceMarketBatchPayable(address(market));

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
  // Accept Request Batch Payable
  //

  function test_acceptRequestBatchPayable_fixed() external {
    uint256 initialCurrencyBalance = CURRENCY_OWNER.balance;
    uint256 initialTokenBalance = TOKEN_OWNER.balance;

    RequestParams memory request = RequestParams({
        isListing: true,
        isERC1155: true,
        tokenContract: address(erc1155),
        tokenId: TOKEN_ID,
        quantity: 1,
        currency: address(0),
        pricePerToken: 10,
        expiry: uint96(block.timestamp)
    });

    uint256[] memory requestIds = new uint256[](2);
    request.isERC1155 = true;
    requestIds[0] = createListing(request);
    request.isERC1155 = false;
    requestIds[1] = createListing(request);

    uint256[] memory quantities = new uint256[](2);
    address[] memory recipients = new address[](2);
    for (uint256 i = 0; i < 2; i++) {
      quantities[i] = 1;
      recipients[i] = CURRENCY_OWNER;
    }

    // Expect the same events as before
    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestIds[0], CURRENCY_OWNER, address(erc1155), CURRENCY_OWNER, 1, 0);
    vm.expectEmit(true, true, true, true, address(market));
    emit RequestAccepted(requestIds[1], CURRENCY_OWNER, address(erc721), CURRENCY_OWNER, 1, 0);

    // Execute batch accept with value above expected price
    vm.prank(CURRENCY_OWNER);
    marketB.acceptRequestBatchPayable{value: 30}(requestIds, quantities, recipients, emptyFees, emptyFeeRecipients);

    // Verify the ETH balance after the transaction (should have spent 20)
    assertEq(TOKEN_OWNER.balance, initialTokenBalance + 20);
    assertEq(CURRENCY_OWNER.balance, initialCurrencyBalance - 20);
  }

  function test_acceptListingBatchPayable(RequestParams memory request, address[] memory recipients) external {
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
    request.currency = address(0); // Force native currency
    _fixRequest(request, true);

    // Prevent overflow
    request.pricePerToken /= 2;
    request.quantity /= 2;
    _fixRequest(request, true); // Fix values too low

    uint256 totalPrice2 = request.pricePerToken * request.quantity * 2;
    uint256 nativeBalCurrency = CURRENCY_OWNER.balance;
    uint256 nativeBalTokenOwner = TOKEN_OWNER.balance;
    uint256 nativeBalRoyal = ROYALTY_RECIPIENT.balance;

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
    marketB.acceptRequestBatchPayable{value: totalPrice2}(
        requestIds, 
        quantities, 
        recipients,
        emptyFees,
        emptyFeeRecipients
    );
    vm.stopPrank();

    uint256 royalty2 = (((totalPrice2 / 2) * ROYALTY_FEE) / 10_000) * 2; // Cater for rounding error

    assertEq(erc1155.balanceOf(recipients[0], TOKEN_ID), request.quantity);
    assertEq(erc1155.balanceOf(recipients[1], TOKEN_ID), request.quantity);
    assertEq(CURRENCY_OWNER.balance, nativeBalCurrency - totalPrice2);
    assertEq(TOKEN_OWNER.balance, nativeBalTokenOwner + totalPrice2 - royalty2);
    assertEq(ROYALTY_RECIPIENT.balance, nativeBalRoyal + royalty2);
  }

  function test_acceptListingBatchPayable_incorrectValue(RequestParams memory request, address[] memory recipients) external {
    vm.assume(recipients.length > 1);
    vm.assume(recipients[0] != recipients[1]);
    assembly {
        mstore(recipients, 2)
    }
    _assumeNotPrecompile(recipients[0]);
    _assumeNotPrecompile(recipients[1]);

    request.isERC1155 = true;
    request.currency = address(0); // Force native currency
    _fixRequest(request, true);

    uint256[] memory requestIds = new uint256[](2);
    requestIds[0] = createListing(request);
    request.expiry++;
    requestIds[1] = createListing(request);

    uint256[] memory quantities = new uint256[](2);
    quantities[0] = request.quantity;
    quantities[1] = request.quantity;

    uint256 totalPrice = request.pricePerToken * request.quantity * 2;
    uint256 initialBalCurrency = CURRENCY_OWNER.balance;
    
    // Test with insufficient value
    vm.prank(CURRENCY_OWNER);
    vm.expectRevert("TransferHelper::safeTransferETH: ETH transfer failed");
    marketB.acceptRequestBatchPayable{value: totalPrice - 1}(
        requestIds,
        quantities,
        recipients,
        emptyFees,
        emptyFeeRecipients
    );

    // Test with excess value
    vm.prank(CURRENCY_OWNER);
    marketB.acceptRequestBatchPayable{value: totalPrice + 1}(
        requestIds,
        quantities,
        recipients,
        emptyFees,
        emptyFeeRecipients
    );

    // Check excess value is returned
    assertEq(CURRENCY_OWNER.balance, initialBalCurrency - totalPrice);
  }

  function test_acceptListingBatchPayable_mixedCurrency(RequestParams memory requestA, RequestParams memory requestB, address[] memory recipients) external {
    vm.assume(recipients.length > 1);
    assembly {
        mstore(recipients, 2)
    }
    // Max one can be ERC-721 because of how test data is generated
    vm.assume(requestA.isERC1155 || requestB.isERC1155);

    uint256 initialBalCurrency = CURRENCY_OWNER.balance;
    uint256 initialBalERC20 = erc20.balanceOf(CURRENCY_OWNER);

    requestA.currency = address(erc20);
    requestB.currency = address(0);

    uint256[] memory requestIds = new uint256[](2);
    requestIds[0] = createListing(requestA);
    requestIds[1] = createListing(requestB);

    uint256[] memory quantities = new uint256[](2);
    quantities[0] = requestA.quantity;
    quantities[1] = requestB.quantity;

    // Allows mixed currencies when accepting batch
    vm.prank(CURRENCY_OWNER);
    // Send whole balance. Will be refunded
    marketB.acceptRequestBatchPayable{value: initialBalCurrency}(
        requestIds,
        quantities,
        recipients,
        emptyFees,
        emptyFeeRecipients
    );

    // Check balances
    assertEq(erc20.balanceOf(CURRENCY_OWNER), initialBalERC20 - requestA.pricePerToken * requestA.quantity);
    assertEq(CURRENCY_OWNER.balance, initialBalCurrency - requestB.pricePerToken * requestB.quantity);
  }
}
