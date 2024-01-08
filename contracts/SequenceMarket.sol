// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import {ISequenceMarket} from "./interfaces/ISequenceMarket.sol";
import {IERC721} from "./interfaces/IERC721.sol";
import {IERC2981} from "./interfaces/IERC2981.sol";
import {IERC20} from "@0xsequence/erc-1155/contracts/interfaces/IERC20.sol";
import {IERC165} from "@0xsequence/erc-1155/contracts/interfaces/IERC165.sol";
import {IERC1155} from "@0xsequence/erc-1155/contracts/interfaces/IERC1155.sol";
import {TransferHelper} from "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract SequenceMarket is ISequenceMarket, Ownable, ReentrancyGuard {
  mapping(uint256 => Request) internal _requests;
  mapping(address => CustomRoyalty) public customRoyalties;

  uint256 private _nextRequestId;

  constructor(address _owner) {
    _transferOwnership(_owner);
  }

  /**
   * Creates a request.
   * @param request The request's details.
   * @return requestId The ID of the request.
   */
  function createRequest(RequestParams calldata request) external nonReentrant returns (uint256 requestId) {
    return _createRequest(request);
  }

  /**
   * Creates requests.
   * @param requests The requests' details.
   * @return requestIds The IDs of the requests.
   */
  function createRequestBatch(RequestParams[] calldata requests) external nonReentrant returns (uint256[] memory requestIds) {
    uint256 len = requests.length;
    requestIds = new uint256[](len);
    for (uint256 i; i < len; i++) {
      requestIds[i] = _createRequest(requests[i]);
    }
  }

  /**
   * Performs creation of a request.
   * @param request The request's details.
   * @return requestId The ID of the request.
   */
  function _createRequest(RequestParams calldata request) internal returns (uint256 requestId) {
    uint256 quantity = request.quantity;
    address tokenContract = request.tokenContract;

    if (request.pricePerToken == 0) {
      revert InvalidPrice();
    }
    // solhint-disable-next-line not-rely-on-time
    if (request.expiry <= block.timestamp) {
      revert InvalidExpiry();
    }

    // Check interfaces
    _requireInterface(tokenContract, request.isERC1155 ? type(IERC1155).interfaceId : type(IERC721).interfaceId);
    if (request.currency == address(0)) {
      revert InvalidCurrency();
    }

    if (request.isListing) {
      // Check valid token for listing
      if (!_hasApprovedTokens(request.isERC1155, tokenContract, request.tokenId, quantity, msg.sender)) {
        revert InvalidTokenApproval(tokenContract, request.tokenId, quantity, msg.sender);
      }
    } else {
      // Check approved currency for offer inc royalty
      uint256 total = quantity * request.pricePerToken;
      (, uint256 royaltyAmount) = getRoyaltyInfo(tokenContract, request.tokenId, total);
      total += royaltyAmount;
      if (!_hasApprovedCurrency(request.currency, total, msg.sender)) {
        revert InvalidCurrencyApproval(request.currency, total, msg.sender);
      }
      // Check quantity. Covered by _hasApprovedTokens for listings
      if ((request.isERC1155 && quantity == 0) || (!request.isERC1155 && quantity != 1)) {
        revert InvalidQuantity();
      }
    }

    Request memory request = Request({
      isListing: request.isListing,
      isERC1155: request.isERC1155,
      creator: msg.sender,
      tokenContract: tokenContract,
      tokenId: request.tokenId,
      quantity: quantity,
      currency: request.currency,
      pricePerToken: request.pricePerToken,
      expiry: request.expiry
    });

    requestId = uint256(_nextRequestId);
    _nextRequestId++;
    _requests[requestId] = request;

    emit RequestCreated(
      requestId,
      msg.sender,
      tokenContract,
      request.tokenId,
      request.isListing,
      quantity,
      request.currency,
      request.pricePerToken,
      request.expiry
      );

    return requestId;
  }

  /**
   * Accepts a request.
   * @param requestId The ID of the request.
   * @param quantity The quantity of tokens to accept.
   * @param additionalFees The additional fees to pay.
   * @param additionalFeeReceivers The addresses to send the additional fees to.
   */
  function acceptRequest(
    uint256 requestId,
    uint256 quantity,
    uint256[] calldata additionalFees,
    address[] calldata additionalFeeReceivers
  )
    external
    nonReentrant
  {
    _acceptRequest(requestId, quantity, additionalFees, additionalFeeReceivers);
  }

  /**
   * Accepts requests.
   * @param requestIds The IDs of the requests.
   * @param quantities The quantities of tokens to accept.
   * @param additionalFees The additional fees to pay.
   * @param additionalFeeReceivers The addresses to send the additional fees to.
   * @dev Additional fees are applied to each request.
   */
  function acceptRequestBatch(
    uint256[] calldata requestIds,
    uint256[] calldata quantities,
    uint256[] calldata additionalFees,
    address[] calldata additionalFeeReceivers
  )
    external
    nonReentrant
  {
    uint256 len = requestIds.length;
    if (len != quantities.length) {
      revert InvalidBatchRequest();
    }

    for (uint256 i; i < len; i++) {
      _acceptRequest(requestIds[i], quantities[i], additionalFees, additionalFeeReceivers);
    }
  }

  /**
   * Performs acceptance of a request.
   * @param requestId The ID of the request.
   * @param quantity The quantity of tokens to accept.
   * @param additionalFees The additional fees to pay.
   * @param additionalFeeReceivers The addresses to send the additional fees to.
   */
  function _acceptRequest(
    uint256 requestId,
    uint256 quantity,
    uint256[] calldata additionalFees,
    address[] calldata additionalFeeReceivers
  )
    internal
  {
    Request memory request = _requests[requestId];
    if (request.creator == address(0)) {
      // Request cancelled, completed or never existed
      revert InvalidRequestId(requestId);
    }
    if (quantity == 0 || quantity > request.quantity) {
      revert InvalidQuantity();
    }
    if (_isExpired(request)) {
      revert InvalidExpiry();
    }
    if (additionalFees.length != additionalFeeReceivers.length) {
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

    address currencyReceiver = request.isListing ? request.creator : msg.sender;
    address tokenReceiver = request.isListing ? msg.sender : request.creator;

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
      TransferHelper.safeTransferFrom(request.currency, tokenReceiver, royaltyRecipient, royaltyAmount);
    }

    // Transfer additional fees
    uint256 totalFees;
    for (uint256 i; i < additionalFees.length; i++) {
      uint256 fee = additionalFees[i];
      address feeReceiver = additionalFeeReceivers[i];
      if (feeReceiver == address(0) || fee == 0) {
        revert InvalidAdditionalFees();
      }
      totalFees += fee;
      TransferHelper.safeTransferFrom(request.currency, tokenReceiver, feeReceiver, fee);
    }
    if (!request.isListing) {
      // Fees are paid by the taker. This reduces the cost for offers.
      // Underflow prevents fees > cost
      remainingCost -= totalFees;
    } else if (totalFees > remainingCost) {
      // Fees cannot exceed cost - royalties
      revert InvalidAdditionalFees();
    }

    // Transfer currency
    TransferHelper.safeTransferFrom(request.currency, tokenReceiver, currencyReceiver, remainingCost);

    // Transfer token
    if (request.isERC1155) {
      IERC1155(tokenContract).safeTransferFrom(currencyReceiver, tokenReceiver, request.tokenId, quantity, "");
    } else {
      IERC721(tokenContract).safeTransferFrom(currencyReceiver, tokenReceiver, request.tokenId);
    }

    emit RequestAccepted(requestId, msg.sender, tokenContract, quantity, _requests[requestId].quantity);
  }

  /**
   * Cancels a request.
   * @param requestId The ID of the request.
   */
  function cancelRequest(uint256 requestId) external nonReentrant {
    _cancelRequest(requestId);
  }

  /**
   * Cancels requests.
   * @param requestIds The IDs of the requests.
   */
  function cancelRequestBatch(uint256[] calldata requestIds) external nonReentrant {
    for (uint256 i; i < requestIds.length; i++) {
      _cancelRequest(requestIds[i]);
    }
  }

  /**
   * Performs cancellation of a request.
   * @param requestId The ID of the request.
   */
  function _cancelRequest(uint256 requestId) internal {
    Request storage request = _requests[requestId];
    if (request.creator != msg.sender) {
      revert InvalidRequestId(requestId);
    }
    address tokenContract = request.tokenContract;

    // Refund some gas
    delete _requests[requestId];

    emit RequestCancelled(requestId, tokenContract);
  }

  /**
   * Gets a request.
   * @param requestId The ID of the request.
   * @return request The request.
   */
  function getRequest(uint256 requestId) external view returns (Request memory request) {
    return _requests[requestId];
  }

  /**
   * Gets requests.
   * @param requestIds The IDs of the requests.
   * @return requests The requests.
   */
  function getRequestBatch(uint256[] calldata requestIds) external view returns (Request[] memory requests) {
    uint256 len = requestIds.length;
    requests = new Request[](len);
    for (uint256 i; i < len; i++) {
      requests[i] = _requests[requestIds[i]];
    }
  }

  /**
   * Checks if a request is valid.
   * @param requestId The ID of the request.
   * @param quantity The amount of tokens to exchange. 0 is assumed to be the request's available quantity.
   * @return valid The validity of the request.
   * @return request The request.
   * @notice A request is valid if it is active, has not expired and give amount of tokens (currency for offers, tokens for listings) are transferrable.
   */
  function isRequestValid(uint256 requestId, uint256 quantity) public view returns (bool valid, Request memory request) {
    request = _requests[requestId];
    if (quantity == 0) {
      // 0 is assumed to be max quantity
      quantity = request.quantity;
    }
    valid = request.creator != address(0) && !_isExpired(request) && quantity <= request.quantity;
    if (valid) {
      if (request.isListing) {
        valid = _hasApprovedTokens(request.isERC1155, request.tokenContract, request.tokenId, quantity, request.creator);
      } else {
        // Add royalty
        uint256 cost = request.pricePerToken * quantity;
        (, uint256 royaltyAmount) = getRoyaltyInfo(request.tokenContract, request.tokenId, cost);
        valid = _hasApprovedCurrency(request.currency, cost + royaltyAmount, request.creator);
      }
    }
    return (valid, request);
  }

  /**
   * Checks if requests are valid.
   * @param requestIds The IDs of the requests.
   * @param quantities The amount of tokens to exchange per request. 0 is assumed to be the request's available quantity.
   * @return valid The validities of the requests.
   * @return requests The requests.
   * @notice A request is valid if it is active, has not expired and give amount of tokens (currency for offers, tokens for listings) are transferrable.
   */
  function isRequestValidBatch(uint256[] calldata requestIds, uint256[] calldata quantities)
    external
    view
    returns (bool[] memory valid, Request[] memory requests)
  {
    uint256 len = requestIds.length;
    if (len != quantities.length) {
      revert InvalidBatchRequest();
    }
    valid = new bool[](len);
    requests = new Request[](len);
    for (uint256 i; i < len; i++) {
      (valid[i], requests[i]) = isRequestValid(requestIds[i], quantities[i]);
    }
  }

  /**
   * Checks if a request has expired.
   * @param request The request to check.
   * @return isExpired True if the request has expired.
   */
  function _isExpired(Request memory request) internal view returns (bool isExpired) {
    // solhint-disable-next-line not-rely-on-time
    return request.expiry <= block.timestamp;
  }

  /**
   * Will set the royalties fees and recipient for contracts that don't support ERC-2981.
   * @param tokenContract The contract the custom royalties apply to.
   * @param recipient Address to send the royalties to.
   * @param fee Fee percentage with a 10000 basis (e.g. 0.3% is 30 and 1% is 100 and 100% is 10000).
   * @dev Can only be called by the owner.
   * @notice This can be called even when the contract supports ERC-2891, but will be ignored if it does.
   */
  function setRoyaltyInfo(address tokenContract, address recipient, uint96 fee) public onlyOwner {
    if (fee > 10000) {
      revert InvalidRoyalty();
    }
    customRoyalties[tokenContract] = CustomRoyalty(recipient, fee);
    emit CustomRoyaltyChanged(tokenContract, recipient, fee);
  }

  /**
   * Returns the royalty details for the given token and cost.
   * @param tokenContract Address of the token being traded.
   * @param tokenId The ID of the token.
   * @param cost Amount of currency sent/received for the trade.
   * @return recipient Address to send royalties to.
   * @return royalty Amount of currency to be paid as royalties.
   */
  function getRoyaltyInfo(address tokenContract, uint256 tokenId, uint256 cost)
    public
    view
    returns (address recipient, uint256 royalty)
  {
    try IERC2981(address(tokenContract)).royaltyInfo(tokenId, cost) returns (address _r, uint256 _c) {
      return (_r, _c);
    } catch {} // solhint-disable-line no-empty-blocks

    // Fail over to custom royalty
    CustomRoyalty memory customRoyalty = customRoyalties[tokenContract];
    return (customRoyalty.recipient, customRoyalty.fee * cost / 10000);
  }

  /**
   * Checks if the amount of currency is approved for transfer exceeds the given amount.
   * @param currency The address of the currency.
   * @param amount The amount of currency.
   * @param who The address of the owner of the currency.
   * @return isValid True if the amount of currency is sufficient and approved for transfer.
   */
  function _hasApprovedCurrency(address currency, uint256 amount, address who) internal view returns (bool isValid) {
    return IERC20(currency).balanceOf(who) >= amount && IERC20(currency).allowance(who, address(this)) >= amount;
  }

  /**
   * Checks if a token contract is ERC1155 or ERC721 and if the token is owned and approved for transfer.
   * @param isERC1155 True if the token is an ERC1155 token, false if it is an ERC721 token.
   * @param tokenContract The address of the token contract.
   * @param tokenId The ID of the token.
   * @param quantity The quantity of tokens to list.
   * @param who The address of the owner of the token.
   * @return isValid True if the token is owned and approved for transfer.
   * @dev Returns false if the token contract is not ERC1155 or ERC721.
   */
  function _hasApprovedTokens(bool isERC1155, address tokenContract, uint256 tokenId, uint256 quantity, address who)
    internal
    view
    returns (bool isValid)
  {
    address market = address(this);

    if (isERC1155) {
      // ERC1155
      return quantity > 0 && IERC1155(tokenContract).balanceOf(who, tokenId) >= quantity
        && IERC1155(tokenContract).isApprovedForAll(who, market);
    }

    // ERC721
    address tokenOwner;
    address operator;

    try IERC721(tokenContract).ownerOf(tokenId) returns (address _tokenOwner) {
      tokenOwner = _tokenOwner;

      try IERC721(tokenContract).getApproved(tokenId) returns (address _operator) {
        operator = _operator;
      } catch {} // solhint-disable-line no-empty-blocks
    } catch {} // solhint-disable-line no-empty-blocks

    return quantity == 1 && who == tokenOwner
      && (operator == market || IERC721(tokenContract).isApprovedForAll(who, market));
  }

  /**
   * Checks if a contract implements an interface.
   * @param contractAddress The address of the contract.
   * @param interfaceId The interface ID.
   * @dev Reverts if the contract does not implement the interface.
   */
  function _requireInterface(address contractAddress, bytes4 interfaceId) internal view {
    if (contractAddress.code.length != 0) {
      try IERC165(contractAddress).supportsInterface(interfaceId) returns (bool supported) {
        if (supported) {
          // Success
          return;
        }
      } catch {}
    }
    // Fail over
    revert UnsupportedContractInterface(contractAddress, interfaceId);
  }
}
