/**
 * When working with a dataset that is periodically refreshed, but you need to
 * retain the history of old values, a common scheme for tracking such changes
 * is to append a "date first seen" and a "date last seen" attribute to each
 * record.  The implication here is that the other values in the record are
 * valid during the timeframe defined by those two dates.  By appending this
 * "valid date range" information, you can construct queries using "as of dates"
 * to find historical information.  This function macro assists in the
 * management of that date range.
 *
 * This function will append and manage three additional attributes to the
 * original data you provide.  You must provide the names of those attributes,
 * so as to ensure that they make sense with respect to the other attributes
 * in the dataset, but the data types of those attributes are defined within
 * this function macro.  Those additional attributes are:
 *
 *  -   uniqueIDField (UNSIGNED4):  A constructed numeric identifier that
 *      should be globally unique within the dataset
 *  -   dateFirstSeenField (Std.Date.Date_t):  The date the exact contents of
 *      the record were first seen, in YYYYMMDD numeric format
 *  -   dateLastSeenField (Std.Date.Date_t):  The date the exact contents of the
 *      record were last seen, in YYYYMMDD numeric format
 *
 * The function is normally invoked with both a new dataset and an old dataset.
 * The old dataset must have the three attributes defined above already present.
 * It is not required that the new dataset have those attributes (they will be
 * added if needed).  An old dataset is actually optional; if not provided,
 * the net effect is to initialize the new dataset with the three additional
 * attributes set to appropriate values.
 *
 * Dates inserted into the resulting dataset are typically based around the
 * asOfDate argument value.  There is a special case, however:  If an old
 * record has been replaced with new data, then then old record's
 * lastSeenDateField value will be updated to "yesterday's" date, defined as
 * the date one day prior to the asOfDate given to the function.  Doing this
 * relaxes an update requirement:  Specifically, you can run this update
 * function only periodically and the ranges described by the first/last seen
 * dates will not have gaps, when viewing a collection of entity records
 * and their changes.
 *
 * REQUIREMENTS
 *
 *  -   Each record in the dataset represents an entity of some kind, or at
 *      least a collection of related values, and that entity is identified
 *      by a value in a single attribute ('entityIDField' in the code); this
 *      entity ID value is used to find records between the old and new datasets
 *      that are supposed to match; the entity ID value is assumed to be
 *      unique within the newFile dataset
 *
 * There is sample code at the end of this file.
 *
 * @param   newFile             The dataset containing new data to process;
 *                              REQUIRED
 * @param   entityIDField       The name of the attribute containing the
 *                              identifier for collection of data within the
 *                              record; this is not a string; within newFile,
 *                              the values within this attribute are assumed
 *                              to be unique; REQUIRED
 * @param   dateFirstSeenField  The name of the attribute that will contain
 *                              the date that exact combination of values within
 *                              the record were first seen; this is not a string;
 *                              OPTIONAL, defaults to dt_first_seen
 * @param   dateLastSeenField   The name of the attribute that will contain
 *                              the date that exact combination of values within
 *                              the record were last seen; this is not a string;
 *                              OPTIONAL, defaults to dt_last_seen
 * @param   uniqueIDField       The name of the attribute that will contain
 *                              a globally unique identifier for the record
 *                              (this function manages the values); this is
 *                              not a string; OPTIONAL, defaults to gid
 * @param   origFile            The dataset containing the previous data that
 *                              will be merged with newFile; in general, this
 *                              dataset's record definition should be the same
 *                              as newFile with the three additional attributes
 *                              added; OPTIONAL, defaults to an empty dataset
 * @param   asOfDate            The date value to use when updating
 *                              dateFirstSeenField and dateLastSeenField values;
 *                              OPTIONAL, defaults to the current date
 *
 * @return  A new dataset with the same structure as newFile but with the
 *          three additional tracking attributes (described above)
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
EXPORT WholeUpdate(newFile,
                   entityIDField,
                   dateFirstSeenField = 'dt_first_seen',
                   dateLastSeenField = 'dt_last_seen',
                   uniqueIDField = 'gid',
                   origFile = '',
                   asOfDate = 0) := FUNCTIONMACRO
    IMPORT Std;

    // Define our working dates and mark them independent to avoid
    // recalculating them
    LOCAL workingDate := IF(asOfDate = 0, Std.Date.Today(), asOfDate) : INDEPENDENT;
    LOCAL priorWorkingDate := Std.Date.AdjustDate(workingDate, day_delta := -1) : INDEPENDENT;

    // Use either a given old file or construct an empty dataset in the
    // correct format
    LOCAL workingOrigFile := #IF(#TEXT(origFile) != '')
                                origFile
                             #ELSE
                                DATASET
                                    (
                                        [],
                                        {
                                            RECORDOF(newFile),
                                            UNSIGNED4       uniqueIDField,
                                            Std.Date.Date_t dateFirstSeenField,
                                            Std.Date.Date_t dateLastSeenField
                                        }
                                    )
                             #END;

    // Distribute data so we can work on everything locally from here on out
    LOCAL origFileDistributed := DISTRIBUTE(workingOrigFile, HASH32(entityIDField));
    LOCAL newFileDistributed := DISTRIBUTE(newFile, HASH32(entityIDField));

    // Carve out the latest version of every record for entityIDField
    LOCAL latestOrigFileRecs1 := UNGROUP(TOPN(GROUP(SORT(origFileDistributed, entityIDField, LOCAL), entityIDField, LOCAL), 1, -dateLastSeenField));

    // Peel off the older original records; we will concatenate them with
    // the result
    LOCAL olderOrigFileRecs := JOIN
        (
            origFileDistributed,
            latestOrigFileRecs1,
            LEFT.uniqueIDField = RIGHT.uniqueIDField,
            TRANSFORM(LEFT),
            LEFT ONLY, LOCAL
        );

    // Find latest original records that have no match in the new file; these
    // are deleted entity records and will also be concatenated with the result
    LOCAL deletedLatestOrigFileRecs := JOIN
        (
            latestOrigFileRecs1,
            newFileDistributed,
            LEFT.entityIDField = RIGHT.entityIDField,
            TRANSFORM(LEFT),
            LEFT ONLY, LOCAL
        );

    // Remove deleted records from the latest original record list; all records
    // here should have matching entityIDField values in the newFile;
    LOCAL latestOrigFileRecs2 := JOIN
        (
            latestOrigFileRecs1,
            deletedLatestOrigFileRecs,
            LEFT.entityIDField = RIGHT.entityIDField,
            TRANSFORM(LEFT),
            LEFT ONLY, LOCAL
        );

    // Find new records that aren't in the original file; these will also be
    // concatenated with the result
    LOCAL newRecords := JOIN
        (
            newFileDistributed,
            latestOrigFileRecs2,
            LEFT.entityIDField = RIGHT.entityIDField,
            TRANSFORM
                (
                    RECORDOF(RIGHT),
                    SELF.entityIDField := LEFT.entityIDField,
                    SELF.dateFirstSeenField := workingDate,
                    SELF.dateLastSeenField := workingDate,
                    SELF.uniqueIDField := HASH32(SELF.entityIDField, SELF.dateFirstSeenField),
                    SELF := LEFT
                ),
            LEFT ONLY, LOCAL
        );

    // For each entityID in the new file, determine if there are any differences
    // as compared to the latest records from the old file
    LOCAL differences := JOIN
        (
            newFileDistributed,
            latestOrigFileRecs2,
            LEFT.entityIDField = RIGHT.entityIDField,
            TRANSFORM
                (
                    {
                        TYPEOF(RIGHT.entityIDField)     entityIDField,
                        BOOLEAN                         foundDiff
                    },

                    diffFields := ROWDIFF(LEFT, RIGHT);
                    diffWithoutTrackingFields := REGEXREPLACE('(\\b' + #TEXT(uniqueIDField) + '\\b)|(\\b' + #TEXT(dateFirstSeenField) + '\\b)|(\\b' + #TEXT(dateLastSeenField) + '\\b)', diffFields, ',', NOCASE);
                    withoutCommaRuns := REGEXREPLACE(',,+', diffWithoutTrackingFields, ',');
                    withoutBoundingCommas := REGEXREPLACE('(^,)|(,$)', withoutCommaRuns, '');

                    SELF.entityIDField := LEFT.entityIDField,
                    SELF.foundDiff := withoutBoundingCommas != ''
                ),
            LOCAL, LOOKUP
        );

    // Original records that are unchanged in the new file; update the
    // dateLastSeen field; these will be concatenated with the final result
    LOCAL originalUnchanged := JOIN
        (
            latestOrigFileRecs2,
            differences(NOT foundDiff),
            LEFT.entityIDField = RIGHT.entityIDField,
            TRANSFORM
                (
                    RECORDOF(LEFT),
                    SELF.dateLastSeenField := workingDate,
                    SELF := LEFT
                ),
            LOCAL, LOOKUP
        );

    // Original records that have changed; we need to extract them and add
    // them unchanged to the result; update the last seen date to the day
    // prior to the as-of date
    LOCAL originalUpdated := JOIN
        (
            latestOrigFileRecs2,
            differences(foundDiff),
            LEFT.entityIDField = RIGHT.entityIDField,
            TRANSFORM
                (
                    RECORDOF(LEFT),
                    SELF.dateLastSeenField := priorWorkingDate,
                    SELF := LEFT
                ),
            LOCAL, LOOKUP
        );

    // Updates to existing records; create new records with the updated data
    // and concatenate to the final result
    LOCAL originalUpdatedNew := JOIN
        (
            newFileDistributed,
            differences(foundDiff),
            LEFT.entityIDField = RIGHT.entityIDField,
            TRANSFORM
                (
                    RECORDOF(workingOrigFile),
                    SELF.entityIDField := LEFT.entityIDField,
                    SELF.dateFirstSeenField := workingDate,
                    SELF.dateLastSeenField := workingDate,
                    SELF.uniqueIDField := HASH32(SELF.entityIDField, SELF.dateFirstSeenField),
                    SELF := LEFT
                ),
            LOCAL, LOOKUP
        );

    LOCAL finalResult := olderOrigFileRecs
                            + deletedLatestOrigFileRecs
                            + newRecords
                            + originalUnchanged
                            + originalUpdated
                            + originalUpdatedNew;

    RETURN finalResult;
ENDMACRO;

/*==============================================================================

// Sample BWR code

IMPORT Useful_ECL;

#WORKUNIT('name', 'WholeUpdate testing');

DataRec := RECORD
    UNSIGNED1           entityID;
    STRING              fname;
    STRING              lname;
END;

//--------------------------------------------------

// Initial run

test1 := DATASET
    (
        [
            {1, 'Dan', 'Camper'},
            {2, 'John', 'Doe'}
        ],
        DataRec
    );

res1 := Useful_ECL.WholeUpdate
    (
        NOFOLD(test1),
        entityID,
        asOfDate := 20180101
    );
OUTPUT(SORT(res1, entityID, dt_first_seen), NAMED('as_of_20180101'));

//--------------------------------------------------

// Change only first name of entity 1

test2 := DATASET
    (
        [
            {1, 'Daniel', 'Camper'},
            {2, 'John', 'Doe'}
        ],
        DataRec
    );

res2 := Useful_ECL.WholeUpdate
    (
        NOFOLD(test2),
        entityID,
        origFile := res1,
        asOfDate := 20180102
    );
OUTPUT(SORT(res2, entityID, dt_first_seen), NAMED('as_of_20180102'));

//--------------------------------------------------

// Change only first name of entity 2

test3 := DATASET
    (
        [
            {1, 'Daniel', 'Camper'},
            {2, 'Johnny', 'Doe'}
        ],
        DataRec
    );

res3 := Useful_ECL.WholeUpdate
    (
        NOFOLD(test3),
        entityID,
        origFile := res2,
        asOfDate := 20180201
    );
OUTPUT(SORT(res3, entityID, dt_first_seen), NAMED('as_of_20180201'));

//--------------------------------------------------

// Everything unchanged

test4 := DATASET
    (
        [
            {1, 'Daniel', 'Camper'},
            {2, 'Johnny', 'Doe'}
        ],
        DataRec
    );

res4 := Useful_ECL.WholeUpdate
    (
        NOFOLD(test4),
        entityID,
        origFile := res3,
        asOfDate := 20180202
    );
OUTPUT(SORT(res4, entityID, dt_first_seen), NAMED('as_of_20180202'));

//--------------------------------------------------

// Delete entity 1

test5 := DATASET
    (
        [
            {2, 'Johnny', 'Doe'}
        ],
        DataRec
    );

res5 := Useful_ECL.WholeUpdate
    (
        NOFOLD(test5),
        entityID,
        origFile := res4,
        asOfDate := 20180203
    );
OUTPUT(SORT(res5, entityID, dt_first_seen), NAMED('as_of_20180203'));

//--------------------------------------------------

// Add entity 3

test6 := DATASET
    (
        [
            {2, 'Johnny', 'Doe'},
            {3, 'Jane', 'Doe'}
        ],
        DataRec
    );

res6 := Useful_ECL.WholeUpdate
    (
        NOFOLD(test6),
        entityID,
        origFile := res5
    );
OUTPUT(SORT(res6, entityID, dt_first_seen), NAMED('as_of_today'));
==============================================================================*/
