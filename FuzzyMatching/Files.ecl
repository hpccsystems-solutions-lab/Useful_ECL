IMPORT Std;

EXPORT Files := MODULE

    EXPORT GUID_t       := STRING36;        // UUID string format
    EXPORT NAMEID_t     := UNSIGNED4;
    EXPORT NAME_HASH_t  := UNSIGNED8;

    //------------------------------------------------------------

    EXPORT CommonRawDataLayout := RECORD
        GUID_t      entity_guid;            // Entity ID
        GUID_t      name_guid;              // Entity Name ID
        UTF8        name;                   // Entity Name
    END;

    //------------------------------------------------------------

    EXPORT NameIndex(STRING path) := INDEX
        (
            {NAME_HASH_t name_hash},
            {
                UNSIGNED1   edit_distance,
                UNSIGNED1   word_id,
                NAMEID_t    name_id
            },
            DYNAMIC(path)
        );

    //------------------------------------------------------------

    EXPORT NameIDIndex(STRING path) := INDEX
        (
            {NAMEID_t name_id},
            {
                GUID_t      entity_guid,
                UNSIGNED1   word_count
            },
            DYNAMIC(path)
        );

    //------------------------------------------------------------

    EXPORT EntityIDIndex(STRING path) := INDEX
        (
            {GUID_t entity_guid},
            {
                NAMEID_t    name_id,
                GUID_t      name_guid,
                UTF8        full_name   {BLOB}
            },
            DYNAMIC(path)
        );

    //------------------------------------------------------------

    EXPORT StopwordDS(STRING path) := DATASET(path, {UTF8 word}, FLAT, OPT);

    //------------------------------------------------------------

END;
