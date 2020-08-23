// SPDX-License-Identifier: GPL
pragma solidity ^0.6.6;

import "./interfaces/IOneSwapToken.sol";


abstract contract OneSwapBlackList is IOneSwapBlackList {
    address private _owner;
    mapping(address => bool) private _isBlackListed;

    constructor() public {
        _owner = msg.sender;
    }

    function owner() public view override returns (address) {
        return _owner;
    }
    function isBlackListed(address user) public view override returns (bool) {
        return _isBlackListed[user];
    }
    modifier onlyOwner() {
        require(msg.sender == _owner, "msg.sender is not owner");
        _;
    }

    function changeOwner(address newOwner) public override onlyOwner {
        _setOwner(newOwner);
    }

    function addBlackLists(address[] calldata _evilUser) public override onlyOwner {
        for (uint i = 0; i < _evilUser.length; i++) {
            _isBlackListed[_evilUser[i]] = true;
        }
        emit AddedBlackLists(_evilUser);
    }

    function removeBlackLists(address[] calldata _clearedUser) public override onlyOwner {
        for (uint i = 0; i < _clearedUser.length; i++) {
            delete _isBlackListed[_clearedUser[i]];
        }
        emit RemovedBlackLists(_clearedUser);
    }

    function _setOwner(address newOwner) internal {
        if (newOwner != address(0)) {
            _owner = newOwner;
            emit OwnerChanged(newOwner);
        }
    }
}
