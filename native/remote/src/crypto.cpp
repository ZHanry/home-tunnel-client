#include "crypto.hpp"
#include <algorithm>
#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>
#include <cstring>
#endif

namespace ht::rd {
CryptoResult sha256(std::span<const uint8_t> input, std::array<uint8_t,32>& digest) {
    digest.fill(0);
#if defined(_WIN32)
    if(input.size()>65536) return CryptoResult::invalid;
    BCRYPT_ALG_HANDLE algorithm=nullptr;
    if(BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_SHA256_ALGORITHM,nullptr,0)!=0) return CryptoResult::unavailable;
    const auto status=BCryptHash(algorithm,nullptr,0,const_cast<PUCHAR>(input.data()),static_cast<ULONG>(input.size()),digest.data(),static_cast<ULONG>(digest.size()));
    BCryptCloseAlgorithmProvider(algorithm,0);
    return status==0 ? CryptoResult::valid : CryptoResult::invalid;
#else
    (void)input;
    return CryptoResult::unavailable;
#endif
}
CryptoResult verify_p256(std::span<const uint8_t> message,
    const std::array<uint8_t,64>& public_key_xy,const std::array<uint8_t,64>& signature_raw) {
#if defined(_WIN32)
    std::array<uint8_t,32> digest{};
    const auto hashed=sha256(message,digest);
    if(hashed!=CryptoResult::valid) return hashed;
    BCRYPT_ALG_HANDLE algorithm=nullptr;
    if(BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_ECDSA_P256_ALGORITHM,nullptr,0)!=0) return CryptoResult::unavailable;
    std::array<uint8_t,sizeof(BCRYPT_ECCKEY_BLOB)+64> blob{};
    BCRYPT_ECCKEY_BLOB header{BCRYPT_ECDSA_PUBLIC_P256_MAGIC,32};
    std::memcpy(blob.data(),&header,sizeof(header));
    std::copy(public_key_xy.begin(),public_key_xy.end(),blob.begin()+sizeof(header));
    BCRYPT_KEY_HANDLE key=nullptr;
    auto status=BCryptImportKeyPair(algorithm,nullptr,BCRYPT_ECCPUBLIC_BLOB,&key,blob.data(),static_cast<ULONG>(blob.size()),0);
    if(status==0) status=BCryptVerifySignature(key,nullptr,digest.data(),static_cast<ULONG>(digest.size()),const_cast<PUCHAR>(signature_raw.data()),static_cast<ULONG>(signature_raw.size()),0);
    if(key) BCryptDestroyKey(key);
    BCryptCloseAlgorithmProvider(algorithm,0);
    return status==0 ? CryptoResult::valid : CryptoResult::invalid;
#else
    (void)message;(void)public_key_xy;(void)signature_raw;
    return CryptoResult::unavailable;
#endif
}
}
