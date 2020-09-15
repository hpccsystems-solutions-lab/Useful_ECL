/**
 * ECL's TABLE() function has two modes.  The more common mode is the
 * "CrossTab Report" form, which is an aggregation.  The other mode is a
 * "vertical slice" mode, which is a way of extracting a subset of fields
 * from a dataset.  The "vertical slice" mode has a limitation that
 * prevents you from citing a child dataset as one of the fields to
 * include in the result.
 *
 * This function macro codifies the workaround for that limitation, at
 * the expense of using a comma-delimited string instead of a record
 * definition for the second argument for TABLE().
 *
 * An example is included at the end of this file.
 *
 * @param   inFile          The dataset to slice; REQUIRED
 * @param   fieldListStr    A comma-delimited list of fields within
 *                          inFile that you would like to extract;
 *                          REQUIRED
 *
 * @return  A copy of inFile containing only those fields referenced
 *          in fieldListStr.
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
VerticalSlice(inFile, fieldListStr) := FUNCTIONMACRO
    #UNIQUENAME(needsDelim);
    #UNIQUENAME(fieldName);
    #UNIQUENAME(fieldNamePos);

    #UNIQUENAME(trimmedFieldList);
    LOCAL %trimmedFieldList% := TRIM((STRING)fieldListStr, ALL);

    RETURN TABLE
        (
            inFile,
            {
                #SET(needsDelim, 0)
                #SET(fieldNamePos, 1)
                #LOOP
                    #SET(fieldName, REGEXFIND('^([^,]+)', %trimmedFieldList%[%fieldNamePos%..], 1))
                    #IF(%'fieldName'% != '')
                        #IF(%needsDelim% = 1) , #END

                        TYPEOF(inFile.%fieldName%) %fieldName% := %fieldName%

                        #SET(needsDelim, 1)
                        #SET(fieldNamePos, %fieldNamePos% + LENGTH(%'fieldName'%) + 1)
                    #ELSE
                        #BREAK
                    #END
                #END
            }
        );
ENDMACRO;

/******************************************************************************
// Example:

ChildRec := {UNSIGNED1 age};

ParentRec := {STRING name, DATASET(ChildRec) ages};

ds0 := DATASET
    (
        5,
        TRANSFORM
            (
                ParentRec,
                SELF.name := 'blah',
                SELF.ages := DATASET
                    (
                        2,
                        TRANSFORM
                            (
                                ChildRec,
                                SELF.age := RANDOM() % 100 + 1
                            )
                    )
            )
    );

ds := NOFOLD(ds0);

res := VerticalSlice(ds, 'ages'); // Would be TABLE(ds, {ages}) if that worked

OUTPUT(res);

******************************************************************************/
