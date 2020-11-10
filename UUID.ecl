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
 * The code here relies on libuuid being installed on all HPCC nodes that will
 * execute it.  For completeness, that means all Thor worker nodes, all Roxie
 * nodes, and the hthor node.  Both the library and header file for UUID need
 * to be installed on the eclccserver node as well, so that code compiles
 * correctly.  This code assumes that the header is located at <uuid/uuid.h>,
 * which is accurate for Ubuntu but may vary with other distributions.
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
 *      AsString(CONST UUIDBin_t uuid)
 *      AsBinary(CONST UUIDStr_t uuid)
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
EXPORT UUID := MODULE

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
        #option library uuid
        #include <uuid/uuid.h>

        #body

        uuid_t  newValue;

        uuid_generate(newValue);
        memcpy(__result, newValue, sizeof(uuid_t));
    ENDEMBED;

    /**
     * Create a new UUID value in human-readable string form.
     *
     * @return  A new UUIDStr_t value.
     *
     * @see     GenerateBin
     */
    EXPORT UUIDStr_t GenerateStr() VOLATILE := EMBED(c++)
        #option library uuid
        #include <uuid/uuid.h>

        #body

        uuid_t  newValue;
        char    buffer[37];

        uuid_generate(newValue);
        uuid_unparse(newValue, buffer);
        memcpy(__result, buffer, 36);
    ENDEMBED;

    /**
     * Return the standard "null UUID" value in compact binary form.
     *
     * @return  A null UUIDBin_t value.
     *
     * @see     NullValueStr
     */
    EXPORT UUIDBin_t NullValueBin() := EMBED(c++)
        #option library uuid
        #option pure;
        #include <uuid/uuid.h>

        #body

        uuid_t  newValue;

        uuid_clear(newValue);
        memcpy(__result, newValue, sizeof(uuid_t));
    ENDEMBED;

    /**
     * Return the standard "null UUID" value in human-readable string form.
     *
     * @return  A null UUIDStr_t value.
     *
     * @see     NullValueBin
     */
    EXPORT UUIDStr_t NullValueStr() := EMBED(c++)
        #option library uuid
        #option pure;
        #include <uuid/uuid.h>

        #body

        uuid_t  newValue;
        char    buffer[37];

        uuid_clear(newValue);
        uuid_unparse(newValue, buffer);
        memcpy(__result, buffer, 36);
    ENDEMBED;

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
        #option library uuid
        #option pure;
        #include <uuid/uuid.h>

        #body

        return uuid_is_null(static_cast<const unsigned char*>(uuid)) == 1;
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
    EXPORT BOOLEAN IsNullValueStr(CONST UUIDStr_t uuid) := EMBED(c++)
        #option library uuid
        #option pure;
        #include <uuid/uuid.h>

        #body

        char    buffer[37];
        uuid_t  parsedValue;

        memcpy(buffer, uuid, 36);
        buffer[36] = 0;
        if (uuid_parse(buffer, parsedValue) != 0)
            return false;

        return uuid_is_null(parsedValue) == 1;
    ENDEMBED;

    /**
     * Convert a binary UUID value to its human-readable string version.
     *
     * @param   uuid        The binary UUID value to convert.
     *
     * @return  A new UUIDStr_t value.
     *
     * @see     AsBinary
     */
    EXPORT UUIDStr_t AsString(CONST UUIDBin_t uuid) := EMBED(c++)
        #option library uuid
        #option pure;
        #include <uuid/uuid.h>

        #body

        char    buffer[37];

        uuid_unparse(static_cast<const unsigned char*>(uuid), buffer);
        memcpy(__result, buffer, 36);
    ENDEMBED;

    /**
     * Convert a string UUID value to its compact binary version.
     *
     * @param   uuid        The string UUID value to convert.
     *
     * @return  A new UUIDBin_t value.  If the argument is not a valid UUID
     *          then a (binary null UUID will be returned.
     *
     * @see     AsString
     */
    EXPORT UUIDBin_t AsBinary(CONST UUIDStr_t uuid) := EMBED(c++)
        #option library uuid
        #option pure;
        #include <uuid/uuid.h>

        #body

        char    buffer[37];
        uuid_t  parsedValue;

        memcpy(buffer, uuid, 36);
        buffer[36] = 0;
        if (uuid_parse(buffer, parsedValue) != 0)
            uuid_clear(parsedValue);

        memcpy(__result, parsedValue, 16);
    ENDEMBED;

END;
