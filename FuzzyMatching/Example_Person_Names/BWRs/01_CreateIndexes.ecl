IMPORT Std;

#WORKUNIT('name', 'Fuzzy Person Name Index Build');

//-----------------------------------------------------------------------------
// This code is intended to be executed under Thor
//-----------------------------------------------------------------------------

IMPORT $.^.^ AS Root;
IMPORT $.^ AS Home;

//-----------------------------------------------------------------------------

RAW_DATA_PATH := Home.Constants.PATH_PREFIX + '::person_namelist.csv';
rawData := DATASET(RAW_DATA_PATH, Root.Files.CommonRawDataLayout, CSV(UNICODE));

//-----------------------------------------------------------------------------

UNSIGNED1 AdaptedDistance(UTF8 s) := FUNCTION
    textLen := LENGTH(s);
    RETURN MAP
        (
            textLen < 3     => 0,
            textLen < 9     => 1,
            textLen < 13    => 2,
            textLen < 21    => 3,
            0
        );
END;

//-----------------------------------------------------------------------------

Root.FuzzyNameMatch.Build(rawData,
                          Home.Constants.NAME_INDEX_PATH,
                          Home.Constants.NAME_ID_INDEX_PATH,
                          Home.Constants.ENTITY_ID_INDEX_PATH,
                          CleanNameFunction := Home.CleanPersonName,
                          AdaptedDistanceFunction := AdaptedDistance);
