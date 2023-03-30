// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {IWallet} from "src/wallet/IWallet.sol";
import {IWalletFactory} from "src/wallet/IWalletFactory.sol";
import {IEntryPoint} from "src/interfaces/IEntryPoint.sol";
import {UserOperation} from "src/interfaces/UserOperation.sol";
import {createSignature} from "test/utils/createSignature.sol";
import {getUserOpHash} from "test/utils/getUserOpHash.sol";
import {MumbaiConfig} from "config/MumbaiConfig.sol";

contract EntToEndTestWalletDeploy is Test {
    IEntryPoint public constant entryPoint = IEntryPoint(MumbaiConfig.ENTRY_POINT);
    IWalletFactory public constant walletFactory = IWalletFactory(MumbaiConfig.FACTORY);

    address payable public beneficiary = payable(MumbaiConfig.BENEFICIARY);
    uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY_TESTNET");
    address walletOwner = MumbaiConfig.WALLET_OWNER;

    // Test case
    bytes32 public userOpHash;
    address aggregator;
    uint256 missingWalletFunds;
    bytes32 salt = keccak256(abi.encodePacked(address(walletFactory), address(entryPoint), block.timestamp));

    UserOperation public userOp;

    function setUp() public {
        // 0. Determine what the sender account will be beforehand
        address sender = walletFactory.computeAddress(address(entryPoint), walletOwner, salt);
        vm.deal(sender, 1 ether);

        // 1. Generate a userOperation
        userOp = UserOperation({
            sender: sender,
            nonce: 0, // 0 nonce, wallet is not deployed and won't be called
            initCode: "",
            callData: "",
            callGasLimit: 2_000_000,
            verificationGasLimit: 3_000_000,
            preVerificationGas: 1_000_000,
            maxFeePerGas: 1_000_105_660,
            maxPriorityFeePerGas: 1_000_000_000,
            paymasterAndData: "",
            signature: ""
        });

        // 2. Set initCode, to trigger wallet deploy
        bytes memory initCode = abi.encodePacked(
            abi.encodePacked(address(walletFactory)),
            abi.encodeWithSelector(walletFactory.deployWallet.selector, address(entryPoint), walletOwner, salt)
        );
        userOp.initCode = initCode;

        // Sign userOperation and attach signature
        userOpHash = entryPoint.getUserOpHash(userOp);
        bytes memory signature = createSignature(userOp, userOpHash, ownerPrivateKey, vm);
        userOp.signature = signature;

        // Set remainder of test case
        aggregator = address(0);
        missingWalletFunds = 1096029019333521;

        // 3. Fund deployer with ETH
        vm.deal(address(MumbaiConfig.DEPLOYER), 5 ether);
    }

    /// @notice Validate that the WalletFactory deploys a smart wallet
    function testWalletFactoryDeploy() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // Deploy wallet through the entryPoint
        entryPoint.handleOps(userOps, beneficiary);

        // Verify wallet was deployed as expected
        address expectedWalletAddress = walletFactory.computeAddress(address(entryPoint), walletOwner, salt);
        IWallet deployedWallet = IWallet(expectedWalletAddress);

        // Extract the code at the expected address
        uint256 codeSize = expectedWalletAddress.code.length;
        assertGt(codeSize, 0);
        assertEq(deployedWallet.owner(), walletOwner);
        assertEq(deployedWallet.entryPoint(), address(entryPoint));
    }
}