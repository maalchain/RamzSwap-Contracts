pragma solidity =0.5.16;

import '../RamzSwapMAAL20.sol';

contract MAAL20 is RamzSwapMAAL20 {
    constructor(uint _totalSupply) public {
        _mint(msg.sender, _totalSupply);
    }
}
