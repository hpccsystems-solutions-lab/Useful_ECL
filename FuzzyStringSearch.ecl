/**
 * ECL module that supports fast, inexact matching of query words against a
 * dictionary of words.  Inexact matching is useful for matching words that
 * differ by only a few characters, perhaps due to typos or transpositions.
 * Very large word sets are fully supported for both dictionary and query
 * words, making this a good big data matching solution in a distributed
 * environment like HPCC.
 *
 * The code here relies on computing the Levenshtein Distance (the
 * "edit distance") between any two words, which is informally defined as
 * the minimum number of single-character edits (insertions, deletions or
 * substitutions) required to change one word into the other.  More
 * information on edit distances can be found at
 * https://en.wikipedia.org/wiki/Levenshtein_distance.
 *
 * This module creates an ECL index that represents the dictionary of words.
 * Query words, either singularly or in the form of a dataset, can then
 * be quickly matched against the dictionary.  The result is a dataset
 * where each record contains a query word, a dictionary word, and the
 * actual edit distance between them.
 *
 * A maximum edit distance ("MaxED") is provided at both index creation
 * time and at search time.  Fuzzy matches with edit distances greater than
 * the search MaxED will not be returned.  The index grows dramatically
 * with higher MaxED values and longer words; a MaxED of 1 or 2 is typical
 * when matching single words.  You can use different MaxED values for index
 * creation and search; the MaxED value for search will be the limit used
 * for results.  Searching with a MaxED higher than the MaxED used to create
 * the index will return only partial results (if any) for any edit distance
 * value beyond the MaxED used for index creation, so for accuracy the MaxED
 * value you use for search should not exceed the value used to create
 * the index.
 *
 * This module supports an "adaptive edit distance" feature.  Rather than
 * setting a fixed maximum edit distance, you can supply a -1 value for the
 * MaxED parameter and the function will choose an appropriate value on a
 * per-word basis.  The value chosen will be basically, "1 for every seven
 * characters."  So, a three-character word will use a MaxED of 1, a
 * nine-character word use a MaxED of 2, and so on, up to a hardcoded
 * maximum, currently 5.
 *
 * This module provides data normalization only for the TextSearch() function,
 * where it is slightly harder to implement.  For dictionary creation and
 * the other search functions, you should prepare your data by converting the
 * strings to uppercase or lowercase, removing space runs, etc so that all
 * values are normalized as much as possible.  Exactly what normalization
 * steps you perform depend on your use-case.
 *
 * The module supports UTF-8 strings for both the dictionary and query words.
 * It uses the current locale when computing the actual edit distance between
 * two UTF-8 strings.
 *
 * Attributes exported by this module (detailed descriptions are inlined with
 * each exported symbol):
 *
 *      // Record Definitions
 *      WordRec
 *      LookupRec
 *      SearchResultRec
 *      TextSearchResultRec
 *
 *      // Function Prototypes
 *      NormalizeWordPrototype()
 *
 *      // Functions -- see code for parameter list
 *      DoNothingNormalization()
 *      HashLookupIndexDef()
 *      CreateIndex()
 *      BulkSearch()
 *      WordSearch()
 *      TextSearch()
 *
 * Example code may be found at the end of this file.
 *
 * The methods used in this module (primarily the "deletion neighborhood"
 * concept) were inspired by a paper written by Daniel Karch, Dennis Luxen,
 * and Peter Sanders from the Karlsruhe Institute of Technology, titled
 * "Improved Fast Similarity Search in Dictionaries"
 * (https://arxiv.org/abs/1008.1191v2).  This paper, in turn, was based on the
 * work described in "Fast Similarity Search in Large Dictionaries" by
 * Thomas Bocek, Ela Hunt, and Burkhard Stiller
 * (https://fastss.csg.uzh.ch/ifi-2007.02.pdf).
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */

IMPORT Std;

