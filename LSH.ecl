/**
 * Implementation of Locality Sensitive Hashing, at scale. Both index creation and searching
 * are supported.
 *
 * This module contains some toplevel exported attributes, primarily data types and record
 * definitions, to make it easier for external code to interface with the data created here.
 * A shared module contains the implementation, then two exported modules act as the interface
 * (Build and Search). The exported functions are:
 *
 *      Build('<fileScope>').CreateFiles()
 *      Search('<fileScope>').SearchMany()
 *      Search('<fileScope>').SearchOne()
 *
 * <fileScope> refers to an HPCC logical file scope. Files created by this module will be
 * created there, and the search functions will expect those same files to be available.
 * The build process writes a configuration file, containing build parameters, to the file
 * scope; the search functions will use that config to ensure that the same parameters
 * are used. This makes it easy to create different search indexes with different parameters
 * and (more) easily switch between them during read.
 *
 * The tag "entity" is used to denote "the thing being indexed/searched." In reality, you
 * can index/search anything that is a string, and an entity ID is really just a GUID.
 * Also, note that the string can be anything: a simple string, a string that is a
 * concatenation of other data, etc. As long as you normalize and construct the string the
 * same way for both building and searching, It Just Works. You just need to use an
 * EntityLayout record structure for both building and searching.
 *
 * Building the indexes requires passing three LSH-specific parameters. Changing these parameters
 * "tunes" the build and search. Tuning is beyond the scope of this comment block;
 * Wikipedia is your friend (maybe). Those three parameters are:
 *
 *      denseSignatureSize: LSH signatures have a size
 *      hashBandSize:       LSH signatures are cut up and hashed, and those hash
 *                          values are what are searched to create the initial
 *                          matching candidate list. This parameter indicates how
 *                          large the band is.
 *      ngramLength:          The raw string data is cut up into ngrams (character runs).
 *                          Typically this value is 2, but you can change it if you want.
 *
 * Searching requires you to determine the minimum hash band overlap for the initial
 * filter. Think of it this way: Entity information (both search corpus and search term) is
 * cut up in N bands. Out of N, how many bands should overlap between a search term and a
 * corpus entry for you to consider it a candidate match? N/2 means you want at least a
 * 50% overlap, for example.
 *
 * A complete example of both build and search is in a comment block at the end of this file.
 *
 * Tutorial on LSH: https://www.pinecone.io/learn/series/faiss/locality-sensitive-hashing/
 * Another tutorial: https://medium.com/@hbrylkowski/locality-sensitive-hashing-explained-304eb39291e4
 *
 * Origin:  https://github.com/hpccsystems-solutions-lab/Useful_ECL
 */

