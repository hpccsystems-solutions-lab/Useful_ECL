/***
 * Given a recordset, this function macro returns a new recordset containing
 * only top-level attributes (other than SET OF fields) that have been converted
 * to newDataType data type.  Top-level SET OF attributes, embedded records and
 * child datasets are ignored and not included in the output.
 *
 * @param   inFile          The recordset to process; REQUIRED
 * @param   newDataType     The datatype to coerce all top-level attributes to,
 *                          expressed as a string; OPTIONAL, defaults to 'STRING'
 *
 * @return  The new recordset
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
EXPORT ConvertTopLevelFieldsToNewDataType(inFile, newDataType = '\'STRING\'') := FUNCTIONMACRO
    IMPORT Std;

    LOADXML('<xml/>');
    #UNIQUENAME(recLevel);
    #UNIQUENAME(needsDelim);
    #SET(needsDelim, 0);
    #EXPORTXML(inFileFields, RECORDOF(inFile))

    LOCAL outLayout := RECORD
        #SET(recLevel, 0)
        #FOR(inFileFields)
            #FOR(Field)
                #IF(%{@isRecord}% = 1 OR %{@isDataset}% = 1)
                    #SET(recLevel, %recLevel% + 1)
                #ELSEIF(%{@isEnd}% = 1)
                    #SET(recLevel, %recLevel% - 1)
                #ELSEIF(%recLevel% = 0)
                    #IF(%'@type'%[..7] != 'set of ')
                        #EXPAND(newDataType)  %@name%;
                    #END
                #END
            #END
        #END
    END;

    LOCAL outFile := PROJECT
        (
            inFile,
            TRANSFORM
                (
                    outLayout,
                    #SET(recLevel, 0)
                    #FOR(inFileFields)
                        #FOR(Field)
                            #IF(%{@isRecord}% = 1 OR %{@isDataset}% = 1)
                                #SET(recLevel, %recLevel% + 1)
                            #ELSEIF(%{@isEnd}% = 1)
                                #SET(recLevel, %recLevel% - 1)
                            #ELSEIF(%recLevel% = 0)
                                #IF(%'@type'%[..7] != 'set of ')
                                    #IF(%needsDelim% = 1) , #END
                                    #EXPAND('SELF.' + %'@name'%) := (#EXPAND(newDataType))#EXPAND('LEFT.' + %'@name'%)
                                    #SET(needsDelim, 1)
                                #END
                            #END
                        #END
                    #END
                )
        );

    RETURN outFile;
ENDMACRO;