EXPORT FuzzyStringSearch := MODULE

    // Maximum when using adaptive edit distances, don't exceed this value
    SHARED MAX_ADAPTIVE_EDIT_DISTANCE := 5;

    // Simple record defining either a dictionary or query word (string)
    EXPORT WordRec := RECORD
        UTF8                    word;
    END;

    // The record definition of results from BulkSearch() or Search()
    SHARED RelatedWordRec := RECORD
        UTF8                    dictionary_word;
        UNSIGNED1               edit_distance;
    END;

    // The record definition of results from BulkSearch() or Search()
    EXPORT SearchResultRec := RECORD
        UTF8                    given_word;
        RelatedWordRec;
    END;

    // The record definition of results from TextSearch()
    EXPORT TextSearchResultRec := RECORD
        UNSIGNED2               word_pos;
        UTF8                    given_word;
        DATASET(RelatedWordRec) related_words;
    END;

    // Record definition used to hold the deletion neighborhood hashes
    SHARED HashRec := RECORD
        UNSIGNED8               hash_value;
    END;

    // The record definition used by the dictionary index file and by
    // the internal matching function
    EXPORT LookupRec := RECORD
        HashRec;
        WordRec;
    END;

    /**
     * Function prototype -- must be overridden with a concrete function
     *
     * Given a single word, return a 'normalized' version of the word to be
     * used for index creation or searching.
     *
     * @param   oneWord     A word to normalize; REQUIRED
     *
     * @return  The given word, normalized in whatever manner is correct
     *          for the current use-case.
     *
     * @see     TextSearch
     * @see     DoNothingNormalization
     */
    EXPORT UTF8 NormalizeWordPrototype(UTF8 oneWord);

    /**
     * Concrete instantiation of the NormalizeWordPrototype() prototype
     * that does nothing.
     *
     * @param   oneWord     A word to normalize; REQUIRED
     *
     * @return  The given word, unchanged.
     *
     * @see     NormalizeWordPrototype
     * @see     TextSearch
     */
    EXPORT UTF8 DoNothingNormalization(UTF8 oneWord) := FUNCTION
        RETURN oneWord;
    END;

    /**
     * Internal helper function.
     *
     * Given a dataset of words and a MaxED value, this function generates
     * a dataset in the layout used for either index creation or searching.
     * For each word, substrings are created and hashed into 64-bit numbers
     * (the deletion neighborhood).  The number of records generated for each
     * word depends on the length of the word and the max_edit_distance value
     * provided.
     *
     * @param   words               A dataset in WordRec layout containing
     *                              the words to process; this dataset
     *                              should not be empty; REQUIRED
     * @param   max_edit_distance   The maximum edit distance to use when
     *                              creating word substrings; this is
     *                              typically a value of 1 or 2 for single-
     *                              word values, but may be slightly larger
     *                              when dealing with longer "words";
     *                              a value of -1 will enable an 'adaptive
     *                              edit distance' which means that the value
     *                              for any single word will depend on the
     *                              length of that word (roughly, 1 for every
     *                              five characters)
     *                              REQUIRED
     *
     * @return  A new DATASET(LookupRec)
     */
    SHARED DATASET(LookupRec) CreateDeletionNeighborhoodHashes(DATASET(WordRec) words, INTEGER1 max_edit_distance) := FUNCTION
        STREAMED DATASET(HashRec) _CreateDeletionNeighborhood(CONST UTF8 _one_word,
                                                              INTEGER1 _max_distance,
                                                              UNSIGNED2 _max_adaptive_distance = MAX_ADAPTIVE_EDIT_DISTANCE) := EMBED(C++)
            #option pure;
            #include <string>
            #include <set>

            #define UCHAR_TYPE uint16_t
            #include <unicode/unistr.h>

            typedef std::set<hash64_t> HashValueSet;

            // Compute the 64-bit hash for a Unicode string value
            hash64_t HashString(const icu::UnicodeString& aString)
            {
                std::string     outString;

                aString.toUTF8String(outString);

                return rtlHash64Data(outString.size(), outString.data(), HASH64_INIT);
            }

            // Recursive function that deletes single characters; depth here is associated with the
            // the MaxED value
            void PopulateHashSet(const icu::UnicodeString& aWord, unsigned int depth, HashValueSet& aSet)
            {
                // Abort if we've gone deep enough or if the word is too short
                // (don't allow single-character substrings in the result)
                if (depth > 0 && aWord.countChar32() > 2)
                {
                    UnicodeString   myWord;

                    for (int32_t x = 0; x < aWord.countChar32(); x++)
                    {
                        myWord = aWord;
                        myWord.remove(x, 1);
                        aSet.insert(HashString(myWord));
                        PopulateHashSet(myWord, depth - 1, aSet);
                    }
                }
            }

            class StreamDataset : public RtlCInterface, implements IRowStream
            {
                public:

                    StreamDataset(IEngineRowAllocator* _resultAllocator, unsigned int wordLen, const char* word, int maxEditDistance, unsigned int maxAdaptiveDistance)
                        : resultAllocator(_resultAllocator), myWord(word, wordLen, "UTF-8"), isInited(false)
                    {
                        myEditDistance = (maxEditDistance >= 0 ? maxEditDistance : std::min(maxAdaptiveDistance, (wordLen - 1) / 7 + 1));
                        isStopped = (wordLen == 0);
                    }

                    RTLIMPLEMENT_IINTERFACE

                    // Each time a row is requested, provide a copy of the next
                    // hash value
                    virtual const void* nextRow()
                    {
                        if (isStopped)
                        {
                            return NULL;
                        }

                        if (!isInited)
                        {
                            // Insert hash of given word into our substring set
                            // to start things off
                            hashSet.insert(HashString(myWord));

                            // Build substrings and insert their hashes into
                            // our hash set
                            PopulateHashSet(myWord, myEditDistance, hashSet);

                            hashSetIter = hashSet.begin();
                            isInited = true;
                        }

                        if (hashSetIter != hashSet.end())
                        {
                            hash64_t                oneHash = *hashSetIter;
                            RtlDynamicRowBuilder    rowBuilder(resultAllocator);
                            unsigned int            len = sizeof(oneHash);
                            byte*                   row = rowBuilder.ensureCapacity(len, NULL);

                            *(hash64_t*)(row) = oneHash;

                            ++hashSetIter;

                            return rowBuilder.finalizeRowClear(len);
                        }

                        isStopped = true;

                        return NULL;
                    }

                    virtual void stop()
                    {
                        isStopped = true;
                    }

                protected:

                    Linked<IEngineRowAllocator> resultAllocator;

                private:

                    icu::UnicodeString              myWord;         // Word we are processing
                    unsigned int                    myEditDistance; // The max edit distance we're calculating
                    HashValueSet                    hashSet;        // Contains unique hash values
                    HashValueSet::const_iterator    hashSetIter;    // Iterator used to track hash items for nextRow()
                    bool                            isInited;
                    bool                            isStopped;
            };

            #body

            return new StreamDataset(_resultAllocator, rtlUtf8Size(len_one_word, _one_word), _one_word, _max_distance, _max_adaptive_distance);
        ENDEMBED;

        // Collect hashes of the deletion neighborhood,
        // flattening the result; note that results from
        // _CreateDeletionNeighborhood() are deduplicated
        result := NORMALIZE
            (
                words,
                _CreateDeletionNeighborhood(LEFT.word, max_edit_distance),
                TRANSFORM
                (
                    LookupRec,
                    SELF.hash_value := RIGHT.hash_value,
                    SELF.word := LEFT.word
                )
            );

        RETURN result;
    END;

    /**
     * INDEX definition for the hash lookup
     *
     * @param   path    Full logical pathname to the dictionary index file;
     *                  index may be physically present or not; REQUIRED
     *
     * @return  INDEX definition
     *
     * @see     CreateIndex
     * @see     BulkSearch
     * @see     Search
     */
    EXPORT HashLookupIndexDef(STRING path) := INDEX
        (
            {LookupRec.hash_value},
            {LookupRec},
            path,
            OPT
        );

    /**
     * Create an index file representing a dictionary of words.  This index
     * will be used later when comparing query words.  Only words that are
     * at least three characters in length will have index entries suitable
     * for edit distance searching.
     *
     * @param   words               A dataset in WordRec layout containing
     *                              the words to process; words are
     *                              deduplicated; this dataset should not
     *                              be empty; REQUIRED
     * @param   newIndexPath        Full logical path of the index file to
     *                              create; any existing file of the same
     *                              name will be deleted; REQUIRED
     * @param   maxEditDistance     The maximum edit distance this index
     *                              file will support; this is
     *                              typically a value of 1 or 2 for single-
     *                              word values, but may be slightly larger
     *                              when dealing with longer "words";
     *                              a value of -1 will enable an 'adaptive
     *                              edit distance' which means that the value
     *                              for any single word will depend on the
     *                              length of that word (roughly, 1 for every
     *                              five characters); OPTIONAL, defaults to 1
     *
     * @return  An action that creates an index file.  If a file of the same
     *          already exists, it will be overwritten.
     *
     * @see     BulkSearch
     * @see     WordSearch
     * @see     TextSearch
     */
    EXPORT CreateIndex(DATASET(WordRec) words,
                       STRING newIndexPath,
                       INTEGER1 maxEditDistance = 1) := FUNCTION
        uniqueWords := TABLE(words(word != U8''), {word}, word, MERGE);
        lookupData := CreateDeletionNeighborhoodHashes(uniqueWords, maxEditDistance);
        indexDef := HashLookupIndexDef(newIndexPath);

        RETURN BUILD(indexDef, lookupData, OVERWRITE);
    END;

    /**
     * Attempt to match a dataset of query words against a dictionary
     * represented by an index file previously created with CreateIndex().
     * Only words that are at least three characters in length will have
     * edit distance searching performed (shorter words will have only exact
     * matching).
     *
     * @param   words               A dataset in WordRec layout containing
     *                              the query words to match; words are
     *                              deduplicated; this dataset should not
     *                              be empty; REQUIRED
     * @param   indexPath           Full logical path of the index file
     *                              containing the dictionary words, previously
     *                              created with a call to CreateIndex();
     *                              REQUIRED
     * @param   maxEditDistance     The maximum edit distance to use when
     *                              comparing query words to dictionary words;
     *                              a value of -1 will enable an 'adaptive
     *                              edit distance' which means that the value
     *                              for any single word will depend on the
     *                              length of that word (roughly, 1 for every
     *                              five characters); OPTIONAL, defaults to 1
     *
     * @return  A new DATASET(SearchResultRec) containing any matches.  Note
     *          that only those query words with matches in the dictionary
     *          will appear in the result.
     *
     * @see     SearchResultRec
     * @see     CreateIndex
     * @see     WordSearch
     * @see     TextSearch
     */
    EXPORT DATASET(SearchResultRec) BulkSearch(DATASET(WordRec) words,
                                               STRING indexPath,
                                               INTEGER1 maxEditDistance = 1) := FUNCTION
        uniqueWords := TABLE(words(word != U8''), {word}, word, MERGE);
        wordHashes := CreateDeletionNeighborhoodHashes(uniqueWords, maxEditDistance);
        indexDef := HashLookupIndexDef(indexPath);

        initialResult := JOIN
            (
                wordHashes,
                indexDef,
                LEFT.hash_value = RIGHT.hash_value,
                TRANSFORM
                    (
                        SearchResultRec,

                        myMaxDist := IF(maxEditDistance >= 0, maxEditDistance, MIN(MAX_ADAPTIVE_EDIT_DISTANCE, ((LENGTH(LEFT.word) - 1) DIV 7 + 1)));
                        computedDistance := Std.Uni.EditDistance(LEFT.word, RIGHT.word, '', myMaxDist);

                        SELF.edit_distance := IF(computedDistance <= myMaxDist, computedDistance, SKIP),
                        SELF.given_word := LEFT.word,
                        SELF.dictionary_word := RIGHT.word
                    ),
                LIMIT(0)
            );

        dedupedResult := TABLE
            (
                initialResult,
                {
                    given_word,
                    dictionary_word,
                    edit_distance
                },
                given_word, dictionary_word, edit_distance,
                MERGE
            );

        RETURN PROJECT(dedupedResult, SearchResultRec);
    END;

    /**
     * Attempt to match a single query word against a dictionary represented
     * by an index file previously created with CreateIndex().  The query word
     * must be at least three characters in length to be searched with the
     * edit distance algorithm (a shorter word will have only exact matching).
     *
     * @param   word                The query word to match; should not be an
     *                              empty string; REQUIRED
     * @param   indexPath           Full logical path of the index file
     *                              containing the dictionary words, previously
     *                              created with a call to CreateIndex();
     *                              REQUIRED
     * @param   maxEditDistance     The maximum edit distance to use when
     *                              comparing the given word to dictionary
     *                              words; a value of -1 will enable an
     *                              'adaptive edit distance' which means that
     *                              the value will depend on the length of
     *                              the given word (roughly, 1 for every
     *                              five characters); OPTIONAL, defaults to 1
     *
     * @return  A new DATASET(SearchResultRec) containing any matches.  If there
     *          is no match found then an empty dataset will be returned.
     *
     * @see     SearchResultRec
     * @see     CreateIndex
     * @see     BulkSearch
     * @see     TextSearch
     */
    EXPORT DATASET(SearchResultRec) WordSearch(UTF8 word,
                                               STRING indexPath,
                                               INTEGER1 maxEditDistance = 1) := FUNCTION
        RETURN BulkSearch(DATASET([word], WordRec), indexPath, maxEditDistance);
    END;

    /**
     * Attempt to match words within with a string against a dictionary
     * represented by an index file previously created with CreateIndex().
     * The string can contain one or more words, delimited by spaces.
     * Only words that are at least three characters in length will have
     * edit distance searching performed (shorter words will have only exact
     * matching).
     *
     * Each word that is extracted from the string must be normalized using
     * the function you provide as an argument to this function call.  A
     * default normalization function is provided that uppercases the word
     * and removes leading and trailing non-alphanumeric characters.
     *
     * If the desire is to search multi-word strings as a whole, without
     * breaking them up into individual words, then BulkSearch() or
     * WordSearch() should be used instead.
     *
     * @param   text                A string containing one or more words;
     *                              each word is processed through the
     *                              function defined by the normWordFunction
     *                              argument; REQUIRED
     * @param   indexPath           Full logical path of the index file
     *                              containing the dictionary words, previously
     *                              created with a call to CreateIndex();
     *                              REQUIRED
     * @param   normWordFunction    The function called for each word extracted
     *                              from the text argument to normalize its
     *                              value for searching; OPTIONAL, defaults
     *                              to a function that does nothing
     * @param   maxEditDistance     The maximum edit distance to use when
     *                              comparing each word to dictionary words;
     *                              a value of -1 will enable an 'adaptive
     *                              edit distance' which means that the value
     *                              for any single word will depend on the
     *                              length of that word (roughly, 1 for every
     *                              five characters); OPTIONAL, defaults to 1
     *
     * @return  A new DATASET(TextSearchResultRec) dataset containing all of
     *          original words, their relative positions within the string,
     *          and a child dataset for each showing any possible matches
     *          (possibly none) from the dictionary.
     *
     * @see     CreateIndex
     * @see     BulkSearch
     * @see     WordSearch
     */
    EXPORT TextSearch(UTF8 text,
                      STRING indexPath,
                      NormalizeWordPrototype normWordFunction = DoNothingNormalization,
                      INTEGER1 maxEditDistance = 1) := FUNCTION
        wordSet := (SET OF UTF8)Std.Uni.SplitWords(text, ' ');

        PositionWordRec := RECORD(WordRec)
            UNSIGNED2   word_pos;
        END;

        wordDS := PROJECT
            (
                DATASET(wordSet, {UTF8 w}),
                TRANSFORM
                    (
                        PositionWordRec,
                        SELF.word_pos := COUNTER,
                        SELF.word := normWordFunction(LEFT.w)
                    )
            );

        bulkResults := BulkSearch(wordDS, indexPath, maxEditDistance);

        res := DENORMALIZE
            (
                wordDS,
                bulkResults,
                LEFT.word = RIGHT.given_word,
                GROUP,
                TRANSFORM
                    (
                        TextSearchResultRec,
                        SELF.word_pos := LEFT.word_pos,
                        SELF.given_word := LEFT.word,
                        SELF.related_words := PROJECT(ROWS(RIGHT), RelatedWordRec),
                        SELF := LEFT
                    ),
                LEFT OUTER
            );
        RETURN res;
    END;

