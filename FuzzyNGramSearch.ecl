/**
 * Implementation of ngram-based fuzzy searching, at scale. Both index creation and searching
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
 *
 * The tag "entity" is used to denote "the thing being indexed/searched." In reality, you
 * can index/search anything that is a UTF-8 string, and an entity ID is really just a GUID.
 * Also, note that the string can be anything: a simple string, a string that is a
 * concatenation of other data, etc. As long as you normalize and construct the string the
 * same way for both building and searching, It Just Works. You just need to use an
 * EntityLayout record structure for both building and searching.
 *
 * The only build parameter for "tuning" is the ngram size. The system defaults to a
 * value of 2, but 3 is often used as well. YMMV, and you should test.
 *
 * A complete example of both build and search is in a comment block at the end of this file.
 *
 * Origin:  https://github.com/hpccsystems-solutions-lab/Useful_ECL
 */

EXPORT FuzzyNGramSearch := MODULE

    IMPORT Std;

    //--------------------------------------------------------------------

    SHARED DEFAULT_NGRAM_LENGTH := 2;

    //--------------------------------------------------------------------

    EXPORT EntityID_t := UNSIGNED8;
    EXPORT VocabID_t := UNSIGNED2;

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
        VocabID_t           pos;
        NGramLayout;
    END;

    EXPORT NGramLookupLayout := RECORD
        VocabID_t           lookup_id;
        EntityID_t          id;
        SET OF VocabID_t    ngram_pos_set;
    END;

    EXPORT SearchResultLayout := RECORD
        EntityID_t          search_id;
        EntityID_t          entity_id;
        REAL8               similarity;
    END;

    //====================================================================

    SHARED Util(STRING fileScope) := MODULE

        EXPORT FS := MODULE
            SHARED fsPrefix := Std.Str.RemoveSuffix(fileScope, '::');

            EXPORT VOCABULARY_FILENAME := fsPrefix + '::vocabulary';
            EXPORT NGRAM_LOOKUP_FILENAME := fsPrefix + '::ngram_lookup';

            EXPORT vocabDS := DATASET(VOCABULARY_FILENAME, VocabLayout, FLAT);
            EXPORT corpusNGramsDS := DATASET(NGRAM_LOOKUP_FILENAME, NGramLookupLayout, FLAT);
        END;

        //--------------------------------------------------------------------

        EXPORT DATASET(NGramLayout) MakeNGrams(CONST UTF8 s, UNSIGNED1 ngram_length = DEFAULT_NGRAM_LENGTH) := EMBED(C++)
            #option pure

            #include <set>
            #include <string>

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

            size_t byteCountForCharCount(const char* inputString, size_t inputStringSize, size_t currentPos, size_t charsNeeded)
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

            #body

            size_t sSize = rtlUtf8Size(lenS, s);

            size_t currentPos = 0;
            std::set<std::string> ngramSet;

            if (lenS >= ngram_length)
            {
                // Collect unique ngrams
                while (currentPos < (sSize - ngram_length + 1))
                {
                    size_t numBytesToCopy = byteCountForCharCount(s, sSize, currentPos, ngram_length);

                    if (numBytesToCopy >= ngram_length)
                        ngramSet.insert(std::string(s + currentPos, numBytesToCopy));
                    currentPos += byteCountForCharCount(s, sSize, currentPos, 1);
                }
            }

            // Compute result buffer size and allocate
            __lenResult = 0;
            for (auto& n : ngramSet)
            {
                // stringLen + stringData
                __lenResult += (sizeof(size32_t) + n.size());
            }

            if (__lenResult > 0)
            {
                __result = rtlMalloc(__lenResult);

                byte* outPtr = static_cast<byte*>(__result);
                size32_t stringLen = ngram_length;

                for (auto& n : ngramSet)
                {
                    memcpy_iflen(outPtr, &stringLen, sizeof(stringLen));
                    outPtr += sizeof(stringLen);
                    memcpy_iflen(outPtr, n.data(), n.size());
                    outPtr += n.size();
                }
            }
            else
            {
                __result = nullptr;
            }
        ENDEMBED;

        //--------------------------------------------------------------------

        SHARED CreateEntityNGrams(DATASET(EntityLayout) entities, UNSIGNED1 ngramLength) := FUNCTION
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
            
            RETURN entityNGrams;
        END;

        //--------------------------------------------------------------------

        EXPORT CreateVocabulary(DATASET(EntityLayout) entities, UNSIGNED1 ngramLength) := FUNCTION
            rawNGrams := CreateEntityNGrams(entities, ngramLength);

            // Deduplicate only the ngrams
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

            RETURN vocab;
        END;

        //--------------------------------------------------------------------

        EXPORT CreateNGramLookups(DATASET(EntityLayout) entities, DATASET(VocabLayout) vocabulary, UNSIGNED1 ngramLength) := FUNCTION
            // Convert entity names into ngrams, keeping the ID associated with each
            entityNGrams := CreateEntityNGrams(entities, ngramLength);

            // Convert found ngrams into their positions
            vocabMatches := JOIN
                (
                    entityNGrams,
                    vocabulary,
                    LEFT.ngram = RIGHT.ngram,
                    TRANSFORM
                        (
                            {
                                EntityID_t  id,
                                VocabID_t   ngram_pos
                            },
                            SELF.id := LEFT.id,
                            SELF.ngram_pos := RIGHT.pos
                        ),
                    LOOKUP
                );

            distVocabMatches := DISTRIBUTE(vocabMatches, HASH64(id));

            // Convert the positions to a sorted set
            ngramLookups0 := PROJECT
                (
                    distVocabMatches,
                    TRANSFORM
                        (
                            {
                                EntityID_t  id,
                                SET OF VocabID_t ngram_pos_set,
                                LEFT.ngram_pos
                            },
                            SELF.id := LEFT.id,
                            SELF.ngram_pos_set := [LEFT.ngram_pos],
                            SELF := LEFT
                        )
                );

            ngramLookups1 := ROLLUP
                (
                    SORT(ngramLookups0, id, ngram_pos, LOCAL),
                    TRANSFORM
                        (
                            RECORDOF(LEFT),
                            SELF.ngram_pos_set := LEFT.ngram_pos_set + RIGHT.ngram_pos_set,
                            SELF := LEFT
                        ),
                    id,
                    LOCAL
                );

            // Extract each ngram position; this becomes our primary key to each record
            ngramLookups := NORMALIZE
                (
                    ngramLookups1,
                    COUNT(LEFT.ngram_pos_set),
                    TRANSFORM
                        (
                            NGramLookupLayout,
                            SELF.lookup_id := LEFT.ngram_pos_set[COUNTER],
                            SELF := LEFT
                        )
                );

            RETURN ngramLookups;
        END;

        //--------------------------------------------------------------------

        // Assumes that SET values are sorted ascending
        EXPORT REAL8 JaccardSimilarity(SET OF VocabID_t set1, SET OF VocabID_t set2) := EMBED(C++)
            #option pure;

            #body

            const unsigned uint16_t * numSet1 = static_cast<const unsigned uint16_t *>(set1);
            unsigned long numElements1 = lenSet1 / sizeof(unsigned uint16_t);
            unsigned long pos1 = 0;

            const unsigned uint16_t * numSet2 = static_cast<const unsigned uint16_t *>(set2);
            unsigned long numElements2 = lenSet2 / sizeof(unsigned uint16_t);
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

        EXPORT CreateFiles(DATASET(EntityLayout) entities, UNSIGNED1 ngramLength = DEFAULT_NGRAM_LENGTH) := FUNCTION
            // Distribute the corpus for efficiency
            distEntities := DISTRIBUTE(entities, SKEW(0.05));

            // Create vocabulary
            vocab := UtilMod.CreateVocabulary(distEntities, ngramLength);
            createVocabFileAction := OUTPUT(vocab, {vocab}, FSMod.VOCABULARY_FILENAME, COMPRESSED, OVERWRITE);

            // Create dense signatures
            corpusNGrams0 := UtilMod.CreateNGramLookups(distEntities, vocab, ngramLength);
            corpusNGrams := corpusNGrams0;
            createSignaturesFileAction := OUTPUT(corpusNGrams, {corpusNGrams}, FSMod.NGRAM_LOOKUP_FILENAME, COMPRESSED, OVERWRITE);

            buildAllAction := PARALLEL
                (
                    createVocabFileAction,
                    createSignaturesFileAction
                );

            RETURN buildAllAction;
        END;

    END; // Module Build

    //====================================================================

    EXPORT Search(STRING fileScope) := MODULE

        SHARED UtilMod := Util(fileScope);
        SHARED FSMod := UtilMod.FS;

        EXPORT SearchMany(DATASET(EntityLayout) searchEntities, REAL8 minSimilarity) := FUNCTION
            // Files we need
            vocab := FSMod.vocabDS;
            corpusNGrams := FSMod.corpusNGramsDS;

            // Create dense signatures for the search entities
            searchSigs := UtilMod.CreateNGramLookups(searchEntities, vocab, LENGTH(vocab[1].ngram));

            // Find initial matches
            initialMatches := JOIN
                (
                    corpusNGrams,
                    searchSigs,
                    LEFT.lookup_id = RIGHT.lookup_id,
                    TRANSFORM
                        (
                            {
                                EntityID_t          search_id,
                                EntityID_t          entity_id,
                                SET OF VocabID_t    search_ngram_pos_set;
                                SET OF VocabID_t    entity_ngram_pos_set;
                            },
                            SELF.entity_id := LEFT.id,
                            SELF.search_id := RIGHT.id,
                            SELF.entity_ngram_pos_set := LEFT.ngram_pos_set,
                            SELF.search_ngram_pos_set := RIGHT.ngram_pos_set
                        ),
                    LOOKUP
                );

            // Dedup so as to avoid running similarity computation on identical pairs
            dedupedMatches := TABLE
                (
                    initialMatches,
                    {
                        search_id,
                        entity_id,
                        entity_ngram_pos_set,
                        search_ngram_pos_set
                    },
                    search_id, entity_id, entity_ngram_pos_set, search_ngram_pos_set,
                    MERGE
                );

            // Filter out dissimilar matches
            matches := PROJECT
                (
                    dedupedMatches,
                    TRANSFORM
                        (
                            SearchResultLayout,
                            sim := UtilMod.JaccardSimilarity(LEFT.entity_ngram_pos_set, LEFT.search_ngram_pos_set);
                            SELF.similarity := IF(sim >= minSimilarity, sim, SKIP),
                            SELF := LEFT
                        )
                );

            RETURN matches;
        END;

        //--------------------------------------------------------------------

        EXPORT SearchOne(UTF8 searchString, REAL8 minSimilarity) := FUNCTION
            RETURN SearchMany(DATASET([{0, searchString}], EntityLayout), minSimilarity);
        END;

    END; // Module Search

