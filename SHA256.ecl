/**
 * Return the SHA256 hash of some input.
 *
 * @param   b   A DATA blob of what you want to hash
 *
 * @return  A STRING64 version of the hash. This is a
 *          readable hex-encoded version of the binary
 *          hash value.
 *
 * See sample calls at the end of this file.
 *
 * Origin:  https://github.com/hpccsystems-solutions-lab/Useful_ECL
 */
EXPORT STRING64 SHA256(DATA b) := EMBED(C++ : pure)
    #include "openssl/evp.h"

    static const char hexchar[] = "0123456789ABCDEF";

    #body

    EVP_MD_CTX* openSSLContext = nullptr;

    try
    {
        openSSLContext = EVP_MD_CTX_new();
        if (!openSSLContext)
            rtlFail(-1, "Unable to create an SHA256 context");

        if (EVP_DigestInit_ex(openSSLContext, EVP_sha256(), nullptr) != 1)
            rtlFail(-1, "Unable to initialize an SHA256 context");

        if (EVP_DigestUpdate(openSSLContext, b, lenB) != 1)
            rtlFail(-1, "Unable to update an SHA256 context");

        const unsigned int  digestLen = EVP_MD_CTX_get_size(openSSLContext);
        unsigned char       buffer[digestLen];

        if (EVP_DigestFinal_ex(openSSLContext, buffer, nullptr) != 1)
            rtlFail(-1, "Unable to finalize an SHA256 context");

        // Convert blob to hex string for result
        char* outPtr = static_cast<char*>(__result);
        for (unsigned int x = 0; x < digestLen; x++)
        {
            *outPtr++ = hexchar[buffer[x] >> 4];
            *outPtr++ = hexchar[buffer[x] & 0x0f];
        }
    }
    catch (...)
    {
        if (openSSLContext)
            EVP_MD_CTX_free(openSSLContext);
        throw;
    }

    EVP_MD_CTX_free(openSSLContext);
ENDEMBED;

/*************************************************************************************************

TestSHA256(s, r) := MACRO
    ASSERT(SHA256((DATA)s) = (STRING)r, FAIL);
    OUTPUT(IF(s != '', s, '<empty string>') + ': ' + SHA256((DATA)s));
ENDMACRO;

TestSHA256('CAMPER', 'CB3332EEFDA965B4D26E4001A926DB478F27575AE4029283B67AC8A86F4FA4C7');
TestSHA256('Colorless green ideas sleep furiously.', '0F6BE6CC79C301CEA386173C0919FEE806E78075618656D24F733AA5052EBF6D');
TestSHA256('', 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855');

*************************************************************************************************/
