// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface ISupervisedSend {
    event SupervisedSend(address indexed from,address indexed to,address indexed supervisor,address token, uint amount,uint reward,uint32 unlockTime);
    event SupervisedUnlockSend(address indexed from,address indexed to,address indexed supervisor,address token,uint amount,uint reward,uint32 unlockTime);
    event EarlyUnlockBySupervisor(address indexed from,address indexed to,address indexed supervisor,address token,uint amount,uint reward,uint32 unlockTime);
    event EarlyUnlockBySender(address indexed from,address indexed to,address indexed supervisor,address token,uint amount,uint reward,uint32 unlockTime);

    function supervisedSend(address to, address supervisor, uint112 reward, uint112 amount, address token, uint32 unlockTime, uint256 serialNumber) external ;
    function supervisedUnlockSend(address from, address to, address supervisor, address token, uint32 unlockTime, uint256 serialNumber) external ;
    function earlyUnlockBySupervisor(address from, address to, address unlockTo, address token, uint32 unlockTime, uint256 serialNumber) external ;
    function earlyUnlockBySender(address to, address supervisor, address token, uint32 unlockTime, uint256 serialNumber) external ;
}
