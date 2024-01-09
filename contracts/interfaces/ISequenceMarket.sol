// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

interface ISequenceMarketStorage {
  /**
   * Request parameters.
   * @param isListing True if the request is a listing, false if it is an offer.
   * @param isERC1155 True if the token is an ERC1155 token, false if it is an ERC721 token.
   * @param tokenContract The address of the token contract.
   * @param tokenId The ID of the token.
   * @param quantity The quantity of tokens.
   * @param expiry The expiry of the request.
   * @param currency The address of the currency.
   * @param pricePerToken The price per token, including royalty fees.
   */
  struct RequestParams {
    bool isListing; // True if the request is a listing, false if it is an offer.
    bool isERC1155; // True if the token is an ERC1155 token, false if it is an ERC721 token.
    address tokenContract;
    uint256 tokenId;
    uint256 quantity;
    uint96 expiry;
    address currency;
    uint256 pricePerToken;
  }

  /**
   * Request storage.
   * @param creator The address of the request creator.
   * @param isListing True if the request is a listing, false if it is an offer.
   * @param isERC1155 True if the token is an ERC1155 token, false if it is an ERC721 token.
   * @param tokenContract The address of the token contract.
   * @param tokenId The ID of the token.
   * @param quantity The quantity of tokens.
   * @param expiry The expiry of the request.
   * @param currency The address of the currency.
   * @param pricePerToken The price per token, including royalty fees.
   */
  struct Request {
    address creator;
    bool isListing;
    bool isERC1155;
    address tokenContract;
    uint256 tokenId;
    uint256 quantity;
    uint96 expiry;
    address currency;
    uint256 pricePerToken;
  }

  /**
   * Custom royalty parameters.
   * @param recipient Address to send the fees to.
   * @param fee Fee percentage with a 10000 basis (e.g. 0.3% is 30 and 1% is 100 and 100% is 10000).
   * @dev Used to store custom royalty settings for contracts do not support ERC2981.
   */
  struct CustomRoyalty {
    address recipient;
    uint96 fee;
  }
}

interface ISequenceMarketFunctions is ISequenceMarketStorage {
  /**
   * Creates a request.
   * @param request The request's details.
   * @return requestId The ID of the request.
   * @notice A listing is when the maker is selling tokens for currency.
   * @notice An offer is when the maker is buying tokens with currency.
   */
  function createRequest(RequestParams calldata request) external returns (uint256 requestId);

  /**
   * Creates requests.
   * @param requests The requests' details.
   * @return requestIds The IDs of the requests.
   */
  function createRequestBatch(RequestParams[] calldata requests) external returns (uint256[] memory requestIds);

  /**
   * Accepts a request.
   * @param requestId The ID of the request.
   * @param quantity The quantity of tokens to accept.
   * @param receiver The receiver of the accepted tokens.
   * @param additionalFees The additional fees to pay.
   * @param additionalFeeReceivers The addresses to send the additional fees to.
   */
  function acceptRequest(
    uint256 requestId,
    uint256 quantity,
    address receiver,
    uint256[] calldata additionalFees,
    address[] calldata additionalFeeReceivers
  )
    external;

  /**
   * Accepts requests.
   * @param requestIds The IDs of the requests.
   * @param quantities The quantities of tokens to accept.
   * @param receivers The receivers of the accepted tokens.
   * @param additionalFees The additional fees to pay.
   * @param additionalFeeReceivers The addresses to send the additional fees to.
   * @dev Additional fees are applied to each request.
   */
  function acceptRequestBatch(
    uint256[] calldata requestIds,
    uint256[] calldata quantities,
    address[] calldata receivers,
    uint256[] calldata additionalFees,
    address[] calldata additionalFeeReceivers
  )
    external;

  /**
   * Cancels a request.
   * @param requestId The ID of the request.
   */
  function cancelRequest(uint256 requestId) external;

  /**
   * Cancels requests.
   * @param requestIds The IDs of the requests.
   */
  function cancelRequestBatch(uint256[] calldata requestIds) external;

  /**
   * Gets a request.
   * @param requestId The ID of the request.
   * @return request The request.
   */
  function getRequest(uint256 requestId) external view returns (Request memory request);

  /**
   * Gets requests.
   * @param requestIds The IDs of the requests.
   * @return requests The requests.
   */
  function getRequestBatch(uint256[] calldata requestIds) external view returns (Request[] memory requests);

  /**
   * Checks if a request is valid.
   * @param requestId The ID of the request.
   * @param quantity The amount of tokens to exchange. 0 is assumed to be the request's available quantity.
   * @return valid The validity of the request.
   * @return request The request.
   * @notice A request is valid if it is active, has not expired and give amount of tokens (currency for offers, tokens for listings) are transferrable.
   */
  function isRequestValid(uint256 requestId, uint256 quantity) external view returns (bool valid, Request memory request);

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
    returns (bool[] memory valid, Request[] memory requests);

  /**
   * Returns the royalty details for the given token and cost.
   * @param tokenContract Address of the token being traded.
   * @param tokenId The ID of the token.
   * @param cost Amount of currency sent/received for the trade.
   * @return recipient Address to send royalties to.
   * @return royalty Amount of currency to be paid as royalties.
   */
  function getRoyaltyInfo(address tokenContract, uint256 tokenId, uint256 cost)
    external
    view
    returns (address recipient, uint256 royalty);
}

interface ISequenceMarketSignals {
  //
  // Events
  //

  /// Emitted when a request is created.
  event RequestCreated(
    uint256 indexed requestId,
    address indexed creator,
    address indexed tokenContract,
    uint256 tokenId,
    bool isListing,
    uint256 quantity,
    address currency,
    uint256 pricePerToken,
    uint256 expiry
  );

  /// Emitted when a request is accepted.
  event RequestAccepted(
    uint256 indexed requestId,
    address indexed buyer,
    address indexed tokenContract,
    address receiver,
    uint256 quantity,
    uint256 quantityRemaining
  );

  /// Emitted when a request is cancelled.
  event RequestCancelled(uint256 indexed requestId, address indexed tokenContract);

  /// Emitted when custom royalty settings are changed.
  event CustomRoyaltyChanged(address indexed tokenContract, address recipient, uint96 fee);

  //
  // Errors
  //

  /// Thrown when the contract address does not support the required interface.
  error UnsupportedContractInterface(address contractAddress, bytes4 interfaceId);

  /// Thrown when the token approval is invalid.
  error InvalidTokenApproval(address tokenContract, uint256 tokenId, uint256 quantity, address owner);

  /// Thrown when the currency approval is invalid.
  error InvalidCurrencyApproval(address currency, uint256 quantity, address owner);

  /// Thrown when request id is invalid.
  error InvalidRequestId(uint256 requestId);

  /// Thrown when the parameters of a batch accept request are invalid.
  error InvalidBatchRequest();

  /// Thrown when quantity is invalid.
  error InvalidQuantity();

  /// Thrown when price is invalid.
  error InvalidPrice();

  /// Thrown when royalty is invalid.
  error InvalidRoyalty();

  /// Thrown when expiry is invalid.
  error InvalidExpiry();

  /// Thrown when the additional fees are invalid.
  error InvalidAdditionalFees();
}

// solhint-disable-next-line no-empty-blocks
interface ISequenceMarket is ISequenceMarketFunctions, ISequenceMarketSignals {}
