/***
 * Given a dataset, this function macro returns a string composed of record
 * attribute names separated by the given delimiter.  This string can be used
 * as a header line for a CSV output.
 *
 * Field names from child datasets will be included in the output in standard
 * xxx.yyy.zzz syntax.  This, however, may not match the actual output of the
 * data.  Callers should review the output and compare it with the data that
 * will be written.
 *
 * @param   inFile      The dataset to process; REQUIRED
 * @param   delim       The string delimiter to separate column names;
 *                      OPTIONAL, defaults to a comma (',')
 *
 * @return  Single STRING value composed of record attribute names separated
 *          by the given delimiter string.  If you intend to use this result
 *          as a CSV(HEADING()) parameter then remember to concatenate a
 *          linefeed (\n).
 */
EXPORT CSVHeaderStrForDataset(inFile, delim = '\',\'') := FUNCTIONMACRO
    LOADXML('<xml/>');
    #DECLARE(prefixStr);
    #SET(prefixStr, '');
    #DECLARE(fieldStr);
    #SET(fieldStr, '');
    #EXPORTXML(inFileFields, RECORDOF(inFile));
    
    #FOR(inFileFields)
        #FOR(field)
            #IF(%{@isRecord}% = 1 OR %{@isDataset}% = 1)
                #SET(prefixStr, %'prefixStr'% + %'{@label}'% + '.')
            #ELSEIF(%{@isEnd}% = 1)
                #SET(prefixStr, REGEXFIND('^(.*\\.)?[^.]+\\.', %'prefixStr'%, 1, NOCASE))
            #ELSE
                #IF(%'fieldStr'% != '')
                    #APPEND(fieldStr, delim)
                #END
                #APPEND(fieldStr, %'prefixStr'% + %'{@name}'%)
            #END
        #END
    #END
    
    RETURN %'fieldStr'%;
ENDMACRO;
