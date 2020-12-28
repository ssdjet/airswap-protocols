/*
  Copyright 2020 Swap Holdings Ltd.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/cryptography/MerkleProof.sol";

/**
 * @title Pool: Claim Tokens Based on a Pricing Function
 */
contract Pool is Ownable {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  uint256 internal constant MAX_PERCENTAGE = 100;
  bytes1 internal constant UNCLAIMED = 0x00;
  bytes1 internal constant CLAIMED = 0x01;

  // Larger the scale, lower the output for a claim
  uint256 public scale;

  // Max percentage for a claim with infinite score
  uint256 public max;

  // Mapping of tree root to boolean to enable claims
  mapping(bytes32 => bool) public roots;

  // Mapping of tree root to account to mark as claimed
  mapping(bytes32 => mapping(address => bytes1)) public claimed;

  /**
   * @notice Events
   */
  event Enable(bytes32 root);
  event Withdraw(
    bytes32[] roots,
    address account,
    address token,
    uint256 amount
  );
  event SetScale(uint256 scale);
  event SetMax(uint256 max);

  /**
   * @notice Structs
   */
  struct Claim {
    bytes32 root;
    uint256 score;
    bytes32[] proof;
  }

  /**
   * @notice Constructor
   * @param _scale uint256
   * @param _max uint256
   */
  constructor(uint256 _scale, uint256 _max) public {
    require(_max <= MAX_PERCENTAGE, "MAX_TOO_HIGH");
    scale = _scale;
    max = _max;
  }

  /**
   * @notice Enables claims for a merkle tree of a set of scores
   * @param root bytes32
   */
  function enable(bytes32 root) external onlyOwner {
    require(roots[root] == false, "ROOT_EXISTS");
    roots[root] = true;
    emit Enable(root);
  }

  /**
   * @notice Withdraw tokens from the pool using claims
   * @param claims Claim[]
   * @param token address
   */
  function withdraw(Claim[] memory claims, address token) external {
    require(claims.length > 0, "CLAIMS_MUST_BE_PROVIDED");
    uint256 totalScore = 0;
    bytes32[] memory rootList = new bytes32[](claims.length);
    Claim memory claim;
    for (uint256 i = 0; i < claims.length; i++) {
      claim = claims[i];
      require(roots[claim.root], "ROOT_NOT_ENABLED");
      require(
        claimed[claim.root][msg.sender] == UNCLAIMED,
        "CLAIM_ALREADY_MADE"
      );
      require(
        verify(msg.sender, claim.root, claim.score, claim.proof),
        "PROOF_INVALID"
      );
      totalScore = totalScore.add(claim.score);
      claimed[claim.root][msg.sender] = CLAIMED;
    }
    uint256 amount = calculate(totalScore, token);
    IERC20(token).safeTransfer(msg.sender, amount);
    emit Withdraw(rootList, msg.sender, token, amount);
  }

  /**
   * @notice Calculate output amount for an input score
   * @param score uint256
   * @param token address
   */
  function calculate(uint256 score, address token)
    public
    view
    returns (uint256 amount)
  {
    return
      (
        max.mul(
          (score.mul(IERC20(token).balanceOf(address(this)))).div(
            ((uint256(10)**scale).add(score))
          )
        )
      )
        .div(100);
  }

  /**
   * @notice Verify a claim proof
   * @param participant address
   * @param root bytes32
   * @param score uint256
   * @param proof bytes32[]
   */
  function verify(
    address participant,
    bytes32 root,
    uint256 score,
    bytes32[] memory proof
  ) public view returns (bool valid) {
    bytes32 leaf = keccak256(abi.encodePacked(participant, score));
    return MerkleProof.verify(proof, root, leaf);
  }

  /**
   * @notice Set scale
   * @dev Only owner
   */
  function setScale(uint256 _scale) external onlyOwner {
    scale = _scale;
    emit SetScale(scale);
  }

  /**
   * @notice Set max
   * @dev Only owner
   */
  function setMax(uint256 _max) external onlyOwner {
    require(_max <= MAX_PERCENTAGE, "MAX_TOO_HIGH");
    max = _max;
    emit SetMax(max);
  }
}
