/**
 * Function macro that performs a JOIN with the goal of blending matching
 * records.  "Blending" means choosing values from the LEFT or RIGHT
 * depending on whether values are actually present or not.  You can of course
 * do this manually by explicitly testing LEFT and RIGHT values during the
 * assignment to SELF for any particular attribute; this function macro
 * merely automates the creation of that per-attribute assignment for all
 * attributes in the result RECORD.
 *
 * LIMITATIONS
 *
 *  -   Embedded records and child datasets are not tested or even assigned;
 *      if any such records are in the result RECORD then they will be
 *      assigned empty values
 *  -   A string attribute (STRING, UNICODE, or UTF8) will be considered to
 *      not have a value if the length is zero
 *  -   A numeric attribute will be considered to not have a value if its
 *      value is zero
 *  -   A SET attribute will be considered to not have a value if it is empty
 *
 * @param   lhs                 The dataset that will be considered LEFT in
 *                              the JOIN; REQUIRED
 * @param   rhs                 The dataset that will be considered RIGHT in
 *                              the JOIN; REQUIRED
 * @param   joinConditionStr    The boolean test used to find matching records
 *                              records, expressed as a string; this should be
 *                              written as if it was included as a regular
 *                              JOIN condition, e.g. 'LEFT.id = RIGHT.id';
 *                              REQUIRED
 * @param   resultRec           The RECORD definition for the result of the
 *                              JOIN; REQUIRED
 * @param   joinFlagsStr        Flags for the JOIN, expressed as a string
 *                              (e.g. 'LEFT OUTER, LOCAL'); OPTIONAL, defaults
 *                              to an empty string
 * @param   prefer              A string indicating which dataset to prefer
 *                              when testing attribute values; valid values
 *                              are 'lhs' and 'rhs'; if a non-empty/zero value
 *                              is found in the preferred dataset then it will
 *                              be assigned to SELF, without testing the other
 *                              dataset; OPTIONAL, defaults to 'lhs'
 *
 * @return  A new dataset that is the result of the JOIN, with a resultRec
 *          RECORD definition
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
EXPORT BlendJoin(lhs, rhs, joinConditionStr, resultRec, joinFlagsStr = '\'\'', prefer = '\'lhs\'') := FUNCTIONMACRO
    LOADXML('<xml/>');
    #EXPORTXML(resultFields, resultRec);
    #EXPORTXML(lhsFields, RECORDOF(lhs));
    #EXPORTXML(rhsFields, RECORDOF(rhs));
    #UNIQUENAME(needsDelim);

    // Setup our preferred LEFT and RIGHT
    #UNIQUENAME(prefDS);
    #UNIQUENAME(altDS);
    #IF(prefer = 'rhs')
        #SET(prefDS, 'RIGHT')
        #SET(altDS, 'LEFT')
    #ELSE
        #SET(prefDS, 'LEFT')
        #SET(altDS, 'RIGHT')
    #END

    // Make a SET containing all of the valid attribute names from lhs
    #SET(needsDelim, 0);
    #UNIQUENAME(lshFieldSet);
    LOCAL %lshFieldSet% :=
        [
            #FOR(lhsFields)
                #FOR(field)
                    #IF(%{@isRecord}% = 0 AND %{@isDataset}% = 0 AND %{@isEnd}% = 0)
                        #IF(%needsDelim% = 1) , #END
                        %'@name'%
                        #SET(needsDelim, 1)
                    #END
                #END
            #END
        ];

    // Make a SET containing all of the valid attribute names from rhs
    #SET(needsDelim, 0);
    #UNIQUENAME(rshFieldSet);
    LOCAL %rshFieldSet% :=
        [
            #FOR(rhsFields)
                #FOR(field)
                    #IF(%{@isRecord}% = 0 AND %{@isDataset}% = 0 AND %{@isEnd}% = 0)
                        #IF(%needsDelim% = 1) , #END
                        %'@name'%
                        #SET(needsDelim, 1)
                    #END
                #END
            #END
        ];

    // Helper functions
    #UNIQUENAME(IsLHSField);
    LOCAL %IsLHSField%(STRING f) := f IN %lshFieldSet%;

    #UNIQUENAME(IsRHSField);
    LOCAL %IsRHSField%(STRING f) := f IN %rshFieldSet%;

    #UNIQUENAME(IsSharedField);
    LOCAL %IsSharedField%(STRING f) := %IsLHSField%(f) AND %IsRHSField%(f);

    #UNIQUENAME(GeneralType);
    LOCAL %GeneralType%(STRING typeStr) := MAP
        (
            typeStr[..7] = 'set of '    =>  's',
            typeStr[..6] = 'string'     =>  'c',
            typeStr[..7] = 'unicode'    =>  'c',
            typeStr[..4] = 'utf8'       =>  'c',
            'n'
        );

    // Build the actual JOIN
    #UNIQUENAME(joinResult);
    LOCAL %joinResult% := JOIN
        (
            lhs,
            rhs,
            #EXPAND(joinConditionStr),
            TRANSFORM
                (
                    resultRec,
                    #FOR(resultFields)
                        #FOR(field)
                            #IF(%{@isRecord}% = 0 AND %{@isDataset}% = 0 AND %{@isEnd}% = 0)
                                #IF(%IsSharedField%(%'@name'%))
                                    #IF(%GeneralType%(%'@type'%) = 's')
                                        SELF.%@name% := (%@type%)(IF(%prefDS%.%@name% != [], %prefDS%.%@name%, %altDS%.%@name%)),
                                    #ELSEIF(%GeneralType%(%'@type'%) = 'c')
                                        SELF.%@name% := (%@type%)(IF(TRIM((STRING)%prefDS%.%@name%, LEFT, RIGHT) != '', %prefDS%.%@name%, %altDS%.%@name%)),
                                    #ELSEIF(%GeneralType%(%'@type'%) = 'n')
                                        SELF.%@name% := (%@type%)(IF(%prefDS%.%@name% != 0, %prefDS%.%@name%, %altDS%.%@name%)),
                                    #END
                                #ELSEIF(%IsLHSField%(%'@name'%))
                                    SELF.%@name% := LEFT.%@name%,
                                #ELSEIF(%IsRHSField%(%'@name'%))
                                    SELF.%@name% := RIGHT.%@name%,
                                #END
                            #END
                        #END
                    #END
                    SELF := []
                )
            #IF(joinFlagsStr != '')
                , #EXPAND(joinFlagsStr)
            #END
        );

    RETURN %joinResult%;
ENDMACRO;

/*******************************************************************************

// Example code

Rec1 := RECORD
    UNSIGNED4   id;
    STRING      fname;
    STRING      mname;
    STRING      lname;
    UNSIGNED8   account_number := 0;
END;

ds1 := DATASET
    (
        [
            {1, 'Dan', 'S', 'Camper'},
            {2, 'John', '', 'Public', 9876}
        ],
        Rec1
    );

Rec2 := RECORD
    UNSIGNED4   id;
    STRING      fname;
    STRING      lname;
    UNSIGNED8   account_number;
END;

ds2 := DATASET
    (
        [
            {1, '', 'Campbell', 1234}
        ],
        Rec2
    );

//-------------------------------------------

preferLHS := BlendJoin
    (
        NOFOLD(ds1),
        NOFOLD(ds2),
        'LEFT.id = RIGHT.id',
        Rec1,
        joinFlagsStr := 'LEFT OUTER',
        prefer := 'lhs'
    );

OUTPUT(preferLHS, NAMED('BlendJoin_preferLHS'));

// id   fname   mname   lname       account_number
// 1    Dan     S       Camper      1234
// 2    John            Public      9876

preferRHS := BlendJoin
    (
        NOFOLD(ds1),
        NOFOLD(ds2),
        'LEFT.id = RIGHT.id',
        Rec1,
        joinFlagsStr := 'LEFT OUTER',
        prefer := 'rhs'
    );

OUTPUT(preferRHS, NAMED('BlendJoin_preferRHS'));

// id   fname   mname   lname       account_number
// 1    Dan     S       Campbell    1234
// 2    John            Public      9876

*******************************************************************************/
