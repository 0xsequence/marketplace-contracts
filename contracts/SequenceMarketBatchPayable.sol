// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import {SequenceMarket, ISequenceMarketFunctions} from "./SequenceMarket.sol";
import {ISequenceMarketBatchPayable, ISequenceMarketBatchPayableFunctions} from "./interfaces/ISequenceMarketBatchPayable.sol";
import {IERC721} from "./interfaces/IERC721.sol";
import {IERC1155} from "@0xsequence/erc-1155/contracts/interfaces/IERC1155.sol";
import {TransferHelper} from "@uniswap/lib/contracts/libraries/TransferHelper.sol";

contract SequenceMarketBatchPayable is SequenceMarket, ISequenceMarketBatchPayable {

  /// @inheritdoc ISequenceMarketFunctions
  function acceptRequest(
    uint256 requestId,
    uint256 quantity,
    address recipient,
    uint256[] calldata additionalFees,
    address[] calldata additionalFeeRecipients
  ) external payable override(SequenceMarket, ISequenceMarketFunctions) nonReentrant {
    _acceptRequest(requestId, quantity, recipient, additionalFees, additionalFeeRecipients);

    // Transfer any remaining native token back to currency sender (msg.sender)
    uint256 thisBal = address(this).balance;
    if (thisBal > 0) {
      TransferHelper.safeTransferETH(msg.sender, thisBal);
    }
  }

  /// @inheritdoc ISequenceMarketBatchPayableFunctions
  function acceptRequestBatchPayable(
    uint256[] calldata requestIds,
    uint256[] calldata quantities,
    address[] calldata recipients,
    uint256[] calldata additionalFees,
    address[] calldata additionalFeeRecipients
  ) external payable nonReentrant {
    uint256 len = requestIds.length;
    if (len != quantities.length || len != recipients.length) {
      revert InvalidBatchRequest();
    }

    for (uint256 i; i < len;) {
      _acceptRequest(requestIds[i], quantities[i], recipients[i], additionalFees, additionalFeeRecipients);
      unchecked { ++i; }
    }

    // Transfer any remaining native token back to currency sender (msg.sender)
    uint256 thisBal = address(this).balance;
    if (thisBal > 0) {
      TransferHelper.safeTransferETH(msg.sender, thisBal);
    }
  }

  /**
   * Performs acceptance of a request.
   * @param requestId The ID of the request.
   * @param quantity The quantity of tokens to accept.
   * @param recipient The recipient of the accepted tokens.
   * @param additionalFees The additional fees to pay.
   * @param additionalFeeRecipients The addresses to send the additional fees to.
   * @dev This function is identical to SequenceMarket._acceptRequest, but with native the currency refund removed.
   */
  function _acceptRequest(
    uint256 requestId,
    uint256 quantity,
    address recipient,
    uint256[] calldata additionalFees,
    address[] calldata additionalFeeRecipients
  ) internal override {
    Request memory request = _requests[requestId];
    if (request.creator == address(0)) {
      // Request cancelled, completed or never existed
      revert InvalidRequestId(requestId);
    }
    if (quantity == 0 || quantity > request.quantity) {
      revert InvalidQuantity();
    }
    if (
      requestId < invalidBeforeId[request.creator]
        || requestId < invalidTokenBeforeId[request.creator][request.tokenContract]
    ) {
      revert Invalidated();
    }
    if (_isExpired(request)) {
      revert InvalidExpiry();
    }
    if (additionalFees.length != additionalFeeRecipients.length) {
      revert InvalidAdditionalFees();
    }

    // Update request state
    if (request.quantity == quantity) {
      // Refund some gas
      delete _requests[requestId];
    } else {
      _requests[requestId].quantity -= quantity;
    }
    address tokenContract = request.tokenContract;

    // Calculate payables
    uint256 remainingCost = request.pricePerToken * quantity;
    (address royaltyRecipient, uint256 royaltyAmount) = getRoyaltyInfo(tokenContract, request.tokenId, remainingCost);

    address currencySender;
    address currencyRecipient;
    address tokenSender;
    address tokenRecipient;
    if (request.isListing) {
      currencySender = msg.sender;
      currencyRecipient = request.creator;
      tokenSender = request.creator;
      tokenRecipient = recipient;
    } else {
      currencySender = request.creator;
      currencyRecipient = recipient;
      tokenSender = msg.sender;
      tokenRecipient = request.creator;
    }

    bool isNative = request.currency == address(0);

    if (royaltyAmount > 0) {
      if (request.isListing) {
        // Royalties are paid by the maker. This reduces the cost for listings.
        // Underflow prevents fees > cost
        remainingCost -= royaltyAmount;
      } else if (royaltyAmount > remainingCost) {
        // Royalty cannot exceed cost
        revert InvalidRoyalty();
      }
      // Transfer royalties
      if (isNative) {
        // Transfer native token
        TransferHelper.safeTransferETH(royaltyRecipient, royaltyAmount);
      } else {
        // Transfer currency
        TransferHelper.safeTransferFrom(request.currency, currencySender, royaltyRecipient, royaltyAmount);
      }
    }

    // Transfer additional fees
    uint256 totalFees;
    uint256 len = additionalFees.length;
    for (uint256 i; i < len;) {
      uint256 fee = additionalFees[i];
      address feeRecipient = additionalFeeRecipients[i];
      if (feeRecipient == address(0) || fee == 0) {
        revert InvalidAdditionalFees();
      }
      if (isNative) {
        TransferHelper.safeTransferETH(feeRecipient, fee);
      } else {
        TransferHelper.safeTransferFrom(request.currency, currencySender, feeRecipient, fee);
      }
      totalFees += fee;
      unchecked { ++i; }
    }
    if (!request.isListing) {
      // Fees are paid by the taker. This reduces the cost for offers.
      // Underflow prevents fees > cost
      remainingCost -= totalFees;
    } else if (totalFees > remainingCost) {
      // Fees cannot exceed cost - royalties
      revert InvalidAdditionalFees();
    }

    if (isNative) {
      // Transfer native token
      TransferHelper.safeTransferETH(currencyRecipient, remainingCost);
    } else {
      // Transfer currency
      TransferHelper.safeTransferFrom(request.currency, currencySender, currencyRecipient, remainingCost);
    }

    // Transfer token
    if (request.isERC1155) {
      IERC1155(tokenContract).safeTransferFrom(tokenSender, tokenRecipient, request.tokenId, quantity, "");
    } else {
      IERC721(tokenContract).safeTransferFrom(tokenSender, tokenRecipient, request.tokenId);
    }

    emit RequestAccepted(requestId, msg.sender, tokenContract, recipient, quantity, _requests[requestId].quantity);
  }
}
