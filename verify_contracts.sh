#!/bin/bash

# Script para verificar los contratos importantes desplegados en Arbitrum
# Usa tu API key de Arbiscan V2

API_KEY="${ETHERSCAN_API_KEY}"
OPTIMIZER_RUNS=200
COMPILER_VERSION="0.8.28"

# Direcciones de los contratos desplegados
ROLES="0x5a2F59379F169E4e8657C582053Fbc5062e186f8"
ADDRESS_PROVIDER="0xac75F46b530E5638cba65297bc2cCfcef0b3841D"
MARKET_NEUTRAL="0x0b90ed75f035E4a97B563a9eE8e239C29B40e090"
PROTOCOL_STORAGE="0x88A73b2C344Adb777343E6A71Ec4e9c5Cc77B42C"
PROXY_MANAGER="0x5F18851887a5c9C0063d4f358CE2d55435470172"

# Argumentos del constructor codificados usando cast
# Roles: constructor(address, address, address)
# ADMIN1, ADMIN2, ADMIN3
ADMIN1="0x7F4C831de10684f85867899708cB49FfbF4983B9"
ADMIN2="0xdD8f39262841F9425ed9180D0D989312E41EbEEc"
ADMIN3="0xD023851C8AC8ceC385988e7E5af84b1A6D1f9079"

echo "Verificando contratos en Arbitrum..."
echo "===================================="

# 1. Roles (más importante - sistema de permisos)
echo "Verificando Roles..."
forge verify-contract \
    --chain arbitrum \
    --num-of-optimizations $OPTIMIZER_RUNS \
    --compiler-version $COMPILER_VERSION \
    --watch \
    --etherscan-api-key $API_KEY \
    $ROLES \
    src/security/Roles.sol:Roles \
    --constructor-args $(cast abi-encode "constructor(address,address,address)" $ADMIN1 $ADMIN2 $ADMIN3)

# 2. AddressProvider (registro central)
echo "Verificando AddressProvider..."
forge verify-contract \
    --chain arbitrum \
    --num-of-optimizations $OPTIMIZER_RUNS \
    --compiler-version $COMPILER_VERSION \
    --watch \
    --etherscan-api-key $API_KEY \
    $ADDRESS_PROVIDER \
    src/core/config/AddressProvider.sol:AddressProvider \
    --constructor-args $(cast abi-encode "constructor(address)" $ROLES)

# 3. MarketNeutral (executor principal)
echo "Verificando MarketNeutral..."
forge verify-contract \
    --chain arbitrum \
    --num-of-optimizations $OPTIMIZER_RUNS \
    --compiler-version $COMPILER_VERSION \
    --watch \
    --etherscan-api-key $API_KEY \
    $MARKET_NEUTRAL \
    src/core/bundles/executors/MarketNeutral.sol:MarketNeutral \
    --constructor-args $(cast abi-encode "constructor(address)" $ADDRESS_PROVIDER)

# 4. ProtocolStorage (almacenamiento central)
echo "Verificando ProtocolStorage..."
forge verify-contract \
    --chain arbitrum \
    --num-of-optimizations $OPTIMIZER_RUNS \
    --compiler-version $COMPILER_VERSION \
    --watch \
    --etherscan-api-key $API_KEY \
    $PROTOCOL_STORAGE \
    src/core/ProtocolStorage.sol:ProtocolStorage \
    --constructor-args $(cast abi-encode "constructor(address)" $ROLES)

# 5. ProxyManager (gestión de proxies)
echo "Verificando ProxyManager..."
forge verify-contract \
    --chain arbitrum \
    --num-of-optimizations $OPTIMIZER_RUNS \
    --compiler-version $COMPILER_VERSION \
    --watch \
    --etherscan-api-key $API_KEY \
    $PROXY_MANAGER \
    src/core/bundles/storage/ProxyManager.sol:ProxyManager \
    --constructor-args $(cast abi-encode "constructor(address)" $ADDRESS_PROVIDER)

echo "===================================="
echo "Verificación completada!"

