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
import "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract EddyGatewayCrossChain is UniversalContract,Initializable, OwnableUpgradeable, UUPSUpgradeable{
    address public constant BTC_ZETH = 0x13A0c5930C028511Dc02665E7285134B6d11A5f4;
    address public constant WZETA = 0x5F0b1a82749cb4E2278EC87F8BF6B618dC71a8bf;
    address internal constant USDC_BSC = 0x05BA149A7bd6dC1F937fA9046A9e05C05f3b18b0;
    address internal constant USDC_ETH = 0x0cbe0dF132a6c6B4a2974Fa1b7Fb953CF0Cc798a;
    address internal constant USDT_ETH = 0x7c8dDa80bbBE1254a7aACf3219EBe1481c6E01d7;
    address internal constant USDT_BSC = 0x91d4F0D54090Df2D81e834c3c8CE71C6c865e79F;
    address public constant UniswapRouter = 0x2ca7d64A7EFE2D62A725E2B35Cf7230D6677FfEe;
    address public constant UniswapFactory = 0x9fd96203f7b22bCF72d9DCb40ff98302376cE09c;
    uint16 internal constant MAX_DEADLINE = 200;
    address private constant EddyTreasurySafe = 0xD8242f33A3CFf8542a3F71196eB2e63a26E6059F;
    address internal constant FOUR_POOL = 0x448028804461e8e5a8877c228F3adFd58c3Da6B6;
    address internal constant ULTI_STABLESWAP = 0x89cb3fA2A7910A268e9f7F619108aFADBD7587c4;
    address internal constant ULTI_ETH = 0xe573a6e11f8506620F123DBF930222163D46BCB6;
    address internal constant ULTI_BSC = 0xD10932EB3616a937bd4a2652c87E9FeBbAce53e5;
    uint256 public feePercent;
    uint256 public gasLimit;
    uint256 public slippage;
    mapping(address => uint256) public tokenToIndex;
    GatewayZEVM public gateway;
    struct DecodedMessage {
        address targetZRC20;
        bool isTargetZRC20;
        address intermediateToken;
        address contractAddress;
        bytes32[] proof;
        uint32 destChainId;
        bool isV3Swap;
    }
    bytes32 public merkleRoot;
    uint256 public customFee;
    uint256 constant BITCOIN = 8332;
    mapping (uint256 => address) public chainToContract;
    mapping (uint256 => address) public chainToIntermediateToken;
    address constant abortAddress = address(0);
     struct HandleSwapAndSendTokensParams {
        address targetZRC20;
        address gasZRC20CC;
        uint256 gasFeeCC;
        address sender;
        uint256 targetAmount;
        address inputToken;
    }
    uint32 constant BITCOIN_EDDY = 9999; // chain Id from eddy db
    uint32 constant SOLANA_EDDY = 88888; // chain Id from eddy db
    mapping (uint256 => address) public solanaTokenToZrc20;
    mapping(address => uint24) public feeTierToToken;
    address internal constant UNISWAP_ROUTER_V3 = 0x9b30CfbACD3504252F82263F72D6acf62bf733C2;
    address internal constant QUOTER_V2 = 0xce1b1d19d0D16326f5D7Ea315adB376a93ABC84d;
    error WrongAmount();
    error ApprovalFailed();
    error NoPriceData();
    error IdenticalAddresses();
    error ZeroAddress();
    error Unauthorized();
    error WrongGasContract();
    error NotEnoughToPayGasFee();

    modifier onlyGateway() {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Function to update slippage
     * @param _slippage Slippage percentage in basis points (e.g., 10 = 1%)
     */
    function updateSlippage(uint256 _slippage) external onlyOwner {
        slippage = _slippage;
    }

    function updateIndexForToken(address token, uint256 index) external onlyOwner {
        tokenToIndex[token] = index;
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
     */

    function setGasLimit(uint256 _gasLimit) external onlyOwner {
        gasLimit = _gasLimit;
    }

    /**
     * Function to update mapping of fee tier to token
     * @param token Token address
     * @param feeTier Univ3 fee tier
     */
    function updateFeeTierToToken(address token, uint24 feeTier) external onlyOwner {
        feeTierToToken[token] = feeTier;
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

    event EddyCrossChainSwap(
        address zrc20,
        address targetZRC20,
        uint256 amount,
        uint256 outputAmount,
        address walletAddress,
        uint256 fees
    );

     function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @notice Function to add contract address on destination chain
     * @param chainId Chain ID 
     * @param contractAddress  Contract address on destination chain 
     */
    function addChainToContract(uint256 chainId, address contractAddress) external onlyOwner {
        chainToContract[chainId] = contractAddress;
    }


    /**
     * @notice Function to add intermediate token address on destination chain
     * @param chainId Chain ID 
     * @param intermediateToken ZRC20 address of intermediate token
     */
    function addChainToIntermediateToken(uint256 chainId, address intermediateToken) external onlyOwner {
        chainToIntermediateToken[chainId] = intermediateToken;
    }

    /**
     * @notice Function to add solana token to zrc20 mapping
     * @param tokenId Token ID
     * @param zrc20 ZRC20 address
     */
    function addSolanaTokenToZrc20(uint256 tokenId, address zrc20) external onlyOwner {
        solanaTokenToZrc20[tokenId] = zrc20;

    }

    /**
     * @notice Function to decode solana wallet address
     * @param data Data 
     * @param offset Offset
     */
    function bytesToSolana(
        bytes calldata data,
        uint256 offset
    ) internal pure returns (bytes memory) {
        bytes memory bech32Bytes = new bytes(44);
        for (uint i = 0; i < 44; i++) {
            bech32Bytes[i] = data[i + offset];
        }
        return bech32Bytes;
    }

    /**
     * @notice - Function to withdraw using gateway
     * @param _sender Sender address
     * @param _inputToken input token address
     * @param _outputToken output token address
     * @param _amount amount to withdraw
     */
    function withdraw(
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
                    abortAddress: abortAddress,
                    revertMessage: abi.encode(_sender, _inputToken),
                    onRevertGasLimit: gasLimit
                })
        );
    }

    /**
     * Swap and send ERC20 tokens
     * @param targetZRC20 Target ZRC20
     * @param gasZRC20 Gas ZRC20
     * @param gasFee Gas fee
     * @param recipient Receipient
     * @param targetAmount Target amount
     * @param inputToken Input token
     * @return amountsOut Amounts out
     */

    function _swapAndSendERC20TokensUniV2(
        address targetZRC20,
        address gasZRC20,
        uint256 gasFee,
        bytes memory recipient,
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

        withdraw(recipient,inputToken, targetZRC20, targetAmount- amounts[0]);

        amountsOut = targetAmount - amountInMax;
        
    }

    /**
     * Swap and send ERC20 tokens
     * @param targetZRC20 Target ZRC20
     * @param gasZRC20 Gas ZRC20
     * @param gasFee Gas fee
     * @param recipient Recipient
     * @param targetAmount Target amount
     * @param inputToken Input token
     * @return amountsOut Amounts out
     */
    function _swapAndSendERC20UniV3(
       address targetZRC20,
        address gasZRC20,
        uint256 gasFee,
        bytes memory recipient,
        uint256 targetAmount,
        address inputToken
    ) internal returns(uint256 amountsOut) {
        uint24 feeTierTarget = feeTierToToken[targetZRC20];
        uint24 feeTierGas = feeTierToToken[gasZRC20];
        bytes memory path;
        if(targetZRC20 == USDC_ETH){
            // @dev - path in reverse order
            path = abi.encodePacked(gasZRC20,feeTierGas,targetZRC20);
        }else {
            //@dev - path in reverse order
            path = abi.encodePacked(gasZRC20,feeTierGas,USDC_ETH,feeTierTarget,targetZRC20);
        }
        // Get amountOut for Input gasToken
        (uint256 amountInMax, , , ) = IQuoterV2(address(QUOTER_V2)).quoteExactOutput(path, gasFee);
        amountInMax =  amountInMax + (slippage * amountInMax) / 1000;
        // Give approval to uniswap
        IZRC20(targetZRC20).approve(UNISWAP_ROUTER_V3, amountInMax);
        require(IZRC20(targetZRC20).allowance(address(this), UNISWAP_ROUTER_V3) >= amountInMax, "INSUFFICIENT_ALLOWANCE IN _swapAndSendERC20Tokens");

        // Execute the swap using Uniswap V3
        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: path,
            recipient: address(this),
            deadline: block.timestamp + MAX_DEADLINE,
            amountOut: gasFee,
            amountInMaximum: amountInMax
        });

        // Swap gasFees for targetZRC20
        uint256 amountUsed = ISwapRouter(UNISWAP_ROUTER_V3).exactOutput(params);

        require(IZRC20(gasZRC20).balanceOf(address(this)) >= gasFee, "INSUFFICIENT_GAS_FOR_WITHDRAW");

        // Gateway changes
        if (!IZRC20(gasZRC20).approve(address(gateway), gasFee)) {
            revert ApprovalFailed();
        }
        
        if (!IZRC20(targetZRC20).approve(address(gateway), targetAmount - amountUsed)) {
            revert ApprovalFailed();
        }

        // Withdraw gasFees     
        withdraw(recipient,inputToken, targetZRC20, targetAmount- amountUsed);
        amountsOut = targetAmount - amountUsed;

    }


     /**
     * Swap and send erc20 tokens after receiving gas fee
     * @param targetZRC20 Target ZRC20
     * @param gasZRC20 Gas ZRC20
     * @param gasFee Gas fee
     * @param recipient Recipient
     * @param targetAmount Target amount
     * @param inputToken Input token
     * @param isV3Swap swap using v3 or v2
     */
    function _swapAndSendERC20Tokens(
        address targetZRC20,
        address gasZRC20,
        uint256 gasFee,
        bytes memory recipient,
        uint256 targetAmount,
        address inputToken,
        bool isV3Swap
    ) internal returns(uint256 amountsOut) {
        if(isV3Swap){
            amountsOut = _swapAndSendERC20UniV3(
                targetZRC20,
                gasZRC20,
                gasFee,
                recipient,
                targetAmount,
                inputToken
            );
        }else{
            amountsOut = _swapAndSendERC20TokensUniV2(
                targetZRC20,
                gasZRC20,
                gasFee,
                recipient,
                targetAmount,
                inputToken
            );
        }
    }



    
    // returns sorted token addresses, used to handle return values from pairs sorted in this order
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
     * @notice Function to swap zrc20 to target zrc20
     * @param _zrc20 ZRC20 address
     * @param _amount Amount to swap
     * @param _targetZRC20 Target ZRC20 address
     * @param _minAmountOut Minimum amount out
     * @param isV3Swap swap using v3 or v2
     */
    function _swap(
        address _zrc20,//USDT.ETH
        uint256 _amount,
        address _targetZRC20, // USDC.BSC
        uint256 _minAmountOut,
        bool isV3Swap
    ) internal returns (uint256 outputAmount){
         if((_zrc20 == USDC_BSC || _zrc20 == USDC_ETH || _zrc20 == USDT_ETH || _zrc20 == USDT_BSC) && (_targetZRC20 == USDC_BSC || _targetZRC20 == USDC_ETH || _targetZRC20 == USDT_ETH || _targetZRC20 == USDT_BSC)){
             IZRC20(_zrc20).approve(FOUR_POOL, _amount);
             outputAmount = IEddyStableSwap(FOUR_POOL).exchange(tokenToIndex[_zrc20],tokenToIndex[_targetZRC20], _amount, _minAmountOut);    
        }else if((_zrc20 == ULTI_ETH || _zrc20 == ULTI_BSC) && (_targetZRC20 == ULTI_ETH || _targetZRC20 == ULTI_BSC)){
             IZRC20(_zrc20).approve(ULTI_STABLESWAP, _amount);
             outputAmount = IEddyStableSwap(ULTI_STABLESWAP).exchange(tokenToIndex[_zrc20],tokenToIndex[_targetZRC20], _amount, _minAmountOut);
        }else if(isV3Swap){
            outputAmount = SwapHelperLib._doSwapV3(
                UNISWAP_ROUTER_V3,
                USDC_ETH,
                _zrc20,
                _targetZRC20,
                _amount,
                _minAmountOut,
                feeTierToToken[_zrc20],
                feeTierToToken[_targetZRC20]
            );
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
     * @notice Function to call external contract on dest chain using gateway
     * @param receiver Receiver address
     * @param amount Amount to send
     * @param zrc20 ZRC20 address
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


    function getSelector(string memory functionSignature) private pure returns (bytes4) {
        return bytes4(keccak256(bytes(functionSignature)));
    }


    function handleEvmWithdraw(
        address contractAddress,
        address zrc20,
        address tokenToUse,
        address targetZRC20,
        uint256 outputAmount,
        uint256 gasFeeCC,
        address evmWalletAddress
    ) private {

        require(contractAddress != address(0), "ZERO_ADDRESS");

        require(tokenToUse != address(0), "ZERO_ADDRESS");


        if (!IZRC20(tokenToUse).approve(address(gateway), outputAmount + gasFeeCC)) {
            revert ApprovalFailed();
        }
        
        // Calculate the function selector
        bytes4 selector = getSelector("swapETHtoERC20(uint256,address,address)");

         withdrawAndCall(
            abi.encodePacked(contractAddress),
            outputAmount - gasFeeCC,
            tokenToUse,
            abi.encodeWithSelector(selector,outputAmount - gasFeeCC,targetZRC20,evmWalletAddress),
            CallOptions({
                isArbitraryCall: true,
                gasLimit: gasLimit
            }),
            RevertOptions({
                revertAddress: address(this),
                callOnRevert: true,
                abortAddress: abortAddress,
                revertMessage: abi.encode(evmWalletAddress,zrc20),
                onRevertGasLimit: gasLimit
            })
        );
    }

    function decodeMessage(bytes calldata message) internal pure returns (DecodedMessage memory) {
        // First check basic length for required fields (target + bool)
        require(message.length >= 76, "Invalid message length"); //  4+ 20 + 20 + 32 bytes minimum

        //Decode destination chainId here 
        uint32 chainId = BytesHelperLib.bytesToUint32(message,0); // 4
        // First decode the target and bool
        address targetZRC20 = BytesHelperLib.bytesToAddress(message, 4); // 4 + 20 = 24

        bool isTargetZRC20;
        bool isV3Swap;
        if(chainId == BITCOIN_EDDY){
           require(message.length >= 98, "Invalid message length for BTC");
           isTargetZRC20 = abi.decode(message[66:98],(bool)); // 24(targetZRC20) + 42 bytes(bechdata)
           isV3Swap = BytesHelperLib.bytesToBool(message, 98);
        }else if (chainId == SOLANA_EDDY){
            require(message.length >= 100, "Invalid message length for SOLANA");
            isTargetZRC20 = abi.decode(message[68:100],(bool)); // 24(targetZRC20) + 44 bytes(bechdata)
            isV3Swap = BytesHelperLib.bytesToBool(message, 100);
        }else {
            isTargetZRC20 = abi.decode(message[44:76],(bool));
            isV3Swap = BytesHelperLib.bytesToBool(message, 76);
        }
    
        // Initialize additional addresses to zero address
        address intermediateToken = address(0);  
        address contractAddress = address(0); 
        bytes32[] memory proof;
        uint256 proofStartOffset;

    
        // Only decode additional addresses if isTargetZRC20 is FALSE and they are provided
        if (!isTargetZRC20 && message.length >= 116) {
            intermediateToken = BytesHelperLib.bytesToAddress(message, 77);
            contractAddress = BytesHelperLib.bytesToAddress(message, 97);
            proofStartOffset = 117;
        }else{
            if(chainId == BITCOIN_EDDY){
                proofStartOffset = 99;
            }else if(chainId == SOLANA_EDDY){
                proofStartOffset = 101;
            }else{
                proofStartOffset = 77;
            }
        }
        // Decode proof if there's data after the addresses
        if (message.length > proofStartOffset) {
            // Get the offset of the array data
            uint256 arrayOffset;
            assembly {
                arrayOffset := calldataload(add(message.offset, proofStartOffset))
            }
        
            // Read array length
            uint256 proofLength;
            assembly {
                let lengthPosition := add(add(message.offset, proofStartOffset), arrayOffset)
                proofLength := calldataload(lengthPosition)
            }
        
            // Initialize proof array
            proof = new bytes32[](proofLength);
        
            // Read proof elements
            uint256 elementsStart = proofStartOffset + arrayOffset + 32;
        
            for(uint256 i = 0; i < proofLength; i++) {
                assembly {
                    let elementPosition := add(add(message.offset, elementsStart), mul(i, 32))
                    mstore(add(proof, add(32, mul(i, 32))), calldataload(elementPosition))
                }
            }
        } else {
            // If no proof data, initialize empty array
            proof = new bytes32[](0);
        }
        

        return DecodedMessage({
            targetZRC20: targetZRC20,
            isTargetZRC20: isTargetZRC20,
            intermediateToken: intermediateToken,
            contractAddress: contractAddress,
            proof: proof,
            destChainId: chainId,
            isV3Swap: isV3Swap
        });
    }

    function decodeMessageBitcoin(
        bytes calldata message
    ) public view returns (DecodedMessage memory) {
        require(message.length >= 40, "Invalid message length");
        // targetZRC20 + evmWallet + isTargetZRC20 + chainId
        // 20 + 20 + 1 + 4 = 45
        // Only if dest chain is solana
        // chainID + tokenId + evmWallet + isTargetZRC20
        // 4 + 4 + 44 + 1 = 53
        uint32 chainId = BytesHelperLib.bytesToUint32(message,0); // 4
        address targetZRC20;
        if(chainId == SOLANA_EDDY){
            uint32 tokenId = BytesHelperLib.bytesToUint32(message,4); //4
            targetZRC20 = solanaTokenToZrc20[tokenId];
        }else{
            targetZRC20 = BytesHelperLib.bytesToAddress(message, 4); //20
        }
        bool isTargetZRC20 = chainId == SOLANA_EDDY ? BytesHelperLib.bytesToBool(message,52)  : BytesHelperLib.bytesToBool(message, 44); //1
        bool isV3Swap = chainId == SOLANA_EDDY ? BytesHelperLib.bytesToBool(message, 53) : BytesHelperLib.bytesToBool(message, 45); //1
        if(!isTargetZRC20 && message.length >= 45){
            return DecodedMessage({
                targetZRC20: targetZRC20,
                isTargetZRC20: isTargetZRC20,
                intermediateToken: chainToIntermediateToken[chainId],
                contractAddress: chainToContract[chainId],
                proof: new bytes32[](0),
                destChainId: chainId,
                isV3Swap: isV3Swap
            });
        }else{
            return DecodedMessage({
                targetZRC20: targetZRC20,
                isTargetZRC20: isTargetZRC20,
                intermediateToken: address(0),
                contractAddress: address(0),
                proof: new bytes32[](0),
                destChainId: chainId,
                isV3Swap: isV3Swap
            });
        }
        
    }
    

    
    function _handleBTCCase(
        address evmWalletAddress,
        address zrc20,
        address targetZRC20,
        uint256 amount,
        uint256 amountOutMin,
        uint256 platformFeesForTx,
        bytes calldata message,
        bool isV3Swap
    ) private {
        uint256 swapAmount = amount - platformFeesForTx;
        bytes memory recipientAddressBech32 = bytesToBech32Bytes(message, 24);
        uint256 outputAmount = _swap(zrc20, swapAmount, targetZRC20, amountOutMin,isV3Swap);
        (, uint256 gasFee) = IZRC20(targetZRC20).withdrawGasFee();
        if (outputAmount < gasFee) revert WrongAmount();

        if(!IZRC20(targetZRC20).approve(address(gateway), outputAmount + gasFee)) {
            revert ApprovalFailed();
        }

        withdraw(recipientAddressBech32, zrc20, targetZRC20, outputAmount - gasFee);
        _handleBTCEvent(evmWalletAddress, zrc20, targetZRC20, amount, outputAmount, platformFeesForTx);
    }

    function _handleSolanaCase(
        address evmWalletAddress,
        address zrc20,
        address targetZRC20,
        uint256 amount,
        uint256 amountOutMin,
        uint256 platformFeesForTx,
        bytes calldata message,
        bool isV3Swap
    ) private {
        uint256 swapAmount = amount - platformFeesForTx;
        bytes memory recipientAddressBech32 = bytesToSolana(message, 24);
        uint256 outputAmount = _swap(zrc20, swapAmount, targetZRC20, amountOutMin,isV3Swap);
        (address gasZRC20, uint256 gasFee) = IZRC20(targetZRC20).withdrawGasFee();
        if(targetZRC20 == gasZRC20) {
            if (outputAmount < gasFee) revert WrongAmount();
            if(!IZRC20(targetZRC20).approve(address(gateway), outputAmount + gasFee)) {
                revert ApprovalFailed();
            }
            withdraw(recipientAddressBech32, zrc20, targetZRC20, outputAmount - gasFee);
            _handleBTCEvent(evmWalletAddress, zrc20, targetZRC20, amount, outputAmount - gasFee, platformFeesForTx);
        }else{
            uint256 amountAfterGasFees = _swapAndSendERC20Tokens(
                targetZRC20,
                gasZRC20,
                gasFee,
                recipientAddressBech32,
                outputAmount,
                zrc20,
                isV3Swap
            );

            _handleBTCEvent(evmWalletAddress, zrc20, targetZRC20, amount,amountAfterGasFees, platformFeesForTx);
        }
    }
    

    function _handleBTCToSolanaCase(
        address zrc20,
        address targetZRC20,
        uint256 amount,
        uint256 amountOutMin,
        uint256 platformFeesForTx,
        bytes calldata message,
        bool isV3Swap
    ) private {
        uint256 swapAmount = amount - platformFeesForTx;
        bytes memory recipientAddressBech32 = bytesToSolana(message,8);
        uint256 outputAmount = _swap(zrc20, swapAmount, targetZRC20, amountOutMin,isV3Swap);
        (address gasZRC20, uint256 gasFee) = IZRC20(targetZRC20).withdrawGasFee();

        if(targetZRC20 == gasZRC20) {
            if (outputAmount < gasFee) revert WrongAmount();
            if(!IZRC20(targetZRC20).approve(address(gateway), outputAmount + gasFee)) {
                revert ApprovalFailed();
            }

            withdraw(recipientAddressBech32, zrc20, targetZRC20, outputAmount - gasFee);
            _handleBTCEvent(address(0), zrc20, targetZRC20, amount, outputAmount - gasFee, platformFeesForTx);
        }else{
             uint256 amountAfterGasFees = _swapAndSendERC20Tokens(
                targetZRC20,
                gasZRC20,
                gasFee,
                recipientAddressBech32,
                outputAmount,
                zrc20,
                isV3Swap
            );

            _handleBTCEvent(address(0), zrc20, targetZRC20, amount, amountAfterGasFees, platformFeesForTx);
        }
    }

    function _handleBTCEvent(
        address evmWalletAddress,
        address zrc20,
        address targetZRC20,
        uint256 amount,
        uint256 outputAmount,
        uint256 platformFeesForTx
    ) private {
        emit EddyCrossChainSwap(zrc20, targetZRC20, amount, outputAmount, evmWalletAddress, platformFeesForTx);
    }

    /**
     * @notice Function to calculate amount out min for univ2
     * @param zrc20 ZRC20 address
     * @param targetZRC20 Target ZRC20 address 
     * @param swapAmount Swap amount
     */
    function getMinimumAmountUniv2(
        address zrc20,
        address targetZRC20, 
        uint256 swapAmount
    ) private view returns (uint256 amountOutMin) {
        uint[] memory amountsQuote = UniswapV2Library.getAmountsOut(
            UniswapFactory,
            swapAmount,
            getPathForTokens(zrc20, targetZRC20)
        );
        
        amountOutMin = (amountsQuote[amountsQuote.length - 1]) - (slippage * amountsQuote[amountsQuote.length - 1]) / 1000;
    }

    /**
     * @notice Function to calculate amount out min
     * @param zrc20 ZRC20 address
     * @param tokenToUse Token to use
     * @param swapAmount Swap amount
     * @param isV3Swap Swap using v3 or v2
     * @return amountOutMin Amount out min
     */
    function calculateAmountOutMin(
        address zrc20,
        address tokenToUse, 
        uint256 swapAmount,
        bool isV3Swap
    ) private returns (uint256 amountOutMin) {
        if(isV3Swap){
            amountOutMin = getMinimumAmountUniv3(zrc20, tokenToUse, swapAmount);
        }else{
            amountOutMin = getMinimumAmountUniv2(zrc20, tokenToUse, swapAmount);
        }
    }

    /**
     * @notice Function to get minimum amount for univ3
     * @param zrc20 ZRC20 address
     * @param targetZRC20 Target ZRC20 address
     * @param amount Amount
     * @return amountOutMin Amount out min
     */
    function getMinimumAmountUniv3(
        address zrc20,
        address targetZRC20,
        uint256 amount
    ) internal returns(uint256 amountOutMin){
        bytes memory path;
        if(targetZRC20 == USDC_ETH){
            path = abi.encodePacked(zrc20,feeTierToToken[zrc20], targetZRC20);
        }else if(zrc20 == USDC_ETH){
            path = abi.encodePacked(zrc20,feeTierToToken[targetZRC20], targetZRC20);
        }else{
            path = abi.encodePacked(zrc20,feeTierToToken[zrc20],USDC_ETH,feeTierToToken[targetZRC20], targetZRC20);
        }

        (uint256 amountOut, , , ) = IQuoterV2(address(QUOTER_V2)).quoteExactInput(path, amount);

        amountOutMin = amountOut  - (slippage * amountOut) / 1000;
    }

    function handleFeeTransfer(bytes32[] memory merkleProof, address sender,address zrc20,uint256 amount, bool btcToSolana) private returns (uint256 platformFeesForTx) {
        if(btcToSolana){
            platformFeesForTx = (amount * feePercent) / 1000; // platformFee = 5 <> 0.5%
            TransferHelper.safeTransfer(zrc20, EddyTreasurySafe,platformFeesForTx);
        }else{
            bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(sender))));
            bool isWhitelisted = MerkleProof.verify(merkleProof, merkleRoot, leaf);
            uint256 feeToApply = isWhitelisted ? customFee : feePercent;
            platformFeesForTx = (amount * feeToApply) / 1000; // platformFee = 5 <> 0.5%
            TransferHelper.safeTransfer(zrc20, EddyTreasurySafe,platformFeesForTx);
        }
        
    }

    function getEvmAddress(MessageContext calldata context,bytes calldata message, uint32 chainId) internal pure returns(address evmWalletAddress) {
        if (chainId == BITCOIN_EDDY || chainId == SOLANA_EDDY) {
            evmWalletAddress = context.sender;
        } else {
            evmWalletAddress = BytesHelperLib.bytesToAddress(message, 24);
        }
    }


    function onCall(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message
    ) external override onlyGateway {
        DecodedMessage memory decoded = context.chainID == BITCOIN ? decodeMessageBitcoin(message) : decodeMessage(message);
        //Bool to check for solana btc case
        bool btcToSolana = context.chainID == BITCOIN && decoded.destChainId == SOLANA_EDDY;
        address evmWalletAddress;
        if(!btcToSolana){
            evmWalletAddress = getEvmAddress(context,message, decoded.destChainId);
        }
        // address evmWalletAddress = decoded.targetZRC20 == BTC_ZETH ? BytesHelperLib.bytesToAddress(context.origin, 0) : BytesHelperLib.bytesToAddress(message, 20);
        uint256 platformFeesForTx = handleFeeTransfer(decoded.proof, evmWalletAddress, zrc20, amount, btcToSolana);
        // TransferHelper.safeTransfer(zrc20, EddyTreasurySafe, platformFeesForTx);
        address tokenToUse = decoded.isTargetZRC20 ? decoded.targetZRC20 : decoded.intermediateToken;
        uint256 amountOutMin = calculateAmountOutMin(zrc20, tokenToUse, amount - platformFeesForTx, decoded.isV3Swap);
        (address gasZRC20, uint256 gasFee) = decoded.isTargetZRC20 ? IZRC20(tokenToUse).withdrawGasFee() : IZRC20(tokenToUse).withdrawGasFeeWithGasLimit(gasLimit);
        if(btcToSolana){
            _handleBTCToSolanaCase(
                zrc20,
                decoded.targetZRC20,
                amount,
                amountOutMin,
                platformFeesForTx,
                message,
                decoded.isV3Swap
            );
        }else if (decoded.destChainId == BITCOIN_EDDY && !btcToSolana) {
            _handleBTCCase(
                evmWalletAddress,
                zrc20,
                decoded.targetZRC20,
                amount,
                amountOutMin,
                platformFeesForTx,
                message,
                decoded.isV3Swap
            );
        } else if (decoded.destChainId == SOLANA_EDDY && !btcToSolana){
            _handleSolanaCase(
                evmWalletAddress,
                zrc20,
                decoded.targetZRC20,
                amount,
                amountOutMin,
                platformFeesForTx,
                message,
                decoded.isV3Swap
            );
        }else {
            // bytes32 recipient = getRecipientOnly(message);
            // address evmWalletAddress = BytesHelperLib.bytesToAddress(message, 20);
            uint256 outputAmount = _swap(
                zrc20,
                amount - platformFeesForTx,
                tokenToUse,
                amountOutMin,
                decoded.isV3Swap
            );

            if (gasZRC20 != tokenToUse) {
                // target token not gas token
                // withdraw token not gas token
                HandleSwapAndSendTokensParams memory params;
                params.targetZRC20 = decoded.targetZRC20;
                params.gasZRC20CC = gasZRC20;
                params.gasFeeCC = gasFee;
                params.sender = evmWalletAddress;
                params.targetAmount =  outputAmount;
                params.inputToken = zrc20;
                
                uint256 amountsOutTarget = _swapAndSendERC20Tokens(
                    params.targetZRC20,
                    params.gasZRC20CC,
                    params.gasFeeCC,
                    abi.encodePacked(params.sender),
                    params.targetAmount,
                    params.inputToken,
                    decoded.isV3Swap
                );
                emit EddyCrossChainSwap(zrc20,tokenToUse, amount, amountsOutTarget, evmWalletAddress, platformFeesForTx);
              
            } else if(gasZRC20 == tokenToUse && decoded.isTargetZRC20){
                if (gasZRC20 != tokenToUse) revert WrongGasContract();
                if (gasFee >= outputAmount) revert NotEnoughToPayGasFee();
                if(!IZRC20(decoded.targetZRC20).approve(address(gateway),outputAmount + gasFee)){
                    revert ApprovalFailed();
                }
                withdraw(
                    abi.encodePacked(evmWalletAddress),
                    zrc20,
                    decoded.targetZRC20,
                    outputAmount - gasFee
                );
                
                emit EddyCrossChainSwap(
                    zrc20,
                    decoded.targetZRC20,
                    amount,
                    outputAmount - gasFee,
                    evmWalletAddress,
                    platformFeesForTx
                );
            }else {
                if (gasZRC20 != tokenToUse) revert WrongGasContract();
                if (gasFee >= outputAmount) revert NotEnoughToPayGasFee();
                handleEvmWithdraw(
                    decoded.contractAddress,
                    zrc20,
                    tokenToUse,
                    decoded.targetZRC20,
                    outputAmount,
                    gasFee,
                    evmWalletAddress
                );

                emit EddyCrossChainSwap(zrc20,decoded.targetZRC20, amount, outputAmount, evmWalletAddress, platformFeesForTx);
            }

        }
    }

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

    /// @notice Withdraw the token
    /// @param token The token to withdraw
    /// @param receiver The receiver of the token
    function withdrawToken(address token, address receiver) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        TransferHelper.safeTransfer(token, receiver, balance);
    }

    function onRevert(RevertContext calldata context) external onlyGateway {
        (address senderEvmAddress, address zrc20) = abi.decode(context.revertMessage, (address, address));
        (address gasZRC20, uint256 gasFee) = IZRC20(zrc20).withdrawGasFee();
        uint[] memory amountsQuote = UniswapV2Library.getAmountsOut(
            UniswapFactory,
            context.amount,
            getPathForTokens(context.asset,zrc20)
        );

        uint amountOutMin = (amountsQuote[amountsQuote.length - 1]) - (slippage * amountsQuote[amountsQuote.length - 1]) / 1000;

        // swap reverted token with input token
        uint256 amountOut = _swap(
            context.asset,
            context.amount,
            zrc20,
            amountOutMin,
            false
        );

        if(gasZRC20 == zrc20){
            // Case where input token is gas token
            if(!IZRC20(zrc20).approve(address(gateway),amountOut + gasFee)){
                revert ApprovalFailed();
            }

            gateway.withdraw(
                abi.encodePacked(senderEvmAddress),
                amountOut - gasFee,
                zrc20,
                RevertOptions({
                    revertAddress: senderEvmAddress,
                    callOnRevert: false,
                    abortAddress: address(0),
                    revertMessage: "",
                    onRevertGasLimit: gasLimit
                })
            );
        }else{
            //Case where input token is not gas token
            _swapAndSendERC20Tokens(
                zrc20,
                gasZRC20,
                gasFee,
                abi.encodePacked(senderEvmAddress),
                amountOut,
                context.asset,
                false
            );
        }   
    }

    receive() external payable {}

    fallback() external payable {}

}