END;

/*****************************************************************************

// Example:  Create a dictionary index file

IMPORT FuzzyStringSearch;

dictionaryWords := DATASET
    (
        ['THE', 'QUICK', 'BROWN', 'FOX', 'JUMPED', 'OVER', 'THE', 'LAZY', 'DOG'],
        FuzzyStringSearch.WordRec
    );

FuzzyStringSearch.CreateIndex
    (
        dictionaryWords,
        '~fuzzy_search::demo_idx',
        maxEditDistance := 1
    );

*/

/*****************************************************************************

// Example:  Bulk search against the dictionary index file

IMPORT FuzzyStringSearch;

queryWords := DATASET
    (
        ['THE', 'QUIK', 'BROWNN', 'FAX', 'JUMPED', 'UNDER', 'THE', 'LAZY', 'LOG'],
        FuzzyStringSearch.WordRec
    );

results := FuzzyStringSearch.BulkSearch
    (
        queryWords,
        '~fuzzy_search::demo_idx',
        maxEditDistance := 1
    );

OUTPUT(results);

// given_word      dictionary_word     edit_distance
//--------------------------------------------------
// LOG             DOG                 1
// FAX             FOX                 1
// JUMPED          JUMPED              0
// THE             THE                 0
// BROWNN          BROWN               1
// LAZY            LAZY                0
// QUIK            QUICK               1

*/

