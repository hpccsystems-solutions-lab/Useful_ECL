EXPORT Constants := MODULE
    EXPORT PATH_PREFIX := '~fuzzy_match';

    EXPORT STOPWORD_PATH := PATH_PREFIX + '::business::stopwords';
    EXPORT NAME_INDEX_PATH := PATH_PREFIX + '::business::name.idx';
    EXPORT NAME_ID_INDEX_PATH := PATH_PREFIX + '::business::nameid.idx';
    EXPORT ENTITY_ID_INDEX_PATH := PATH_PREFIX + '::business::entityid.idx';

    // Words appearing in more than this number of names will be considered stopwords
    INDEX_STOPWORD_WORD_FREQ_CUTOFF := 5000;
END;