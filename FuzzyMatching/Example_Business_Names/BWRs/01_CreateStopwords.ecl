IMPORT Std;

#WORKUNIT('name', 'Create Fuzzy Business Name Stopwords');

//-----------------------------------------------------------------------------
// This code is intended to be executed under Thor
//-----------------------------------------------------------------------------

IMPORT $.^.^ AS Root;
IMPORT $.^ AS Home;

//-----------------------------------------------------------------------------

RAW_DATA_PATH := Home.Constants.PATH_PREFIX + '::business_namelist.csv';
rawData := DATASET(RAW_DATA_PATH, Root.Files.CommonRawDataLayout, CSV(UNICODE));

//-----------------------------------------------------------------------------

// Note that the record definition for the raw file does not read all of the
// fields in, so while this looks like a whole-record-deduplication, it really
// looks at only the first few fields
dedupedRawData := DEDUP(SORT(rawData, WHOLE RECORD), WHOLE RECORD);

cleanedFullNames := PROJECT
    (
        dedupedRawData(entity_guid != '' AND name != ''),
        TRANSFORM
            (
                {
                    RECORDOF(LEFT),
                    UTF8                full_name,
                    Root.Files.NAMEID_t name_id
                },
                SELF.name := Home.CleanBusinessName(LEFT.name),
                SELF.full_name := LEFT.name,
                SELF.name_id := COUNTER,
                SELF := LEFT
            )
    );

// Minimize the fields we use for performance
trimmedCleanedFullNames := TABLE(cleanedFullNames, {name, name_id});

// Make sure file is relatively evenly spread across Thor workers
distCleanedFullNames := DISTRIBUTE(trimmedCleanedFullNames, SKEW(0.05));

// Break (full) name value into words, noting their name_id origin
cleanedNames := NORMALIZE
    (
        distCleanedFullNames,
        Root.FuzzyNameMatch.MakeWordDS(LEFT.name),
        TRANSFORM
            (
                {
                    UTF8        name,
                    UNSIGNED4   name_id
                },
                SELF.name := IF(Root.FuzzyNameMatch.IsValidWord(RIGHT.word), RIGHT.word, SKIP),
                SELF.name_id := LEFT.name_id
            )
    );

// For each unique name word, count the number of names in which that word appears and
// compute an inverse frequency value (IFV) for it; also compute a hash of the name
// word, which will be used as the key for an index
nameFrequency := TABLE
    (
        cleanedNames,
        {
            UTF8        word := name,
            UNSIGNED4   name_count := COUNT(GROUP)
        },
        name,
        MERGE
    );

indexStopwords := nameFrequency(name_count >= $.Constants.INDEX_STOPWORD_WORD_FREQ_CUTOFF);
nonStopwords := nameFrequency(name_count < $.Constants.INDEX_STOPWORD_WORD_FREQ_CUTOFF);

// Debug output
OUTPUT(COUNT(nameFrequency), NAMED('word_count'));
OUTPUT($.Constants.INDEX_STOPWORD_WORD_FREQ_CUTOFF, NAMED('word_freq_cutoff'));
OUTPUT(TOPN(nonStopWords, 1000, -name_count), NAMED('other_words_sample'), ALL);

// Files
OUTPUT(indexStopwords, {indexStopwords}, Home.Constants.STOPWORD_PATH, COMPRESSED, OVERWRITE);

