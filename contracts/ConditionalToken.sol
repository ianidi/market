// contracts/ERC20.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ConditionalToken is ERC20, ERC20Burnable, Ownable {
    constructor(string memory name_, string memory symbol_, uint8 _decimals) ERC20(name_, symbol_) public {
        _setupDecimals(decimals_);
    }

    function mint(address account, uint256 amount)
        public
        onlyOwner
    {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount)
        public
        onlyOwner
    {
        _burn(account, amount);
    }
}
