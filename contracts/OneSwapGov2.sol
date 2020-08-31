// SPDX-License-Identifier: GPL
pragma solidity ^0.6.6;

import "./interfaces/IOneSwapToken.sol";
import "./interfaces/IOneSwapGov2.sol";
import "./interfaces/IOneSwapFactory.sol";

contract OneSwapGov2 is IOneSwapGov2 {

    struct VoterInfo {
        uint24  votedProposal;
        uint8   votedOpinion;
        uint112 votedAmt;     // enouth to store ONES
        uint112 depositedAmt; // enouth to store ONES
    }

    uint8   private constant _PROPOSAL_TYPE_FUNDS    = 0; // ask for funds
    uint8   private constant _PROPOSAL_TYPE_PARAM    = 1; // change factory.feeBPS
    uint8   private constant _PROPOSAL_TYPE_UPGRADE  = 2; // change factory.pairLogic
    uint8   private constant _PROPOSAL_TYPE_TEXT     = 3; // pure text proposal
    uint8   private constant _YES = 1;
    uint8   private constant _NO  = 2;
    uint32  private constant _MIN_FEE_BPS = 0;
    uint32  private constant _MAX_FEE_BPS = 50;
    uint256 private constant _MAX_FUNDS_REQUEST = 5000000; // 5000000 ONES
    uint256 private constant _FAILED_PROPOSAL_COST = 1000; //    1000 ONES
    uint256 private constant _SUBMIT_ONES_PERCENT = 1; // 1%
    uint256 private constant _VOTE_PERIOD = 3 days;

    address public  immutable override ones;
    uint256 private immutable _maxFundsRequest;    // 5000000 ONES
    uint256 private immutable _failedProposalCost; //    1000 ONES

    uint24  private _proposalID;
    uint8   private _proposalType; // FUNDS            | PARAM        | UPGRADE            | TEXT
    uint32  private _deadline;     // unix timestamp   | same         | same               | same
    address private _addr;         // beneficiary addr | factory addr | factory addr       | not used
    uint256 private _value;        // amount of funds  | feeBPS       | pair logic address | not used
    address private _proposer;
    uint112 private _totalYes;
    uint112 private _totalNo;
    mapping (address => VoterInfo) private _voters;

    constructor(address _ones) public {
        ones = _ones;
        uint256 onesDec = IERC20(_ones).decimals();
        _maxFundsRequest = _MAX_FUNDS_REQUEST * (10 ** onesDec);
        _failedProposalCost  = _FAILED_PROPOSAL_COST * (10 ** onesDec);
    }

    function proposalInfo() external view override returns (
            uint24 id, address proposer, uint8 _type, uint32 deadline, address addr, uint256 value,
            uint112 totalYes, uint112 totalNo) {
        id        = _proposalID;
        proposer  = _proposer;
        _type     = _proposalType;
        deadline  = _deadline;
        value     = _value;
        addr      = _addr;
        totalYes  = _totalYes;
        totalNo   = _totalNo;
    }
    function voterInfo(address voter) external view override returns (
            uint24 votedProposalID, uint8 votedOpinion, uint112 votedAmt, uint112 depositedAmt) {
        VoterInfo memory info = _voters[voter];
        votedProposalID = info.votedProposal;
        votedOpinion    = info.votedOpinion;
        votedAmt        = info.votedAmt;
        depositedAmt    = info.depositedAmt;
    }

    // submit new proposals
    function submitFundsProposal(string calldata title, string calldata desc, string calldata url,
            address beneficiary, uint256 fundsAmt, uint112 voteAmt) external override {
        if (fundsAmt > 0) {
            require(fundsAmt <= _maxFundsRequest, "OneSwapGov2: ASK_TOO_MANY_FUNDS");
            uint256 govOnes = IERC20(ones).balanceOf(address(this));
            require(govOnes >= fundsAmt, "OneSwapGov2: INSUFFICIENT_FUNDS");
        }
        _newProposal(_PROPOSAL_TYPE_FUNDS, beneficiary, fundsAmt, voteAmt);
        emit NewFundsProposal(_proposalID, title, desc, url, _deadline, beneficiary, fundsAmt);
        _vote(_YES, voteAmt);
    }
    function submitParamProposal(string calldata title, string calldata desc, string calldata url,
            address factory, uint32 feeBPS, uint112 voteAmt) external override {
        require(feeBPS >= _MIN_FEE_BPS && feeBPS <= _MAX_FEE_BPS, "OneSwapGov2: INVALID_FEE_BPS");
        _newProposal(_PROPOSAL_TYPE_PARAM, factory, feeBPS, voteAmt);
        emit NewParamProposal(_proposalID, title, desc, url, _deadline, factory, feeBPS);
        _vote(_YES, voteAmt);
    }
    function submitUpgradeProposal(string calldata title, string calldata desc, string calldata url,
            address factory, address pairLogic, uint112 voteAmt) external override {
        _newProposal(_PROPOSAL_TYPE_UPGRADE, factory, uint256(pairLogic), voteAmt);
        emit NewUpgradeProposal(_proposalID, title, desc, url, _deadline, factory, pairLogic);
        _vote(_YES, voteAmt);
    }
    function submitTextProposal(string calldata title, string calldata desc, string calldata url,
            uint112 voteAmt) external override {
        _newProposal(_PROPOSAL_TYPE_TEXT, address(0), 0, voteAmt);
        emit NewTextProposal(_proposalID, title, desc, url, _deadline);
        _vote(_YES, voteAmt);
    }

    function _newProposal(uint8 _type, address addr, uint256 value, uint112 voteAmt) private {
        require(_type >= _PROPOSAL_TYPE_FUNDS && _type <= _PROPOSAL_TYPE_TEXT,
            "OneSwapGov2: INVALID_PROPOSAL_TYPE");
        require(_type == _PROPOSAL_TYPE_TEXT || msg.sender == IOneSwapToken(ones).owner(),
            "OneSwapGov2: NOT_ONES_OWNER");
        require(_deadline == 0, "OneSwapGov2: LAST_PROPOSAL_NOT_FINISHED");

        uint256 totalOnes = IERC20(ones).totalSupply();
        uint256 thresOnes = (totalOnes/100) * _SUBMIT_ONES_PERCENT;
        require(voteAmt >= thresOnes, "OneSwapGov2: VOTE_AMOUNT_TOO_LESS");

        _proposalID++;
        _proposalType = _type;
        _proposer = msg.sender;
        // solhint-disable-next-line not-rely-on-time
        _deadline = uint32(block.timestamp + _VOTE_PERIOD);
        _value = value;
        _addr = addr;
        _totalYes = 0;
        _totalNo = 0;
    }
 
    function vote(uint8 opinion, uint112 voteAmt) external override {
        require(_YES <= opinion && opinion <= _NO, "OneSwapGov2: INVALID_OPINION");
        // require(_deadline > 0, "OneSwapGov2: NO_PROPOSAL");
        // solhint-disable-next-line not-rely-on-time
        require(uint256(_deadline) >= block.timestamp, "OneSwapGov2: DEADLINE_REACHED");
        _vote(opinion, voteAmt);
    }

    function _vote(uint8 opinion, uint112 addedVoteAmt) private {
        require(addedVoteAmt > 0, "OneSwapGov2: ZERO_VOTE_AMOUNT");

        (uint24 currProposalID, uint24 votedProposalID,
            uint8 votedOpinion, uint112 votedAmt, uint112 depositedAmt) = _getVoterInfo();

        // cancel previous votes if opinion changed
        bool isRevote = false;
        if ((votedProposalID == currProposalID) && (votedOpinion != opinion)) {
            if (votedOpinion == _YES) {
                assert(_totalYes >= votedAmt);
                _totalYes -= votedAmt;
            } else {
                assert(_totalNo >= votedAmt);
                _totalNo -= votedAmt;
            }
            votedAmt = 0;
            isRevote = true;
        }

        // need to deposit more ONES?
        assert(depositedAmt >= votedAmt);
        if (addedVoteAmt > depositedAmt - votedAmt) {
            uint112 moreDeposit = addedVoteAmt - (depositedAmt - votedAmt);
            depositedAmt += moreDeposit;
            IERC20(ones).transferFrom(msg.sender, address(this), moreDeposit);
        }

        if (opinion == _YES) {
            _totalYes += addedVoteAmt;
        } else {
            _totalNo += addedVoteAmt;
        }
        votedAmt += addedVoteAmt;
        _setVoterInfo(currProposalID, opinion, votedAmt, depositedAmt);
 
        if (isRevote) {
            emit Revote(currProposalID, msg.sender, opinion, addedVoteAmt);
        } else if (votedAmt > addedVoteAmt) {
            emit AddVote(currProposalID, msg.sender, opinion, addedVoteAmt);
        } else {
            emit NewVote(currProposalID, msg.sender, opinion, addedVoteAmt);
        }
    }
    function _getVoterInfo() private view returns (uint24 currProposalID,
            uint24 votedProposalID, uint8 votedOpinion, uint112 votedAmt, uint112 depositedAmt) {
        currProposalID = _proposalID;
        VoterInfo memory voter = _voters[msg.sender];
        depositedAmt = voter.depositedAmt;
        if (voter.votedProposal == currProposalID) {
            votedProposalID = currProposalID;
            votedOpinion = voter.votedOpinion;
            votedAmt = voter.votedAmt;
        }
    }
    function _setVoterInfo(uint24 proposalID,
            uint8 opinion, uint112 votedAmt, uint112 depositedAmt) private {
        _voters[msg.sender] = VoterInfo({
            votedProposal: proposalID,
            votedOpinion: opinion,
            votedAmt: votedAmt,
            depositedAmt: depositedAmt
        });
    }

    function tally() external override {
        require(_deadline > 0, "OneSwapGov2: NO_PROPOSAL");
        // solhint-disable-next-line not-rely-on-time
        require(uint256(_deadline) <= block.timestamp, "OneSwapGov2: STILL_VOTING");

        bool ok = _totalYes > _totalNo;
        uint8 _type = _proposalType;
        uint256 val = _value;
        address addr = _addr;
        address proposer = _proposer;
        _resetProposal();
        if (ok) {
            _execProposal(_type, addr, val);
        } else {
            _taxProposer(proposer);
        }
        emit TallyResult(_proposalID, ok);
    }
    function _resetProposal() private {
        _proposalType = 0;
        _deadline     = 0;
        _value        = 0;
        _addr         = address(0);
        _proposer     = address(0);
        _totalYes     = 0;
        _totalNo      = 0;
    }
    function _execProposal(uint8 _type, address addr, uint256 val) private {
        if (_type == _PROPOSAL_TYPE_FUNDS) {
            if (val > 0) {
                IERC20(ones).transfer(addr, val);
            }
        } else if (_type == _PROPOSAL_TYPE_PARAM) {
            IOneSwapFactory(addr).setFeeBPS(uint32(val));
        } else if (_type == _PROPOSAL_TYPE_UPGRADE) {
            IOneSwapFactory(addr).setPairLogic(address(val));
        }
    }
    function _taxProposer(address proposerAddr) private {
        // burn 1000 ONES of proposer
        uint256 cost = _failedProposalCost;

        VoterInfo memory proposerInfo = _voters[proposerAddr];
        if (proposerInfo.depositedAmt > cost) {
            proposerInfo.depositedAmt -= uint112(cost);
        } else { // unreachable!
            cost = proposerInfo.depositedAmt;
            proposerInfo.depositedAmt = 0;
        }
        _voters[proposerAddr] = proposerInfo;

        IOneSwapToken(ones).burn(cost);
    }

    function withdrawOnes(uint112 amt) external override {
        VoterInfo memory voter = _voters[msg.sender];

        require(_deadline == 0 || voter.votedProposal < _proposalID, "OneSwapGov2: IN_VOTING");
        require(amt > 0 && amt <= voter.depositedAmt, "OneSwapGov2: INVALID_WITHDRAW_AMOUNT");

        voter.depositedAmt -= amt;
        if (voter.depositedAmt == 0) {
            delete _voters[msg.sender];
        } else {
            _voters[msg.sender] = voter;
        }
        IERC20(ones).transfer(msg.sender, amt);
    }

}
