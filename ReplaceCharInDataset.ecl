/***
 * Find-and-replace within all string, unicode and UTF-8 fields within a dataset.
 * Note that child datasets and embedded records are skipped (so, only the
 * top level of the input dataset is processed).
 *
 * @param   inFile          The dataset to process; REQUIRED
 * @param   target          The string you want to search for; REQUIRED
 * @param   replacement     The string to replace target with; can be an
 *                          empty string, which will delete target; REQUIRED
 *
 * @return  The input dataset with the find-and-replace actions performed
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
EXPORT ReplaceCharInDataset(inFile, target, replacement) := FUNCTIONMACRO
    IMPORT Std;

    LOADXML('<xml/>');
    #UNIQUENAME(recLevel);
    #SET(recLevel, 0);
    #EXPORTXML(inFileFields, RECORDOF(inFile))

    RETURN PROJECT
        (
            inFile,
            TRANSFORM
                (
                    RECORDOF(inFile),
                    #FOR(inFileFields)
                        #FOR(Field)
                            #IF(%{@isRecord}% = 1 OR %{@isDataset}% = 1)
                                #SET(recLevel, %recLevel% + 1)
                            #ELSEIF(%{@isEnd}% = 1)
                                #SET(recLevel, %recLevel% - 1)
                            #ELSEIF(%recLevel% = 0)
                                #IF(%'@type'%[..7] != 'set of ')
                                    #IF(REGEXFIND('string', %'@type'%))
                                        #EXPAND('SELF.' + %'@name'%) := Std.Str.FindReplace(#EXPAND('LEFT.' + %'@name'%), (STRING)target, (STRING)replacement),
                                    #ELSEIF(REGEXFIND('unicode', %'@type'%))
                                        #EXPAND('SELF.' + %'@name'%) := Std.Uni.FindReplace(#EXPAND('LEFT.' + %'@name'%), (UNICODE)target, (UNICODE)replacement),
                                    #ELSEIF(REGEXFIND('utf', %'@type'%))
                                        #EXPAND('SELF.' + %'@name'%) := (UTF8)Std.Uni.FindReplace((UNICODE)#EXPAND('LEFT.' + %'@name'%), (UNICODE)target, (UNICODE)replacement),
                                    #END
                                #END
                            #END
                        #END
                    #END
                    SELF := LEFT
                )
        );
ENDMACRO;
