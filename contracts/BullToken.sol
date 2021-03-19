// contracts/ERC20.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BullToken is ERC20 {
    constructor() public ERC20("Bull", "Bull") {}
}
