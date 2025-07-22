/**
 * Set of functions for creating and testing Universally Unique Identifier
 * (UUID) values.  More information on UUIDs can be found here:
 *
 *      https://en.wikipedia.org/wiki/Universally_unique_identifier
 *
 * UUIDs can be represented in either a compact 16-byte form or a human-readable
 * (and somewhat more portable) 36-character string.  There are separate
 * functions for creating and testing UUID values in binary or string forms,
 * denoted by a 'Bin' or 'Str' suffix.  A pair of functions for converting
 * binary representations to string and vice-versa are also included.
 *
 * UUIDv7 is a 128-bit unique identifier like it's older siblings, such as
 * the widely used UUIDv4. But unlike v4, UUIDv7 is time-sortable with 1 ms
 * precision. By combining the timestamp and the random parts, UUIDv7 becomes
 * an excellent choice for record identifiers in databases, including
 * distributed ones.
 *
 * This module is API-compatible with Useful_ECL.UUIDv4.
 *
 * Exported data types:
 *
 *      UUIDBin_t (DATA16)
 *      UUIDStr_t (STRING36)
 *
 * Exported functions:
 *
 *      GenerateBin()
 *      GenerateStr()
 *      NullValueBin()
 *      NullValueStr()
 *      IsNullValueBin(CONST UUIDBin_t uuid)
 *      IsNullValueStr(CONST UUIDStr_t uuid)
 *      AsStr(CONST UUIDBin_t uuid)
 *      AsBin(CONST UUIDStr_t uuid)
 *
 * Origin:  https://github.com/hpccsystems-solutions-lab/Useful_ECL
 */
EXPORT UUIDv7 := MODULE

    /**
     * Exported Data Types
     */
    EXPORT UUIDBin_t := DATA16;
    EXPORT UUIDStr_t := STRING36;

    /**
     * Create a new UUID value in compact binary form.
     *
     * @return  A new UUIDBin_t value.
     *
     * @see     GenerateStr
     */
    EXPORT UUIDBin_t GenerateBin() VOLATILE := EMBED(c++)
        #include <array>
        #include <chrono>
        #include <cstdint>
        #include <cstdio>
        #include <random>

        // random bytes
        static std::random_device rd;
        static std::mt19937_64 gen(rd());
        static std::uniform_int_distribution<uint64_t> dis;

        #body

        std::array<uint8_t, 16> value;
        uint64_t* chunks = reinterpret_cast<uint64_t*>(value.data());
        chunks[0] = dis(gen);
        chunks[1] = dis(gen);

        // current timestamp in ms
        auto now = std::chrono::system_clock::now();
        auto millis = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();

        // timestamp
        value[0] = (millis >> 40) & 0xFF;
        value[1] = (millis >> 32) & 0xFF;
        value[2] = (millis >> 24) & 0xFF;
        value[3] = (millis >> 16) & 0xFF;
        value[4] = (millis >> 8) & 0xFF;
        value[5] = millis & 0xFF;

        // version and variant
        value[6] = (value[6] & 0x0F) | 0x70;
        value[8] = (value[8] & 0x3F) | 0x80;

        memcpy(__result, value.data(), 16);
    ENDEMBED;

    /**
     * Convert a binary UUID value to its human-readable string version.
     *
     * @param   uuid        The binary UUID value to convert.
     *
     * @return  A new UUIDStr_t value.
     *
     * @see     AsBin
     */
    EXPORT UUIDStr_t AsStr(CONST UUIDBin_t uuid) := EMBED(c++)
        #option pure;
        #include <iostream>
        #include <sstream>
        #include <iomanip>
        #include <string>
        #include <vector>

        #body

        std::ostringstream oss;
        const unsigned char* u = static_cast<const unsigned char*>(uuid);

        for (size_t i = 0; i < 16; ++i)
        {
            if (i == 4 || i == 6 || i == 8 || i == 10)
                oss << '-';

            oss << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(u[i]);
        }

        memcpy(__result, oss.str().data(), 36);
    ENDEMBED;

    /**
     * Convert a string UUID value to its compact binary version.
     *
     * @param   uuid        The string UUID value to convert.
     *
     * @return  A new UUIDBin_t value.  If the argument is not a valid UUID
     *          then a (binary null UUID will be returned.
     *
     * @see     AsStr
     */
    EXPORT UUIDBin_t AsBin(CONST UUIDStr_t uuid) := EMBED(c++)
        #option pure;
        #include <iostream>
        #include <sstream>
        #include <string>
        #include <vector>
        #include <iomanip>
        #include <stdexcept>

        uint8_t hexCharToInt(char c)
        {
            if (c >= '0' && c <= '9') return c - '0';
            if (c >= 'a' && c <= 'f') return c - 'a' + 10;
            if (c >= 'A' && c <= 'F') return c - 'A' + 10;
            throw std::invalid_argument("Invalid hexadecimal character");
        }

        #body

        std::vector<uint8_t> binaryUUID;
        binaryUUID.reserve(16);

        for (size_t i = 0; i < uuidLen; ++i)
        {
            if (uuid[i] == '-') continue;

            if (i % 2 == 0) {
                // Convert two characters to one byte
                uint8_t byte = (hexCharToInt(uuid[i]) << 4) | hexCharToInt(uuid[i + 1]);
                binaryUUID.push_back(byte);
            }
        }

        memcpy(__result, binaryUUID.data(), 16);
    ENDEMBED;

    /**
     * Create a new UUID value in human-readable string form.
     *
     * @return  A new UUIDStr_t value.
     *
     * @see     GenerateBin
     * @see     AsString
     */
    EXPORT UUIDStr_t GenerateStr() VOLATILE := AsStr(GenerateBin());

    /**
     * Return the standard "null UUID" value in compact binary form.
     *
     * @return  A null UUIDBin_t value.
     *
     * @see     NullValueStr
     */
    EXPORT UUIDBin_t NullValueBin() := EMBED(c++)
        #option pure;

        #body

        memset(__result, 0, 16);
    ENDEMBED;

    /**
     * Return the standard "null UUID" value in human-readable string form.
     *
     * @return  A null UUIDStr_t value.
     *
     * @see     NullValueBin
     */
    EXPORT UUIDStr_t NullValueStr() := '00000000-0000-0000-0000-000000000000';

    /**
     * Test if the given binary UUID value is NULL.
     *
     * @param   uuid        The binary UUID value to test.
     *
     * @return  TRUE if the argument is a null UUID value, FALSE otherwise.
     *
     * @see     IsNullValueStr
     */
    EXPORT BOOLEAN IsNullValueBin(CONST UUIDBin_t uuid) := EMBED(c++)
        #option pure;

        #body

        std::vector<uint8_t> zeroBlock(16, 0);
        return memcmp(uuid, zeroBlock.data(), 16) == 0;
    ENDEMBED;

    /**
     * Test if the given string UUID value is NULL.
     *
     * @param   uuid        The string UUID value to test.
     *
     * @return  TRUE if the argument is a null UUID value, FALSE otherwise.
     *
     * @see     IsNullValueBin
     */
    EXPORT BOOLEAN IsNullValueStr(CONST UUIDStr_t uuid) := (uuid = NullValueStr());

END;
