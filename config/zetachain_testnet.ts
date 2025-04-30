const ZETACHAIN_TESTNET_CONFIG = {
    chain: {
        chainId: 7001,
        explorerURL: "https://zetachain-testnet.blockscout.com",
    },
    defaultAddress: {
        Gateway: "0x6c533f7fe93fae114d0954697069df33c9b74fd7",
        USDC_SEP: "0xcC683A782f4B30c138787CB5576a86AF66fdc31d",
        USDC_ARBSEP: "0x4bC32034caCcc9B7e02536945eDbC286bACbA073",
        UniswapV2Factory: "0x9fd96203f7b22bCF72d9DCb40ff98302376cE09c",
        UniswapV2Router: "0x2ca7d64A7EFE2D62A725E2B35Cf7230D6677FfEe",
        MultiSig: "0xfa0d8ebca31a1501144a785a2929e9f91b0571d0",
        DODORouteProxy: "0x026eea5c10f526153e7578E5257801f8610D1142",
        DODOApprove: "0x143bE32C854E4Ddce45aD48dAe3343821556D0c3"
    }, 
    deployedAddress: {
        GatewayCrossChainImpl: "0x78d43a889F42a344Fe98C3fb9455791Dc8178d55",
        GatewayCrossChainProxy: "0x69716E51E3F8Bec9c3D4E1bB46396384AE11C594",
        GatewayTransferNativeImpl: "0xFe837A3530dD566401d35beFCd55582AF7c4dfFC",
        GatewayTransferNativeProxy: "0x056FcE6B76AF3050F54B71Fc9B5fcb7C387BfC1A"
    },
  };
  
  export { ZETACHAIN_TESTNET_CONFIG };
  