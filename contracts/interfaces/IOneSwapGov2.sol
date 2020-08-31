// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

interface IOneSwapGov2 {
    event NewFundsProposal  (uint64 proposalID, string title, string desc, string url, uint32 deadline, address beneficiary, uint256 amount);
    event NewParamProposal  (uint64 proposalID, string title, string desc, string url, uint32 deadline, address factory, uint32 feeBPS);
    event NewUpgradeProposal(uint64 proposalID, string title, string desc, string url, uint32 deadline, address factory, address pairLogic);
    event NewTextProposal   (uint64 proposalID, string title, string desc, string url, uint32 deadline);
    event NewVote(uint64 proposalID, address voter, uint8 opinion, uint112 voteAmt);
    event AddVote(uint64 proposalID, address voter, uint8 opinion, uint112 voteAmt);
    event Revote (uint64 proposalID, address voter, uint8 opinion, uint112 voteAmt);
    event TallyResult(uint64 proposalID, bool pass);

    function ones() external pure returns (address);
    function proposalInfo() external view returns (
            uint24 id, address proposer, uint8 _type, uint32 deadline, address addr, uint256 value,
            uint112 totalYes, uint112 totalNo);
    function voterInfo(address voter) external view returns (
            uint24 votedProposalID, uint8 votedOpinion, uint112 votedAmt, uint112 depositedAmt);

    function submitFundsProposal  (string calldata title, string calldata desc, string calldata url, address beneficiary, uint256 fundsAmt, uint112 voteAmt) external;
    function submitParamProposal  (string calldata title, string calldata desc, string calldata url, address factory, uint32 feeBPS, uint112 voteAmt) external;
    function submitUpgradeProposal(string calldata title, string calldata desc, string calldata url, address factory, address pairLogic, uint112 voteAmt) external;
    function submitTextProposal   (string calldata title, string calldata desc, string calldata url, uint112 voteAmt) external;
    function vote(uint8 opinion, uint112 voteAmt) external;
    function tally() external;
    function withdrawOnes(uint112 amt) external;
}
