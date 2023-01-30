// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.1;

import {MinerAPI} from "https://github.com/Zondax/filecoin-solidity-mock-api/blob/master/contracts/v0.8/MinerAPI.sol";
import {MinerTypes} from "https://github.com/Zondax/filecoin-solidity-mock-api/blob/master/contracts/v0.8/types/MinerTypes.sol";
import "./PFSPLoanWallet.sol";

contract LoanPoolContract {
    struct Funders {
        address funder;
        uint256 amount;
    }

    struct LoanTx {
        address sp;
        uint256 amount;
        uint256 timeStarted;
    }

    address public minerApiAddress;
    Funders[] public fundersArr;
    uint256 public counter = 0;
    uint256 public maxAmount = 10 ether; // Only 10 just for testing
    address public admin;
    mapping(address => uint256) public funders;
    mapping(uint256 => LoanTx) public loanTxs;
    event LoanApplied(address indexed sp, uint256 indexed txIndex, uint256 amount);
    event Withdraw(address indexed funer, uint256 amount);

    constructor(address _minerApiAddress) {
        admin = msg.sender;
        minerApiAddress = _minerApiAddress;
    }

    function funderWithdraw(uint256 _amount) external {
        require(funders[msg.sender] > 0, "You have not funded");
        require(_amount <= funders[msg.sender], "Please input a valid amount");
        require(_amount <= address(this).balance, "Please tell admin to fund the treasury");

        funders[msg.sender] -= _amount;

        for (uint256 i = 0; i < fundersArr.length; i++) {
            if (fundersArr[i].funder == msg.sender) {
                fundersArr[i].amount -= _amount;
            }
        }

        // TODO: maybe can add a part call the Treasury Contract to add funder or update the funder amount

        address withdrawer = msg.sender;
        (bool success, ) = withdrawer.call{value: _amount}("");
        require(success, "tx failed");
        emit Withdraw(withdrawer, _amount);
    }

    function applyLoan(uint256 amount) external {
        require(amount <= maxAmount, "Please loan an amount lower than Max Amount");
        require(amount <= address(this).balance, "Please loan an amount lower than Max Amount");
        address applicant = msg.sender;

        loanTxs[counter] = LoanTx(applicant, amount, block.timestamp);

        MinerAPI minerApiInstance = MinerAPI(minerApiAddress);
        MinerTypes.ChangeBeneficiaryParams memory params;
        // beneficiary changed to our newly created LoanWallet
        address newPFSPWallet = address(new PFSPLoanWallet(admin, applicant));
        params.new_beneficiary = addressToString(newPFSPWallet);
        params.new_expiration = 180 days;
        params.new_quota = 90;
        minerApiInstance.change_beneficiary(params);

        (bool success, ) = applicant.call{value: amount}("");
        require(success, "tx failed");

        emit LoanApplied(applicant, counter, amount);
        counter++;
    }

    receive() external payable {
        // TODO: maybe can add a part call the Treasury Contract to add funder or update the funder amount
        if (funders[msg.sender] == 0) {
            funders[msg.sender] = msg.value;
        } else {
            funders[msg.sender] += msg.value;
        }

        bool funderExist = false;
        for (uint256 i = 0; i < fundersArr.length; i++) {
            if (fundersArr[i].funder == msg.sender) {
                funderExist = true;
                fundersArr[i].amount += msg.value;
            }
        }

        if (funderExist == false) fundersArr.push(Funders(msg.sender, msg.value));
    }

    function getFundersAmount(address _id) external view returns (uint256) {
        return funders[_id];
    }

    function getFundersList() external view returns (Funders[] memory) {
        return fundersArr;
    }

    function addressToString(address _addr) public pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(51);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }
}
