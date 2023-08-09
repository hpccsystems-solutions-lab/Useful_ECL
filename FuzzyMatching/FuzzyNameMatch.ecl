IMPORT Std;
IMPORT $;

EXPORT FuzzyNameMatch := MODULE

    /**
     * Prototype for a function that "cleans" an entity name.
     * Basically, a caller provides a name as the sole argument
     * and expects a "cleaned" version as the result.
     *
     * @param   name        The entity name to clean; REQUIRED
     *
     * @return  The cleaned version of the argument.
     *
     * @see     Build()
     *          BestMatches()
     */
    EXPORT UTF8 CleanNamePrototype(UTF8 name);

    /**
     * Prototype for a function that returns a Levenstein
     * edit distance given a string.  This is used to
     * dynamically determine an edit distance value
     * derived from the length of the string.
     *
     * @param   str         The string to examine; REQUIRED
     *
     * @return  The Levenstein edit distance that should be
     *          used for the given string.  If an adaptive
     *          distance is not needed, simply ignore the
     *          argument and return a constant value.
     *
     * @see     Build()
     *          BestMatches()
     */
    EXPORT UNSIGNED1 AdaptedDistancePrototype(UTF8 str);

    /**
     * Convert a multi-word string to a dataset of individual words,
     * numbering and deduping the words along the way.
     *
     * @param   s           A string to process; REQUIRED
     *
     * @return  A dataset in the format {UTF8 name, UNSIGNED1 word_id}
     *          where name will contain one word from the original
     *          argument and word_id will be its first position
     *          within the string.
     */
    EXPORT MakeWordDS(UTF8 s) := FUNCTION
        wordsDS := PROJECT
            (
                DATASET(Std.Uni.SplitWords(s, ' '), {UTF8 word}),
                TRANSFORM
                    (
                        {
                            RECORDOF(LEFT),
                            UNSIGNED1   word_id
                        },
                        SELF.word_id := COUNTER,
                        SELF := LEFT
                    )
            );

        RETURN DEDUP(SORT(wordsDS, word, word_id, LOCAL), word, LOCAL);
    END;

    // Name test; returns TRUE if the name is 'acceptable' for indexing or querying
    /**
     * Test to see if a word is broadly acceptable for indexing or searching.
     *
     * @param   s       The word to test; REQUIRED
     *
     * @return  TRUE if the word is acceptable, FALSE otherwise.
     */
    EXPORT IsValidWord(UTF8 s) := FUNCTION
        tooShort := LENGTH(s) < 2;
        beginsWithNum := (s[1] >= '0' AND s[1] <= '9');
        RETURN NOT(tooShort OR beginsWithNum);
    END;

    /**
     * Internal helper function.
     *
     * Given a string, return dataset of strings representing the argument's
     * deletion neighborhood.
     *
     * @param   text                A string to process; REQUIRED
     * @param   max_edit_distance   The maximum edit distance to use when
     *                              creating the deletion neighborhood;
     *                              REQUIRED
     *
     * @return  A new DATASET({UTF8 text})
     */
    SHARED STREAMED DATASET({UTF8 text}) CreateStringDeletionNeighborhood(CONST UTF8 text, UNSIGNED1 max_edit_distance) := EMBED(C++)
        #option pure;
        #include <set>
        #include <string>

        #define UCHAR_TYPE uint16_t
        #include "unicode/unistr.h"

        typedef std::set<std::string> TextSet;

        using icu::UnicodeString;

        #body

        class StreamedStringDataset : public RtlCInterface, implements IRowStream
        {
            public:

                StreamedStringDataset(IEngineRowAllocator* _resultAllocator, unsigned int _word_byte_count, const char* _word, unsigned int _max_edit_distance)
                    : resultAllocator(_resultAllocator), myText(_word, _word_byte_count, "UTF-8"), myEditDistance(_max_edit_distance), isInited(false), isStopped(false)
                {}

                RTLIMPLEMENT_IINTERFACE

                void AppendToCollection(const UnicodeString& textLine)
                {
                    outString.clear();
                    textLine.toUTF8String(outString);
                    deletionNeighborhood.insert(outString);
                }

                void PopulateDeletionNeighborhood(const UnicodeString& textLine, unsigned int depth)
                {
                    if (depth > 0 && textLine.countChar32() > 2)
                    {
                        UnicodeString   myTextLine;

                        for (int32_t x = 0; x < textLine.countChar32(); x++)
                        {
                            myTextLine = textLine;
                            myTextLine.remove(x, 1);
                            AppendToCollection(myTextLine);
                            PopulateDeletionNeighborhood(myTextLine, depth - 1);
                        }
                    }
                }

                virtual const void* nextRow()
                {
                    if (isStopped)
                    {
                        return nullptr;
                    }

                    if (!isInited)
                    {
                        AppendToCollection(myText);
                        PopulateDeletionNeighborhood(myText, myEditDistance);
                        deletionNeighborhoodIter = deletionNeighborhood.begin();
                        isInited = true;
                    }

                    if (deletionNeighborhoodIter != deletionNeighborhood.end())
                    {
                        const std::string&      textLine = *deletionNeighborhoodIter;
                        RtlDynamicRowBuilder    rowBuilder(resultAllocator);
                        unsigned int            len = sizeof(__int32) + textLine.size();
                        byte*                   row = rowBuilder.ensureCapacity(len, nullptr);

                        *(__int32*)(row) = rtlUtf8Length(textLine.size(), textLine.data());
                        memcpy(row + sizeof(__int32), textLine.data(), textLine.size());

                        ++deletionNeighborhoodIter;

                        return rowBuilder.finalizeRowClear(len);
                    }

                    isStopped = true;

                    return nullptr;
                }

                virtual void stop()
                {
                    isStopped = true;
                }

            protected:

                Linked<IEngineRowAllocator> resultAllocator;

            private:

                UnicodeString               myText;
                unsigned int                myEditDistance;
                TextSet                     deletionNeighborhood;
                TextSet::const_iterator     deletionNeighborhoodIter;
                std::string                 outString;
                bool                        isInited;
                bool                        isStopped;
        };

        return new StreamedStringDataset(_resultAllocator, rtlUtf8Size(lenText, text), text, max_edit_distance);
    ENDEMBED;

    //===========================================================================================================

    /**
     * Given raw data in DATASET($.Files.CommonRawDataLayout) format,
     * create all indexes necessary for fuzzy searching.
     *
     * @param   rawData                     A dataset containing the names to index; REQUIRED
     * @param   nameIndexPath               Logical pathname of word -> nameID index that
     *                                      will be created; REQUIRED
     * @param   nameIDIndexPath             Logical pathname of nameID -> entityID index that
     *                                      will be created; REQUIRED
     * @param   entityIDIndexPath           Logical pathname of entityID -> <fullEntityInfo> index
     *                                      that will be created; REQUIRED
     * @param   CleanNameFunction           Function that will be used to clean and normalize a
     *                                      single name value; this function must accept a single
     *                                      UTF8 value and return a UTF8 value representing the
     *                                      cleaned/normalized version of the input value; REQUIRED
     * @param   AdaptedDistanceFunction     Function that will be used to determing the edit
     *                                      distance value used when creating a deletion neighborhood
     *                                      for a single name value; the function accept a single
     *                                      UTF8 value and return an UNSIGNED1 value; REQUIRED
     * @param   stopwordPath                Logical pathname of a simple dataset listing the
     *                                      words that should not be indexed (see $.Files.StopwordDS
     *                                      for the record definition); the file referenced by this
     *                                      pathname may be creatd with BWR_CreateNameStopwords.ecl;
     *                                      pass an empty string to not use stopwords; OPTIONAL,
     *                                      defaults to an empty string
     *
     * @return  An action that constructs all indexes.
     */
    EXPORT Build(DATASET($.Files.CommonRawDataLayout) rawData,
                 STRING nameIndexPath,
                 STRING nameIDIndexPath,
                 STRING entityIDIndexPath,
                 CleanNamePrototype CleanNameFunction,
                 AdaptedDistancePrototype AdaptedDistanceFunction,
                 STRING stopwordPath = '') := FUNCTION

        // Note that the record definition for the raw file does not read all of the
        // fields in, so while this looks like a whole-record-deduplication, it really
        // looks at only the first few fields
        dedupedRawData := DEDUP(SORT(rawData, WHOLE RECORD), WHOLE RECORD);

        cleanedFullNames := PROJECT
            (
                dedupedRawData(entity_guid != '' AND IsValidWord(name)),
                TRANSFORM
                    (
                        {
                            RECORDOF(LEFT),
                            UTF8                full_name,
                            $.Files.NAMEID_t    name_id
                        },
                        SELF.name_guid := IF(LEFT.name_guid != '', LEFT.name_guid, LEFT.entity_guid),
                        SELF.name := CleanNameFunction(LEFT.name),
                        SELF.full_name := LEFT.name,
                        SELF.name_id := COUNTER,
                        SELF := LEFT
                    )
            );

        // Minimize the fields we use for performance
        trimmedCleanedFullNames := TABLE(cleanedFullNames, {name, name_id});

        // Make sure file is relatively evenly spread across Thor workers
        distCleanedFullNames := DISTRIBUTE(trimmedCleanedFullNames, SKEW(0.05));

        // Break (full) name value into words, duplicating all other field values; skip known-invalid
        // words as early as possible
        cleanedNames := NORMALIZE
            (
                distCleanedFullNames,
                MakeWordDS(LEFT.name),
                TRANSFORM
                    (
                        {
                            RECORDOF(LEFT),
                            UNSIGNED1 word_id // used as a "word position" within the full name
                        },
                        SELF.name := IF(IsValidWord(RIGHT.word), RIGHT.word, SKIP),
                        SELF.word_id := RIGHT.word_id,
                        SELF := LEFT
                    )
            );

        stopwordsRemoved0 := JOIN
            (
                cleanedNames,
                $.Files.StopwordDS(stopwordPath),
                LEFT.name = RIGHT.word,
                TRANSFORM(LEFT),
                LEFT ONLY, ALL
            );

        // Remove stopwords from the list if possible
        stopwordsRemoved := IF(stopWordPath = '', cleanedNames, stopwordsRemoved0);

        // Create deletion neighborhood variations of each word, duplicating all other values;
        // at the same time, precompute the actual edit distance between a neighborhood word
        // and its origin word (this keeps us from computing the edit distance at query time,
        // which provides a significant speed boost)
        neighborhoodNames0 := NORMALIZE
            (
                stopwordsRemoved,
                CreateStringDeletionNeighborhood(LEFT.name, AdaptedDistanceFunction(LEFT.name)),
                TRANSFORM
                    (
                        {
                            $.Files.NAME_HASH_t name_hash,
                            UNSIGNED1           edit_distance,
                            RECORDOF(LEFT) - [name]
                        },
                        SELF.name_hash := HASH64(RIGHT.text),
                        SELF.edit_distance := Std.Uni.EditDistance(LEFT.name, RIGHT.text),
                        SELF := LEFT
                    )
            );

        // Create metaphone version of each word, duplicating all other values
        metaphoneNames := PROJECT
            (
                stopwordsRemoved,
                TRANSFORM
                    (
                        RECORDOF(neighborhoodNames0),
                        SELF.name_hash := HASH64(Std.Metaphone.Double((STRING)LEFT.name)),
                        SELF.edit_distance := 1, // broad assumption that a "sounds like" match is similar to edit distance 1
                        SELF := LEFT
                    )
            );

        neighborhoodNames := neighborhoodNames0 + metaphoneNames;

        buildNameIndexAction := BUILD($.Files.NameIndex(nameIndexPath), neighborhoodNames, UPDATE, OVERWRITE);

        //-------------------------

        stopwordSet := IF(stopwordPath = '', (SET OF UTF8)[], SET($.Files.StopwordDS(stopwordPath), word));
        nameIDFile := PROJECT
            (
                cleanedFullNames,
                TRANSFORM
                    (
                        {
                            $.Files.NAMEID_t    name_id,
                            $.Files.GUID_t      entity_guid,
                            UNSIGNED1           word_count // count of words in original name excluding any from stopword list
                        },
                        wordList := MakeWordDS(LEFT.name);
                        SELF.word_count := COUNT(wordList(word NOT IN stopwordSet)),
                        SELF := LEFT
                    )
            );

        buildNameIDIndexAction := BUILD($.Files.NameIDIndex(nameIDIndexPath), nameIDFile, UPDATE, OVERWRITE);

        //-------------------------

        entityIDFile := PROJECT
            (
                cleanedFullNames,
                TRANSFORM
                    (
                        {
                            $.Files.GUID_t      entity_guid,
                            $.Files.NAMEID_t    name_id,
                            $.Files.GUID_t      name_guid,
                            UTF8                full_name
                        },
                        SELF := LEFT
                    )
            );

        buildEntityIDIndexAction := BUILD($.Files.EntityIDIndex(entityIDIndexPath), entityIDFile, UPDATE, OVERWRITE);

        //-------------------------

        RETURN PARALLEL
            (
                buildNameIndexAction,
                buildNameIDIndexAction,
                buildEntityIDIndexAction
            );

    END; // Build()

    //===========================================================================================================

    /**
     * Leveraging indexes built with the Build() function in this module, perform a fuzzy
     * match and return the best group of matches.
     *
     * @param   fullName                    The name to search; REQUIRED
     * @param   nameIndexPath               Logical pathname of word -> nameID index that
     *                                      was created by the Build() function; REQUIRED
     * @param   nameIDIndexPath             Logical pathname of nameID -> entityID index that
     *                                      was created by the Build() function; REQUIRED
     * @param   entityIDIndexPath           Logical pathname of entityID -> <fullEntityInfo> index
     *                                      that was created by the Build() function; REQUIRED
     * @param   CleanNameFunction           Function that will be used to clean and normalize a
     *                                      single name value; this function must accept a single
     *                                      UTF8 value and return a UTF8 value representing the
     *                                      cleaned/normalized version of the input value; REQUIRED
     * @param   AdaptedDistanceFunction     Function that will be used to determing the edit
     *                                      distance value used when creating a deletion neighborhood
     *                                      for a single name value; the function accept a single
     *                                      UTF8 value and return an UNSIGNED1 value; REQUIRED
     * @param   stopwordPath                Logical pathname of a simple dataset listing the
     *                                      words that should not be indexed (see $.Files.StopwordDS
     *                                      for the record definition); the file referenced by this
     *                                      pathname may be creatd with BWR_CreateNameStopwords.ecl;
     *                                      pass an empty string to not use stopwords; OPTIONAL,
     *                                      defaults to an empty string
     * @param   maxDirectMatches            The number of "direct matches" that this function will
     *                                      return; note that when entity IDs are resolved, aliases
     *                                      may be pulled in and they may grow the returned results
     *                                      to a larger number of records; OPTIONAL, defaults to 2000
     *
     * @return  A dataset containing the best matching results; format roughly follows
     *          $.Files.EntityIDIndex with two additional fiels:
     *              is_match    Boolean indicating whether the fullName actually matched that name
     *                          or if the result was due to an alias match
     *              score       The numeric score of the match
     */
    EXPORT BestMatches(UTF8 fullName,
                       STRING nameIndexPath,
                       STRING nameIDIndexPath,
                       STRING entityIDIndexPath,
                       CleanNamePrototype CleanNameFunction,
                       AdaptedDistancePrototype AdaptedDistanceFunction,
                       STRING stopwordPath = '',
                       UNSIGNED2 maxDirectMatches = 2000) := FUNCTION

        // Weird concatenate-then-split to take into account single name variables
        // containing multiple words
        queryWords0 := MakeWordDS(CleanNameFunction(fullName));
        hardStopwordsRemoved := JOIN
            (
                queryWords0,
                $.Files.StopwordDS(stopwordPath),
                LEFT.word = RIGHT.word,
                TRANSFORM(LEFT),
                LEFT ONLY, ALL
            );
        queryWords := IF(stopwordPath = '', queryWords0, hardStopwordsRemoved);
        queryWordsCount := COUNT(queryWords);

        // Compute deletion neighborhood variations of each word in the inputs, converting them
        // to hash values for searching
        neighborhoodQueryNames0 := NORMALIZE
            (
                queryWords,
                CreateStringDeletionNeighborhood(LEFT.word, AdaptedDistanceFunction(LEFT.word)),
                TRANSFORM
                    (
                        {
                            $.Files.NAME_HASH_t name_hash
                        },
                        SELF.name_hash := IF(IsValidWord(RIGHT.text), HASH64(RIGHT.text), SKIP)
                    )
            );

        // Create metaphone variation of each word in the inputs, converting them to
        // hash values for searching
        metaphoneNames := PROJECT
            (
                queryWords,
                TRANSFORM
                    (
                        RECORDOF(neighborhoodQueryNames0),
                        SELF.name_hash := HASH64(Std.Metaphone.Double((STRING)LEFT.word))
                    )
            );

        neighborhoodQueryNames := neighborhoodQueryNames0 + metaphoneNames;

        // Find exact matches between deletion neighborhood hashes and previously-indexed words
        initialMatch0 := JOIN
            (
                neighborhoodQueryNames,
                $.Files.NameIndex(nameIndexPath),
                LEFT.name_hash = RIGHT.name_hash,
                TRANSFORM(RIGHT),
                LIMIT(0)
            );

        // For each word position within a name, find the best match (least edit distance)
        initialMatch := ROLLUP
            (
                SORT(initialMatch0, name_id, word_id),
                TRANSFORM
                    (
                        RECORDOF(LEFT),
                        keepLeft := LEFT.edit_distance <= RIGHT.edit_distance;
                        SELF.name_hash := IF(keepLeft, LEFT.name_hash, RIGHT.name_hash),
                        SELF.edit_distance := IF(keepLeft, LEFT.edit_distance, RIGHT.edit_distance),
                        SELF := LEFT
                    ),
                name_id, word_id
            );

        // For each full name, count the number of words that matched and sum their edit distance
        nameIDsMatched := TABLE
            (
                initialMatch,
                {
                    name_id,
                    UNSIGNED1   query_words_matched_count := COUNT(GROUP),
                    UNSIGNED2   query_edit_distance_sum := SUM(GROUP, edit_distance)
                },
                name_id
            );

        // The highest word count out of our matches
        maxMatchedCount := MAX(nameIDsMatched, query_words_matched_count);

        // Grab the entity GUID and original word count for each matched name; compute
        // a matching score
        entitiesMatched := JOIN
            (
                nameIDsMatched,
                $.Files.NameIDIndex(nameIDIndexPath),
                LEFT.name_id = RIGHT.name_id,
                TRANSFORM
                    (
                        {
                            $.Files.GUID_t      entity_guid,
                            $.Files.NAMEID_t    name_id,
                            UNSIGNED2           score
                        },
                        queryWordCountRatio := (maxMatchedCount - LEFT.query_words_matched_count) / maxMatchedCount; // Inv ratio of matching query word count to max match count
                        matchedWordCountRatio := (RIGHT.word_count - LEFT.query_words_matched_count) / RIGHT.word_count; // Inv ratio of query word match count and actual words

                        matchedWordCountPenalty := 10 * matchedWordCountRatio;
                        editDistancePenalty := 10 * LEFT.query_edit_distance_sum;
                        queryWordCountPenalty := 10 * queryWordCountRatio;

                        SELF.score := MAX(100 - matchedWordCountPenalty - editDistancePenalty - queryWordCountPenalty, 0),
                        SELF := LEFT,
                        SELF := RIGHT
                    ),
                LIMIT(0)
            );

        // We need only entity GUID values and their best scores
        entitiesCollapsed := TABLE
            (
                entitiesMatched,
                {
                    entity_guid,
                    UNSIGNED2 score := MAX(GROUP, score)
                },
                entity_guid
            );

        scoresWithCounts := TABLE
            (
                entitiesCollapsed,
                {
                    score,
                    UNSIGNED2   cnt := COUNT(GROUP),
                    UNSIGNED2   running_cnt := 0
                },
                score,
                MERGE
            );

        scoresRunningCounts := ITERATE
            (
                SORT(scoresWithCounts, -score),
                TRANSFORM
                    (
                        RECORDOF(LEFT),
                        SELF.running_cnt := LEFT.running_cnt + RIGHT.cnt,
                        SELF := RIGHT
                    )
            );

        topScores := SET(scoresRunningCounts(running_cnt <= maxDirectMatches), score);
        bestEntities := entitiesCollapsed(score IN topScores);

        // Grab the complete information for each remaining entity GUID
        fullEntities0 := JOIN
            (
                bestEntities,
                $.Files.EntityIDIndex(entityIDIndexPath),
                LEFT.entity_guid = RIGHT.entity_guid,
                TRANSFORM
                    (
                        {
                            UNSIGNED2   score,
                            RECORDOF(RIGHT)
                        },
                        SELF.score := LEFT.score,
                        SELF := RIGHT
                    ),
                LIMIT(0)
            );

        // Append our boolean indicating whether we directly matched a record
        // or the result was from an alias lookup
        fullEntities := JOIN
            (
                fullEntities0,
                entitiesMatched,
                LEFT.name_id = RIGHT.name_id,
                TRANSFORM
                    (
                        {
                            BOOLEAN is_match := FALSE,
                            RECORDOF(LEFT) - [name_id]
                        },
                        SELF.is_match := LEFT.name_id = RIGHT.name_id,
                        SELF := LEFT
                    ),
                LEFT OUTER, LOOKUP
            );

        RETURN fullEntities;
    END; // BestMatches

END; // Module