/*****************************************************************************

// Example:  Single-word search against the dictionary index file

IMPORT FuzzyStringSearch;

results := FuzzyStringSearch.WordSearch
    (
        'QUIK',
        '~fuzzy_search::demo_idx',
        maxEditDistance := 1
    );

OUTPUT(results);

// given_word      dictionary_word     edit_distance
//--------------------------------------------------
// QUIK            QUICK               1

*/

/*****************************************************************************

// Example:  Text search against the dictionary index file

IMPORT FuzzyStringSearch;

UTF8 NormalizeWordUpperCase(UTF8 oneWord) := FUNCTION
    upperWord := Std.Uni.ToUpperCase(oneWord);
    noBeginningPunct := REGEXREPLACE(U8'^[^[:alnum:]]+', upperWord, U8'');
    noEndingPunct := REGEXREPLACE(U8'[^[:alnum:]]+$', noBeginningPunct, U8'');

    RETURN noEndingPunct;
END;

results := FuzzyStringSearch.TextSearch
    (
        'Fax me the big box picture.',
        '~fuzzy_search::demo_idx',
        normWordFunction := NormalizeWordUpperCase,
        maxEditDistance := 1
    );

OUTPUT(SORT(results, word_pos));

//                           related_words
// word_pos  given_word      dictionary_word     edit_distance
//------------------------------------------------------------
// 1         FAX             FOX                 1
// 2         ME
// 3         THE             THE                 0
// 4         BIG
// 5         BOX             FOX                 1
// 6         PICTURE

*/
