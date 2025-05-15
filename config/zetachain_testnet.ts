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
        GatewayCrossChainImpl: "0x19E10fb5875C4901D9650aFc001197285dBBC060",
        GatewayCrossChainProxy: "0xA3148a1765897EC0A9bCA57f855C0B4718060b78",
        GatewayTransferNativeImpl: "0x8bBD9D807ffc5c772e802333FB41Ea059F2f44d6",
        GatewayTransferNativeProxy: "0x351a86A2C8dc47D396305AAcd7F126E096b2eee4"
    },
  };
  
  export { ZETACHAIN_TESTNET_CONFIG };
  