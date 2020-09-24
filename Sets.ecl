/**
 * This is a module containing functions for processing ECL SET OF [type]
 * values.  It contains functions for the following:
 *
 *  -   DEDUPLICATE the values within a set:  The deduplicated values are
 *      returned in the same order in which they appear in the input.
 *
 *  -   Find the UNION of values between two sets:  Merge two sets together,
 *      deduplicate the values, and return the result as one set.  The returned
 *      values appear in the same order in which they appear in the first set,
 *      then the same order in which they appear in the second set.
 *
 *  -   Find the INTERSECTION of values between two sets:  Return the values
 *      shared between two sets, deduplicated, as one set.  The returned
 *      values appear in the same order in which they appear in the first set,
 *      then the same order in which they appear in the second set.
 *
 *  -   Find the DIFFERENCE of values between two sets:  Return the
 *      deduplicated values from the first set that do not appear in the second
 *      set as one set.  The returned values appear in the same order in which
 *      they appear in the first set.
 *
 * The ECL-only way of performing these kinds of operations is to convert the
 * sets to a dataset, perform the operation, then convert the result back to
 * a set.  This is not very efficient, consumes quite a bit of memory, and can
 * be quite painful if executed within a TRANSFORM iterating over millions
 * of records.
 *
 * The code here is has been designed to use as little memory as possible and
 * avoids copying any input set values unless they are part of the final result.
 *
 * The following data types are supported:
 *
 *      SET OF INTEGER[n]
 *      SET OF UNSIGNED[n]
 *      SET OF REAL[n]
 *      SET OF STRING[n]
 *      SET OF VARSTRING[n]
 *      SET OF UNICODE[n]
 *      SET OF VARUNICODE[n]
 *      SET OF DATA[n]
 *
 * This code directly supports INTEGER8, UNSIGNED8, REAL8 and DATA types.  All
 * other data types listed above will be implicitly cast to a directly
 * supported data type, and the result will be that same directly supported
 * datatype.  The ECL compiler should be able to take care of implicit casts of
 * returned values.
 *
 * There are explicit exported functions defined.  You should choose the
 * most appropriate method for your datatype.  The functions for each datatype
 * are:
 *
 *      SET OF INTEGER[n] / SET OF UNSIGNED[n] (if max value < 2^63)
 *          IntegerDedup()
 *          IntegerUnion()
 *          IntegerIntersection()
 *          IntegerDifference()
 *
 *      SET OF UNSIGNED[n]
 *          UnsignedDedup()
 *          UnsignedUnion()
 *          UnsignedIntersection()
 *          UnsignedDifference()
 *
 *      SET OF REAL4 / SET OF REAL8 / SET OF REAL
 *          RealDedup()
 *          RealUnion()
 *          RealIntersection()
 *          RealDifference()
 *
 *      SET OF DATA[n]
 *          DataDedup()
 *          DataUnion()
 *          DataIntersection()
 *          DataDifference()
 *
 *      SET OF STRING[n] / SET OF VARSTRING[n]
 *          StringDedup()
 *          StringUnion()
 *          StringIntersection()
 *          StringDifference()
 *
 *
 *      SET OF UNICODE[n] / SET OF VARUNICODE[n]
 *          UnicodeDedup()
 *          UnicodeUnion()
 *          UnicodeIntersection()
 *          UnicodeDifference()
 *
 * There is test code located within a comment block at the end of this file.
 * The code exercises all of the methods here with a variety of input values.
 *
 * Implementation notes:
 *
 * The hard work is done with embedded C++ functions.  Astute readers will note
 * a huge similarity between the individual C++ functions.  Normally,
 * those functions would be perfect candidates for a template function
 * implementation.  Unfortunately, embedded C++ functions within ECL do not
 * have any visibility to each other nor to a well-defined shared code space.
 * The C++ portions could have been written as an ECL service plugin instead,
 * which would allow template functions to be used, but plugins require extra
 * cluster maintenance (you have to install them separately).  The choice here
 * was to go ahead and duplicate the C++ code so that the impact on the ECL
 * programmer was minimal.
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
EXPORT Sets := MODULE

    SHARED MERGE_TYPE_UNION := 1;
    SHARED MERGE_TYPE_INTERSECTION := 2;
    SHARED MERGE_TYPE_DIFFERENCE := 3;

    SHARED InternalCode := MODULE

        /**
         * Deduplicates and merges two SET OF INTEGER8 ECL sets.  If one of the
         * set arguments is empty then the function deduplicates the non-empty
         * set.
         *
         * @param   the_set1    The first set to process; may be any
         *                      SET OF INTEGER[n] or SET OF UNSIGNED[n] where no
         *                      value exceeds 2^63 - 1; may be empty
         * @param   the_set2    The second set to process; may be any
         *                      SET OF INTEGER[n] or SET OF UNSIGNED[n] where no
         *                      value exceeds 2^63 - 1; may be empty
         * @param   merge_type  1 = perform a union of unique values between
         *                      the sets; 2 = perform an intersection of unique
         *                      values between the sets; any other value throws
         *                      an error
         *
         * @return  A new SET OF INTEGER8 value containing unique values; if
         *          merge_type == 1 then the values will represent all unique values
         *          from the two given sets; if merge_type == 2 then the values will
         *          represent all unique common values from the two given sets
         */
        EXPORT SET OF INTEGER8 _MergeInteger(SET OF INTEGER8 the_set1, SET OF INTEGER8 the_set2, UNSIGNED2 merge_type) := EMBED(C++)
            #option pure;
            #body
            typedef __int64 ELEMENT_TYPE;

            __lenResult = 0;
            __result = NULL;
            __isAllResult = false;

            unsigned long numElements1 = lenThe_set1 / sizeof(ELEMENT_TYPE);
            unsigned long numElements2 = lenThe_set2 / sizeof(ELEMENT_TYPE);
            unsigned long totalNumElements = numElements1 + numElements2;
            bool allowOneSetEmpty = merge_type != 2;

            if (totalNumElements > 0 && (allowOneSetEmpty || (numElements1 > 0 && numElements2 > 0)))
            {
                const ELEMENT_TYPE* source1 = static_cast<const ELEMENT_TYPE*>(the_set1);
                const ELEMENT_TYPE* source2 = static_cast<const ELEMENT_TYPE*>(the_set2);
                bool omitFromResult[totalNumElements];

                // Initialize our omitFromResult array to zero (false)
                memset(omitFromResult, 0, sizeof(omitFromResult));

                if (numElements1 > 0)
                {
                    // For each untagged value in the first set, mark the same value
                    // later in the set as tagged
                    for (unsigned long x = 0; x < numElements1 - 1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            for (unsigned long y = x + 1; y < numElements1; y++)
                            {
                                if (source1[y] == source1[x])
                                {
                                    omitFromResult[y] = true;
                                }
                            }
                        }
                    }
                }

                if (numElements2 > 0)
                {
                    // For each untagged value in the second set, mark the same value
                    // later in the set as tagged
                    for (unsigned long x = 0; x < numElements2 - 1; x++)
                    {
                        if (omitFromResult[numElements1 + x] == false)
                        {
                            for (unsigned long y = x + 1; y < numElements2; y++)
                            {
                                if (source2[y] == source2[x])
                                {
                                    omitFromResult[numElements1 + y] = true;
                                }
                            }
                        }
                    }
                }

                // At this point omitFromResult[false] indicates which elements are
                // unique within their respective sets

                unsigned long numElementsToCheck = totalNumElements;

                if (merge_type == 1)
                {
                    // Union of values

                    // Deduplicate the untagged values between the two sets
                    for (unsigned long x = 0; x < numElements1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            for (unsigned long y = 0; y < numElements2; y++)
                            {
                                if (omitFromResult[numElements1 + y] == false && source2[y] == source1[x])
                                {
                                    omitFromResult[numElements1 + y] = true;
                                    break;
                                }
                            }
                        }
                    }
                }
                else if (merge_type == 2)
                {
                    // Intersection of values
                    numElementsToCheck = numElements1;

                    // Find matching values between the two sets
                    for (unsigned long x = 0; x < numElements1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            bool    wasFound = false;

                            for (unsigned long y = 0; y < numElements2; y++)
                            {
                                if (omitFromResult[numElements1 + y] == false && source2[y] == source1[x])
                                {
                                    wasFound = true;
                                    break;
                                }
                            }

                            if (!wasFound)
                            {
                                // We didn't find the value in the second set,
                                // so mark it in the first set so we don't pick
                                // it up
                                omitFromResult[x] = true;
                            }
                        }
                    }
                }
                else if (merge_type == 3)
                {
                    // Difference of values
                    numElementsToCheck = numElements1;

                    // Find matching values between sets and, if found, tag the
                    // value in the first set
                    for (unsigned long x = 0; x < numElements1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            for (unsigned long y = 0; y < numElements2; y++)
                            {
                                if (omitFromResult[numElements1 + y] == false && source2[y] == source1[x])
                                {
                                    omitFromResult[x] = true;
                                    break;
                                }
                            }
                        }
                    }
                }
                else
                {
                    rtlFail(0, "_MergeInteger: Unknown merge_type value");
                }

                // Count up the number of untagged values; this will be the number
                // of result values in the source
                unsigned long numResultElements = 0;

                for (unsigned long x = 0; x < numElementsToCheck; x++)
                {
                    if (omitFromResult[x] == false)
                    {
                        ++numResultElements;
                    }
                }

                if (numResultElements > 0)
                {
                    // Allocate memory to hold numResultElements values
                    __lenResult = numResultElements * sizeof(ELEMENT_TYPE);
                    __result = rtlMalloc(__lenResult);

                    unsigned long destOffset = 0;

                    // Copy only the untagged values from the first set to the result
                    for (unsigned long x = 0; x < numElements1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            reinterpret_cast<ELEMENT_TYPE*>(__result)[destOffset++] = source1[x];
                        }
                    }

                    if (numElementsToCheck > numElements1)
                    {
                        // Copy only the untagged values from the second set to the result
                        for (unsigned long x = 0; x < numElements2; x++)
                        {
                            if (omitFromResult[numElements1 + x] == false)
                            {
                                reinterpret_cast<ELEMENT_TYPE*>(__result)[destOffset++] = source2[x];
                            }
                        }
                    }
                }
            }
        ENDEMBED;

        /**
         * Deduplicates and merges two SET OF UNSIGNED8 ECL sets.  If one of the
         * set arguments is empty then the function deduplicates the non-empty
         * set.
         *
         * @param   the_set1    The first set to process; may be any
         *                      SET OF UNSIGNED[n]; may be empty
         * @param   the_set2    The second set to process; may be any
         *                      SET OF UNSIGNED[n]; may be empty
         * @param   merge_type  1 = perform a union of unique values between
         *                      the sets; 2 = perform an intersection of unique
         *                      values between the sets; any other value throws
         *                      an error
         *
         * @return  A new SET OF UNSIGNED8 value containing unique values; if
         *          merge_type == 1 then the values will represent all unique values
         *          from the two given sets; if merge_type == 2 then the values will
         *          represent all unique common values from the two given sets
         */
        EXPORT SET OF UNSIGNED8 _MergeUnsigned(SET OF UNSIGNED8 the_set1, SET OF UNSIGNED8 the_set2, UNSIGNED2 merge_type) := EMBED(C++)
            #option pure;
            #body
            typedef unsigned __int64 ELEMENT_TYPE;

            __lenResult = 0;
            __result = NULL;
            __isAllResult = false;

            unsigned long numElements1 = lenThe_set1 / sizeof(ELEMENT_TYPE);
            unsigned long numElements2 = lenThe_set2 / sizeof(ELEMENT_TYPE);
            unsigned long totalNumElements = numElements1 + numElements2;
            bool allowOneSetEmpty = merge_type != 2;

            if (totalNumElements > 0 && (allowOneSetEmpty || (numElements1 > 0 && numElements2 > 0)))
            {
                const ELEMENT_TYPE* source1 = static_cast<const ELEMENT_TYPE*>(the_set1);
                const ELEMENT_TYPE* source2 = static_cast<const ELEMENT_TYPE*>(the_set2);
                bool omitFromResult[totalNumElements];

                // Initialize our omitFromResult array to zero (false)
                memset(omitFromResult, 0, sizeof(omitFromResult));

                if (numElements1 > 0)
                {
                    // For each untagged value in the first set, mark the same value
                    // later in the set as tagged
                    for (unsigned long x = 0; x < numElements1 - 1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            for (unsigned long y = x + 1; y < numElements1; y++)
                            {
                                if (source1[y] == source1[x])
                                {
                                    omitFromResult[y] = true;
                                }
                            }
                        }
                    }
                }

                if (numElements2 > 0)
                {
                    // For each untagged value in the second set, mark the same value
                    // later in the set as tagged
                    for (unsigned long x = 0; x < numElements2 - 1; x++)
                    {
                        if (omitFromResult[numElements1 + x] == false)
                        {
                            for (unsigned long y = x + 1; y < numElements2; y++)
                            {
                                if (source2[y] == source2[x])
                                {
                                    omitFromResult[numElements1 + y] = true;
                                }
                            }
                        }
                    }
                }

                // At this point omitFromResult[false] indicates which elements are
                // unique within their respective sets

                unsigned long numElementsToCheck = totalNumElements;

                if (merge_type == 1)
                {
                    // Union of values

                    // Deduplicate the untagged values between the two sets
                    for (unsigned long x = 0; x < numElements1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            for (unsigned long y = 0; y < numElements2; y++)
                            {
                                if (omitFromResult[numElements1 + y] == false && source2[y] == source1[x])
                                {
                                    omitFromResult[numElements1 + y] = true;
                                    break;
                                }
                            }
                        }
                    }
                }
                else if (merge_type == 2)
                {
                    // Intersection of values
                    numElementsToCheck = numElements1;

                    // Find matching values between the two sets
                    for (unsigned long x = 0; x < numElements1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            bool    wasFound = false;

                            for (unsigned long y = 0; y < numElements2; y++)
                            {
                                if (omitFromResult[numElements1 + y] == false && source2[y] == source1[x])
                                {
                                    wasFound = true;
                                    break;
                                }
                            }

                            if (!wasFound)
                            {
                                // We didn't find the value in the second set,
                                // so mark it in the first set so we don't pick
                                // it up
                                omitFromResult[x] = true;
                            }
                        }
                    }
                }
                else if (merge_type == 3)
                {
                    // Difference of values
                    numElementsToCheck = numElements1;

                    // Find matching values between sets and, if found, tag both
                    for (unsigned long x = 0; x < numElements1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            for (unsigned long y = 0; y < numElements2; y++)
                            {
                                if (omitFromResult[numElements1 + y] == false && source2[y] == source1[x])
                                {
                                    omitFromResult[x] = true;
                                    break;
                                }
                            }
                        }
                    }
                }
                else
                {
                    rtlFail(0, "_MergeUnsigned: Unknown merge_type value");
                }

                // Count up the number of untagged values; this will be the number
                // of result values in the source
                unsigned long numResultElements = 0;

                for (unsigned long x = 0; x < numElementsToCheck; x++)
                {
                    if (omitFromResult[x] == false)
                    {
                        ++numResultElements;
                    }
                }

                if (numResultElements > 0)
                {
                    // Allocate memory to hold numResultElements values
                    __lenResult = numResultElements * sizeof(ELEMENT_TYPE);
                    __result = rtlMalloc(__lenResult);

                    unsigned long destOffset = 0;

                    // Copy only the untagged values from the first set to the result
                    for (unsigned long x = 0; x < numElements1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            reinterpret_cast<ELEMENT_TYPE*>(__result)[destOffset++] = source1[x];
                        }
                    }

                    if (numElementsToCheck > numElements1)
                    {
                        // Copy only the untagged values from the second set to the result
                        for (unsigned long x = 0; x < numElements2; x++)
                        {
                            if (omitFromResult[numElements1 + x] == false)
                            {
                                reinterpret_cast<ELEMENT_TYPE*>(__result)[destOffset++] = source2[x];
                            }
                        }
                    }
                }
            }
        ENDEMBED;

        /**
         * Deduplicates and merges two SET OF REAL8 ECL sets.  If one of the
         * set arguments is empty then the function deduplicates the non-empty
         * set.
         *
         * @param   the_set1    The first set to process; may be any
         *                      SET OF REAL[n]; may be empty
         * @param   the_set2    The second set to process; may be any
         *                      SET OF REAL[n]; may be empty
         * @param   merge_type  1 = perform a union of unique values between
         *                      the sets; 2 = perform an intersection of unique
         *                      values between the sets; any other value throws
         *                      an error
         *
         * @return  A new SET OF REAL8 value containing unique values; if
         *          merge_type == 1 then the values will represent all unique values
         *          from the two given sets; if merge_type == 2 then the values will
         *          represent all unique common values from the two given sets
         */
        EXPORT SET OF REAL8 _MergeReal(SET OF REAL8 the_set1, SET OF REAL8 the_set2, UNSIGNED2 merge_type) := EMBED(C++)
            #option pure;
            typedef double ELEMENT_TYPE;

            __lenResult = 0;
            __result = NULL;
            __isAllResult = false;

            unsigned long numElements1 = lenThe_set1 / sizeof(ELEMENT_TYPE);
            unsigned long numElements2 = lenThe_set2 / sizeof(ELEMENT_TYPE);
            unsigned long totalNumElements = numElements1 + numElements2;
            bool allowOneSetEmpty = merge_type != 2;

            if (totalNumElements > 0 && (allowOneSetEmpty || (numElements1 > 0 && numElements2 > 0)))
            {
                const ELEMENT_TYPE* source1 = static_cast<const ELEMENT_TYPE*>(the_set1);
                const ELEMENT_TYPE* source2 = static_cast<const ELEMENT_TYPE*>(the_set2);
                bool omitFromResult[totalNumElements];

                // Initialize our omitFromResult array to zero (false)
                memset(omitFromResult, 0, sizeof(omitFromResult));

                if (numElements1 > 0)
                {
                    // For each untagged value in the first set, mark the same value
                    // later in the set as tagged
                    for (unsigned long x = 0; x < numElements1 - 1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            for (unsigned long y = x + 1; y < numElements1; y++)
                            {
                                if (source1[y] == source1[x])
                                {
                                    omitFromResult[y] = true;
                                }
                            }
                        }
                    }
                }

                if (numElements2 > 0)
                {
                    // For each untagged value in the second set, mark the same value
                    // later in the set as tagged
                    for (unsigned long x = 0; x < numElements2 - 1; x++)
                    {
                        if (omitFromResult[numElements1 + x] == false)
                        {
                            for (unsigned long y = x + 1; y < numElements2; y++)
                            {
                                if (source2[y] == source2[x])
                                {
                                    omitFromResult[numElements1 + y] = true;
                                }
                            }
                        }
                    }
                }

                // At this point omitFromResult[false] indicates which elements are
                // unique within their respective sets

                unsigned long numElementsToCheck = totalNumElements;

                if (merge_type == 1)
                {
                    // Union of values

                    // Deduplicate the untagged values between the two sets
                    for (unsigned long x = 0; x < numElements1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            for (unsigned long y = 0; y < numElements2; y++)
                            {
                                if (omitFromResult[numElements1 + y] == false && source2[y] == source1[x])
                                {
                                    omitFromResult[numElements1 + y] = true;
                                    break;
                                }
                            }
                        }
                    }
                }
                else if (merge_type == 2)
                {
                    // Intersection of values
                    numElementsToCheck = numElements1;

                    // Find matching values between the two sets
                    for (unsigned long x = 0; x < numElements1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            bool    wasFound = false;

                            for (unsigned long y = 0; y < numElements2; y++)
                            {
                                if (omitFromResult[numElements1 + y] == false && source2[y] == source1[x])
                                {
                                    wasFound = true;
                                    break;
                                }
                            }

                            if (!wasFound)
                            {
                                // We didn't find the value in the second set,
                                // so mark it in the first set so we don't pick
                                // it up
                                omitFromResult[x] = true;
                            }
                        }
                    }
                }
                else if (merge_type == 3)
                {
                    // Difference of values
                    numElementsToCheck = numElements1;

                    // Find matching values between sets and, if found, tag both
                    for (unsigned long x = 0; x < numElements1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            for (unsigned long y = 0; y < numElements2; y++)
                            {
                                if (omitFromResult[numElements1 + y] == false && source2[y] == source1[x])
                                {
                                    omitFromResult[x] = true;
                                    break;
                                }
                            }
                        }
                    }
                }
                else
                {
                    rtlFail(0, "_MergeReal: Unknown merge_type value");
                }

                // Count up the number of untagged values; this will be the number
                // of result values in the source
                unsigned long numResultElements = 0;

                for (unsigned long x = 0; x < numElementsToCheck; x++)
                {
                    if (omitFromResult[x] == false)
                    {
                        ++numResultElements;
                    }
                }

                if (numResultElements > 0)
                {
                    // Allocate memory to hold numResultElements values
                    __lenResult = numResultElements * sizeof(ELEMENT_TYPE);
                    __result = rtlMalloc(__lenResult);

                    unsigned long destOffset = 0;

                    // Copy only the untagged values from the first set to the result
                    for (unsigned long x = 0; x < numElements1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            reinterpret_cast<ELEMENT_TYPE*>(__result)[destOffset++] = source1[x];
                        }
                    }

                    if (numElementsToCheck > numElements1)
                    {
                        // Copy only the untagged values from the second set to the result
                        for (unsigned long x = 0; x < numElements2; x++)
                        {
                            if (omitFromResult[numElements1 + x] == false)
                            {
                                reinterpret_cast<ELEMENT_TYPE*>(__result)[destOffset++] = source2[x];
                            }
                        }
                    }
                }
            }
        ENDEMBED;

        /**
         * Deduplicates and merges two SET OF DATA ECL sets.  If one of the
         * set arguments is empty then the function deduplicates the non-empty
         * set.
         *
         * @param   the_set1    The first set to process; may be any
         *                      SET OF DATA[n]; may be empty
         * @param   the_set2    The second set to process; may be any
         *                      SET OF DATA[n]; may be empty
         * @param   merge_type  1 = perform a union of unique values between
         *                      the sets; 2 = perform an intersection of unique
         *                      values between the sets; any other value throws
         *                      an error
         *
         * @return  A new SET OF DATA value containing unique values; if
         *          merge_type == 1 then the values will represent all unique values
         *          from the two given sets; if merge_type == 2 then the values will
         *          represent all unique common values from the two given sets
         */
        EXPORT SET OF DATA _MergeData(SET OF DATA the_set1, SET OF DATA the_set2, UNSIGNED2 merge_type) := EMBED(C++)
            #option pure;
            #include <vector>

            class MergeDataInfo
            {
                public:

                    MergeDataInfo(int32_t _size, const void* _dataPtr)
                        :   size(_size), dataPtr(_dataPtr)
                        {}

                    MergeDataInfo(const void* ptr)
                        {
                            size = *reinterpret_cast<const int32_t*>(ptr);
                            dataPtr = ptr + sizeof(int32_t);
                        }

                    unsigned long BytesUsed()
                        {
                            return sizeof(size) + size;
                        }

                    void CopyToMem(void* destPtr)
                        {
                            *reinterpret_cast<int32_t*>(destPtr) = size;
                            if (size > 0)
                            {
                                memcpy(destPtr + sizeof(int32_t), dataPtr, size);
                            }
                        }

                    int32_t size;
                    const void* dataPtr;
            };

            inline bool operator==(const MergeDataInfo& lhs, const MergeDataInfo& rhs)
                {
                    return (lhs.size == rhs.size && (lhs.size == 0 || memcmp(lhs.dataPtr, rhs.dataPtr, lhs.size) == 0));
                }

            typedef std::vector<MergeDataInfo> MergeDataList;

            #body

            __lenResult = 0;
            __result = NULL;
            __isAllResult = false;

            const void*     sourcePtr1 = the_set1;
            const void*     sourcePtr2 = the_set2;
            unsigned long   numElements1 = 0;
            unsigned long   numElements2 = 0;
            MergeDataList   sourceObjects1;
            MergeDataList   sourceObjects2;
            unsigned long   totalNumElements = 0;

            if (lenThe_set1 > 0)
            {
                while (sourcePtr1 < the_set1 + lenThe_set1)
                {
                    MergeDataInfo newElement(sourcePtr1);

                    sourceObjects1.push_back(newElement);
                    sourcePtr1 += newElement.BytesUsed();
                    ++numElements1;
                }
            }

            if (lenThe_set2 > 0)
            {
                while (sourcePtr2 < the_set2 + lenThe_set2)
                {
                    MergeDataInfo newElement(sourcePtr2);

                    sourceObjects2.push_back(newElement);
                    sourcePtr2 += newElement.BytesUsed();
                    ++numElements2;
                }
            }

            totalNumElements = numElements1 + numElements2;
            bool allowOneSetEmpty = merge_type != 2;

            if (totalNumElements > 0 && (allowOneSetEmpty || (numElements1 > 0 && numElements2 > 0)))
            {
                bool omitFromResult[totalNumElements];

                // Initialize our omitFromResult array to zero (false)
                memset(omitFromResult, 0, sizeof(omitFromResult));

                if (numElements1 > 0)
                {
                    // For each untagged value in the first set, mark the same value
                    // later in the set as tagged
                    for (unsigned long x = 0; x < numElements1 - 1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            for (unsigned long y = x + 1; y < numElements1; y++)
                            {
                                if (sourceObjects1[y] == sourceObjects1[x])
                                {
                                    omitFromResult[y] = true;
                                }
                            }
                        }
                    }
                }

                if (numElements2 > 0)
                {
                    // For each untagged value in the second set, mark the same value
                    // later in the set as tagged
                    for (unsigned long x = 0; x < numElements2 - 1; x++)
                    {
                        if (omitFromResult[numElements1 + x] == false)
                        {
                            for (unsigned long y = x + 1; y < numElements2; y++)
                            {
                                if (sourceObjects2[y] == sourceObjects2[x])
                                {
                                    omitFromResult[numElements1 + y] = true;
                                }
                            }
                        }
                    }
                }

                // At this point omitFromResult[false] indicates which elements are
                // unique within their respective sets

                unsigned long numElementsToCheck = totalNumElements;

                if (merge_type == 1)
                {
                    // Union of values

                    // Deduplicate the untagged values between the two sets
                    for (unsigned long x = 0; x < numElements1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            for (unsigned long y = 0; y < numElements2; y++)
                            {
                                if (omitFromResult[numElements1 + y] == false && sourceObjects2[y] == sourceObjects1[x])
                                {
                                    omitFromResult[numElements1 + y] = true;
                                    break;
                                }
                            }
                        }
                    }
                }
                else if (merge_type == 2)
                {
                    // Intersection or difference of values
                    numElementsToCheck = numElements1;

                    // Find matching values between the two sets
                    for (unsigned long x = 0; x < numElements1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            bool    wasFound = false;

                            for (unsigned long y = 0; y < numElements2; y++)
                            {
                                if (omitFromResult[numElements1 + y] == false && sourceObjects2[y] == sourceObjects1[x])
                                {
                                    wasFound = true;
                                    break;
                                }
                            }

                            if (!wasFound)
                            {
                                // We didn't find the value in the second set,
                                // so mark it in the first set so we don't pick
                                // it up
                                omitFromResult[x] = true;
                            }
                        }
                    }
                }
                else if (merge_type == 3)
                {
                    // Difference of values
                    numElementsToCheck = numElements1;

                    // Find matching values between sets and, if found, tag both
                    for (unsigned long x = 0; x < numElements1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            for (unsigned long y = 0; y < numElements2; y++)
                            {
                                if (omitFromResult[numElements1 + y] == false && sourceObjects2[y] == sourceObjects1[x])
                                {
                                    omitFromResult[x] = true;
                                    break;
                                }
                            }
                        }
                    }
                }
                else
                {
                    rtlFail(0, "_MergeData: Unknown merge_type value");
                }

                // Count up the number of untagged values; these will be the number
                // of result values; also sum the amount of memory they use
                unsigned long   numResultElements = 0;
                unsigned long   totalLength = 0;

                for (unsigned long x = 0; x < numElementsToCheck; x++)
                {
                    if (omitFromResult[x] == false)
                    {
                        ++numResultElements;

                        if (x < numElements1)
                        {
                            totalLength += sourceObjects1[x].BytesUsed();
                        }
                        else
                        {
                            totalLength += sourceObjects2[x - numElements1].BytesUsed();
                        }
                    }
                }

                if (numResultElements > 0)
                {
                    // Allocate memory to hold numResultElements values
                    __lenResult = totalLength;
                    __result = rtlMalloc(__lenResult);

                    void* destPtr = __result;

                    // Copy only the untagged values from the first set to the result
                    for (unsigned long x = 0; x < numElements1; x++)
                    {
                        if (omitFromResult[x] == false)
                        {
                            sourceObjects1[x].CopyToMem(destPtr);
                            destPtr += sourceObjects1[x].BytesUsed();
                        }
                    }

                    if (numElementsToCheck > numElements1)
                    {
                        // Copy only the untagged values from the second set to the result
                        for (unsigned long x = 0; x < numElements2; x++)
                        {
                            if (omitFromResult[numElements1 + x] == false)
                            {
                                sourceObjects2[x].CopyToMem(destPtr);
                                destPtr += sourceObjects2[x].BytesUsed();
                            }
                        }
                    }
                }
            }
        ENDEMBED;

    END; // InternalCode module

    //--------------------------------------------------------------------------
    // Exported Functions
    //--------------------------------------------------------------------------

    /**
     * Deduplicates a SET OF INTEGER value.  This function will also work fine
     * with SET OF UNSIGNED values if none of the values are greater than
     * 2^63 - 1.
     *
     * @param   the_set     The set to deduplicate; may be any SET OF INTEGER[n]
     *                      or SET OF UNSIGNED[n] where no value exceeds
     *                      2^63 - 1.
     *
     * @return  A new SET OF INTEGER8 values, deduplicated; the order of the
     *          retained values is the same as in the input
     */
    EXPORT SET OF INTEGER8 IntegerDedup(SET OF INTEGER8 the_set) := FUNCTION
        RETURN InternalCode._MergeInteger(the_set, (SET OF INTEGER8)[], MERGE_TYPE_UNION);
    END;

    /**
     * Computes the union of and deduplicates the values within two
     * SET OF INTEGER attributes.   This function will also work fine with
     * SET OF UNSIGNED attributes if none of the values are greater
     * than 2^63 - 1.
     *
     * @param   the_set1    The set to process; may be any SET OF INTEGER[n]
     *                      or SET OF UNSIGNED[n] where no value exceeds
     *                      2^63 - 1; may be empty
     * @param   the_set2    The set to process; may be any SET OF INTEGER[n]
     *                      or SET OF UNSIGNED[n] where no value exceeds
     *                      2^63 - 1; may be empty
     *
     * @return  A new SET OF INTEGER8 values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF INTEGER8 IntegerUnion(SET OF INTEGER8 the_set1, SET OF INTEGER8 the_set2) := FUNCTION
        RETURN InternalCode._MergeInteger(the_set1, the_set2, MERGE_TYPE_UNION);
    END;

    /**
     * Computes the intersection of and deduplicates the values within two
     * SET OF INTEGER attributes.   This function will also work fine with
     * SET OF UNSIGNED attributes if none of the values are greater
     * than 2^63 - 1.
     *
     * @param   the_set1    The set to process; may be any SET OF INTEGER[n]
     *                      or SET OF UNSIGNED[n] where no value exceeds
     *                      2^63 - 1; may be empty
     * @param   the_set2    The set to process; may be any SET OF INTEGER[n]
     *                      or SET OF UNSIGNED[n] where no value exceeds
     *                      2^63 - 1; may be empty
     *
     * @return  A new SET OF INTEGER8 values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF INTEGER8 IntegerIntersection(SET OF INTEGER8 the_set1, SET OF INTEGER8 the_set2) := FUNCTION
        RETURN InternalCode._MergeInteger(the_set1, the_set2, MERGE_TYPE_INTERSECTION);
    END;

    /**
     * Computes the difference of and deduplicates the values within two
     * SET OF INTEGER attributes.   This function will also work fine with
     * SET OF UNSIGNED attributes if none of the values are greater
     * than 2^63 - 1.
     *
     * @param   the_set1    The set to process; may be any SET OF INTEGER[n]
     *                      or SET OF UNSIGNED[n] where no value exceeds
     *                      2^63 - 1; may be empty
     * @param   the_set2    The set to process; may be any SET OF INTEGER[n]
     *                      or SET OF UNSIGNED[n] where no value exceeds
     *                      2^63 - 1; may be empty
     *
     * @return  A new SET OF INTEGER8 values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF INTEGER8 IntegerDifference(SET OF INTEGER8 the_set1, SET OF INTEGER8 the_set2) := FUNCTION
        RETURN InternalCode._MergeInteger(the_set1, the_set2, MERGE_TYPE_DIFFERENCE);
    END;

    /**
     * Deduplicates a SET OF UNSIGNED value.
     *
     * @param   the_set     The set to deduplicate; may be any SET OF UNSIGNED[n]
     *
     * @return  A new SET OF UNSIGNED8 values, deduplicated; the order of the
     *          retained values is the same as in the input
     */
    EXPORT SET OF UNSIGNED8 UnsignedDedup(SET OF UNSIGNED8 the_set) := FUNCTION
        RETURN InternalCode._MergeUnsigned(the_set, (SET OF UNSIGNED8)[], MERGE_TYPE_UNION);
    END;

    /**
     * Computes the union of and deduplicates the values within two
     * SET OF UNSIGNED attributes.
     *
     * @param   the_set1    The set to process; may be any SET OF UNSIGNED[n];
     *                      may be empty
     * @param   the_set2    The set to process; may be any SET OF UNSIGNED[n];
     *                      may be empty
     *
     * @return  A new SET OF UNSIGNED8 values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF UNSIGNED8 UnsignedUnion(SET OF UNSIGNED8 the_set1, SET OF UNSIGNED8 the_set2) := FUNCTION
        RETURN InternalCode._MergeUnsigned(the_set1, the_set2, MERGE_TYPE_UNION);
    END;

    /**
     * Computes the intersection of and deduplicates the values within two
     * SET OF UNSIGNED attributes.
     *
     * @param   the_set1    The set to process; may be any SET OF UNSIGNED[n];
     *                      may be empty
     * @param   the_set2    The set to process; may be any SET OF UNSIGNED[n];
     *                      may be empty
     *
     * @return  A new SET OF UNSIGNED8 values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF UNSIGNED8 UnsignedIntersection(SET OF UNSIGNED8 the_set1, SET OF UNSIGNED8 the_set2) := FUNCTION
        RETURN InternalCode._MergeUnsigned(the_set1, the_set2, MERGE_TYPE_INTERSECTION);
    END;

    /**
     * Computes the difference of and deduplicates the values within two
     * SET OF UNSIGNED attributes.
     *
     * @param   the_set1    The set to process; may be any SET OF UNSIGNED[n];
     *                      may be empty
     * @param   the_set2    The set to process; may be any SET OF UNSIGNED[n];
     *                      may be empty
     *
     * @return  A new SET OF UNSIGNED8 values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF UNSIGNED8 UnsignedDifference(SET OF UNSIGNED8 the_set1, SET OF UNSIGNED8 the_set2) := FUNCTION
        RETURN InternalCode._MergeUnsigned(the_set1, the_set2, MERGE_TYPE_DIFFERENCE);
    END;

    /**
     * Deduplicates a SET OF REAL value.
     *
     * @param   the_set     The set to deduplicate; may be any SET OF REAL[n]
     *
     * @return  SET OF REAL8 values, deduplicated; the order of the retained
     *          values is the same as in the input
     */
    EXPORT SET OF REAL8 RealDedup(SET OF REAL8 the_set) := FUNCTION
        RETURN InternalCode._MergeReal(the_set, (SET OF REAL8)[], MERGE_TYPE_UNION);
    END;

    /**
     * Computes the union of and deduplicates the values within two
     * SET OF REAL attributes.
     *
     * @param   the_set1    The set to process; may be any SET OF REAL[n];
     *                      may be empty
     * @param   the_set2    The set to process; may be any SET OF REAL[n];
     *                      may be empty
     *
     * @return  A new SET OF REAL8 values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF REAL8 RealUnion(SET OF REAL8 the_set1, SET OF REAL8 the_set2) := FUNCTION
        RETURN InternalCode._MergeReal(the_set1, the_set2, MERGE_TYPE_UNION);
    END;

    /**
     * Computes the intersection of and deduplicates the values within two
     * SET OF REAL attributes.
     *
     * @param   the_set1    The set to process; may be any SET OF REAL[n];
     *                      may be empty
     * @param   the_set2    The set to process; may be any SET OF REAL[n];
     *                      may be empty
     *
     * @return  A new SET OF REAL8 values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF REAL8 RealIntersection(SET OF REAL8 the_set1, SET OF REAL8 the_set2) := FUNCTION
        RETURN InternalCode._MergeReal(the_set1, the_set2, MERGE_TYPE_INTERSECTION);
    END;

    /**
     * Computes the difference of and deduplicates the values within two
     * SET OF REAL attributes.
     *
     * @param   the_set1    The set to process; may be any SET OF REAL[n];
     *                      may be empty
     * @param   the_set2    The set to process; may be any SET OF REAL[n];
     *                      may be empty
     *
     * @return  A new SET OF REAL8 values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF REAL8 RealDifference(SET OF REAL8 the_set1, SET OF REAL8 the_set2) := FUNCTION
        RETURN InternalCode._MergeReal(the_set1, the_set2, MERGE_TYPE_DIFFERENCE);
    END;

    /**
     * Deduplicates a SET OF DATA value.  Duplicate values are determined by
     * bytewise comparison.
     *
     * @param   the_set     The set to deduplicate; may be any SET OF DATA[n]
     *
     * @return  SET OF DATA values, deduplicated; the order of the retained
     *          values is the same as in the input
     */
    EXPORT SET OF DATA DataDedup(SET OF DATA the_set) := FUNCTION
        RETURN InternalCode._MergeData(the_set, (SET OF DATA)[], MERGE_TYPE_UNION);
    END;

    /**
     * Computes the union of and deduplicates the values within two
     * SET OF DATA attributes.  Duplicate values are determined by bytewise
     * comparison.
     *
     * @param   the_set1    The set to process; may be any SET OF DATA[n];
     *                      may be empty
     * @param   the_set2    The set to process; may be any SET OF DATA[n];
     *                      may be empty
     *
     * @return  A new SET OF DATA values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF DATA DataUnion(SET OF DATA the_set1, SET OF DATA the_set2) := FUNCTION
        RETURN InternalCode._MergeData(the_set1, the_set2, MERGE_TYPE_UNION);
    END;

    /**
     * Computes the intersection of and deduplicates the values within two
     * SET OF DATA attributes.  Duplicate values are determined by bytewise
     * comparison.
     *
     * @param   the_set1    The set to process; may be any SET OF DATA[n];
     *                      may be empty
     * @param   the_set2    The set to process; may be any SET OF DATA[n];
     *                      may be empty
     *
     * @return  A new SET OF DATA values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF DATA DataIntersection(SET OF DATA the_set1, SET OF DATA the_set2) := FUNCTION
        RETURN InternalCode._MergeData(the_set1, the_set2, MERGE_TYPE_INTERSECTION);
    END;

    /**
     * Computes the difference of and deduplicates the values within two
     * SET OF DATA attributes.  Duplicate values are determined by bytewise
     * comparison.
     *
     * @param   the_set1    The set to process; may be any SET OF DATA[n];
     *                      may be empty
     * @param   the_set2    The set to process; may be any SET OF DATA[n];
     *                      may be empty
     *
     * @return  A new SET OF DATA values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF DATA DataDifference(SET OF DATA the_set1, SET OF DATA the_set2) := FUNCTION
        RETURN InternalCode._MergeData(the_set1, the_set2, MERGE_TYPE_DIFFERENCE);
    END;

    /**
     * Deduplicates a SET OF STRING value.  Duplicate values are determined by
     * bytewise comparison, so this is inherently a case-sensitive comparison.
     * Note that the strings are coerced to DATA types during conversion, then
     * back to STRING for return.
     *
     * @param   the_set     The set to deduplicate; may be any SET OF STRING[n]
     *                      or SET OF VARSTRING[n]
     *
     * @return  SET OF STRING values, deduplicated; the order of the retained
     *          values is the same as in the input
     */
    EXPORT SET OF STRING StringDedup(SET OF STRING the_set) := FUNCTION
        RETURN (SET OF STRING)DataDedup((SET OF DATA)the_set);
    END;

    /**
     * Computes the union of and deduplicates the values within two
     * SET OF STRING attributes.  Duplicate values are determined by bytewise
     * comparison, so this is inherently a case-sensitive comparison.  Note
     * that the strings are coerced to DATA types during conversion, then back
     * to STRING for return.
     *
     * @param   the_set1    The set to process; may be any SET OF STRING[n]
     *                      or SET OF VARSTRING[n]; may be empty
     * @param   the_set2    The set to process; may be any SET OF STRING[n]
     *                      or SET OF VARSTRING[n]; may be empty
     *
     * @return  A new SET OF STRING values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF STRING StringUnion(SET OF STRING the_set1, SET OF STRING the_set2) := FUNCTION
        RETURN (SET OF STRING)DataUnion((SET OF DATA)the_set1, (SET OF DATA)the_set2);
    END;

    /**
     * Computes the intersection of and deduplicates the values within two
     * SET OF STRING attributes.  Duplicate values are determined by bytewise
     * comparison, so this is inherently a case-sensitive comparison.  Note
     * that the strings are coerced to DATA types during conversion, then back
     * to STRING for return.
     *
     * @param   the_set1    The set to process; may be any SET OF STRING[n]
     *                      or SET OF VARSTRING[n]; may be empty
     * @param   the_set2    The set to process; may be any SET OF STRING[n]
     *                      or SET OF VARSTRING[n]; may be empty
     *
     * @return  A new SET OF STRING values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF STRING StringIntersection(SET OF STRING the_set1, SET OF STRING the_set2) := FUNCTION
        RETURN (SET OF STRING)DataIntersection((SET OF DATA)the_set1, (SET OF DATA)the_set2);
    END;

    /**
     * Computes the difference of and deduplicates the values within two
     * SET OF STRING attributes.  Duplicate values are determined by bytewise
     * comparison, so this is inherently a case-sensitive comparison.  Note
     * that the strings are coerced to DATA types during conversion, then back
     * to STRING for return.
     *
     * @param   the_set1    The set to process; may be any SET OF STRING[n]
     *                      or SET OF VARSTRING[n]; may be empty
     * @param   the_set2    The set to process; may be any SET OF STRING[n]
     *                      or SET OF VARSTRING[n]; may be empty
     *
     * @return  A new SET OF STRING values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF STRING StringDifference(SET OF STRING the_set1, SET OF STRING the_set2) := FUNCTION
        RETURN (SET OF STRING)DataDifference((SET OF DATA)the_set1, (SET OF DATA)the_set2);
    END;

    /**
     * Deduplicates a SET OF UNICODE value.  Duplicate values are determined by
     * bytewise comparison.  Note that the unicode strings are coerced to DATA
     * types during conversion, then back to UNICODE for return.
     *
     * @param   the_set     The set to deduplicate; may be any SET OF UNICODE[n]
     *                      or SET OF VARUNICODE[n]
     *
     * @return  SET OF UNICODE values, deduplicated; the order of the retained
     *          values is the same as in the input
     */
    EXPORT SET OF UNICODE UnicodeDedup(SET OF UNICODE the_set) := FUNCTION
        RETURN (SET OF UNICODE)DataDedup((SET OF DATA)the_set);
    END;

    /**
     * Computes the union of and deduplicates the values within two
     * SET OF UNICODE attributes.  Duplicate values are determined by bytewise
     * comparison, so this is inherently a case-sensitive comparison.  Note
     * that the strings are coerced to DATA types during conversion, then back
     * to UNICODE for return.
     *
     * @param   the_set1    The set to process; may be any SET OF UNICODE[n]
     *                      or SET OF VARUNICODE; may be empty
     *                      may be empty
     * @param   the_set2    The set to process; may be any SET OF UNICODE[n]
     *                      or SET OF VARUNICODE; may be empty
     *
     * @return  A new SET OF UNICODE values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF UNICODE UnicodeUnion(SET OF UNICODE the_set1, SET OF UNICODE the_set2) := FUNCTION
        RETURN (SET OF UNICODE)DataUnion((SET OF DATA)the_set1, (SET OF DATA)the_set2);
    END;

    /**
     * Computes the intersection of and deduplicates the values within two
     * SET OF UNICODE attributes.  Duplicate values are determined by bytewise
     * comparison, so this is inherently a case-sensitive comparison.  Note
     * that the strings are coerced to DATA types during conversion, then back
     * to UNICODE for return.
     *
     * @param   the_set1    The set to process; may be any SET OF UNICODE[n]
     *                      or SET OF VARUNICODE; may be empty
     *                      may be empty
     * @param   the_set2    The set to process; may be any SET OF UNICODE[n]
     *                      or SET OF VARUNICODE; may be empty
     *
     * @return  A new SET OF UNICODE values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF UNICODE UnicodeIntersection(SET OF UNICODE the_set1, SET OF UNICODE the_set2) := FUNCTION
        RETURN (SET OF UNICODE)DataIntersection((SET OF DATA)the_set1, (SET OF DATA)the_set2);
    END;

    /**
     * Computes the difference of and deduplicates the values within two
     * SET OF UNICODE attributes.  Duplicate values are determined by bytewise
     * comparison, so this is inherently a case-sensitive comparison.  Note
     * that the strings are coerced to DATA types during conversion, then back
     * to UNICODE for return.
     *
     * @param   the_set1    The set to process; may be any SET OF UNICODE[n]
     *                      or SET OF VARUNICODE; may be empty
     *                      may be empty
     * @param   the_set2    The set to process; may be any SET OF UNICODE[n]
     *                      or SET OF VARUNICODE; may be empty
     *
     * @return  A new SET OF UNICODE values, deduplicated; the order of the
     *          retained values is the same as in the input (beginning with
     *          first set and then with the second set)
     */
    EXPORT SET OF UNICODE UnicodeDifference(SET OF UNICODE the_set1, SET OF UNICODE the_set2) := FUNCTION
        RETURN (SET OF UNICODE)DataDifference((SET OF DATA)the_set1, (SET OF DATA)the_set2);
    END;

