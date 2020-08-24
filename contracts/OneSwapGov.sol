// SPDX-License-Identifier: GPL
pragma solidity ^0.6.6;

import "./interfaces/IOneSwapToken.sol";
import "./interfaces/IOneSwapGov.sol";
import "./interfaces/IOneSwapFactory.sol";

contract OneSwapGov is IOneSwapGov {

    struct Proposal {    // FUNDS            | PARAM        | TEXT
        address addr;    // beneficiary addr | factory addr | N/A
        uint32 deadline; // unix timestamp   | same         | same
        uint32 value;    // amount of funds  | feeBPS       | N/A
        uint8 _type;     // proposal type    | same         | same
    }
    struct Vote {
        uint8 opinion;
        address prevVoter;
    }

    uint64 private constant _MAX_UINT64 = uint64(-1);
    uint8 private constant _PROPOSAL_TYPE_FUNDS = 0;
    uint8 private constant _PROPOSAL_TYPE_PARAM = 1;
    uint8 private constant _PROPOSAL_TYPE_TEXT  = 2;
    uint32 private constant _MIN_FEE_BPS = 0;
    uint32 private constant _MAX_FEE_BPS = 50;

    uint8 private constant _YES = 1;
    uint8 private constant _NO  = 2;

    uint private constant _VOTE_PERIOD = 3 days;
    uint private constant _SUBMIT_ONES_PERCENT = 1;

    address public immutable override ones;

    uint64 public override numProposals;
    mapping (uint64 => Proposal) public override proposals;
    mapping (uint64 => address) public override lastVoter;
    mapping (uint64 => mapping (address => Vote)) public override votes;
    mapping (uint64 => uint) private _yesCoins;
    mapping (uint64 => uint) private _noCoins;

    constructor(address _ones) public {
        ones = _ones;
        // numProposals = 0;
    }

    // submit new proposals
    function submitFundsProposal(string calldata title, string calldata desc, string calldata url,
            uint32 amount, address beneficiary) external override {
        if (amount > 0) {
            uint govCoins = IERC20(ones).balanceOf(address(this));
            uint dec = IERC20(ones).decimals();
            require(govCoins >= uint(amount) * (10 ** dec), "OneSwapGov: AMOUNT_TOO_LARGE");
        }
        (uint64 proposalID, uint32 deadline) = _newProposal(_PROPOSAL_TYPE_FUNDS, beneficiary, amount);
        emit NewFundsProposal(proposalID, title, desc, url, deadline, amount, beneficiary);
    }
    function submitParamProposal(string calldata title, string calldata desc, string calldata url,
            uint32 feeBPS, address factory) external override {
        require(feeBPS >= _MIN_FEE_BPS && feeBPS <= _MAX_FEE_BPS, "OneSwapGov: INVALID_FEE_BPS");
        (uint64 proposalID, uint32 deadline) = _newProposal(_PROPOSAL_TYPE_PARAM, factory, feeBPS);
        emit NewParamProposal(proposalID, title, desc, url, deadline, feeBPS, factory);
    }
    function submitTextProposal(string calldata title, string calldata desc, string calldata url) external override {
        (uint64 proposalID, uint32 deadline) = _newProposal(_PROPOSAL_TYPE_TEXT, address(0), 0);
        emit NewTextProposal(proposalID, title, desc, url, deadline);
    }

    function _newProposal(uint8 _type, address addr, uint32 value) private returns (uint64 proposalID, uint32 deadline) {
        require(_type >= _PROPOSAL_TYPE_FUNDS && _type <= _PROPOSAL_TYPE_TEXT,
            "OneSwapGov: INVALID_PROPOSAL_TYPE");

        uint totalCoins = IERC20(ones).totalSupply();
        uint thresCoins = (totalCoins/100) * _SUBMIT_ONES_PERCENT;
        uint senderCoins = IERC20(ones).balanceOf(msg.sender);

        // the sender must have enough coins
        require(senderCoins >= thresCoins, "OneSwapGov: NOT_ENOUGH_ONES");

        proposalID = numProposals;
        numProposals = numProposals+1;
        // solhint-disable-next-line not-rely-on-time
        deadline = uint32(block.timestamp + _VOTE_PERIOD);

        Proposal memory proposal;
        proposal._type = _type;
        proposal.deadline = deadline;
        proposal.addr = addr;
        proposal.value = value;
        proposals[proposalID] = proposal;

        lastVoter[proposalID] = msg.sender;
        Vote memory v;
        v.opinion = _YES;
        v.prevVoter = address(0);
        votes[proposalID][msg.sender] = v;
    }

    // Have never voted before, vote for the first time
    function vote(uint64 id, uint8 opinion) external override {
        uint balance = IERC20(ones).balanceOf(msg.sender);
        require(balance > 0, "OneSwapGov: NO_ONES");

        Proposal memory proposal = proposals[id];
        require(proposal.deadline != 0, "OneSwapGov: NO_PROPOSAL");
        // solhint-disable-next-line not-rely-on-time
        require(uint(proposal.deadline) >= block.timestamp, "OneSwapGov: DEADLINE_REACHED");

        require(_YES<=opinion && opinion<=_NO, "OneSwapGov: INVALID_OPINION");
        Vote memory v = votes[id][msg.sender];
        require(v.opinion == 0, "OneSwapGov: ALREADY_VOTED");

        v.prevVoter = lastVoter[id];
        v.opinion = opinion;
        votes[id][msg.sender] = v;

        lastVoter[id] = msg.sender;

        emit NewVote(id, msg.sender, opinion);
    }

    // Have ever voted before, need to change my opinion
    function revote(uint64 id, uint8 opinion) external override {
        require(_YES<=opinion && opinion<=_NO, "OneSwapGov: INVALID_OPINION");

        Proposal memory proposal = proposals[id];
        require(proposal.deadline != 0, "OneSwapGov: NO_PROPOSAL");
        // solhint-disable-next-line not-rely-on-time
        require(uint(proposal.deadline) >= block.timestamp, "OneSwapGov: DEADLINE_REACHED");

        Vote memory v = votes[id][msg.sender];
        // should have voted before
        require(v.opinion != 0, "OneSwapGov: NOT_VOTED");
        v.opinion = opinion;
        votes[id][msg.sender] = v;

        emit NewVote(id, msg.sender, opinion);
    }

    // Count the votes, if the result is "Pass", transfer coins to the beneficiary
    function tally(uint64 proposalID, uint64 maxEntry) external override {
        Proposal memory proposal = proposals[proposalID];
        require(proposal.deadline != 0, "OneSwapGov: NO_PROPOSAL");
        // solhint-disable-next-line not-rely-on-time
        require(uint(proposal.deadline) <= block.timestamp, "OneSwapGov: DEADLINE_NOT_REACHED");
        require(maxEntry == _MAX_UINT64 || (maxEntry > 0 && msg.sender == IOneSwapToken(ones).owner()),
            "OneSwapGov: INVALID_MAX_ENTRY");

        address currVoter = lastVoter[proposalID];
        require(currVoter != address(0), "OneSwapGov: NO_LAST_VOTER");
        uint yesCoinsSum = _yesCoins[proposalID];
        uint yesCoinsOld = yesCoinsSum;
        uint noCoinsSum = _noCoins[proposalID];
        uint noCoinsOld = noCoinsSum;

        for (uint64 i=0; i < maxEntry && currVoter != address(0); i++) {
            Vote memory v = votes[proposalID][currVoter];
            if(v.opinion == _YES) {
                yesCoinsSum += IERC20(ones).balanceOf(currVoter);
            }
            if(v.opinion == _NO) {
                noCoinsSum += IERC20(ones).balanceOf(currVoter);
            }
            delete votes[proposalID][currVoter];
            currVoter = v.prevVoter;
        }

        if (currVoter != address(0)) {
            lastVoter[proposalID] = currVoter;
            if (yesCoinsSum != yesCoinsOld) {
                _yesCoins[proposalID] = yesCoinsSum;
            }
            if (noCoinsSum != noCoinsOld) {
                _noCoins[proposalID] = noCoinsSum;
            }
        } else {
            bool ok = yesCoinsSum > noCoinsSum;
            delete proposals[proposalID];
            delete lastVoter[proposalID];
            delete _yesCoins[proposalID];
            delete _noCoins[proposalID];
            if (ok) {
                if (proposal._type == _PROPOSAL_TYPE_FUNDS) {
                    if (proposal.value > 0) {
                        uint dec = IERC20(ones).decimals();
                        IERC20(ones).transfer(proposal.addr, proposal.value * (10 ** dec));
                    }
                } else if (proposal._type == _PROPOSAL_TYPE_PARAM) {
                    IOneSwapFactory(proposal.addr).setFeeBPS(proposal.value);
                }
            }
            emit TallyResult(proposalID, ok);
        }
    }

}
