IMPORT Std;

#WORKUNIT('name', 'fuzzy_person_name_match');

//-----------------------------------------------------------------------------
// This code is intended to be compiled and published under Roxie
//-----------------------------------------------------------------------------

IMPORT $.^.^ AS Root;
IMPORT $.^ AS Home;

//-----------------------------------------------------------------------------

UTF8        firstName := '' : STORED('first_name', FORMAT(SEQUENCE(100)));
UTF8        middleName := '' : STORED('middle_name', FORMAT(SEQUENCE(200)));
UTF8        lastName := '' : STORED('last_name', FORMAT(SEQUENCE(300)));
INTEGER1    minScore := 0 : STORED('min_score', FORMAT(SEQUENCE(400)));
BOOLEAN     onlyDirect := FALSE : STORED('only_direct_matches', FORMAT(SEQUENCE(500)));
INTEGER2    pageNum := 1 : STORED('page_num', FORMAT(SEQUENCE(600)));
INTEGER2    pageSize := 100 : STORED('page_size', FORMAT(SEQUENCE(700)));

clampedMinScore := MIN(MAX(minScore, 0), 100);
clampedPageNum := MAX(pageNum, 1);
clampedPageSize := MAX(pageSize, 1);

params := DATASET
    (
        [
            {'first_name', firstName},
            {'middle_name', middleName},
            {'last_name', lastName},
            {'min_score', (UTF8)clampedMinScore},
            {'only_direct_matches', IF(onlyDirect, u8'true', u8'false')},
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

fullName := firstName + ' ' + middleName + ' ' + lastName;

rawResults := Root.FuzzyNameMatch.BestMatches(fullName,
                                              Home.Constants.NAME_INDEX_PATH,
                                              Home.Constants.NAME_ID_INDEX_PATH,
                                              Home.Constants.ENTITY_ID_INDEX_PATH,
                                              CleanNameFunction := Home.CleanPersonName,
                                              AdaptedDistanceFunction := AdaptedDistance,
                                              maxDirectMatches := 2000);

rawResults2 := rawResults(score >= clampedMinScore AND (NOT(onlyDirect) OR is_match));
OUTPUT(COUNT(rawResults2), NAMED('total_found'));

sortedResults := TOPN(rawResults2, (clampedPageNum * clampedPageSize), -score, entity_guid, -is_match);

firstRec := (clampedPageNum -1) * clampedPageSize + 1;
OUTPUT(CHOOSEN(sortedResults, clampedPageSize, firstRec), NAMED('matches'), ALL);
