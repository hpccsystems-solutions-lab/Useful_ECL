/**
 * ECL module containing functions for efficiently deduplicating values within
 * a SET OF [type] attribute.  The following [type] types are supported:
 *
 *      -   INTEGER[n]
 *      -   UNSIGNED[n]
 *      -   REAL[n]
 *      -   STRING[n]
 *      -   VARSTRING
 *      -   UNICODE[n]
 *      -   VARUNICODE
 *      -   DATA[n]
 *
 * This code directly supports INTEGER8, UNSIGNED8, REAL8 and DATA types.  All
 * other data types listed above will be implicitly cast to a directly
 * supported data type, and the result will be a directly supported datatype.
 * The ECL compiler should be able to take care of implicit casts of returned
 * values.
 *
 * There are explicit deduplication functions defined.  You should choose the
 * most appropriate method for your datatype.  The functions are:
 *
 *      -   DedupInteger()
 *      -   DedupUnsigned()
 *      -   DedupReal()
 *      -   DedupData()
 *      -   DedupString()
 *      -   DedupUnicode()
 */
EXPORT Sets := MODULE

    /**
     * Deduplicates a SET OF INTEGER value.
     *
     * @param   the_set     The set to deduplicate; may be any SET OF INTEGER[n]
     *
     * @return  SET OF INTEGER8 values, deduplicated
     */
    EXPORT SET OF INTEGER8 DedupInteger(SET OF INTEGER8 the_set) := EMBED(C++ : DISTRIBUTED)
        #option pure
        typedef __int64 ELEMENT_TYPE;

        __lenResult = 0;
        __result = NULL;
        __isAllResult = false;

        if (lenThe_set >= sizeof(ELEMENT_TYPE))
        {
            unsigned int numElements = lenThe_set / sizeof(ELEMENT_TYPE);
            const ELEMENT_TYPE* source = static_cast<const ELEMENT_TYPE*>(the_set);
            bool seen[numElements];

            // Initialize our seen array to zero (false)
            memset(seen, 0, sizeof(seen));

            if (numElements > 1)
            {
                // For each unseen value, mark the same value later in the set
                // as seen
                for (unsigned int x = 0; x < numElements - 1; x++)
                {
                    if (seen[x] == false)
                    {
                        for (unsigned int y = x + 1; y < numElements; y++)
                        {
                            if (source[y] == source[x])
                            {
                                seen[y] = true;
                            }
                        }
                    }
                }
            }

            // Count up the number of unseen values; these will be the unique
            // values in the source
            unsigned int numUnique = 0;

            for (unsigned int x = 0; x < numElements; x++)
            {
                if (seen[x] == false)
                {
                    ++numUnique;
                }
            }

            // Allocate memory to hold numUnique values
            __lenResult = numUnique * sizeof(ELEMENT_TYPE);
            __result = rtlMalloc(__lenResult);

            // Copy only the unseen/unique values to the result
            unsigned int destOffset = 0;

            for (unsigned int x = 0; x < numElements; x++)
            {
                if (seen[x] == false)
                {
                    reinterpret_cast<ELEMENT_TYPE*>(__result)[destOffset++] = source[x];
                }
            }
        }
    ENDEMBED;

    /**
     * Deduplicates a SET OF UNSIGNED value.
     *
     * @param   the_set     The set to deduplicate; may be any SET OF UNSIGNED[n]
     *
     * @return  SET OF UNSIGNED8 values, deduplicated
     */
    EXPORT SET OF UNSIGNED8 DedupUnsigned(SET OF UNSIGNED8 the_set) := EMBED(C++ : DISTRIBUTED)
        #option pure
        typedef unsigned __int64 ELEMENT_TYPE;

        __lenResult = 0;
        __result = NULL;
        __isAllResult = false;

        if (lenThe_set >= sizeof(ELEMENT_TYPE))
        {
            unsigned int numElements = lenThe_set / sizeof(ELEMENT_TYPE);
            const ELEMENT_TYPE* source = static_cast<const ELEMENT_TYPE*>(the_set);
            bool seen[numElements];

            // Initialize our seen array to zero (false)
            memset(seen, 0, sizeof(seen));

            if (numElements > 1)
            {
                // For each unseen value, mark the same value later in the set
                // as seen
                for (unsigned int x = 0; x < numElements - 1; x++)
                {
                    if (seen[x] == false)
                    {
                        for (unsigned int y = x + 1; y < numElements; y++)
                        {
                            if (source[y] == source[x])
                            {
                                seen[y] = true;
                            }
                        }
                    }
                }
            }

            // Count up the number of unseen values; these will be the unique
            // values in the source
            unsigned int numUnique = 0;

            for (unsigned int x = 0; x < numElements; x++)
            {
                if (seen[x] == false)
                {
                    ++numUnique;
                }
            }

            // Allocate memory to hold numUnique values
            __lenResult = numUnique * sizeof(ELEMENT_TYPE);
            __result = rtlMalloc(__lenResult);

            // Copy only the unseen/unique values to the result
            unsigned int destOffset = 0;

            for (unsigned int x = 0; x < numElements; x++)
            {
                if (seen[x] == false)
                {
                    reinterpret_cast<ELEMENT_TYPE*>(__result)[destOffset++] = source[x];
                }
            }
        }
    ENDEMBED;

    /**
     * Deduplicates a SET OF REAL value.
     *
     * @param   the_set     The set to deduplicate; may be any SET OF REAL[n]
     *
     * @return  SET OF REAL8 values, deduplicated
     */
    EXPORT SET OF REAL8 DedupReal(SET OF REAL8 the_set) := EMBED(C++ : DISTRIBUTED)
        #option pure
        typedef double ELEMENT_TYPE;

        __lenResult = 0;
        __result = NULL;
        __isAllResult = false;

        if (lenThe_set >= sizeof(ELEMENT_TYPE))
        {
            unsigned int numElements = lenThe_set / sizeof(ELEMENT_TYPE);
            const ELEMENT_TYPE* source = static_cast<const ELEMENT_TYPE*>(the_set);
            bool seen[numElements];

            // Initialize our seen array to zero (false)
            memset(seen, 0, sizeof(seen));

            if (numElements > 1)
            {
                // For each unseen value, mark the same value later in the set
                // as seen
                for (unsigned int x = 0; x < numElements - 1; x++)
                {
                    if (seen[x] == false)
                    {
                        for (unsigned int y = x + 1; y < numElements; y++)
                        {
                            if (source[y] == source[x])
                            {
                                seen[y] = true;
                            }
                        }
                    }
                }
            }

            // Count up the number of unseen values; these will be the unique
            // values in the source
            unsigned int numUnique = 0;

            for (unsigned int x = 0; x < numElements; x++)
            {
                if (seen[x] == false)
                {
                    ++numUnique;
                }
            }

            // Allocate memory to hold numUnique values
            __lenResult = numUnique * sizeof(ELEMENT_TYPE);
            __result = rtlMalloc(__lenResult);

            // Copy only the unseen/unique values to the result
            unsigned int destOffset = 0;

            for (unsigned int x = 0; x < numElements; x++)
            {
                if (seen[x] == false)
                {
                    reinterpret_cast<ELEMENT_TYPE*>(__result)[destOffset++] = source[x];
                }
            }
        }
    ENDEMBED;

    /**
     * Deduplicates a SET OF DATA value.  Duplicate values are determined by
     * bytewise comparison.
     *
     * @param   the_set     The set to deduplicate; may be any SET OF DATA[n]
     *
     * @return  SET OF DATA values, deduplicated
     */
    EXPORT SET OF DATA DedupData(SET OF DATA the_set) := EMBED(C++ : DISTRIBUTED)
        #option pure
        #include <vector>

        class StrInfo
        {
            public:

                StrInfo(int32_t _size, const char* _str)
                    :   size(_size), str(_str)
                    {}

                StrInfo(const void* ptr)
                    {
                        size = *reinterpret_cast<const int32_t*>(ptr);
                        str = reinterpret_cast<const char*>(ptr) + sizeof(int32_t);
                    }

                unsigned int TotalLength()
                    {
                        return sizeof(size) + size;
                    }

                void CopyToMem(void* destPtr)
                    {
                        *reinterpret_cast<int32_t*>(destPtr) = size;
                        memcpy(destPtr + sizeof(int32_t), str, size);
                    }

                int32_t size;
                const char* str;
        };

        typedef std::vector<StrInfo> StringList;

        #body

        __lenResult = 0;
        __result = NULL;
        __isAllResult = false;

        if (lenThe_set > 0)
        {
            StringList  collectedStrings;
            const void*   sourcePtr = the_set;
            unsigned int numElements = 0;

            while (sourcePtr < the_set + lenThe_set)
            {
                StrInfo newElement(sourcePtr);

                collectedStrings.push_back(newElement);
                sourcePtr += newElement.TotalLength();
                ++numElements;
            }

            bool seen[numElements];

            // Initialize our seen array to zero (false)
            memset(seen, 0, sizeof(seen));

            if (numElements > 1)
            {
                // For each unseen value, mark the same value later in the set
                // as seen
                for (unsigned int x = 0; x < numElements - 1; x++)
                {
                    if (seen[x] == false)
                    {
                        for (unsigned int y = x + 1; y < numElements; y++)
                        {
                            if (collectedStrings[x].size == collectedStrings[y].size && memcmp(collectedStrings[x].str, collectedStrings[y].str, collectedStrings[x].size) == 0)
                            {
                                seen[y] = true;
                            }
                        }
                    }
                }
            }

            // Count up the number of unseen values; these will be the unique
            // values in the source; also sum the size of the unique strings
            // (along with their length)
            unsigned int numUnique = 0;
            unsigned int totalLength = 0;

            for (unsigned int x = 0; x < numElements; x++)
            {
                if (seen[x] == false)
                {
                    ++numUnique;
                    totalLength += sizeof(collectedStrings[x].size) + collectedStrings[x].size;
                }
            }

            // Allocate memory to hold numUnique values
            __lenResult = totalLength;
            __result = rtlMalloc(__lenResult);

            // Copy only the unseen/unique values to the result
            void* destPtr = __result;

            for (unsigned int x = 0; x < numElements; x++)
            {
                if (seen[x] == false)
                {
                    collectedStrings[x].CopyToMem(destPtr);
                    destPtr += collectedStrings[x].TotalLength();
                }
            }
        }
    ENDEMBED;

    /**
     * Deduplicates a SET OF STRING value.  Duplicate values are determined by
     * bytewise comparison.  Note that the strings are coerced to DATA types
     * during conversion, then back to STRING for return.
     *
     * @param   the_set     The set to deduplicate; may be any SET OF STRING[n]
     *                      or SET OF VARSTRING
     *
     * @return  SET OF STRING values, deduplicated
     */
    EXPORT SET OF STRING DedupString(SET OF STRING the_set) := FUNCTION
        RETURN (SET OF STRING)DedupData((SET OF DATA)the_set);
    END;

    /**
     * Deduplicates a SET OF UNICODE value.  Duplicate values are determined by
     * bytewise comparison.  Note that the unicode strings are coerced to DATA
     * types during conversion, then back to UNICODE for return.
     *
     * @param   the_set     The set to deduplicate; may be any SET OF UNICODE[n]
     *                      or SET OF VARUNICODE
     *
     * @return  SET OF UNICODE values, deduplicated
     */
    EXPORT SET OF UNICODE DedupUnicode(SET OF UNICODE the_set) := FUNCTION
        RETURN (SET OF UNICODE)DedupData((SET OF DATA)the_set);
    END;

END;
