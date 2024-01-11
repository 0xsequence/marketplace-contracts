// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

interface IOrderbookStorage {
  /**
   * Order request parameters.
   * @param isListing True if the order is a listing, false if it is an offer.
   * @param isERC1155 True if the token is an ERC1155 token, false if it is an ERC721 token.
   * @param tokenContract The address of the token contract.
   * @param tokenId The ID of the token.
   * @param quantity The quantity of tokens.
   * @param expiry The expiry of the order.
   * @param currency The address of the currency.
   * @param pricePerToken The price per token, including royalty fees.
   */
  struct OrderRequest {
    bool isListing; // True if the order is a listing, false if it is an offer.
    bool isERC1155; // True if the token is an ERC1155 token, false if it is an ERC721 token.
    address tokenContract;
    uint256 tokenId;
    uint256 quantity;
    uint96 expiry;
    address currency;
    uint256 pricePerToken;
  }

  /**
   * Order parameters.
   * @param creator The address of the order creator.
   * @param isListing True if the order is a listing, false if it is an offer.
   * @param isERC1155 True if the token is an ERC1155 token, false if it is an ERC721 token.
   * @param tokenContract The address of the token contract.
   * @param tokenId The ID of the token.
   * @param quantity The quantity of tokens.
   * @param expiry The expiry of the order.
   * @param currency The address of the currency.
   * @param pricePerToken The price per token, including royalty fees.
   */
  struct Order {
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

interface IOrderbookFunctions is IOrderbookStorage {
  /**
   * Creates an order.
   * @param request The requested order's details.
   * @return orderId The ID of the order.
   * @notice A listing is when the maker is selling tokens for currency.
   * @notice An offer is when the maker is buying tokens with currency.
   */
  function createOrder(OrderRequest calldata request) external returns (uint256 orderId);

  /**
   * Creates orders.
   * @param requests The requested orders' details.
   * @return orderIds The IDs of the orders.
   */
  function createOrderBatch(OrderRequest[] calldata requests) external returns (uint256[] memory orderIds);

  /**
   * Accepts an order.
   * @param orderId The ID of the order.
   * @param quantity The quantity of tokens to accept.
   * @param additionalFees The additional fees to pay.
   * @param additionalFeeReceivers The addresses to send the additional fees to.
   */
  function acceptOrder(
    uint256 orderId,
    uint256 quantity,
    uint256[] calldata additionalFees,
    address[] calldata additionalFeeReceivers
  )
    external;

  /**
   * Accepts orders.
   * @param orderIds The IDs of the orders.
   * @param quantities The quantities of tokens to accept.
   * @param additionalFees The additional fees to pay.
   * @param additionalFeeReceivers The addresses to send the additional fees to.
   */
  function acceptOrderBatch(
    uint256[] calldata orderIds,
    uint256[] calldata quantities,
    uint256[] calldata additionalFees,
    address[] calldata additionalFeeReceivers
  )
    external;

  /**
   * Cancels an order.
   * @param orderId The ID of the order.
   */
  function cancelOrder(uint256 orderId) external;

  /**
   * Cancels orders.
   * @param orderIds The IDs of the orders.
   */
  function cancelOrderBatch(uint256[] calldata orderIds) external;

  /**
   * Gets an order.
   * @param orderId The ID of the order.
   * @return order The order.
   */
  function getOrder(uint256 orderId) external view returns (Order memory order);

  /**
   * Gets orders.
   * @param orderIds The IDs of the orders.
   * @return orders The orders.
   */
  function getOrderBatch(uint256[] calldata orderIds) external view returns (Order[] memory orders);

  /**
   * Checks if an order is valid.
   * @param orderId The ID of the order.
   * @param quantity The amount of tokens to exchange. 0 is assumed to be the order's available quantity.
   * @return valid The validity of the order.
   * @return order The order.
   * @notice An order is valid if it is active, has not expired and give amount of tokens (currency for offers, tokens for listings) are transferrable.
   */
  function isOrderValid(uint256 orderId, uint256 quantity) external view returns (bool valid, Order memory order);

  /**
   * Checks if orders are valid.
   * @param orderIds The IDs of the orders.
   * @param quantities The amount of tokens to exchange per order. 0 is assumed to be the order's available quantity.
   * @return valid The validities of the orders.
   * @return orders The orders.
   * @notice An order is valid if it is active, has not expired and give amount of tokens (currency for offers, tokens for listings) are transferrable.
   */
  function isOrderValidBatch(uint256[] calldata orderIds, uint256[] calldata quantities)
    external
    view
    returns (bool[] memory valid, Order[] memory orders);

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

interface IOrderbookSignals {
  //
  // Events
  //

  /// Emitted when an Order is created.
  event OrderCreated(
    uint256 indexed orderId,
    address indexed creator,
    address indexed tokenContract,
    uint256 tokenId,
    bool isListing,
    uint256 quantity,
    address currency,
    uint256 pricePerToken,
    uint256 expiry
  );

  /// Emitted when an Order is accepted.
  event OrderAccepted(
    uint256 indexed orderId,
    address indexed buyer,
    address indexed tokenContract,
    uint256 quantity,
    uint256 quantityRemaining
  );

  /// Emitted when an Order is cancelled.
  event OrderCancelled(uint256 indexed orderId, address indexed tokenContract);

  /// Emitted when custom royalty settings are changed.
  event CustomRoyaltyChanged(address indexed tokenContract, address recipient, uint96 fee);

  //
  // Errors
  //

  /// Thrown when the contract address does not support the required interface.
  error UnsupportedContractInterface(address contractAddress, bytes4 interfaceId);

  /// Thrown when the token approval is invalid.
  error InvalidTokenApproval(address tokenContract, uint256 tokenId, uint256 quantity, address owner);

  /// Thrown when the currency address is invalid.
  error InvalidCurrency();

  /// Thrown when the currency approval is invalid.
  error InvalidCurrencyApproval(address currency, uint256 quantity, address owner);

  /// Thrown when order id is invalid.
  error InvalidOrderId(uint256 orderId);

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
interface IOrderbook is IOrderbookFunctions, IOrderbookSignals {}
