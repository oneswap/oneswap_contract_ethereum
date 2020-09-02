// SPDX-License-Identifier: GPL
pragma solidity 0.6.12;

import "./interfaces/ISupervisedSend.sol";
import "./libraries/SafeMath256.sol";

struct supervisedSendInfo {
    uint112 amount;
    uint112 reward;
}

contract SupervisedSend is ISupervisedSend {

    using SafeMath256 for uint;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));
    bytes4 private constant SELECTOR2 = bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));

    mapping(bytes32 => mapping (uint=> supervisedSendInfo)) public supervisedSendInfos;

    modifier afterUnlockTime(uint32 unlockTime) {
        require(uint(unlockTime) * 3600 < block.timestamp, "SupervisedSend: NOT_ARRIVING_UNLOCKTIME_YET");
        _;
    }

    modifier beforeUnlockTime(uint32 unlockTime) {
        require(uint(unlockTime) * 3600 > block.timestamp, "SupervisedSend: ALREADY_UNLOCKED");
        _;
    }

    function supervisedSend(address to, address supervisor, uint112 reward, uint112 amount, address token, uint32 unlockTime, uint256 serialNumber) public override {
        bytes32 key = _getSupervisedSendKey(msg.sender, to, supervisor, token, unlockTime);
        supervisedSendInfo memory info = supervisedSendInfos[key][serialNumber];
        require(amount > reward, "SupervisedSend: TOO_MUCH_REWARDS");
        // prevent duplicated send
        require(info.amount == 0 && info.reward == 0, "SupervisedSend: INFO_ALREADY_EXISTS");
        _safeTransferToMe(token, msg.sender, uint(amount).add(uint(reward)));
        //todo: whether or not to allow serialNumber duplicated supervisedSend
        uint updateAmount = uint(info.amount).add(amount);
        uint updateReward = uint(info.reward).add(reward);
        supervisedSendInfos[key][serialNumber]= supervisedSendInfo(uint112(updateAmount), uint112(updateReward));
        emit SupervisedSend(msg.sender, to, supervisor, token, amount, reward, unlockTime);
    }

    // normal unlock: anyone can call this function
    function supervisedUnlockSend(address from, address to, address supervisor, address token, uint32 unlockTime, uint256 serialNumber) public override afterUnlockTime(unlockTime) {
        bytes32 key = _getSupervisedSendKey(from, to, supervisor, token, unlockTime);
        supervisedSendInfo memory info = supervisedSendInfos[key][serialNumber];
        require(info.amount != 0, "SupervisedSend: UNLOCK_AMOUNT_SHOULD_BE_NONZERO");
        delete supervisedSendInfos[key][serialNumber];
        _safeTransfer(token, to, info.amount);
        if (info.reward != 0) {
            _safeTransfer(token, supervisor, info.reward);
        }

        emit SupervisedUnlockSend(from, to, supervisor, token, info.amount, info.reward, unlockTime);
    }

    // early unlock: only supervisor can call this function

    function earlyUnlockBySupervisor(address from, address to, address unlockTo, address token, uint32 unlockTime, uint256 serialNumber) public override beforeUnlockTime(unlockTime) {
        require(unlockTo == from || unlockTo == to, "SupervisedSend: UNLOCKTO_SHOULD_BE_EITHER_FROM_OR_TO");
        bytes32 key = _getSupervisedSendKey(from, to, msg.sender, token, unlockTime);
        supervisedSendInfo memory info = supervisedSendInfos[key][serialNumber];
        require(info.amount != 0, "SupervisedSend: EARLY_UNLOCK_BY_SUPERVISOR_AMOUNT_SHOULD_BE_NONZERO");
        delete supervisedSendInfos[key][serialNumber];
        _safeTransfer(token, unlockTo, info.amount);
        if (info.reward != 0) {
            _safeTransfer(token, msg.sender, info.reward);
        }
        emit EarlyUnlockBySupervisor(from, to, msg.sender, token, info.amount, info.reward, unlockTime);
    }

    // early unlock: only from can call this function
    function earlyUnlockBySender(address to, address supervisor, address token, uint32 unlockTime, uint256 serialNumber) public override beforeUnlockTime(unlockTime) {
        bytes32 key = _getSupervisedSendKey(msg.sender, to, supervisor, token, unlockTime);
        supervisedSendInfo memory info = supervisedSendInfos[key][serialNumber];
        require(info.amount != 0, "SupervisedSend: EARLY_UNLOCK_BY_SENDER_AMOUNT_SHOULD_BE_NONZERO");
        delete supervisedSendInfos[key][serialNumber];
        _safeTransfer(token, to, info.amount);
        if (info.reward != 0) {
            _safeTransfer(token, supervisor, info.reward);
        }
        emit EarlyUnlockBySender(msg.sender, to, supervisor, token, info.amount, info.reward, unlockTime);
    }

    function _getSupervisedSendKey(address from, address to, address supervisor, address token, uint32 unlockTime) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(from, to, supervisor, token, unlockTime));
    }

    function _safeTransferToMe(address token, address from, uint value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR2, from, address(this), value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'SupervisedSend: TRANSFER_TO_ME_FAILED');
    }

    function _safeTransfer(address token, address to, uint value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'SupervisedSend: TRANSFER_FAILED');
    }
}
