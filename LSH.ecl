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
 *
 * Origin:  https://github.com/hpccsystems-solutions-lab/Useful_ECL
 */

EXPORT LSH := MODULE

    IMPORT Std;

    //--------------------------------------------------------------------

    SHARED DEFAULT_NGRAM_LENGTH := 2;

    //--------------------------------------------------------------------

    EXPORT EntityID_t := UNSIGNED6;

    EXPORT EntityLayout := RECORD
        EntityID_t          id;     // Entity GUID
        UTF8                s;      // Data associated with entity
    END;

    EXPORT NGramLayout := RECORD
        UTF8                ngram;
    END;

    EXPORT EntityNGramLayout := RECORD
        EntityID_t          id;
        NGramLayout;
    END;

    EXPORT VocabLayout := RECORD
        UNSIGNED8           pos;
        NGramLayout;
    END;

    EXPORT HashFunctionLayout := RECORD
        UNSIGNED8           hash_set;
        UNSIGNED8           pos;
        UNSIGNED8           hash_value;
    END;

    EXPORT DenseSigLayout := RECORD
        EntityID_t          id;
        SET OF UNSIGNED8    sig;
    END;

    EXPORT HashBandLayout := RECORD
        EntityID_t          id;
        UNSIGNED8           bandHash;
    END;

    EXPORT SearchResultLayout := RECORD
        EntityID_t          search_id;
        EntityID_t          entity_id;
        UNSIGNED6           match_cnt;
        REAL8               similarity;
    END;

    EXPORT ConfigLayout := RECORD
        UNSIGNED1           ngram_length;
        UNSIGNED1           signature_size;
        UNSIGNED1           hash_band_size;
    END;

    //====================================================================

    SHARED Util(STRING fileScope) := MODULE

        EXPORT FS := MODULE
            SHARED fsPrefix := Std.Str.RemoveSuffix(fileScope, '::');
            EXPORT VOCABULARY_FILENAME := fsPrefix + '::vocabulary';
            EXPORT HASH_FUNCTIONS_FILENAME := fsPrefix + '::hashes';
            EXPORT SIGNATURES_FILENAME := fsPrefix + '::signatures';
            EXPORT HASH_BANDS_FILENAME := fsPrefix + '::hash_bands';
            EXPORT CONFIG_FILENAME := fsPrefix + '::config';

            EXPORT vocabDS := DATASET(VOCABULARY_FILENAME, VocabLayout, FLAT);
            EXPORT hashFunctionsDS := DATASET(HASH_FUNCTIONS_FILENAME, HashFunctionLayout, FLAT);
            EXPORT corpusSigsDS := INDEX({DenseSigLayout.id}, {DenseSigLayout}, SIGNATURES_FILENAME);
            EXPORT corpusHashBandsDS := DATASET(HASH_BANDS_FILENAME, HashBandLayout, FLAT);
            EXPORT configDS := DATASET(CONFIG_FILENAME, ConfigLayout, FLAT);
        END;

        //--------------------------------------------------------------------

        EXPORT STREAMED DATASET(NGramLayout) MakeNGrams(CONST UTF8 s, UNSIGNED1 ngram_length = DEFAULT_NGRAM_LENGTH) := EMBED(C++)
            #option pure

            #include <set>
            #include <string>

            class NGramStreamDataset : public RtlCInterface, implements IRowStream
            {
                public:

                    NGramStreamDataset(IEngineRowAllocator* _resultAllocator, size_t _inputStringLength, const char* _inputString, size_t _ngramLength)
                        : resultAllocator(_resultAllocator), inputString(_inputString), ngramLength(_ngramLength)
                    {
                        inputStringSize = rtlUtf8Size(_inputStringLength, inputString);
                        isStopped = (_inputStringLength < ngramLength);
                        currentPos = 0;
                    }

                    RTLIMPLEMENT_IINTERFACE

                    static inline size_t countTrailingBytes(byte value)
                    {
                        if (value < 0xc0) return 0;
                        if (value < 0xe0) return 1;
                        if (value < 0xf0) return 2;
                        if (value < 0xf8) return 3;
                        if (value < 0xfc) return 4;
                        return 5;
                    }

                    static inline size_t bytesForChar(byte ch)
                    {
                        size_t trailingByteCount = countTrailingBytes(ch);

                        if (trailingByteCount > 4)
                            return 0;

                        return trailingByteCount + 1;
                    }

                    size_t numBytesForNumChars(size_t charsNeeded)
                    {
                        size_t byteCount = 0;

                        for (size_t x = 0; x < charsNeeded; x++)
                        {
                            size_t byteCountToSkip = bytesForChar(inputString[currentPos + byteCount]);

                            if (byteCountToSkip == 0 || currentPos + byteCount + byteCountToSkip > inputStringSize)
                            {
                                // Error condition
                                return 0;
                            }

                            byteCount += byteCountToSkip;
                        }

                        return byteCount;
                    }

                    virtual const void* nextRow() override
                    {
                        if (isStopped)
                        {
                            return nullptr;
                        }

                        while (currentPos < inputStringSize)
                        {
                            size_t numBytesToCopy = numBytesForNumChars(ngramLength);

                            if (numBytesToCopy > 0)
                            {
                                const bool didInsert = ngramSet.insert(std::string(inputString + currentPos, numBytesToCopy)).second;

                                if (didInsert)
                                {
                                    RtlDynamicRowBuilder    rowBuilder(resultAllocator);
                                    uint32_t                len = numBytesToCopy;
                                    uint32_t                totalRowSize = sizeof(len) + len;
                                    byte*                   row = rowBuilder.ensureCapacity(totalRowSize, NULL);

                                    memcpy(row, &len, sizeof(len));
                                    memcpy(row + sizeof(len), inputString + currentPos, len);

                                    currentPos += numBytesForNumChars(1);

                                    return rowBuilder.finalizeRowClear(totalRowSize);
                                }
                                else
                                {
                                    // We didn't insert, but we need to advance the current position
                                    currentPos += numBytesForNumChars(1);
                                }
                            }
                            else
                            {
                                isStopped = true;
                                return nullptr;
                            }
                        }

                        isStopped = true;
                        return nullptr;
                    }

                    virtual void stop() override
                    {
                        isStopped = true;
                    }

                private:

                    Linked<IEngineRowAllocator> resultAllocator;
                    bool                        isStopped;
                    std::string                 outString;
                    const char *                inputString;
                    size_t                      inputStringSize;
                    size_t                      ngramLength;
                    size_t                      currentPos;
                    std::set<std::string>       ngramSet;
            };

            #body

            return new NGramStreamDataset(_resultAllocator, lenS, s, ngram_length);
        ENDEMBED;

        //--------------------------------------------------------------------

        EXPORT STREAMED DATASET(HashFunctionLayout) CreateHashFunctions(UNSIGNED8 set_count, UNSIGNED8 vocab_size) := FUNCTION
            STREAMED DATASET(HashFunctionLayout) _CreateHashFunctions(UNSIGNED8 set_count,
                                                                      UNSIGNED8 vocab_size,
                                                                      UNSIGNED1 worker_count = Std.System.Thorlib.Nodes(),
                                                                      UNSIGNED1 worker_id = Std.System.Thorlib.Node()) := EMBED(C++ : activity)
                #include <algorithm>
                #include <chrono>
                #include <random>
                #include <vector>

                class RandomNumStreamDataset : public RtlCInterface, implements IRowStream
                {
                    public:

                        RandomNumStreamDataset(IEngineRowAllocator* _resultAllocator, unsigned __int64 _set_count, unsigned __int64 _vocab_size, unsigned char _worker_count, unsigned char _worker_id)
                            : resultAllocator(_resultAllocator), set_count(_set_count), vocab_size(_vocab_size), worker_count(_worker_count), worker_id(_worker_id)
                        {
                            isStopped = (vocab_size == 0);
                            idx = 0;
                            setCounter = 0;

                            for (unsigned __int64 x = 0; x < vocab_size; x++)
                                pos.push_back(x + 1);

                            rng.seed(std::chrono::system_clock::now().time_since_epoch().count());
                        }

                        RTLIMPLEMENT_IINTERFACE

                        void Randomize()
                        {
                            std::shuffle(pos.begin(), pos.end(), rng);
                        }

                        virtual const void* nextRow()
                        {
                            if (isStopped)
                            {
                                return nullptr;
                            }

                            while (setCounter < set_count)
                            {
                                if ((setCounter % worker_count) == worker_id)
                                {
                                    if (idx == 0)
                                    {
                                        Randomize();
                                    }

                                    if (idx < vocab_size)
                                    {
                                        RtlDynamicRowBuilder    rowBuilder(resultAllocator);
                                        uint32_t                totalRowSize = sizeof(unsigned __int64) * 3;
                                        byte*                   row = rowBuilder.ensureCapacity(totalRowSize, NULL);
                                        unsigned __int64*       nums = (unsigned __int64*)row;

                                        nums[0] = setCounter + 1;   // hash_set
                                        nums[1] = idx + 1;          // pos
                                        nums[2] = pos[idx];         // hash_value
                                        ++idx;

                                        return rowBuilder.finalizeRowClear(totalRowSize);
                                    }

                                    ++setCounter;
                                    idx = 0;
                                }
                                else
                                {
                                    ++setCounter;
                                }
                            }

                            isStopped = true;
                            return nullptr;
                        }

                        virtual void stop()
                        {
                            isStopped = true;
                        }

                    protected:

                        Linked<IEngineRowAllocator>     resultAllocator;
                        std::default_random_engine      rng;

                    private:

                        bool                            isStopped;
                        unsigned __int64                set_count;
                        unsigned __int64                vocab_size;
                        unsigned __int64                idx;
                        unsigned __int64                setCounter;
                        unsigned __int64                worker_count;
                        unsigned __int64                worker_id;
                        std::vector<unsigned __int64>   pos;
                };

                #body

                return new RandomNumStreamDataset(_resultAllocator, set_count, vocab_size, worker_count, worker_id);
            ENDEMBED;

            RETURN _CreateHashFunctions(set_count, vocab_size);
        END;

        //--------------------------------------------------------------------

        EXPORT CreateDenseSig(DATASET(EntityLayout) entities, DATASET(VocabLayout) vocabulary, DATASET(HashFunctionLayout) hashes) := FUNCTION
            ngramLength := LENGTH(vocabulary[1].ngram);

            // Convert entity names into ngrams, keeping the ID associated with each
            entityNGrams := NORMALIZE
                (
                    entities,
                    MakeNGrams(LEFT.s, ngramLength),
                    TRANSFORM
                        (
                            {
                                EntityID_t  id,
                                UTF8        ngram
                            },
                            SELF.id := LEFT.id,
                            SELF.ngram := RIGHT.ngram
                        )
                );

            oneHotMatches0 := JOIN
                (
                    entityNGrams,
                    vocabulary,
                    LEFT.ngram = RIGHT.ngram,
                    TRANSFORM
                        (
                            {
                                EntityID_t  id,
                                UNSIGNED8   pos
                            },
                            SELF.id := LEFT.id,
                            SELF.pos := RIGHT.pos
                        ),
                    SMART, LEFT OUTER, SKEW(0.5)
                );
            oneHotMatches := WHEN(oneHotMatches0, OUTPUT(oneHotMatches0, NAMED('oneHotMatches0')));

            // Construct the hash digits we need for minhash computation
            hashDigits0 := JOIN
                (
                    oneHotMatches,
                    hashes,
                    LEFT.pos = RIGHT.hash_value,
                    TRANSFORM
                        (
                            {
                                EntityID_t  id,
                                RECORDOF(RIGHT)
                            },
                            SELF.id := LEFT.id,
                            SELF := RIGHT
                        ),
                    SMART, LEFT OUTER, SKEW(0.5)
                );
            hashDigits := WHEN(hashDigits0, OUTPUT(SORT(hashDigits0, id, hash_set, pos), NAMED('hashDigits0')));

            // Filter out all but the minhash digits; this also significantly reduces the
            // size of the interim dataset we're working with
            minPosHashDigits0 := TABLE
                (
                    hashDigits,
                    {
                        id,
                        hash_set,
                        UNSIGNED8 pos := MIN(GROUP, pos)
                    },
                    id, hash_set,
                    MERGE
                );
            minPosHashDigits := WHEN(minPosHashDigits0, OUTPUT(minPosHashDigits0, NAMED('minPosHashDigits0')));

            distMinPosHashDigits := DISTRIBUTE(minPosHashDigits, HASH64(id));

            // Convert the positions to a set; they become our dense signature
            hashDigitMin := PROJECT
                (
                    distMinPosHashDigits,
                    TRANSFORM
                        (
                            {
                                DenseSigLayout,
                                LEFT.hash_set
                            },
                            SELF.id := LEFT.id,
                            SELF.sig := [LEFT.pos],
                            SELF := LEFT
                        )
                );

            denseSigs0 := ROLLUP
                (
                    SORT(hashDigitMin, id, hash_set, LOCAL),
                    TRANSFORM
                        (
                            RECORDOF(LEFT),
                            SELF.sig := LEFT.sig + RIGHT.sig,
                            SELF := LEFT
                        ),
                    id,
                    LOCAL
                );
            
            denseSigs := PROJECT
                (
                    denseSigs0,
                    TRANSFORM
                        (
                            DenseSigLayout,
                            SELF := LEFT
                        )
                );

            RETURN denseSigs;
        END;

        //--------------------------------------------------------------------

        EXPORT CreateHashBands(DATASET(DenseSigLayout) entitySignatures, UNSIGNED1 bandSize) := FUNCTION
            bands := NORMALIZE
                (
                    entitySignatures,
                    COUNT(LEFT.sig) / bandSize,
                    TRANSFORM
                        (
                            HashBandLayout,
                            startPos := (COUNTER - 1) * bandSize + 1;
                            endPos := startPos + bandSize - 1;
                            SELF.id := LEFT.id,
                            SELF.bandHash := HASH64(LEFT.sig[startPos .. endPos])
                        )
                );

            RETURN bands;
        END;

        //--------------------------------------------------------------------

        EXPORT REAL8 JaccardSimilarity(SET OF UNSIGNED8 set1, SET OF UNSIGNED8 set2) := EMBED(C++)
            #option pure;

            #include <algorithm>
            #include <vector>

            #body

            std::vector<unsigned __int64> firstSet;
            std::vector<unsigned __int64> secondSet;
            std::vector<unsigned __int64> intersectionSet;
            std::vector<unsigned __int64> unionSet;

            const unsigned __int64 * numSet1 = static_cast<const unsigned __int64 *>(set1);
            const unsigned __int64 * numSet2 = static_cast<const unsigned __int64 *>(set2);

            unsigned long numElements1 = lenSet1 / sizeof(unsigned __int64);
            firstSet.reserve(numElements1);
            for (unsigned long x = 0; x < numElements1; x++)
                firstSet.push_back(numSet1[x]);
            sort(firstSet.begin(), firstSet.end());

            unsigned long numElements2 = lenSet2 / sizeof(unsigned __int64);
            secondSet.reserve(numElements2);
            for (unsigned long x = 0; x < numElements2; x++)
                secondSet.push_back(numSet2[x]);
            sort(secondSet.begin(), secondSet.end());

            std::set_intersection(firstSet.begin(), firstSet.end(), secondSet.begin(), secondSet.end(), std::back_inserter(intersectionSet));
            std::set_union(firstSet.begin(), firstSet.end(), secondSet.begin(), secondSet.end(), std::back_inserter(unionSet));

            return static_cast<double>(intersectionSet.size()) / static_cast<double>(unionSet.size());
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

            // Distribute the corpus for efficiency
            distEntities := DISTRIBUTE(entities, SKEW(0.05));

            // Create vocabulary
            rawNGrams := NORMALIZE
                (
                    distEntities,
                    UtilMod.MakeNGrams(LEFT.s, ngramLength),
                    TRANSFORM
                        (
                            NGramLayout,
                            SELF := RIGHT
                        )
                );

            vocab0 := TABLE(rawNGrams, {ngram}, ngram, MERGE);
            vocab := PROJECT
                (
                    vocab0,
                    TRANSFORM
                        (
                            VocabLayout,
                            SELF.pos := COUNTER,
                            SELF := LEFT
                        )
                );
            createVocabFileAction := OUTPUT(vocab, {vocab}, FSMod.VOCABULARY_FILENAME, COMPRESSED, OVERWRITE);

            // Create hash functions
            hashFunctions := UtilMod.CreateHashFunctions(denseSignatureSize, COUNT(vocab));
            createHashFunctionsFileAction := OUTPUT(hashFunctions, {hashFunctions}, FSMod.HASH_FUNCTIONS_FILENAME, COMPRESSED, OVERWRITE);

            // Create dense signatures
            corpusSigs := UtilMod.CreateDenseSig(distEntities, vocab, hashFunctions);
            createSignaturesFileAction := BUILD(corpusSigs, {id}, {corpusSigs}, FSMod.SIGNATURES_FILENAME, OVERWRITE);

            // Break up signatures into hash bands
            corpusHashBands := UtilMod.CreateHashBands(corpusSigs, hashBandSize);
            createHashBandsFileAction := OUTPUT(corpusHashBands, {corpusHashBands}, FSMod.HASH_BANDS_FILENAME, COMPRESSED, OVERWRITE);

            // Create a single-record config file that records some of these parameters
            config := DATASET
                (
                    [
                        {
                            ngramLength,
                            denseSignatureSize,
                            hashBandSize
                        }
                    ],
                    ConfigLayout
                );
            createConfigFileAction := OUTPUT(config, {config}, FSMod.CONFIG_FILENAME, COMPRESSED, OVERWRITE);

            buildAllAction := PARALLEL
                (
                    createVocabFileAction,
                    createHashFunctionsFileAction,
                    createSignaturesFileAction,
                    createHashBandsFileAction,
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

        EXPORT SearchMany(DATASET(EntityLayout) searchEntities, UNSIGNED2 minHashBandMatchCount) := FUNCTION
            // Files we need
            vocab := FSMod.vocabDS;
            hashFunctions := FSMod.hashFunctionsDS;
            corpusSigs := FSMod.corpusSigsDS;
            corpusHashBands := FSMod.corpusHashBandsDS;
            config := FSMod.configDS;

            // Create dense signatures for the search entities
            searchSigs := UtilMod.CreateDenseSig(searchEntities, vocab, hashFunctions);

            // Break up signatures into hash bands
            searchHashBands := UtilMod.CreateHashBands(searchSigs, config[1].hash_band_size);

            // Find initial matches
            matches := JOIN
                (
                    corpusHashBands,
                    searchHashBands,
                    LEFT.bandHash = RIGHT.bandHash,
                    TRANSFORM
                        (
                            {
                                EntityID_t  search_id,
                                EntityID_t  entity_id
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

            // Append the dense signatures of both the search terms and the filtered candidates
            matchesWithCorpusSigs := JOIN
                (
                    matchSummary,
                    corpusSigs,
                    LEFT.entity_id = RIGHT.id,
                    TRANSFORM
                        (
                            {
                                RECORDOF(LEFT),
                                SET OF UNSIGNED8 entity_sig
                            },
                            SELF.entity_sig := RIGHT.sig,
                            SELF := LEFT
                        ),
                    KEEP(1)
                );

            matchesWithSearchSigs := JOIN
                (
                    matchesWithCorpusSigs,
                    searchSigs,
                    LEFT.search_id = RIGHT.id,
                    TRANSFORM
                        (
                            {
                                RECORDOF(LEFT),
                                SET OF UNSIGNED8 search_sig
                            },
                            SELF.search_sig := RIGHT.sig,
                            SELF := LEFT
                        ),
                    KEEP(1)
                ) : ONWARNING(4531, IGNORE);

            // Compute the Jaccard similarities
            similarities := PROJECT
                (
                    matchesWithSearchSigs,
                    TRANSFORM
                        (
                            SearchResultLayout,
                            SELF.similarity := UtilMod.JaccardSimilarity(LEFT.entity_sig, LEFT.search_sig),
                            SELF := LEFT
                        )
                );

            RETURN similarities;
        END;

        //--------------------------------------------------------------------

        EXPORT SearchOne(UTF8 searchString, UNSIGNED2 minHashBandMatchCount) := FUNCTION
            RETURN SearchMany(DATASET([{0, searchString}], EntityLayout), minHashBandMatchCount);
        END;

    END; // Module Search

END; // Module LHS

/******* EXAMPLE CODE ***********************************************************************

NGRAM_SIZE := 2;
SIG_SIZE := 12;
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
                    OUTPUT(searchManyResults, NAMED('search_many_results')),
                    OUTPUT(searchOneResults, NAMED('search_one_results'))
                ))
    );

*/