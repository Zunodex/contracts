import { GatewaySend } from "../typechain-types";

const SEPOLIA_CONFIG = {
    chain: {
        "chainId": 11155111,
        "explorerURL": "https://sepolia.etherscan.io/",
    },
    defaultAddress: {
        Gateway: "0x0c487a766110c85d301D96E33579C5B317Fa4995",
        USDC: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
        MultiSig: "0xfa0d8ebca31a1501144a785a2929e9f91b0571d0",
        DODORouteProxy: "0x5fa9e06111814840398ceF6E9563d400F6ed3a8d",
        DODOApprove: "0x66c45FF040e86DC613F239123A5E21FFdC3A3fEC",
    }, 
    deployedAddress: {
        Send: "0x6e04364f4ae6084689e4c467b4c22d5198577330",
        GatewaySend: "0xfE5b4cbf273b3e37F4E4E368218093d564345237",
    },
  };
  
  export { SEPOLIA_CONFIG };
  