// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

interface IOneSwapGov {
    event NewFundsProposal(uint64 proposalID, string title, string desc, string url, uint32 deadline, uint32 amount, address beneficiary);
    event NewParamProposal(uint64 proposalID, string title, string desc, string url, uint32 deadline, uint32 feeBPS, address factory);
    event NewTextProposal(uint64 proposalID, string title, string desc, string url, uint32 deadline);
    event NewVote(uint64 proposalID, address voter, uint8 opinion);
    event TallyResult(uint64 proposalID, bool pass);

    function ones() external pure returns (address);
    function numProposals() external view returns (uint64);
    function proposals(uint64 proposalID) external view returns (address addr, uint32 deadline, uint32 value, uint8 _type);
    function lastVoter(uint64 proposalID) external view returns (address);
    function votes(uint64 proposalID, address voter) external view returns (uint8 opinion, address prevVoter);

    function submitFundsProposal(string calldata title, string calldata desc, string calldata url, uint32 amount, address beneficiary) external;
    function submitParamProposal(string calldata title, string calldata desc, string calldata url, uint32 feeBPS, address factory) external;
    function submitTextProposal(string calldata title, string calldata desc, string calldata url) external;
    function vote(uint64 proposalID, uint8 opinion) external;
    function revote(uint64 proposalID, uint8 opinion) external;
    function tally(uint64 proposalID, uint64 maxEntry) external;
}
