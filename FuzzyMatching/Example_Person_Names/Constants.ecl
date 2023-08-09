EXPORT Constants := MODULE
    EXPORT PATH_PREFIX := '~fuzzy_match';

    EXPORT STOPWORD_PATH := PATH_PREFIX + '::person::stopwords';
    EXPORT NAME_INDEX_PATH := PATH_PREFIX + '::person::name.idx';
    EXPORT NAME_ID_INDEX_PATH := PATH_PREFIX + '::person::nameid.idx';
    EXPORT ENTITY_ID_INDEX_PATH := PATH_PREFIX + '::person::entityid.idx';
END;