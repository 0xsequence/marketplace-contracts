// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import {ISequenceMarketFunctions} from "./interfaces/ISequenceMarket.sol";

error InvalidBatchRequest();

contract BatchPayableHelper {
  /**
   * Accepts requests.
   * @param market The market to accept requests on.
   * @param requestIds The IDs of the requests.
   * @param quantities The quantities of tokens to accept.
   * @param recipients The recipients of the accepted tokens.
   * @param additionalFees The additional fees to pay.
   * @param additionalFeeRecipients The addresses to send the additional fees to.
   * @dev Additional fees are applied to each request.
   */
  function acceptRequestBatch(
    ISequenceMarketFunctions market,
    uint256[] calldata requestIds,
    uint256[] calldata quantities,
    address[] calldata recipients,
    uint256[] calldata additionalFees,
    address[] calldata additionalFeeRecipients
  ) external payable {
    if (requestIds.length != quantities.length || requestIds.length != recipients.length) {
      revert InvalidBatchRequest();
    }

    for (uint256 i = 0; i < requestIds.length; i++) {
      market.acceptRequest{value: address(this).balance}(
        requestIds[i], quantities[i], recipients[i], additionalFees, additionalFeeRecipients
      );
    }

    // Return any remaining ETH
    if (address(this).balance > 0) {
      payable(msg.sender).transfer(address(this).balance);
    }
  }

  receive() external payable {}
}