END; // Module FuzzyNGramSearch

/******* EXAMPLE CODE ***********************************************************************

IMPORT FuzzyNGramSearch;

NGRAM_SIZE := 2;
MIN_SIMILARITY := 0.10; // Artificially low to see results

// Make sure the above constants adhere to our setup
ASSERT(NGRAM_SIZE > 1, FAIL);
ASSERT(MIN_SIMILARITY >= 0, FAIL);

//--------------------------------

DO_BUILD := TRUE;
DO_SEARCH := TRUE;
FILE_SCOPE := '~FuzzyNGramSearch_test';

//--------------------------------

corpus0 := DATASET
    (
        [
            {1001, u8'CAMPER'},
            {1002, u8'AAAAAABAAAAAAA'},
            {1003, u8'FUBAR'},
            {1004, u8'Z'}
        ],
        FuzzyNGramSearch.EntityLayout,
        DISTRIBUTED
    );
corpus := NOFOLD(corpus0);

buildAction := FuzzyNGramSearch.Build(FILE_SCOPE).CreateFiles(corpus, NGRAM_SIZE);

//--------------------------------

searchEntities0 := DATASET
    (
        [
            {1, u8'CAMPER'},
            {2, u8'DAN'},
            {3, u8'PERSON'},
            {4, u8'CAMPBELL'}
        ],
        FuzzyNGramSearch.EntityLayout
    );
searchEntities := NOFOLD(searchEntities0);

searchManyResults := FuzzyNGramSearch.Search(FILE_SCOPE).SearchMany(searchEntities, MIN_SIMILARITY);
searchOneResults := FuzzyNGramSearch.Search(FILE_SCOPE).SearchOne(NOFOLD(u8'FUBARSKY'), MIN_SIMILARITY);

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