END;

/*******************************************************************************
// Sample code for testing exported functions

IMPORT Useful_ECL;

ExecuteTest(set1, set2) := MACRO
    #UNIQUENAME(inType);
    #SET(inType, #GETDATATYPE(set1));

    #UNIQUENAME(baseType);
    #IF(REGEXFIND('unsigned', %'inType'%[8..]))
        #SET(baseType, 'Unsigned')
    #ELSEIF(REGEXFIND('integer', %'inType'%[8..]))
        #SET(baseType, 'Integer')
    #ELSEIF(REGEXFIND('real', %'inType'%[8..]))
        #SET(baseType, 'Real')
    #ELSEIF(REGEXFIND('string', %'inType'%[8..]))
        #SET(baseType, 'String')
    #ELSEIF(REGEXFIND('unicode', %'inType'%[8..]))
        #SET(baseType, 'Unicode')
    #ELSE
        #ERROR('Unknown type ' + %'inType'%);
    #END

    #UNIQUENAME(BaseModule);
    #SET(BaseModule, 'Useful_ECL.Sets');
    #UNIQUENAME(DedupFunction);
    #SET(DedupFunction, %'BaseModule'% + '.' + %'baseType'% + 'Dedup');
    #UNIQUENAME(UnionFunction);
    #SET(UnionFunction, %'BaseModule'% + '.' + %'baseType'% + 'Union');
    #UNIQUENAME(IntersectionFunction);
    #SET(IntersectionFunction, %'BaseModule'% + '.' + %'baseType'% + 'Intersection');
    #UNIQUENAME(DifferenceFunction);
    #SET(DifferenceFunction, %'BaseModule'% + '.' + %'baseType'% + 'Difference');

    OUTPUT(set1, NAMED(%'baseType'% + '_value_1'));
    OUTPUT(set2, NAMED(%'baseType'% + '_value_2'));
    OUTPUT(%DedupFunction%(set1), NAMED(%'baseType'% + '_dedup_value_1'));
    OUTPUT(%DedupFunction%(set2), NAMED(%'baseType'% + '_dedup_value_2'));
    OUTPUT(%UnionFunction%(set1, set2), NAMED(%'baseType'% + '_union'));
    OUTPUT(%UnionFunction%((%inType%)[], set2), NAMED(%'baseType'% + '_union_first_empty'));
    OUTPUT(%UnionFunction%(set1, (%inType%)[]), NAMED(%'baseType'% + '_union_second_empty'));
    OUTPUT(%UnionFunction%((%inType%)[], (%inType%)[]), NAMED(%'baseType'% + '_union_both_empty'));
    OUTPUT(%IntersectionFunction%(set1, set2), NAMED(%'baseType'% + '_intersection'));
    OUTPUT(%IntersectionFunction%((%inType%)[], set2), NAMED(%'baseType'% + '_intersection_first_empty'));
    OUTPUT(%IntersectionFunction%(set1, (%inType%)[]), NAMED(%'baseType'% + '_intersection_second_empty'));
    OUTPUT(%IntersectionFunction%((%inType%)[], (%inType%)[]), NAMED(%'baseType'% + '_intersection_both_empty'));
    OUTPUT(%DifferenceFunction%(set1, set2), NAMED(%'baseType'% + '_difference'));
    OUTPUT(%DifferenceFunction%((%inType%)[], set2), NAMED(%'baseType'% + '_difference_first_empty'));
    OUTPUT(%DifferenceFunction%(set1, (%inType%)[]), NAMED(%'baseType'% + '_difference_second_empty'));
    OUTPUT(%DifferenceFunction%((%inType%)[], (%inType%)[]), NAMED(%'baseType'% + '_difference_both_empty'));
ENDMACRO;

ExecuteTest((SET OF UNSIGNED)[1,5,2,1,3,4,5], (SET OF UNSIGNED)[1,3,5,7,9]);
ExecuteTest((SET OF INTEGER)[42,-99,2017,42,0,0,-98], (SET OF INTEGER)[-99,10,2016,10,0,100]);
ExecuteTest((SET OF REAL)[-1.1,2.2,5.5,3.0,4.4,5.5,4], (SET OF REAL)[-9,3,1.1,-4.4,1.1,3.0]);
ExecuteTest((SET OF STRING)['','cpu','ram','display','ram','CPU',''], (SET OF STRING)['keyboard','','ram','DISPLAY']);
ExecuteTest((SET OF UNICODE)[u'coffee',u'tea',u'',u'milk',u'Tea',u'coffee',u''], (SET OF UNICODE)[u'coffe',u'Lemonade',u'soda',u'milk',u'juice',u'Soda']);

*******************************************************************************/