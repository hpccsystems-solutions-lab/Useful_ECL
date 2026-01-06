/**
 * Return the HMAC-SHA256 of some input using OpenSSL 3.x EVP_MAC.
 *
 * This is suitable for deterministic exact-match lookup tokens (e.g., SSNs),
 * assuming the HMAC key is kept secret.
 *
 * @param   b   A DATA blob of what you want to hash (message)
 * @param   k   A DATA blob containing the secret HMAC key (pepper)
 *
 * @return  A STRING64 hex-encoded (uppercase) version of the 32-byte HMAC.
 *
 * Notes:
 *  - Requires OpenSSL 3.x (EVP_MAC / providers).
 *  - Output is always 64 hex chars (STRING64).
 *
 * Origin: https://github.com/hpccsystems-solutions-lab/Useful_ECL
 */
EXPORT STRING64 HMAC_SHA256(DATA b, DATA k) := EMBED(C++ : pure)
    #include "openssl/evp.h"
    #include "openssl/core_names.h"
    #include "openssl/params.h"

    static const char hexchar[] = "0123456789ABCDEF";

    #body

    EVP_MAC* mac = nullptr;
    EVP_MAC_CTX* macCtx = nullptr;

    try
    {
        // Fetch the HMAC implementation from providers.
        mac = EVP_MAC_fetch(nullptr, "HMAC", nullptr);
        if (!mac)
            rtlFail(-1, "Unable to fetch EVP_MAC HMAC implementation (OpenSSL 3 required)");

        macCtx = EVP_MAC_CTX_new(mac);
        if (!macCtx)
            rtlFail(-1, "Unable to allocate EVP_MAC_CTX");

        // Tell HMAC to use SHA-256 as its underlying digest.
        OSSL_PARAM params[] = {OSSL_PARAM_construct_utf8_string(OSSL_MAC_PARAM_DIGEST, const_cast<char*>("SHA256"), 0), OSSL_PARAM_construct_end()};

        // Initialize with key.
        if (EVP_MAC_init(macCtx, static_cast<const unsigned char*>(k), static_cast<size_t>(lenK), params) != 1)
            rtlFail(-1, "Unable to initialize HMAC-SHA256 (EVP_MAC_init failed)");

        // Update with message.
        if (EVP_MAC_update(macCtx, static_cast<const unsigned char*>(b), static_cast<size_t>(lenB)) != 1)
            rtlFail(-1, "Unable to update HMAC-SHA256 (EVP_MAC_update failed)");

        // Determine output size.
        size_t outLen = 0;
        if (EVP_MAC_final(macCtx, nullptr, &outLen, 0) != 1)
            rtlFail(-1, "Unable to determine HMAC output size (EVP_MAC_final size query failed)");

        // SHA-256 HMAC should be 32 bytes, but don't assume.
        if (outLen * 2 > 64)
            rtlFail(-1, "Unexpected HMAC length (too large for STRING64 output)");

        unsigned char out[EVP_MAX_MD_SIZE];

        if (EVP_MAC_final(macCtx, out, &outLen, sizeof(out)) != 1)
            rtlFail(-1, "Unable to finalize HMAC-SHA256 (EVP_MAC_final failed)");

        // Convert to hex string for result (STRING64).
        char* outPtr = static_cast<char*>(__result);
        for (size_t x = 0; x < outLen; x++)
        {
            *outPtr++ = hexchar[out[x] >> 4];
            *outPtr++ = hexchar[out[x] & 0x0f];
        }

        // Pad to exactly 64 chars if needed.
        while ((outPtr - static_cast<char*>(__result)) < 64)
            *outPtr++ = '0';
    }
    catch (...)
    {
        if (macCtx) EVP_MAC_CTX_free(macCtx);
        if (mac) EVP_MAC_free(mac);
        throw;
    }

    if (macCtx) EVP_MAC_CTX_free(macCtx);
    if (mac) EVP_MAC_free(mac);
ENDEMBED;

/*************************************************************************************************

TestHMAC(s, key, r) := MACRO
    ASSERT(HMAC_SHA256((DATA)s, (DATA)key) = (STRING)r, FAIL);
    OUTPUT('key=' + key + ' msg=' + IF(s != '', s, '<empty string>') + ' -> ' + HMAC_SHA256((DATA)s, (DATA)key));
ENDMACRO;

// NOTE: Expected values below correspond to the HMAC-SHA256 outputs for key "secretkey".
// If you change the key, the outputs change.
TestHMAC('CAMPER', 'secretkey', '5DC61FC7839EF4E41AED0E702B4380EBB00C394C58FD54C9C303DFF3E78AF46F');
TestHMAC('Colorless green ideas sleep furiously.', 'secretkey', '493338A6FD9147A3C3D6E5BB4D95FFD8967B69A1AD8C44E291E79E8A454566D6');
TestHMAC('', 'secretkey', '0EC2FBE02EA7C3EB6DD73C12EB2CFFC9061280DFC8365CDCFA5241C6E3D9C9A7');

*************************************************************************************************/
