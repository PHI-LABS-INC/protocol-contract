#!/bin/bash

#   PhiNFT1155 deployed at address: 0x24a53d67bD516EDe56665811C705A45f29a1cd9B
#   PhiRewards deployed at address: 0xE31673065B0638a74f8a7F5DB9217B85d535e694
#   PhiFactory deployed at address: 0x028052F458142d1689F4f851e78947C7075f2D20
#   BondingCurve deployed at address: 0x42ccEA78e5f628f1B84350d6Ad77bE271A612E0D
#   Cred deployed at address: 0xE40Bb8EEeC72be2AB7731eF8E5446c30047A3a20
#   CuratorRewardsDistributor deployed at address: 0x03E89d14D5EFd8d8C39ed8EEf8d4D9eB363462F9
SIGNER='0xe35E5f8B912C25cDb6B00B347cb856467e4112A3'
PHI_FACTORY_ADDRESS='0x8b89382A4A03E89CA498037780C597914102Cc38'
PHI_FACTORY_PROXY_ADDRESS='0x028052F458142d1689F4f851e78947C7075f2D20'
TREASURY='0x6D83cac25CfaCdC7035Bed947B92b64e6a8B8090'
PHI_NFT_1155_ADDRESS='0x24a53d67bD516EDe56665811C705A45f29a1cd9B'
PHI_REWARDS_ADDRESS='0xE31673065B0638a74f8a7F5DB9217B85d535e694'
OJI3_ADDRESS='0x5cD18dA4C84758319C8E1c228b48725f5e4a3506'
PROTOCOL_FEE='150000000000000'  # 0.00015 ether in wei (decimal)
ART_CREATE_FEE='10000000000000'  # 0.00001 ether in wei (decimal)

# Common parameters
VERIFIER_URL='https://api.routescan.io/v2/network/testnet/evm/80084/etherscan/api'
COMPILER_VERSION='0.8.25'
OPTIMIZATIONS=1000
OWNER='0x5cD18dA4C84758319C8E1c228b48725f5e4a3506'

# forge verify-contract 0xE31673065B0638a74f8a7F5DB9217B85d535e694 src/reward/PhiRewards.sol:PhiRewards \
# --etherscan-api-key "xxx" \
# --watch
# --num-of-optimizations $OPTIMIZATIONS \
# --compiler-version $COMPILER_VERSION \
# --constructor-args $(cast abi-encode "constructor(address)" $OWNER) \
# --verifier-url "$VERIFIER_URL" \

# Encode constructor arguments (just the proxy address for PhiFactory)
CONSTRUCTOR_ARGS=$(cast abi-encode "constructor()" $PHI_FACTORY_PROXY_ADDRESS)

echo "Encoding individual arguments:"
echo "SIGNER: $(cast abi-encode "f(address)" $SIGNER)"
echo "TREASURY: $(cast abi-encode "f(address)" $TREASURY)"
echo "PHI_NFT_1155_ADDRESS: $(cast abi-encode "f(address)" $PHI_NFT_1155_ADDRESS)"
echo "PHI_REWARDS_ADDRESS: $(cast abi-encode "f(address)" $PHI_REWARDS_ADDRESS)"
echo "OJI3_ADDRESS: $(cast abi-encode "f(address)" $OJI3_ADDRESS)"
echo "PROTOCOL_FEE: $(cast abi-encode "f(uint256)" $PROTOCOL_FEE)"
echo "ART_CREATE_FEE: $(cast abi-encode "f(uint256)" $ART_CREATE_FEE)"

# Encode initialize function arguments
INITIALIZE_ARGS=$(cast abi-encode "initialize(address,address,address,address,address,uint256,uint256)" \
  $SIGNER $TREASURY $PHI_NFT_1155_ADDRESS $PHI_REWARDS_ADDRESS $OJI3_ADDRESS $PROTOCOL_FEE $ART_CREATE_FEE)
# INITIALIZE_ARGS="000000000000000000000000e35e5f8b912c25cdb6b00b347cb856467e4112a3\
# 0000000000000000000000006d83cac25cfacdc7035bed947b92b64e6a8b8090\
# 00000000000000000000000024a53d67bd516ede56665811c705a45f29a1cd9b\
# 000000000000000000000000e31673065b0638a74f8a7f5db9217b85d535e694\
# 0000000000000000000000005cd18da4c84758319c8e1c228b48725f5e4a3506\
# 0000000000000000000000000000000000000000000000000000886c98b76000\
# 000000000000000000000000000000000000000000000000000009184e72a000"

# Combine constructor and initialize arguments
COMBINED_ARGS="${CONSTRUCTOR_ARGS}${INITIALIZE_ARGS:2}"  # Remove '0x' from INITIALIZE_ARGS


# Run the verify command
forge verify-contract $PHI_FACTORY_ADDRESS src/PhiFactory.sol:PhiFactory \
  --etherscan-api-key "xxx" \
  --watch \
  --num-of-optimizations $OPTIMIZATIONS \
  --compiler-version $COMPILER_VERSION \
  --constructor-args $COMBINED_ARGS \
  --verifier-url "$VERIFIER_URL"