EXPORT LSH := MODULE

    IMPORT Std;

    //--------------------------------------------------------------------

    SHARED DEFAULT_NGRAM_LENGTH := 2;

    //--------------------------------------------------------------------

    EXPORT EntityID_t := UNSIGNED8;
    EXPORT Hash_t := UNSIGNED8;

    EXPORT EntityLayout := RECORD
        EntityID_t          id;     // Entity GUID
        UTF8                s;      // Data associated with entity
    END;

    EXPORT HashFunctionLayout := RECORD
        SET OF Hash_t       hash_value_set;
    END;

    EXPORT DenseSigLayout := RECORD
        EntityID_t          id;
        SET OF Hash_t       sig;
    END;

    EXPORT LookupLayout := RECORD
        Hash_t              lookup_hash;
        EntityID_t          id;
    END;

    EXPORT SearchResultLayout := RECORD
        EntityID_t          search_id;
        EntityID_t          entity_id;
        UNSIGNED6           match_cnt;
        REAL8               similarity;
    END;

    EXPORT ConfigLayout := RECORD
        UNSIGNED1           ngram_length;
        UNSIGNED1           hash_band_size;
        SET OF Hash_t       hashes;
    END;

    //====================================================================

    SHARED Util(STRING fileScope) := MODULE

        EXPORT FS := MODULE
            SHARED fsPrefix := Std.Str.RemoveSuffix(fileScope, '::');
            EXPORT LOOKUP_FILENAME := fsPrefix + '::lookup';
            EXPORT SIGNATURES_FILENAME := fsPrefix + '::signatures';
            EXPORT CONFIG_FILENAME := fsPrefix + '::config';

            EXPORT lookupDS := DATASET(LOOKUP_FILENAME, LookupLayout, FLAT);
            EXPORT signaturesDS := INDEX({DenseSigLayout.id}, {DenseSigLayout}, SIGNATURES_FILENAME);
            EXPORT configDS := DATASET(CONFIG_FILENAME, ConfigLayout, FLAT);
        END;

        //--------------------------------------------------------------------

        EXPORT CreateHashFunctions(UNSIGNED2 hashCount) := FUNCTION
            hashes := DATASET
                (
                    hashCount,
                    TRANSFORM
                        (
                            {
                                Hash_t h
                            },
                            SELF.h := (RANDOM() << 32) | RANDOM()
                        )
                );

            RETURN SET(hashes, h);
        END;

        //--------------------------------------------------------------------

        EXPORT SET OF Hash_t MakeDenseSignature(CONST UTF8 s, UNSIGNED1 ngram_length, SET OF Hash_t hashes) := EMBED(C++)
            #option pure

            #include <algorithm>
            #include <string>
            #include <utility>
            #include <vector>

            typedef unsigned __int64 HashType;

            inline size_t countTrailingBytes(byte value)
            {
                if (value < 0xc0) return 0;
                if (value < 0xe0) return 1;
                if (value < 0xf0) return 2;
                if (value < 0xf8) return 3;
                if (value < 0xfc) return 4;
                return 5;
            }

            inline size_t bytesForChar(byte ch)
            {
                size_t trailingByteCount = countTrailingBytes(ch);

                if (trailingByteCount > 4)
                    return 0;

                return trailingByteCount + 1;
            }

            size_t byteCountForChar(const char* inputString, size_t inputStringSize, size_t currentPos)
            {
                size_t byteCount = bytesForChar(inputString[currentPos]);

                if (byteCount == 0 || (currentPos + byteCount > inputStringSize))
                {
                    // Error condition
                    rtlFail(-1, "Invalid UTF-8 encoding");
                }

                return byteCount;
            }

            #body

            std::vector<HashType> minHashes;

            __lenResult = 0;
            __result = nullptr;
            __isAllResult = false;

            if (lenS >= ngram_length && ngram_length > 0 && lenHashes > 0)
            {
                const HashType* hashSet = static_cast<const HashType*>(hashes);
                unsigned long numHashes = lenHashes / sizeof(HashType);
                size_t sSize = rtlUtf8Size(lenS, s);
                size_t currentPos = 0;
                std::vector<std::pair<size_t, size_t>> byteSizes;
                std::vector<HashType> ngramHashes;
                std::string ngramBuffer;

                // Precompute bytes used for each character
                byteSizes.reserve(lenS);
                for (size_t x = 0; x < lenS; x++)
                {
                    size_t numBytesToCopy = byteCountForChar(s, sSize, currentPos);
                    byteSizes.push_back(std::make_pair(currentPos, numBytesToCopy));
                    currentPos += numBytesToCopy;
                }

                for (size_t x = 0; x < (lenS - ngram_length + 1); x++)
                {
                    // Extract ngram bytes
                    size_t numBytesToCopy = 0;
                    currentPos = byteSizes[x].first;
                    for (size_t y = 0; y < ngram_length; y++)
                        numBytesToCopy += byteSizes[x + y].second;
                    ngramBuffer.assign(s + currentPos, numBytesToCopy);
                    ngramHashes.push_back(rtlHash64Data(ngramBuffer.size(), ngramBuffer.data(), HASH64_INIT));
                }

                // Find the min hash for each hash function
                for (size_t x = 0; x < numHashes; x++)
                {
                    HashType minHash = UINT64_MAX;
                    for (auto& ngramHash : ngramHashes)
                        minHash = std::min(minHash, ngramHash ^ hashSet[x]);
                    minHashes.push_back(minHash);
                }

                // Sort the hash values
                std::sort(minHashes.begin(), minHashes.end());

                // Compute result buffer size and allocate
                __lenResult = sizeof(HashType) * minHashes.size();
                __result = rtlMalloc(__lenResult);

                // Populate the result buffer
                HashType* outPtr = static_cast<HashType*>(__result);
                for (size_t x = 0; x < minHashes.size(); x++)
                {
                    outPtr[x] = minHashes[x];
                }
            }
        ENDEMBED;

        //--------------------------------------------------------------------

        EXPORT CreateHashBands(DATASET(DenseSigLayout) entitySignatures, UNSIGNED1 bandSize) := FUNCTION
            bands := NORMALIZE
                (
                    entitySignatures,
                    COUNT(LEFT.sig) / bandSize,
                    TRANSFORM
                        (
                            LookupLayout,
                            startPos := (COUNTER - 1) * bandSize + 1;
                            endPos := startPos + bandSize - 1;
                            SELF.lookup_hash := HASH64(LEFT.sig[startPos .. endPos]),
                            SELF := LEFT
                        )
                );

            RETURN bands;
        END;

        //--------------------------------------------------------------------

        // Assumption: set1 and set2 are sorted ascending
        EXPORT REAL8 JaccardSimilarity(SET OF Hash_t set1, SET OF Hash_t set2) := EMBED(C++)
            #option pure;

            typedef unsigned __int64 HashType;

            #body

            const HashType * numSet1 = static_cast<const HashType *>(set1);
            unsigned long numElements1 = lenSet1 / sizeof(HashType);
            unsigned long pos1 = 0;

            const HashType * numSet2 = static_cast<const HashType *>(set2);
            unsigned long numElements2 = lenSet2 / sizeof(HashType);
            unsigned long pos2 = 0;

            unsigned long intersectionCount = 0;
            unsigned long unionCount = 0;

            while (pos1 < numElements1 || pos2 < numElements2)
            {
                if (pos1 < numElements1 && pos2 < numElements2)
                {
                    ++unionCount;

                    if (numSet1[pos1] == numSet2[pos2])
                    {
                        ++intersectionCount;
                        ++pos1;
                        ++pos2;
                    }
                    else if (numSet1[pos1] < numSet2[pos2])
                    {
                        ++pos1;
                    }
                    else
                    {
                        ++pos2;
                    }
                }
                else if (pos1 < numElements1)
                {
                    unionCount += (numElements1 - pos1);
                    break;
                }
                else
                {
                    unionCount += (numElements2 - pos2);
                    break;
                }
            }

            return static_cast<double>(intersectionCount) / static_cast<double>(unionCount);
        ENDEMBED;

    END; // Module Util

    //====================================================================

    EXPORT Build(STRING fileScope) := MODULE

        SHARED UtilMod := Util(fileScope);
        SHARED FSMod := UtilMod.FS;

        EXPORT CreateFiles(DATASET(EntityLayout) entities,
                           UNSIGNED2 denseSignatureSize,
                           UNSIGNED2 hashBandSize,
                           UNSIGNED1 ngramLength = DEFAULT_NGRAM_LENGTH) := FUNCTION

            // Hashes we will use for MinHashing
            hashSet := UtilMod.CreateHashFunctions(denseSignatureSize);

            // Distribute the corpus for efficiency
            distEntities := DISTRIBUTE(entities(LENGTH(s) >= ngramLength), SKEW(0.02));

            entitySigs := PROJECT
                (
                    distEntities,
                    TRANSFORM
                        (
                            DenseSigLayout,
                            SELF.id := LEFT.id,
                            SELF.sig := UtilMod.MakeDenseSignature(LEFT.s, ngramLength, hashSet)
                        )
                );
            createSignaturesFileAction := BUILD(FSMod.signaturesDS, entitySigs, OVERWRITE);

            lookupInfo := UtilMod.CreateHashBands(entitySigs, hashBandSize);
            createLookupFileAction := OUTPUT(lookupInfo, {lookupInfo}, FSMod.LOOKUP_FILENAME, COMPRESSED, OVERWRITE);

            // Create a single-record config file that records some of these parameters
            config := DATASET
                (
                    [
                        {
                            ngramLength,
                            hashBandSize,
                            hashSet
                        }
                    ],
                    ConfigLayout
                );
            createConfigFileAction := OUTPUT(config, {config}, FSMod.CONFIG_FILENAME, COMPRESSED, OVERWRITE);

            buildAllAction := PARALLEL
                (
                    createSignaturesFileAction,
                    createLookupFileAction,
                    createConfigFileAction
                );

            RETURN IF
                (
                    hashBandSize < denseSignatureSize AND denseSignatureSize % hashBandSize = 0,
                    buildAllAction,
                    FAIL(-1, 'hashBandSize must be both less than denseSignatureSize and an even divisor of it')
                );
        END;

    END; // Module Build

    //====================================================================

    EXPORT Search(STRING fileScope) := MODULE

        SHARED UtilMod := Util(fileScope);
        SHARED FSMod := UtilMod.FS;

        EXPORT SearchMany(DATASET(EntityLayout) searchEntities, UNSIGNED2 minHashBandMatchCount, REAL8 minSimilarity) := FUNCTION
            // Files we need
            lookupDS := FSMod.lookupDS;
            corpusSignaturesDS := FSMod.signaturesDS;
            config := FSMod.configDS;

            // Create dense signatures for the search entities
            searchSigs := PROJECT
                (
                    searchEntities,
                    TRANSFORM
                        (
                            DenseSigLayout,
                            SELF.id := LEFT.id,
                            SELF.sig := UtilMod.MakeDenseSignature(LEFT.s, config[1].ngram_length, config[1].hashes)
                        )
                );

            // Break up signatures into hash bands
            searchHashBands := UtilMod.CreateHashBands(searchSigs, config[1].hash_band_size);

            // Find initial matches
            matches := JOIN
                (
                    lookupDS,
                    searchHashBands,
                    LEFT.lookup_hash = RIGHT.lookup_hash,
                    TRANSFORM
                        (
                            {
                                EntityID_t      search_id,
                                EntityID_t      entity_id
                            },
                            SELF.entity_id := LEFT.id,
                            SELF.search_id := RIGHT.id
                        ),
                    SMART
                );

            // Count matches and filter out those that don't match enough
            matchSummary0 := TABLE
                (
                    matches,
                    {
                        search_id,
                        entity_id,
                        UNSIGNED6 match_cnt := COUNT(GROUP)
                    },
                    search_id, entity_id,
                    MERGE
                );
            matchSummary := matchSummary0(match_cnt >= minHashBandMatchCount);

            // Append search signatures
            withSearchSig := JOIN
                (
                    matchSummary,
                    searchSigs,
                    LEFT.search_id = RIGHT.id,
                    TRANSFORM
                        (
                            {
                                RECORDOF(LEFT),
                                SET OF Hash_t search_sig
                            },
                            SELF.search_sig := RIGHT.sig,
                            SELF := LEFT
                        ),
                    LOOKUP
                ) : ONWARNING(4531, IGNORE);

            // Append corpus signatures
            withCorpusSig := JOIN
                (
                    withSearchSig,
                    corpusSignaturesDS,
                    LEFT.entity_id = RIGHT.id,
                    TRANSFORM
                        (
                            {
                                RECORDOF(LEFT),
                                SET OF Hash_t entity_sig
                            },
                            SELF.entity_sig := RIGHT.sig,
                            SELF := LEFT
                        ),
                    KEEP(1)
                );

            // Compute the Jaccard similarities
            similarities := PROJECT
                (
                    withCorpusSig,
                    TRANSFORM
                        (
                            SearchResultLayout,
                            sim := UtilMod.JaccardSimilarity(LEFT.entity_sig, LEFT.search_sig);
                            SELF.similarity := IF(sim >= minSimilarity, sim, SKIP),
                            SELF := LEFT
                        )
                );

            RETURN similarities;
        END;

        //--------------------------------------------------------------------

        EXPORT SearchOne(UTF8 searchString, UNSIGNED2 minHashBandMatchCount, REAL8 minSimilarity) := FUNCTION
            RETURN SearchMany(DATASET([{0, searchString}], EntityLayout), minHashBandMatchCount, minSimilarity);
        END;

    END; // Module Search

