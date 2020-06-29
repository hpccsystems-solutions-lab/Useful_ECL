/**
 * Compute various statistics of a numeric field within groups within a dataset.
 * Sample code can be found at the end of the file.
 *
 * @param   inFile              The dataset to process; REQUIRED
 * @param   valueField          The name of the numeric field to use for all
 *                              calculations; this is not a STRING;
 *                              REQUIRED
 * @param   groupingFieldsStr   Comma-delimited STRING giving the fields
 *                              in which to group the data for the purpose
 *                              of calculating the median; cannot be an
 *                              empty string; REQUIRED
 * @param   maxModes            The maximum number of mode values to return;
 *                              OPTIONAL, defaults to 5
 *
 * @return  A new dataset that contains only the grouping fields and a
 *          set of numeric summaries for the values in that group.  The
 *          summary includes:
 *
 *              minimum
 *              maximum
 *              average
 *              median
 *              sum
 *              standard deviation
 *              modes (child dataset)
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
GroupedNumericStats(inFile, valueField, groupingFieldsStr, maxModes = 5) := FUNCTIONMACRO
    #UNIQUENAME(myGroupingFields);
    #SET(myGroupingFields, TRIM(groupingFieldsStr, ALL));

    #UNIQUENAME(leftGroupingFields);
    #SET(leftGroupingFields, REGEXREPLACE('(^|,)', %'myGroupingFields'%, '$1LEFT.'));

    #UNIQUENAME(ValueField_t);
    LOCAL %ValueField_t% := TYPEOF(inFile.valueField);

    #UNIQUENAME(slimFile);
    LOCAL %slimFile% := TABLE(UNGROUP(inFile), {%myGroupingFields%, valueField});

    #UNIQUENAME(ModeRec);
    LOCAL %ModeRec% := RECORD
        %ValueField_t%      valueField;
        UNSIGNED4           cnt;
    END;

    // Create the output dataset
    #UNIQUENAME(ResultRec);
    LOCAL %ResultRec% := RECORD
        RECORDOF(%slimFile%) - [valueField];
        %ValueField_t%      min_value;
        %ValueField_t%      max_value;
        %ValueField_t%      ave_value;
        REAL4               median_value;
        %ValueField_t%      sum_value;
        %ValueField_t%      std_dev_value;
        DATASET(%ModeRec%)  modes;
    END;

    #UNIQUENAME(DataRec);
    #UNIQUENAME(hashValue)
    LOCAL %DataRec% := RECORD
        UNSIGNED8   %hashValue%;
        RECORDOF(%slimFile%);
    END;

    // Assign a hash value for the group fields
    #UNIQUENAME(myDataPlusHash);
    LOCAL %myDataPlusHash% := PROJECT
        (
            %slimFile%,
            TRANSFORM
                (
                    %DataRec%,
                    SELF.%hashValue% := HASH64(%leftGroupingFields%),
                    SELF := LEFT
                )
        );

    // Distribute the data based on the hash
    #UNIQUENAME(distributedData);
    LOCAL %distributedData% := DISTRIBUTE(%myDataPlusHash%, %hashValue%);

    // Create a reduced dataset that contains only the unique values and the
    // number of times those values appear
    #UNIQUENAME(groupedCards);
    LOCAL %groupedCards% := TABLE
        (
            %distributedData%,
            {
                %hashValue%,
                valueField,
                UNSIGNED6   cnt := COUNT(GROUP),
                UNSIGNED6   valueEndPos := 0    // fill in later
            },
            %hashValue%, valueField,
            LOCAL
        );

    // Determine the position of the last record in the original dataset that
    // contains a particular value within the group
    #UNIQUENAME(groupedCards2);
    LOCAL %groupedCards2% := ITERATE
        (
            SORT(%groupedCards%, %hashValue%, valueField, LOCAL),
            TRANSFORM
                (
                    RECORDOF(LEFT),
                    SELF.valueEndPos := IF(LEFT.%hashValue% = RIGHT.%hashValue%, LEFT.valueEndPos + RIGHT.cnt, RIGHT.cnt),
                    SELF := RIGHT
                ),
            LOCAL
        );

    // Find the number of records in each group
    #UNIQUENAME(groupRecCounts);
    LOCAL %groupRecCounts% := TABLE
        (
            %groupedCards2%,
            {
                %hashValue%,
                UNSIGNED2   recCount := MAX(GROUP, valueEndPos)
            },
            %hashValue%,
            LOCAL
        );

    // Build a median info record
    #UNIQUENAME(GroupInfoRec);
    LOCAL %GroupInfoRec% := RECORD
        RECORDOF(%groupRecCounts%);
        UNSIGNED4       medianPos1;
        UNSIGNED4       medianPos2;
        %ValueField_t%  medianVal1;
        %ValueField_t%  medianVal2;
        %ValueField_t%  medianVal;
    END;

    // Compute the median positions in each group
    #UNIQUENAME(groupInfo);
    LOCAL %groupInfo% := PROJECT
        (
            %groupRecCounts%,
            TRANSFORM
                (
                    %GroupInfoRec%,

                    wholeHasEvenNumberOfElements := (LEFT.recCount % 2) = 0;

                    SELF.medianPos1 := IF
                        (
                            LEFT.recCount > 2,
                            LEFT.recCount DIV 2 + IF(wholeHasEvenNumberOfElements, 0, 1),
                            1
                        ),
                    SELF.medianPos2 := IF
                        (
                            LEFT.recCount > 2,
                            SELF.medianPos1 + IF(wholeHasEvenNumberOfElements, 1, 0),
                            LEFT.recCount
                        ),
                    SELF := LEFT,
                    SELF := []
                ),
            LOCAL
        );

    #UNIQUENAME(sequencedData);
    LOCAL %sequencedData% := SORT(%groupedCards2%, %hashValue%, valueEndPos, LOCAL);

    // Extract values of median positions
    #UNIQUENAME(j10);
    LOCAL %j10% := JOIN
        (
            %groupInfo%,
            %sequencedData%,
            LEFT.%hashValue% = RIGHT.%hashValue% AND RIGHT.valueEndPos >= LEFT.medianPos1,
            TRANSFORM
                (
                    %GroupInfoRec%,
                    SELF.medianVal1 := RIGHT.valueField,
                    SELF := LEFT
                ),
            LOCAL, NOSORT, KEEP(1)
        );

    #UNIQUENAME(j20);
    LOCAL %j20% := JOIN
        (
            %j10%,
            %sequencedData%,
            LEFT.%hashValue% = RIGHT.%hashValue% AND RIGHT.valueEndPos >= LEFT.medianPos2,
            TRANSFORM
                (
                    %GroupInfoRec%,
                    SELF.medianVal2 := RIGHT.valueField,
                    SELF := LEFT
                ),
            LOCAL, NOSORT, KEEP(1)
        );

    // Compute median values
    #UNIQUENAME(finalGroupInfo);
    LOCAL %finalGroupInfo% := PROJECT
        (
            %j20%,
            TRANSFORM
                (
                    %GroupInfoRec%,
                    SELF.medianVal := AVE(LEFT.medianVal1, LEFT.medianVal2),
                    SELF := LEFT
                ),
            LOCAL
        );

    // Group for mode determination
    #UNIQUENAME(groupedData);
    LOCAL %groupedData% := GROUP(SORT(%groupedCards%, %hashValue%, LOCAL), %hashValue%, LOCAL);

    #UNIQUENAME(topGroupedData);
    LOCAL %topGroupedData% := TOPN(%groupedData%, (UNSIGNED1)maxModes, -cnt);

    #UNIQUENAME(topRecord);
    LOCAL %topRecord% := TOPN(%topGroupedData%, 1, -cnt);

    #UNIQUENAME(modeValues);
    LOCAL %modeValues% := JOIN
        (
            UNGROUP(%topGroupedData%),
            UNGROUP(%topRecord%),
            LEFT.%hashValue% = RIGHT.%hashValue% AND LEFT.cnt = RIGHT.cnt,
            TRANSFORM(LEFT),
            LOCAL
        );

    // Easy stuff done in one TABLE call
    #UNIQUENAME(finalPrep);
    LOCAL %finalPrep% := TABLE
        (
            %distributedData%,
            {
                %myGroupingFields%,
                %hashValue%,
                %ValueField_t%      min_value := MIN(GROUP, valueField),
                %ValueField_t%      max_value := MAX(GROUP, valueField),
                %ValueField_t%      ave_value := AVE(GROUP, valueField),
                %ValueField_t%      sum_value := SUM(GROUP, valueField),
                %ValueField_t%      std_dev_value := SQRT(VARIANCE(GROUP, valueField))
            },
            %myGroupingFields%, %hashValue%,
            LOCAL
        );

    // Start combining results
    #UNIQUENAME(final10);
    LOCAL %final10% := JOIN
        (
            %finalPrep%,
            %finalGroupInfo%,
            LEFT.%hashValue% = RIGHT.%hashValue%,
            TRANSFORM
                (
                    {
                        UNSIGNED8   %hashValue%,
                        %ResultRec%,
                    },
                    SELF.median_value := RIGHT.medianVal,
                    SELF := LEFT,
                    SELF := []
                ),
            LOCAL, LEFT OUTER
        );

    #UNIQUENAME(final20);
    LOCAL %final20% := DENORMALIZE
        (
            %final10%,
            %modeValues%,
            LEFT.%hashValue% = RIGHT.%hashValue%,
            GROUP,
            TRANSFORM
                (
                    RECORDOF(LEFT),
                    SELF.modes := PROJECT(ROWS(RIGHT), TRANSFORM(%ModeRec%, SELF.valueField := LEFT.v, SELF.cnt := LEFT.cnt)),
                    SELF := LEFT
                ),
            LOCAL, LEFT OUTER
        );

    #UNIQUENAME(finalResults);
    LOCAL %finalResults% := %final20%;

    RETURN PROJECT(%finalResults%, %ResultRec%);
ENDMACRO;

/******************************************************************************

DataRec := RECORD
    UNSIGNED1   g;
    UNSIGNED2   v;
END;

ds0 := DATASET
    (
        [
            {1, 45},
            {1, 62},
            {1, 45},
            {1, 3},
            {1, 56},
            {2, 46},
            {2, 121},
            {2, 47},
            {2, 299},
            {2, 67}
        ],
        DataRec
    );

ds := NOFOLD(ds0);

res := GroupedNumericStats(ds, v, 'g', maxModes := 2);
OUTPUT(res);

*/
