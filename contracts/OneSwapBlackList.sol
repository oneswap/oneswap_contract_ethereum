// SPDX-License-Identifier: GPL
pragma solidity 0.6.12;

import "./interfaces/IOneSwapToken.sol";


abstract contract OneSwapBlackList is IOneSwapBlackList {
    address private _owner;
    address private _newOwner;
    mapping(address => bool) private _isBlackListed;

    constructor() public {
        _owner = msg.sender;
    }

    function owner() public view override returns (address) {
        return _owner;
    }

    function newOwner() public view override returns (address) {
        return _newOwner;
    }

    function isBlackListed(address user) public view override returns (bool) {
        return _isBlackListed[user];
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "OneSwapToken: MSG_SENDER_IS_NOT_OWNER");
        _;
    }

    modifier onlyNewOwner() {
        require(msg.sender == _newOwner, "OneSwapToken: MSG_SENDER_IS_NOT_NEW_OWNER");
        _;
    }

    function changeOwner(address ownerToSet) public override onlyOwner {
        require(ownerToSet != address(0), "OneSwapToken: INVALID_OWNER_ADDRESS");
        require(ownerToSet != _owner, "OneSwapToken: NEW_OWNER_IS_THE_SAME_AS_CURRENT_OWNER");
        require(ownerToSet != _newOwner, "OneSwapToken: NEW_OWNER_IS_THE_SAME_AS_CURRENT_NEW_OWNER");

        _newOwner = ownerToSet;
    }

    function updateOwner() public override onlyNewOwner {
        _owner = _newOwner;
        emit OwnerChanged(_newOwner);
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

}