END; // Module LHS

/******* EXAMPLE CODE ***********************************************************************

NGRAM_SIZE := 2;
SIG_SIZE := 60;
BAND_SIZE := 2; // Must equally divide into SIG_SIZE
MIN_BAND_MATCH_COUNT := 1; // Must be between 1 and (SIG_SIZE / BAND_SIZE), inclusive

//*** MIN_BAND_MATCH_COUNT is only 1 because our test vocabulary is very small

// Make sure the above constants adhere to our setup
ASSERT(SIG_SIZE % BAND_SIZE = 0, FAIL);
ASSERT(MIN_BAND_MATCH_COUNT BETWEEN 1 AND (SIG_SIZE / BAND_SIZE), FAIL);

//--------------------------------

DO_BUILD := TRUE;
DO_SEARCH := TRUE;
FILE_SCOPE := '~lsh_test';

//--------------------------------

corpus0 := DATASET
    (
        [
            {1001, u8'CAMPER'},
            {1002, u8'AAAAAABAAAAAAA'},
            {1003, u8'FUBAR'},
            {1004, u8'Z'}
        ],
        LSH.EntityLayout,
        DISTRIBUTED
    );
corpus := NOFOLD(corpus0);

buildAction := LSH.Build(FILE_SCOPE).CreateFiles(corpus, SIG_SIZE, BAND_SIZE, NGRAM_SIZE);

//--------------------------------

searchEntities0 := DATASET
    (
        [
            {1, u8'CAMPER'},
            {2, u8'DAN'},
            {3, u8'PERSON'},
            {4, u8'CAMPBELL'}
        ],
        LSH.EntityLayout
    );
searchEntities := NOFOLD(searchEntities0);

searchManyResults := LSH.Search(FILE_SCOPE).SearchMany(searchEntities, MIN_BAND_MATCH_COUNT);
searchOneResults := LSH.Search(FILE_SCOPE).SearchOne(NOFOLD(u8'FUBARSKY'), MIN_BAND_MATCH_COUNT);

//--------------------------------

SEQUENTIAL
    (
        IF(DO_BUILD, buildAction),
        IF(DO_SEARCH,
            PARALLEL
                (
                    OUTPUT(TOPN(searchManyResults, 100, -similarity), NAMED('search_many_results')),
                    OUTPUT(TOPN(searchOneResults, 100, -similarity), NAMED('search_one_results'))
                ))
    );

*/