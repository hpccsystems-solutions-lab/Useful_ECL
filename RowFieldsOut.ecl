/***
 * Given a ROW of data, this simple macro outputs all top-level fields as
 * separate, named results.  The name of each output will be the same as the
 * field from which the value was taken, with an optional prefix.  This can be
 * handy when some fields have exceptionally long values and you are viewing
 * the results in ECL Watch.
 *
 * Because this is a MACRO, a series of OUTPUT(); statements will be generated
 * at the place where this macro is called.
 *
 * @param   oneRow  A single ROW of data (not a dataset); REQUIRED
 * @param   prefix  A string to prefix each output (which is normally just
 *                  the name fo the value's field); keep in mind that the prefix
 *                  must adhere to the limitations of a NAMED output string,
 *                  chiefly that it begins with a letter and contains no
 *                  spaces; OPTIONAL, defaults to an empty string
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
EXPORT RowFieldsOut(oneRow, prefix = '\'\'') := MACRO
    LOADXML('<xml/>');
    #EXPORTXML(rowFields, RECORDOF(oneRow));

    #UNIQUENAME(recLevel);
    #SET(recLevel, 0);

    #FOR(rowFields)
        #FOR(Field)
            #IF(%recLevel% = 0)
                OUTPUT(oneRow.%@name%, NAMED(prefix + %'@name'%));
            #END
            #IF(%{@isRecord}% = 1 OR %{@isDataset}% = 1)
                #SET(recLevel, %recLevel% + 1)
            #ELSEIF(%{@isEnd}% = 1)
                #SET(recLevel, %recLevel% - 1)
            #END
        #END
    #END
ENDMACRO;
