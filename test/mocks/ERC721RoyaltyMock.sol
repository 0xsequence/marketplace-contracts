// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import {ERC721Mock} from "./ERC721Mock.sol";
import {IERC2981} from "contracts/interfaces/IERC2981.sol";

contract ERC721RoyaltyMock is ERC721Mock {
  constructor() ERC721Mock() {} // solhint-disable-line no-empty-blocks

  uint256 public royaltyFee;
  address public royaltyRecipient;
  uint256 public royaltyFee666;
  address public royaltyRecipient666;

  /**
   * @notice Called with the sale price to determine how much royalty
   * is owed and to whom.
   * @param _tokenId - the NFT asset queried for royalty information
   * @param _salePrice - the sale price of the NFT asset specified by _tokenId
   * @return receipient - address of who should be sent the royalty payment
   * @return royaltyAmount - the royalty payment amount for _salePrice
   */
  function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
    external
    view
    returns (address receipient, uint256 royaltyAmount)
  {
    if (_tokenId == 666) {
      uint256 fee = _salePrice * royaltyFee666 / 10_000;
      return (royaltyRecipient666, fee);
    } else {
      uint256 fee = _salePrice * royaltyFee / 10_000;
      return (royaltyRecipient, fee);
    }
  }

  function setFee(uint256 _fee) public {
    royaltyFee = _fee;
  }

  function set666Fee(uint256 _fee) public {
    royaltyFee666 = _fee;
  }

  function setFeeRecipient(address _recipient) public {
    royaltyRecipient = _recipient;
  }

  function set666FeeRecipient(address _recipient) public {
    royaltyRecipient666 = _recipient;
  }

  bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

  /**
   * @notice Query if a contract implements an interface
   * @param _interfaceID  The interface identifier, as specified in ERC-165
   * @return `true` if the contract implements `_interfaceID` and
   */
  function supportsInterface(bytes4 _interfaceID) public view virtual override returns (bool) {
    // Should be 0x2a55205a
    if (_interfaceID == _INTERFACE_ID_ERC2981) {
      return true;
    }
    return super.supportsInterface(_interfaceID);
  }
}
