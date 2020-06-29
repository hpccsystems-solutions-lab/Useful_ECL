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
 *  -   Only top-level attributes are checked
 *  -   Embedded records and child datasets are not tested; they will be
 *      blindly assigned to the result from the 'prefer' argument value
 *  -   A string attribute (STRING, UNICODE, or UTF8) will be considered to
 *      not have a value if the length is zero
 *  -   DATA attributes will be considered to not have a value if their
 *      LENGTH is zero
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
 *                              JOIN; this definition must make contain
 *                              definitions for all attributes that are shared
 *                              between lhs and rhs, as well as any attribute
 *                              uniquely defined in the dataset identified
 *                              by the prefer argument; attributes found in
 *                              neither lhs or rhs may be included; REQUIRED
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
    #UNIQUENAME(recLevel);

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
    #SET(recLevel, 0);
    #UNIQUENAME(lshFieldSet);
    LOCAL %lshFieldSet% :=
        [
            #FOR(lhsFields)
                #FOR(field)
                    #IF(%{@isRecord}% = 1 OR %{@isDataset}% = 1)
                        #IF(%recLevel% = 0)
                            #IF(%needsDelim% = 1) , #END
                            %'@name'%
                            #SET(needsDelim, 1)
                        #END
                        #SET(recLevel, %recLevel% + 1)
                    #ELSEIF(%{@isEnd}% = 1)
                        #SET(recLevel, %recLevel% - 1)
                    #ELSEIF(%recLevel% = 0)
                        #IF(%needsDelim% = 1) , #END
                        %'@name'%
                        #SET(needsDelim, 1)
                    #END
                #END
            #END
        ];

    // Make a SET containing all of the valid attribute names from rhs
    #SET(needsDelim, 0);
    #SET(recLevel, 0);
    #UNIQUENAME(rshFieldSet);
    LOCAL %rshFieldSet% :=
        [
            #FOR(rhsFields)
                #FOR(field)
                    #IF(%{@isRecord}% = 1 OR %{@isDataset}% = 1)
                        #IF(%recLevel% = 0)
                            #IF(%needsDelim% = 1) , #END
                            %'@name'%
                            #SET(needsDelim, 1)
                        #END
                        #SET(recLevel, %recLevel% + 1)
                    #ELSEIF(%{@isEnd}% = 1)
                        #SET(recLevel, %recLevel% - 1)
                    #ELSEIF(%recLevel% = 0)
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
            typeStr[..9] = 'table of '                                  =>  'd', // child dataset
            typeStr[..7] = 'set of '                                    =>  's', // any kind of SET
            REGEXFIND('(unicode)|(utf)|(string)', typeStr)              =>  'c', // string-like
            REGEXFIND('data', typeStr)                                  =>  'x', // data
            typeStr = 'boolean'                                         =>  'b', // boolean
            REGEXFIND('(integer)|(unsigned)|(decimal)|(real)', typeStr) =>  'n', // numeric
            'r' // default is embedded record
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
                    #SET(recLevel, 0)
                    #FOR(resultFields)
                        #FOR(field)
                            #IF(%'@name'% != '' AND %recLevel% = 0)
                                #IF(%IsSharedField%(%'@name'%))
                                    #IF(%GeneralType%(%'@type'%) = 's')
                                        SELF.%@name% := (%@type%)(IF(%prefDS%.%@name% != [], %prefDS%.%@name%, %altDS%.%@name%)),
                                    #ELSEIF(%GeneralType%(%'@type'%) = 'c')
                                        SELF.%@name% := (%@type%)(IF(TRIM((STRING)%prefDS%.%@name%, LEFT, RIGHT) != '', %prefDS%.%@name%, %altDS%.%@name%)),
                                    #ELSEIF(%GeneralType%(%'@type'%) = 'n')
                                        SELF.%@name% := (%@type%)(IF(%prefDS%.%@name% != 0, %prefDS%.%@name%, %altDS%.%@name%)),
                                    #ELSEIF(%GeneralType%(%'@type'%) = 'b')
                                        SELF.%@name% := (%@type%)(%prefDS%.%@name%),
                                    #ELSEIF(%GeneralType%(%'@type'%) = 'x')
                                        SELF.%@name% := (%@type%)(IF(LENGTH(%prefDS%.%@name%) > 0, %prefDS%.%@name%, %altDS%.%@name%)),
                                    #ELSE
                                        // Child datasets and embedded child records
                                        SELF.%@name% := %prefDS%.%@name%,
                                    #END
                                #ELSEIF(%IsLHSField%(%'@name'%))
                                    SELF.%@name% := LEFT.%@name%,
                                #ELSEIF(%IsRHSField%(%'@name'%))
                                    SELF.%@name% := RIGHT.%@name%,
                                #END
                            #END
                            #IF(%{@isRecord}% = 1 OR %{@isDataset}% = 1)
                                #SET(recLevel, %recLevel% + 1)
                            #ELSEIF(%{@isEnd}% = 1)
                                #SET(recLevel, %recLevel% - 1)
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

IMPORT Useful_ECL;

PropRec := RECORD
    UNSIGNED1           cnt;
    STRING              desc;
END;

Rec1 := RECORD
    UNSIGNED4           id;
    STRING              fname;
    STRING              mname;
    STRING              lname;
    UNSIGNED8           account_number;
    DATASET(PropRec)    properties;
END;

ds1 := DATASET
    (
        [
            {1, 'Dan', 'S', 'Camper', 0, DATASET([{2, 'car'}], PropRec)},
            {2, 'John', '', 'Public', 9876, DATASET([], PropRec)}
        ],
        Rec1
    );

Rec2 := RECORD
    UNSIGNED4           id;
    STRING              fname;
    STRING              lname;
    UNSIGNED8           account_number;
    DATASET(PropRec)    properties;
END;

ds2 := DATASET
    (
        [
            {1, '', 'Campbell', 1234, DATASET([], PropRec)}
        ],
        Rec2
    );

//-------------------------------------------

preferLHS := Useful_ECL.BlendJoin
    (
        NOFOLD(ds1),
        NOFOLD(ds2),
        'LEFT.id = RIGHT.id',
        Rec1,
        joinFlagsStr := 'LEFT OUTER',
        prefer := 'lhs'
    );

OUTPUT(preferLHS, NAMED('BlendJoin_preferLHS'));

// id   fname   mname   lname       account_number      properties
//                                                      cnt desc
// 1    Dan     S       Camper      1234                2   car
// 2    John            Public      9876

//-------------------------------------------

preferRHS := Useful_ECL.BlendJoin
    (
        NOFOLD(ds1),
        NOFOLD(ds2),
        'LEFT.id = RIGHT.id',
        Rec1,
        joinFlagsStr := 'LEFT OUTER',
        prefer := 'rhs'
    );

OUTPUT(preferRHS, NAMED('BlendJoin_preferRHS'));

// id   fname   mname   lname       account_number      properties
//                                                      cnt desc
// 1    Dan     S       Campbell    1234
// 2    John            Public      9876

*******************************************************************************/
