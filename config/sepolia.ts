import { GatewaySend } from "../typechain-types";

const SEPOLIA_CONFIG = {
    chain: {
        "chainId": 11155111,
        "explorerURL": "https://sepolia.etherscan.io/",
    },
    defaultAddress: {
        Gateway: "0x0c487a766110c85d301D96E33579C5B317Fa4995",
        MultiSig: "0xfa0d8ebca31a1501144a785a2929e9f91b0571d0",
        DODORouteProxy: "0x5fa9e06111814840398ceF6E9563d400F6ed3a8d",
    }, 
    deployedAddress: {
        Send: "0xcac7b4b9648e2a5c2835ccd36490fad7c1091024",
        GatewaySend: "0xa822D83d72af894D59acF9d03E5042d4A8eAa01f",
    },
  };
  
  export { SEPOLIA_CONFIG };
  