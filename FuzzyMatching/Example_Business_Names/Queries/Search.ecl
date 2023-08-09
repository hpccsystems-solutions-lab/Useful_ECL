IMPORT Std;

#WORKUNIT('name', 'fuzzy_business_name_match');

//-----------------------------------------------------------------------------
// This code is intended to be compiled and published under Roxie
//-----------------------------------------------------------------------------

IMPORT $.^.^ AS Root;
IMPORT $.^ AS Home;

//-----------------------------------------------------------------------------

UTF8        businessName := '' : STORED('business_name', FORMAT(SEQUENCE(100)));
INTEGER1    minScore := 0 : STORED('min_score', FORMAT(SEQUENCE(200)));
BOOLEAN     onlyDirect := FALSE : STORED('only_direct_matches', FORMAT(SEQUENCE(300)));
INTEGER2    pageNum := 1 : STORED('page_num', FORMAT(SEQUENCE(400)));
INTEGER2    pageSize := 100 : STORED('page_size', FORMAT(SEQUENCE(500)));

clampedMinScore := MIN(MAX(minScore, 0), 100);
clampedPageNum := MAX(pageNum, 1);
clampedPageSize := MAX(pageSize, 1);

params := DATASET
    (
        [
            {'business_name', businessName},
            {'only_direct_matches', IF(onlyDirect, u8'true', u8'false')},
            {'min_score', (UTF8)clampedMinScore},
            {'page_num', (UTF8)clampedPageNum},
            {'page_size', (UTF8)clampedPageSize}
        ],
        {STRING parameter, UTF8 value}
    );
OUTPUT(params, NAMED('echo'));

UNSIGNED1 AdaptedDistance(UTF8 s) := FUNCTION
    textLen := LENGTH(s);
    RETURN MAP
        (
            textLen < 3     => 0,
            textLen < 21    => 1,
            0
        );
END;

WordsOnStopList(STRING stopwordIndexPath, UTF8 queryStr) := FUNCTION
    RETURN JOIN
        (
            Root.Files.StopwordDS(stopwordIndexPath),
            Root.FuzzyNameMatch.MakeWordDS(Home.CleanBusinessName(queryStr)),
            LEFT.word = RIGHT.word,
            TRANSFORM(LEFT)
        );
END;

OUTPUT(WordsOnStopList(Home.Constants.STOPWORD_PATH, businessName), NAMED('query_words_on_index_stoplist'));

rawResults := Root.FuzzyNameMatch.BestMatches(businessName,
                                              Home.Constants.NAME_INDEX_PATH,
                                              Home.Constants.NAME_ID_INDEX_PATH,
                                              Home.Constants.ENTITY_ID_INDEX_PATH,
                                              CleanNameFunction := Home.CleanBusinessName,
                                              AdaptedDistanceFunction := AdaptedDistance,
                                              stopwordPath := Home.Constants.STOPWORD_PATH);

rawResults2 := rawResults(score >= clampedMinScore AND (NOT(onlyDirect) OR is_match));
OUTPUT(COUNT(rawResults2), NAMED('total_found'));

sortedResults := TOPN(rawResults2, (clampedPageNum * clampedPageSize), -score, entity_guid, -is_match);

firstRec := (clampedPageNum -1) * clampedPageSize + 1;
OUTPUT(CHOOSEN(sortedResults, clampedPageSize, firstRec), NAMED('matches'), ALL);
