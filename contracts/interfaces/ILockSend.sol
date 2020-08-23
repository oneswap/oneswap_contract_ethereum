// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

interface ILockSend {
    event Locksend(address indexed from,address indexed to,address token,uint amount,uint32 unlockTime);
    event Unlock(address indexed from,address indexed to,address token,uint amount,uint32 unlockTime);

    function lockSend(address to, uint amount, address token, uint32 unlockTime) external ;
    function unlock(address from, address to, address token, uint32 unlockTime) external ;
}
