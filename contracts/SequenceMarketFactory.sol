// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import {SequenceMarket} from "./SequenceMarket.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract SequenceMarketFactory {
  address public implementation;

  constructor() {
    implementation = address(new SequenceMarket());
  }

  function deploy(bytes32 salt, address owner) external returns (address proxy) {
    bytes32 saltedHash = keccak256(abi.encodePacked(salt, owner, implementation));
    bytes memory bytecode = _getDeployBytecode(owner);
    proxy = Create2.deploy(0, saltedHash, bytecode);
  }

  function predictAddress(bytes32 salt, address owner) external view returns (address) {
    bytes32 saltedHash = keccak256(abi.encodePacked(salt, owner, implementation));
    bytes memory bytecode = _getDeployBytecode(owner);
    bytes32 bytecodeHash = keccak256(bytecode);
    return Create2.computeAddress(saltedHash, bytecodeHash);
  }

  function _getDeployBytecode(address owner) internal view returns (bytes memory) {
    bytes memory initData = abi.encodeWithSelector(SequenceMarket.initialize.selector, owner);
    return abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initData));
  }
}
