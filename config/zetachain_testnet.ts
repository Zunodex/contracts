const ZETACHAIN_TESTNET_CONFIG = {
    chain: {
        chainId: 7001,
        explorerURL: "https://testnet.zetascan.com/",
    },
    defaultAddress: {
        Gateway: "0x6c533f7fe93fae114d0954697069df33c9b74fd7",
        MultiSig: "0xfa0d8ebca31a1501144a785a2929e9f91b0571d0",
        DODORouteProxy: "0x026eea5c10f526153e7578E5257801f8610D1142",
        DODOApprove: "0x143bE32C854E4Ddce45aD48dAe3343821556D0c3",
        RefundBot: "0xa19c93c48b2051135c3a5c5df9753d53e03ef239",
    }, 
    deployedAddress: {
        GatewayCrossChainImpl: "0xb6a8db416e81314669Be14E91Ae0E07bD7Ec0Daf",
        GatewayCrossChainProxy: "0x0FEA3705B34901cf51953be5001973EA5a739968",
        GatewayTransferNativeImpl: "0xf51705E360f706f46b83029A6f42Cb7b491a24dd",
        GatewayTransferNativeProxy: "0xfd6fFee92D25158b29315C71b0Bb4dE727530FaF"
    },
  };
  
  export { ZETACHAIN_TESTNET_CONFIG };
  