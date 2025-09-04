// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract Mock721 is ERC721 {
    constructor() ERC721("Mock721", "MOCK") {}

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}
