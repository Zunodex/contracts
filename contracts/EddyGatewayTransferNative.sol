// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import "./libraries/BytesHelperLib.sol";
import "./libraries/SwapHelperLib.sol";
import "./libraries/UniswapV2Library.sol";
import "./interfaces/IWETH9.sol";
import "./libraries/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/UniversalContract.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";
import {GatewayZEVM} from "@zetachain/protocol-contracts/contracts/zevm/GatewayZEVM.sol";
import "./interfaces/IEddyStableSwap.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
 

contract EddyGatewayTransferNative is UniversalContract,Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using SwapHelperLib for address;
    using BytesHelperLib for bytes;
    address public constant BTC_ZETH = 0x13A0c5930C028511Dc02665E7285134B6d11A5f4;
    address public constant WZETA = 0x5F0b1a82749cb4E2278EC87F8BF6B618dC71a8bf;
    address public constant UniswapRouter = 0x2ca7d64A7EFE2D62A725E2B35Cf7230D6677FfEe;
    address public constant UniswapFactory = 0x9fd96203f7b22bCF72d9DCb40ff98302376cE09c;
    address internal constant USDC_BSC = 0x05BA149A7bd6dC1F937fA9046A9e05C05f3b18b0;
    address internal constant USDC_ETH = 0x0cbe0dF132a6c6B4a2974Fa1b7Fb953CF0Cc798a;
    address internal constant USDT_ETH = 0x7c8dDa80bbBE1254a7aACf3219EBe1481c6E01d7;
    address internal constant ULTI_ETH = 0xe573a6e11f8506620F123DBF930222163D46BCB6;
    address internal constant ULTI_BSC = 0xD10932EB3616a937bd4a2652c87E9FeBbAce53e5;
    address internal constant USDT_BSC = 0x91d4F0D54090Df2D81e834c3c8CE71C6c865e79F;
    address internal constant FOUR_POOL = 0x448028804461e8e5a8877c228F3adFd58c3Da6B6;
    address internal constant ULTI_STABLESWAP = 0x89cb3fA2A7910A268e9f7F619108aFADBD7587c4;
    address private constant EddyTreasurySafe = 0xD8242f33A3CFf8542a3F71196eB2e63a26E6059F;
    uint16 internal constant MAX_DEADLINE = 200;
    mapping(address => uint256) public tokenToIndex;
    GatewayZEVM public gateway;
    uint256 public feePercent;
    uint256 public slippage;
    uint256 public gasLimit;

    struct WithdrawParams {
        bytes withdrawData;
        uint256 amount;
        address zrc20;
        address targetZRC20;
        uint256 amountOutMin;
        address tokenToUse;
        uint256 allowance;
        uint256 platformFeesForTx;
        address gasZRC20CC;
        uint256 gasFeeCC;
        uint256 amountsOut;
        bytes32 recipient;
        uint256 gasFee;
    }

    mapping(uint256 => address) public intermediateToken;
    mapping(uint256 => address) public chainToGateway;

    struct HandleSwapAndSendTokensParams {
        address targetZRC20;
        address gasZRC20CC;
        uint256 gasFeeCC;
        address sender;
        uint256 targetAmount;
        address inputToken;
    }

    struct DecodedMessage {
        address targetZRC20;
        bool isTargetZRC20;
        address intermediateToken;
        address contractAddress;
    }

    bytes32 public merkleRoot;
    uint256 public customFee;


    error ApprovalFailed();
    error Unauthorized();
    error IdenticalAddresses();
    error ZeroAddress();
    error WrongAmount();
    error WrongGasContract();
    error NotEnoughToPayGasFee();

    modifier onlyGateway() {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _;
    }

    event EddyCrossChainSwap(
        address zrc20,
        address targetZRC20,
        uint256 amount,
        uint256 outputAmount,
        address walletAddress,
        uint256 fees
    );


     /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     * @param gatewayAddress Gateway contract address
     * @param _feePercent Fee percentage in basis points (e.g., 10 = 1%)
     */

    function initialize(
        address payable gatewayAddress,
        uint256 _feePercent,
        uint256 _slippage,
        uint256 _gasLimit
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        gateway = GatewayZEVM(gatewayAddress);
        feePercent = _feePercent;
        slippage = _slippage;
        gasLimit = _gasLimit;
    }

    /**
     * 
     * @param message bytes message
     */

    function _getRecipient(bytes calldata message) internal pure returns (bytes32 recipient) {
        address recipientAddr = BytesHelperLib.bytesToAddress(message, 0);
        recipient = BytesHelperLib.addressToBytes(recipientAddr);
    }

    function updateIndexForToken(address token, uint256 index) external onlyOwner {
        tokenToIndex[token] = index;
    }


    function setOwner(address _owner) external onlyOwner {
        transferOwnership(_owner);
    }

    /**
     * 
     * @param data bytes data
     * @param offset offset
     */
    function bytesToBech32Bytes(
        bytes calldata data,
        uint256 offset
    ) internal pure returns (bytes memory) {
        bytes memory bech32Bytes = new bytes(42);
        for (uint i = 0; i < 42; i++) {
            bech32Bytes[i] = data[i + offset];
        }

        return bech32Bytes;
    }


    /**
     * @notice Function to update slippage
     * @param _slippage Slippage percentage in basis points (e.g., 10 = 1%)
     */
    function updateSlippage(uint256 _slippage) external onlyOwner {
        slippage = _slippage;
    }


    /**
     * Set new fee percentage only by owner
     * @param _feePercent Fee percentage in basis points (e.g., 10 = 1%)
     */
    function setFeePercent(uint256 _feePercent) public onlyOwner {
        feePercent = _feePercent;
    }

    /**
     * Set merkle root only by owner
     * @param _merkleRoot Merkle root
     */
    
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    /**
     * Set custom fee only by owner
     * @param _customFee Custom fee
     */

    function setCustomFee(uint256 _customFee) external onlyOwner {
        customFee = _customFee;
    }

    /**
     * Set gas limit only by owner
     * @param _gasLimit Gas limit
     * @dev This is the gas limit for the call on revert
     */
    
    function setGasLimit(uint256 _gasLimit) external onlyOwner {
        gasLimit = _gasLimit;
    }

    /**
     * Withdraw ZRC20 tokens using gateway
     * @param _sender Sender address
     * @param _inputToken Input token address
     * @param _outputToken Output token address
     * @param _amount Amount to withdraw
     */
    

    function withdraw(
        address _sender,
        address _inputToken,
        address _outputToken,
        uint256 _amount
    ) public {
        gateway.withdraw(
            abi.encodePacked(_sender),
            _amount,
            _outputToken,
               RevertOptions({
                    revertAddress: address(this),
                    callOnRevert: true,
                    abortAddress: address(0),
                    revertMessage: abi.encode(_sender, _inputToken),
                    onRevertGasLimit: gasLimit
                })
        );
    }

    /**
     * Withdraw Bitcoin using gateway
     * @param _sender Sender address
     * @param _inputToken Input token address
     * @param _outputToken Output token address
     * @param _amount Amount to withdraw
     */

    function withdrawBitcoin(
        bytes memory _sender,
        address _inputToken,
        address _outputToken,
        uint256 _amount
    ) public {
        gateway.withdraw(
            _sender,
            _amount,
            _outputToken,
               RevertOptions({
                    revertAddress: address(this),
                    callOnRevert: true,
                    abortAddress: address(0),
                    revertMessage: abi.encode(_sender, _inputToken),
                    onRevertGasLimit: gasLimit
                })
        );
    }


    /**
     * Withdraw and call contract function on destination chain using gateway
     * @param receiver Receiver address
     * @param amount Amount to withdraw
     * @param zrc20 ZRC20 token address
     * @param message Message
     * @param callOptions Call options
     * @param revertOptions Revert options
     */

    function withdrawAndCall(
        bytes memory receiver,
        uint256 amount,
        address zrc20,
        bytes memory message,
        CallOptions memory callOptions,
        RevertOptions memory revertOptions
    ) public {
        gateway.withdrawAndCall(
            receiver,
            amount,
            zrc20,
            message,
            callOptions,
            revertOptions
        );
    }

    /**
     * Sort tokens
     * @param tokenA Token A
     * @param tokenB Token B
     * @return token0 Token 0
     */

    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB) revert IdenticalAddresses();
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        if (token0 == address(0)) revert ZeroAddress();
    }

    /**
     * @notice Get Uniswap pair address for tokens
     * @param factory Factory address
     * @param tokenA First token
     * @param tokenB Second Token
     */

     function uniswapv2PairFor(
        address factory,
        address tokenA,
        address tokenB
    ) public pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(token0, token1)),
                            hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f" // init code hash
                        )
                    )
                )
            )
        );
    }

    /**
     * Get path for tokens
     * @param zrc20 ZRC20 token
     * @param targetZRC20 Target ZRC20 token
     * @return path Path
     */
    function getPathForTokens(
        address zrc20,
        address targetZRC20
    ) internal view returns(address[] memory path) {
        bool existsPairPool = _existsPairPool(
            UniswapFactory,
            zrc20,
            targetZRC20
        );

        if (existsPairPool) {
            path = new address[](2);
            path[0] = zrc20;
            path[1] = targetZRC20;
        } else {
            path = new address[](3);
            path[0] = zrc20;
            path[1] = WZETA;
            path[2] = targetZRC20;
        }
    }

    /**
     * Check if pair pool exists
     * @param uniswapV2Factory Uniswap V2 factory
     * @param zrc20A zrc20A
     * @param zrc20B zrc20B
     */
    function _existsPairPool(
        address uniswapV2Factory,
        address zrc20A,
        address zrc20B
    ) internal view returns (bool) {
        address uniswapPool = uniswapv2PairFor(
            uniswapV2Factory,
            zrc20A,
            zrc20B
        );
        return
            IZRC20(zrc20A).balanceOf(uniswapPool) > 0 &&
            IZRC20(zrc20B).balanceOf(uniswapPool) > 0;
    }

    /**
     * Calculate amount in max
     * @param targetZRC20 Target ZRC20
     * @param gasZRC20 Gas ZRC20
     * @param gasFee Gas fee
     * @return amountInMax Amount in max
     */
    function _calculateAmountInMax(
        address targetZRC20,
        address gasZRC20,
        uint256 gasFee
    ) private view returns (uint256) {
        uint[] memory amountsQuote = UniswapV2Library.getAmountsIn(
            UniswapFactory,
            gasFee,
            getPathForTokens(targetZRC20, gasZRC20)
        );
        return amountsQuote[0] + (slippage * amountsQuote[0]) / 1000;
    }

    /**
     * Swap and send ERC20 tokens
     * @param targetZRC20 Target ZRC20
     * @param gasZRC20 Gas ZRC20
     * @param gasFee Gas fee
     * @param recepient Receipient
     * @param targetAmount Target amount
     * @param inputToken Input token
     * @return amountsOut Amounts out
     */
  function _swapAndSendERC20Tokens(
        address targetZRC20,
        address gasZRC20,
        uint256 gasFee,
        address recepient,
        uint256 targetAmount,
        address inputToken
    ) internal returns(uint256 amountsOut) {

        // Get amountOut for Input gasToken
        uint[] memory amountsQuote = UniswapV2Library.getAmountsIn(
            UniswapFactory,
            gasFee,
            getPathForTokens(targetZRC20, gasZRC20) // [gasAmount ,zetaAmount,usdcAmount] USDC.BSC -> target , gas ->BNB.BNB
        );

        uint amountInMax = (amountsQuote[0]) + (slippage * amountsQuote[0]) / 1000;

        // Give approval to uniswap
        IZRC20(targetZRC20).approve(UniswapRouter, amountInMax);
        require(IZRC20(targetZRC20).allowance(address(this), UniswapRouter) >= amountInMax, "INSUFFICIENT_ALLOWANCE IN _swapAndSendERC20Tokens");

        // Swap gasFees for targetZRC20
        // Revert possibility
        uint[] memory amounts = IUniswapV2Router01(UniswapRouter)
            .swapTokensForExactTokens(
                gasFee, // Amount of gas token required
                amountInMax,
                getPathForTokens(targetZRC20, gasZRC20), //path[0] = targetZRC20, path[1] = gasZRC20
                address(this),
                block.timestamp + MAX_DEADLINE
        );
       
        require(IZRC20(gasZRC20).balanceOf(address(this)) >= gasFee, "INSUFFICIENT_GAS_FOR_WITHDRAW");

        require(targetAmount - amountInMax > 0, "INSUFFICIENT_AMOUNT_FOR_WITHDRAW");

        // Gateway changes
        if (!IZRC20(gasZRC20).approve(address(gateway), gasFee)) {
            revert ApprovalFailed();
        }
        
        if (!IZRC20(targetZRC20).approve(address(gateway), targetAmount - amounts[0])) {
            revert ApprovalFailed();
        }

        // Withdraw gasFees     
        withdraw(recepient,inputToken, targetZRC20, targetAmount- amounts[0]);

        amountsOut = targetAmount - amountInMax;
        
    }

    /**
     * @notice Function to swap tokens
     * @param _zrc20 ZRC20 token
     * @param _amount Amount
     * @param _targetZRC20 Target ZRC20 token
     * @param _minAmountOut Minimum amount out
     */
    function _swap(
        address _zrc20,//USDT.ETH
        uint256 _amount,
        address _targetZRC20, // USDC.BSC
        uint256 _minAmountOut
    ) internal returns (uint256 outputAmount){
         if((_zrc20 == USDC_BSC || _zrc20 == USDC_ETH || _zrc20 == USDT_ETH || _zrc20 == USDT_BSC) && (_targetZRC20 == USDC_BSC || _targetZRC20 == USDC_ETH || _targetZRC20 == USDT_ETH || _targetZRC20 == USDT_BSC)){
             IZRC20(_zrc20).approve(FOUR_POOL, _amount);
             outputAmount = IEddyStableSwap(FOUR_POOL).exchange(tokenToIndex[_zrc20],tokenToIndex[_targetZRC20], _amount, _minAmountOut);    
        }else if((_zrc20 == ULTI_ETH || _zrc20 == ULTI_BSC) && (_targetZRC20 == ULTI_ETH || _targetZRC20 == ULTI_BSC)){
             IZRC20(_zrc20).approve(ULTI_STABLESWAP, _amount);
             outputAmount = IEddyStableSwap(ULTI_STABLESWAP).exchange(tokenToIndex[_zrc20],tokenToIndex[_targetZRC20], _amount, _minAmountOut);
        }else{
            outputAmount = SwapHelperLib._doSwap(
                WZETA,
                UniswapFactory,
                UniswapRouter,
                _zrc20,
                _amount,
                _targetZRC20,
                _minAmountOut
            );
        }

    }


    /**
     * Handle fee transfer
     * @param merkleProof Merkle proof
     * @param sender Sender
     * @param isNative Is native
     * @param zrc20 ZRC20 token
     * @param amount Amount
     * @return platformFeesForTx Platform fees for transaction
     */
    
    function handleFeeTransfer(bytes32[] memory merkleProof, address sender,bool isNative,address zrc20,uint256 amount) private returns (uint256 platformFeesForTx) {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(sender))));
        bool isWhitelisted = MerkleProof.verify(merkleProof, merkleRoot, leaf);
        uint256 feeToApply = isWhitelisted ? customFee : feePercent;
        platformFeesForTx = (amount * feeToApply) / 1000; // platformFee = 5 <> 0.5%
        if(isNative){
            (bool sent, ) = payable(EddyTreasurySafe).call{value: platformFeesForTx}("");
            require(sent, "Failed to transfer zeta to treasury");
        }else{
            TransferHelper.safeTransfer(zrc20, EddyTreasurySafe,platformFeesForTx);
        }
    }
    
    
    function decodeMessage(bytes calldata message) public pure returns (DecodedMessage memory) {
        // First check basic length for required fields (target + bool)
        require(message.length >= 52, "Invalid message length"); // 20+ 32 bytes minimum
    
        // First decode the target and bool
        address targetZRC20 = BytesHelperLib.bytesToAddress(message, 0);
        bool isTargetZRC20 = abi.decode(message[20:52], (bool));


        // Initialize additional addresses to zero address
        address intermediate = address(0);  
        address contractAddress = address(0); 
    
        // Only decode additional addresses if isTargetZRC20 is FALSE and they are provided
        if (!isTargetZRC20 && message.length >= 92) {
            intermediate = BytesHelperLib.bytesToAddress(message, 52);
            contractAddress = BytesHelperLib.bytesToAddress(message,72);
        }

        return DecodedMessage({
            targetZRC20: targetZRC20,
            isTargetZRC20: isTargetZRC20,
            intermediateToken: intermediate,
            contractAddress: contractAddress
        });
        
    }

    /**
     * Transfer Zeta to connected chain
     * @param withdrawData Withdraw data
     * @param zrc20 ZRC20 token
     * @param amountOutMin Amount out min
     * @param merkleProof Merkle proof
     */
    
   function transferZetaToConnectedChain(
        bytes calldata withdrawData,
        address zrc20, // Pass WZETA address here
        uint256 amountOutMin,
        bytes32[] calldata merkleProof
    ) external payable {
        // Store fee in aZeta
        uint256 platformFeesForTx = handleFeeTransfer(merkleProof, msg.sender,true,zrc20,msg.value);

        IWETH9(WZETA).deposit{value: msg.value - platformFeesForTx}();

        DecodedMessage memory decoded = decodeMessage(withdrawData);

        address tokenToUse = decoded.isTargetZRC20 ? decoded.targetZRC20 : decoded.intermediateToken;

        uint256 outputAmount = _swap(
            zrc20,
            msg.value - platformFeesForTx,
            tokenToUse,
            amountOutMin
        );
       

        (address gasZRC20CC, uint256 gasFeeCC) = decoded.isTargetZRC20 ? IZRC20(tokenToUse).withdrawGasFee() : IZRC20(tokenToUse).withdrawGasFeeWithGasLimit(gasLimit);

        if (decoded.targetZRC20 == BTC_ZETH && decoded.isTargetZRC20) {
            bytes memory recipientAddressBech32 = bytesToBech32Bytes(withdrawData, 52);
            if (outputAmount < gasFeeCC) revert WrongAmount();

            if(!IZRC20(tokenToUse).approve(address(gateway), outputAmount + gasFeeCC)){
                revert ApprovalFailed();
            }

            withdrawBitcoin(
                recipientAddressBech32,
                zrc20,
                tokenToUse,
                outputAmount - gasFeeCC
            );

            emit EddyCrossChainSwap(
                zrc20,
                tokenToUse,
                msg.value,
                outputAmount - gasFeeCC,
                msg.sender,
                platformFeesForTx
            );
        } else if (gasZRC20CC != tokenToUse) {
            // Target token is not gas token
            // Swap tokenIn for gasFees
            // bytes32 recipient = BytesHelperLib.addressToBytes(msg.sender);
            HandleSwapAndSendTokensParams memory params;

            params.targetZRC20 = tokenToUse;
            params.gasZRC20CC = gasZRC20CC;
            params.gasFeeCC = gasFeeCC;
            params.sender = msg.sender;
            params.targetAmount =  outputAmount;
            params.inputToken = zrc20;

            uint256 amountsOut = _swapAndSendERC20Tokens(
                params.targetZRC20,
                params.gasZRC20CC,
                params.gasFeeCC,
                params.sender,
                params.targetAmount,
                params.inputToken 
            );

            emit EddyCrossChainSwap(
                zrc20,
                tokenToUse,
                msg.value,
                amountsOut,
                msg.sender,
                platformFeesForTx
            );

        }else if(decoded.isTargetZRC20 && gasZRC20CC == decoded.targetZRC20){
            
            if (gasZRC20CC != tokenToUse) revert WrongGasContract();
            
            if (gasFeeCC >= outputAmount) revert NotEnoughToPayGasFee();

            if(!IZRC20(decoded.targetZRC20).approve(address(gateway),outputAmount + gasFeeCC)){
                revert ApprovalFailed();
            }

            withdraw(
                msg.sender,
                zrc20,
                decoded.targetZRC20,
                outputAmount - gasFeeCC
            );
            
            emit EddyCrossChainSwap(
                zrc20,
                decoded.targetZRC20,
                msg.value,
                outputAmount - gasFeeCC,
                msg.sender,
                platformFeesForTx
            );

        }else {
            // EVM withdraw
            // bytes32 recipient = BytesHelperLib.addressToBytes(msg.sender);
            // Change withdraw in gateway
            // (address gasZRC20, uint256 gasFee) = IZRC20(targetZRC20)
            // .withdrawGasFee();
            
            if (gasZRC20CC != tokenToUse) revert WrongGasContract();
            
            if (gasFeeCC >= outputAmount) revert NotEnoughToPayGasFee();
            
            handleEvmWithdraw(
                decoded.contractAddress,
                zrc20,
                tokenToUse,
                decoded.targetZRC20,
                outputAmount,
                gasFeeCC
            );
            
            emit EddyCrossChainSwap(
                zrc20,
                decoded.targetZRC20,
                msg.value,
                outputAmount - gasFeeCC,
                msg.sender,
                platformFeesForTx
            );
        }


    }


    /**
     * Handler function to prepare data for withdraw and call
     * @param contractAddress Contract address
     * @param zrc20 ZRC20 token
     * @param tokenToUse Token to use
     * @param targetZRC20 Target ZRC20
     * @param outputAmount Output amount
     * @param gasFeeCC Gas fee
     */

    function handleEvmWithdraw(
        address contractAddress,
        address zrc20,
        address tokenToUse,
        address targetZRC20,
        uint256 outputAmount,
        uint256 gasFeeCC
    ) private {

        require(contractAddress != address(0), "ZERO_ADDRESS");

        require(tokenToUse != address(0), "ZERO_ADDRESS");

        if (!IZRC20(tokenToUse).approve(address(gateway), outputAmount + gasFeeCC)) {
            revert ApprovalFailed();
        }

        string memory functionSignature = "swapETHtoERC20(uint256,address,address)";
        
        // Calculate the function selector
        bytes4 selector = bytes4(keccak256(bytes(functionSignature)));

         withdrawAndCall(
            abi.encodePacked(contractAddress),
            outputAmount - gasFeeCC,
            tokenToUse,
            abi.encodeWithSelector(selector,outputAmount - gasFeeCC,targetZRC20,msg.sender),
            CallOptions({
                isArbitraryCall: true,
                gasLimit: gasLimit
            }),
            RevertOptions({
                revertAddress: address(this),
                callOnRevert: true,
                abortAddress: address(0),
                revertMessage: abi.encode(msg.sender, zrc20),
                onRevertGasLimit: gasLimit
            })
        );
    }

    /**
     * Withdraw to native chain
     * @param withdrawData Withdraw data
     * @param amount Amount
     * @param zrc20 ZRC20 token
     * @param amountOutMin Amount out min
     * @param merkleProof Merkle proof
     */
    function withdrawToNativeChain(
        bytes calldata withdrawData, 
        uint256 amount,
        address zrc20,
        uint256 amountOutMin,
        bytes32[] calldata merkleProof
    ) external {
        DecodedMessage memory decoded = decodeMessage(withdrawData);
        WithdrawParams memory params;
        params.withdrawData = withdrawData;
        params.amount = amount;
        params.zrc20 = zrc20;
        params.targetZRC20 = decoded.targetZRC20;
        params.amountOutMin = amountOutMin;
        params.tokenToUse = decoded.isTargetZRC20 ? (decoded.targetZRC20 == zrc20) ? zrc20 : decoded.targetZRC20 : decoded.intermediateToken;
        // check for approval
        params.allowance = IZRC20(zrc20).allowance(msg.sender, address(this));
        require(params.allowance > amount, "Not enough allowance of ZRC20 token");
        require(IZRC20(zrc20).transferFrom(msg.sender, address(this), amount), "INSUFFICIENT ALLOWANCE: TRANSFER FROM FAILED");
        params.platformFeesForTx = handleFeeTransfer(merkleProof,msg.sender,false,zrc20,amount); // platformFee = 5 <> 0.5%
        // TransferHelper.safeTransfer(zrc20, EddyTreasurySafe, params.platformFeesForTx);
       (params.gasZRC20CC, params.gasFeeCC) = decoded.isTargetZRC20 ? IZRC20(params.tokenToUse).withdrawGasFee() : IZRC20(params.tokenToUse).withdrawGasFeeWithGasLimit(gasLimit);
        if (decoded.targetZRC20 != zrc20) {
            params.amountsOut = _swap(
                zrc20,
                amount - params.platformFeesForTx,
                params.tokenToUse,
                amountOutMin
            ); //USDC.BSC - amtoutx
            if (decoded.targetZRC20 == BTC_ZETH) {
                bytes memory recipientAddressBech32 = bytesToBech32Bytes(withdrawData,52);
                (, params.gasFee) = IZRC20(params.tokenToUse).withdrawGasFee();
                if (params.amountsOut < params.gasFee) revert WrongAmount();
                if(!IZRC20(decoded.targetZRC20).approve(address(gateway), params.amountsOut + params.gasFee)){
                    revert ApprovalFailed();
                }
                withdrawBitcoin(recipientAddressBech32, zrc20, decoded.targetZRC20, params.amountsOut - params.gasFee);
                emit EddyCrossChainSwap(zrc20, decoded.targetZRC20, amount, params.amountsOut - params.gasFee, msg.sender, params.platformFeesForTx);
            } else if (params.gasZRC20CC != params.tokenToUse) {
                uint256 tokenAmountsOut = _swapAndSendERC20Tokens(
                    decoded.targetZRC20,
                    params.gasZRC20CC,
                    params.gasFeeCC,
                    msg.sender,
                    params.amountsOut,
                    zrc20
                );
                emit EddyCrossChainSwap(zrc20, decoded.targetZRC20, amount, tokenAmountsOut, msg.sender, params.platformFeesForTx);
            } else if(params.gasZRC20CC == params.tokenToUse && decoded.isTargetZRC20){ {
                if (params.gasZRC20CC != params.tokenToUse) revert WrongGasContract();
                
                if (params.gasFeeCC >= params.amountsOut) revert NotEnoughToPayGasFee();
                
                if(!IZRC20(params.tokenToUse).approve(address(gateway),params.amountsOut + params.gasFeeCC)){
                    revert ApprovalFailed();
                }
                
                withdraw(
                    msg.sender,
                    zrc20,
                    params.tokenToUse,
                    params.amountsOut - params.gasFeeCC
                );
                
                emit EddyCrossChainSwap(zrc20,decoded.targetZRC20, amount, params.amountsOut - params.gasFeeCC, msg.sender, params.platformFeesForTx);
            }}else {
                if (params.gasZRC20CC != params.tokenToUse) revert WrongGasContract();
                
                if (params.gasFeeCC >= params.amountsOut) revert NotEnoughToPayGasFee();


                handleEvmWithdraw(
                    decoded.contractAddress,
                    zrc20,
                    params.tokenToUse,
                    decoded.targetZRC20,
                    params.amountsOut,
                    params.gasFeeCC
                );
                emit EddyCrossChainSwap(zrc20,decoded.targetZRC20, amount, params.amountsOut - params.gasFeeCC, msg.sender, params.platformFeesForTx);
            }
        } else {
            if (decoded.targetZRC20 == BTC_ZETH) {
                bytes memory recipientAddressBech32 = bytesToBech32Bytes(withdrawData,52);
                (, params.gasFee) = IZRC20(params.tokenToUse).withdrawGasFee();
                if (amount - params.platformFeesForTx < params.gasFee) revert WrongAmount();
                if(!IZRC20(decoded.targetZRC20).approve(address(gateway), amount - params.platformFeesForTx + params.gasFee)){
                    revert ApprovalFailed();
                }
                withdrawBitcoin(recipientAddressBech32, zrc20, decoded.targetZRC20, amount - params.platformFeesForTx - params.gasFee);
                emit EddyCrossChainSwap(zrc20, decoded.targetZRC20, amount, amount - params.platformFeesForTx - params.gasFee, msg.sender, params.platformFeesForTx);
            } else if (params.gasZRC20CC != decoded.targetZRC20) {
                uint256 amountsOut = _swapAndSendERC20Tokens(
                    decoded.targetZRC20,
                    params.gasZRC20CC,
                    params.gasFeeCC,
                    msg.sender,
                    amount - params.platformFeesForTx,
                    zrc20
                );
                emit EddyCrossChainSwap(zrc20,decoded.targetZRC20, amount, amountsOut, msg.sender, params.platformFeesForTx);
             } else {
                if (params.gasZRC20CC != params.tokenToUse) revert WrongGasContract();
                
                if (params.gasFeeCC >= amount - params.platformFeesForTx) revert NotEnoughToPayGasFee();
                
                if(!IZRC20(params.tokenToUse).approve(address(gateway),amount - params.platformFeesForTx + params.gasFeeCC)){
                    revert ApprovalFailed();
                }
                
                withdraw(
                    msg.sender,
                    zrc20,
                    params.tokenToUse,
                    params.amountsOut - params.gasFeeCC
                );
                emit EddyCrossChainSwap(zrc20, decoded.targetZRC20, amount, amount - params.platformFeesForTx - params.gasFeeCC, msg.sender, params.platformFeesForTx);
            }
        }
    }


    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * Decode merkle proof from message
     * @param message Message
     * @return sender Sender
     * @return targetToken Target token
     * @return proof Proof
     */
    function decodeMerkleMessage(bytes calldata message) internal pure returns (
        address sender,
        address targetToken,
        bytes32[] memory proof
    ) {
        require(message.length >= 40, "Message too short");
        
        // First 20 bytes are the sender address
        sender = BytesHelperLib.bytesToAddress(message, 0);
        
        // Next 20 bytes are the target token address
        targetToken = BytesHelperLib.bytesToAddress(message, 20);
        
        // Skip the two addresses (40 bytes) to get to the encoded proof
        uint256 proofStart = 40;

        if(message.length < proofStart + 32) {
            proof = new bytes32[](0);
            return (sender, targetToken, proof);
        }
        
        // Get the offset of the array data
        uint256 arrayOffset;
        assembly {
            arrayOffset := calldataload(add(message.offset, proofStart))
        }
        
        // Read array length
        uint256 proofLength;
        assembly {
            let lengthPosition := add(add(message.offset, proofStart), arrayOffset)
            proofLength := calldataload(lengthPosition)
        }
        
        // Initialize proof array
        proof = new bytes32[](proofLength);
        
        // Read proof elements starting after the length
        uint256 elementsStart = proofStart + arrayOffset + 32;
        
        for(uint256 i = 0; i < proofLength; i++) {
            assembly {
                let elementPosition := add(add(message.offset, elementsStart), mul(i, 32))
                mstore(add(proof, add(32, mul(i, 32))), calldataload(elementPosition))
            }
        }
        
        return (sender, targetToken, proof);
    }

    /**
     * @notice Function called by the gateway to execute the cross-chain swap
     * @param context Message context
     * @param zrc20 ZRC20 token address
     * @param amount Amount
     * @param message Message
     * @dev Only the gateway can call this function
     */
    function onCall(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external override onlyGateway {
 
        (address senderEvmAddress, address targetZRC20,bytes32[] memory proof) = decodeMerkleMessage(message);
        // address senderEvmAddress = BytesHelperLib.bytesToAddress(message, 0)
        // address targetZRC20 = BytesHelperLib.bytesToAddress(message, 20);

        // Fee for platform
        uint256 platformFeesForTx = handleFeeTransfer(proof,senderEvmAddress,false,zrc20,amount); // platformFee = 5 <> 0.5%
        // TransferHelper.safeTransfer(zrc20, EddyTreasurySafe, platformFeesForTx);
        if (targetZRC20 == zrc20) {
            // same token
            TransferHelper.safeTransfer(targetZRC20, senderEvmAddress, amount - platformFeesForTx);
        } else {
            uint256 amountOutMin;
            uint[] memory amountsQuote = UniswapV2Library.getAmountsOut(
                UniswapFactory,
                amount - platformFeesForTx,
                getPathForTokens(zrc20, targetZRC20)
            );
            amountOutMin = (amountsQuote[amountsQuote.length - 1]) - (slippage * amountsQuote[amountsQuote.length - 1]) / 1000;
       
            // swap
            uint256 outputAmount = _swap(
                zrc20,
                amount - platformFeesForTx,
                targetZRC20,
                amountOutMin
            );

            if (targetZRC20 == WZETA) {
                // withdraw WZETA to get Zeta in 1:1 ratio
               IWETH9(WZETA).withdraw(outputAmount);
                // transfer wzeta
                payable(senderEvmAddress).transfer(outputAmount);
            } else {
                TransferHelper.safeTransfer(targetZRC20, senderEvmAddress, outputAmount);
            }
        }

        emit EddyCrossChainSwap(zrc20, targetZRC20, amount, amount - platformFeesForTx, senderEvmAddress, platformFeesForTx);       
    }
   

    /**
     * @notice Function called by the gateway to revert the cross-chain swap
     * @param context Revert context
     * @dev Only the gateway can call this function
     */
    function onRevert(RevertContext calldata context) external onlyGateway {
        (address senderEvmAddress, address zrc20) = abi.decode(context.revertMessage, (address, address));
         uint[] memory amountsQuote = UniswapV2Library.getAmountsOut(
                UniswapFactory,
                context.amount,
                getPathForTokens(context.asset,zrc20)
            );

        uint amountOutMin = (amountsQuote[amountsQuote.length - 1]) - (slippage * amountsQuote[amountsQuote.length - 1]) / 1000;

        uint256 amountOut = _swap(
            context.asset,
            context.amount,
            zrc20,
            amountOutMin
        );
        
        TransferHelper.safeTransfer(zrc20,senderEvmAddress,amountOut);
    }

    receive() external payable {}

    fallback() external payable {}
}   