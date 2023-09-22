#WORKUNIT('name', 'C++ Record Reader Generator');

//-----------------------------------------------------------------------------

GenerateDatasetReader(inFileRec,
                      eclWatchOutput = FALSE,
                      functionNameStr = '\'ReadDataset\'',
                      dsParameterNameStr = '\'inFile\'',
                      cppRowVarNameStr = '\'inRow\'',
                      embedOptionsStr = '\'\'') := FUNCTIONMACRO
    IMPORT Std;
    LOADXML('<xml/>');
    #EXPORTXML(inFileFields, inFileRec);

    #UNIQUENAME(inputECLRecName);
    #SET(inputECLRecName, #TEXT(inFileRec));

    #UNIQUENAME(TextLayout);
    LOCAL %TextLayout% := {STRING text};

    #UNIQUENAME(recLevel);
    #SET(recLevel, 0);

    #UNIQUENAME(headerNeedsStdString);
    #SET(headerNeedsStdString, 0);
    #UNIQUENAME(headerNeedsUTF);
    #SET(headerNeedsUTF, 0);

    // Create the struct that will hold each input record's data
    #UNIQUENAME(inputStructDef);
    LOCAL %inputStructDef% := DATASET
        (
            [
                  '    typedef struct ' + %'inputECLRecName'%
                , '    {'
                #FOR(inFileFields)
                    #FOR(Field)
                        #IF(%recLevel% = 0)
                            #IF(REGEXFIND('(string)|(data)', %'@type'%))
                                , '        std::string ' + %'@name'% + '; // ' + %'@ecltype'%
                                #SET(headerNeedsStdString, 1)
                            #ELSEIF(REGEXFIND('utf', %'@type'%))
                                , '        icu::UnicodeString ' + %'@name'% + '; // ' + %'@ecltype'%
                                #SET(headerNeedsUTF, 1)
                            #ELSEIF(%'@type'% IN ['decimal', 'udecimal'])
                                    , '        double ' + %'@name'% + '; // ' + %'@ecltype'%
                            #ELSEIF(REGEXFIND('real', %'@type'%))
                                #IF(%@size% = 4)
                                    , '        float ' + %'@name'% + '; // ' + %'@ecltype'%
                                #ELSEIF(%@size% = 8)
                                    , '        double ' + %'@name'% + '; // ' + %'@ecltype'%
                                #ELSE
                                    #ERROR(%'@name'% + ': Unknown type ' + %'@ecltype'%)
                                #END
                            #ELSEIF(REGEXFIND('unsigned', %'@type'%))
                                #IF(%@size% = 1)
                                    , '        unsigned char ' + %'@name'% + '; // ' + %'@ecltype'%
                                #ELSEIF(%@size% = 2)
                                    , '        uint16_t ' + %'@name'% + '; // ' + %'@ecltype'%
                                #ELSEIF(%@size% IN [3, 4])
                                    , '        uint32_t ' + %'@name'% + '; // ' + %'@ecltype'%
                                #ELSEIF(%@size% IN [5, 6, 7, 8])
                                    , '        unsigned __int64 ' + %'@name'% + '; // ' + %'@ecltype'%
                                #END
                            #ELSEIF(REGEXFIND('integer', %'@type'%))
                                #IF(%@size% = 1)
                                    , '        signed char ' + %'@name'% + '; // ' + %'@ecltype'%
                                #ELSEIF(%@size% = 2)
                                    , '        int16_t ' + %'@name'% + '; // ' + %'@ecltype'%
                                #ELSEIF(%@size% IN [3, 4])
                                    , '        int32_t ' + %'@name'% + '; // ' + %'@ecltype'%
                                #ELSEIF(%@size% IN [5, 6, 7, 8])
                                    , '        signed __int64 ' + %'@name'% + '; // ' + %'@ecltype'%
                                #END
                            #ELSEIF(%'@type'% = 'boolean')
                                , '        bool ' + %'@name'% + '; // ' + %'@ecltype'%
                            #ELSE
                                #ERROR(%'@name'% + ': Unknown type ' + %'@ecltype'%)
                            #END
                        #END
                        #IF(%{@isRecord}% = 1 OR %{@isDataset}% = 1)
                            // #SET(recLevel, %recLevel% + 1)
                            #ERROR('Child datasets or records are not supported')
                        #ELSEIF(%{@isEnd}% = 1)
                            // #SET(recLevel, %recLevel% - 1)
                            #ERROR('Child datasets or records are not supported')
                        #END
                    #END
                #END
                , '    } ' + %'inputECLRecName'% + ';'
            ],
            %TextLayout%
        );

    #UNIQUENAME(rowExtractionFunction, 'ReadRow_$');
    #UNIQUENAME(rowExtractionCode);
    LOCAL %rowExtractionCode% := DATASET
        (
            [
                ''
                , '    void ' + %'rowExtractionFunction'% + '(const byte* row, ' + %'inputECLRecName'% + '& rowStruct)'
                , '    {'
                #FOR(inFileFields)
                    #FOR(Field)
                        // No need to check for reclevel because embedded structures should have
                        // caused an error when constructing %inputStructDef%

                        #UNIQUENAME(lvalue)
                        #SET(lvalue, 'rowStruct.' + %'@name'%)
                        , '        // ' + %'inputECLRecName'% + '.' + %'@name'%

                        #IF(%'@type'% = 'varstring')
                                #UNIQUENAME(byteCountVar)
                                #SET(byteCountVar, %'@name'% + 'ByteCount')
                                , '        const size32_t ' + %'byteCountVar'% + ' = strlen(reinterpret_cast<const char*>(row));'
                                , '        ' + %'lvalue'% + ' = std::string(reinterpret_cast<const char*>(row), ' + %'byteCountVar'% + ');'
                                , '        row += ' + %'byteCountVar'% + ';'
                        #ELSEIF(REGEXFIND('(string)|(data)', %'@type'%))
                            #IF(%@size% < 0)
                                #UNIQUENAME(byteCountVar)
                                #SET(byteCountVar, %'@name'% + 'ByteCount')
                                , '        const size32_t ' + %'byteCountVar'% + ' = *(reinterpret_cast<const size32_t*>(row));'
                                , '        row += sizeof(' + %'byteCountVar'% + ');'
                                , '        ' + %'lvalue'% + ' = std::string(reinterpret_cast<const char*>(row), ' + %'byteCountVar'% + ');'
                                , '        row += ' + %'byteCountVar'% + ';'
                            #ELSE
                                , '        ' + %'lvalue'% + ' = std::string(reinterpret_cast<const char*>(row), ' + %'@size'% + ');'
                                , '        row += ' + %'@size'% + ';'
                            #END
                        #ELSEIF(REGEXFIND('utf', %'@type'%))
                            #UNIQUENAME(charCountVar)
                            #SET(charCountVar, %'@name'% + 'CharCount')
                            , '        const size32_t ' + %'charCountVar'% + ' = *(reinterpret_cast<const size32_t*>(row));'
                            , '        row += sizeof(' + %'charCountVar'% + ');'
                            #UNIQUENAME(byteCountVar)
                            #SET(byteCountVar, %'@name'% + 'ByteCount')
                            , '        size32_t ' + %'byteCountVar'% + ' = rtlUtf8Size(' + %'charCountVar'% + ', reinterpret_cast<const char*>(row));'
                            , '        ' + %'lvalue'% + ' = icu::UnicodeString(reinterpret_cast<const char*>(row), ' + %'byteCountVar'% + ', "UTF-8");'
                            , '        row += ' + %'byteCountVar'% + ';'
                        #ELSEIF(%'@type'% IN ['decimal', 'udecimal'])
                                #UNIQUENAME(pushFunction)
                                #IF(%'@type'% = 'decimal')
                                    #SET(pushFunction, 'DecPushDecimal')
                                #ELSE
                                    #SET(pushFunction, 'DecPushUDecimal')
                                #END
                                #UNIQUENAME(byteCountVar)
                                #SET(byteCountVar, %'@name'% + 'ByteCount')
                                #UNIQUENAME(fieldPrecision)
                                #SET(fieldPrecision, REGEXFIND('_(\\d+)$', %'@ecltype'%, 1))
                                #IF(%'fieldPrecision'% = '')
                                    #SET(fieldPrecision, '0')
                                #END
                                #UNIQUENAME(fieldCritBlockName)
                                #SET(fieldCritBlockName, %'@name'% + 'Crit')
                                , '        {'
                                , '            BcdCriticalBlock ' + %'fieldCritBlockName'% + ';'
                                , '            ' + %'pushFunction'% + '(row, ' + %'@size'% + ', ' + %'fieldPrecision'% + ');'
                                , '            ' + %'lvalue'% + ' = DecPopReal();'
                                , '        }'
                                , '        row += ' + %'@size'% + ';'
                        #ELSEIF(REGEXFIND('real', %'@type'%))
                            #IF(%@size% = 4)
                                , '        ' + %'lvalue'% + ' = *(reinterpret_cast<const float*>(row));'
                            #ELSE
                                , '        ' + %'lvalue'% + ' = *(reinterpret_cast<const double*>(row));'
                            #END
                            , '        row += ' + %'@size'% + ';'
                        #ELSEIF(REGEXFIND('unsigned', %'@type'%))
                            , '        ' + %'lvalue'% + ' = rtlReadUInt(row, ' + %'@size'% + ');'
                            , '        row += ' + %'@size'% + ';'
                        #ELSEIF(REGEXFIND('integer', %'@type'%))
                            , '        ' + %'lvalue'% + ' = rtlReadInt(row, ' + %'@size'% + ');'
                            , '        row += ' + %'@size'% + ';'
                        #ELSEIF(%'@type'% = 'boolean')
                            , '        ' + %'lvalue'% + ' = *(reinterpret_cast<const bool*>(row));'
                            , '        row += sizeof(bool);'
                        #END
                        , ''
                    #END
                #END
                , '    }'
            ],
            %TextLayout%
        );

    #UNIQUENAME(bodySep);
    LOCAL %bodySep% := DATASET
        (
            [
                  ''
                , '    #body'
            ],
            %TextLayout%
        );

    #UNIQUENAME(includeDefinitions);
    LOCAL %includeDefinitions% := %inputStructDef% + %rowExtractionCode% + %bodySep%;


    // Create a options for the EMBED, if necessary
    #UNIQUENAME(embedOptions);
    #SET(embedOptions, '');

    #IF((STRING)embedOptionsStr != '')
        #APPEND(embedOptions, ' : ' + Std.Str.ToLowerCase(TRIM((STRING)embedOptionsStr, ALL)))
    #END

    #UNIQUENAME(eclResultType);
    #SET(eclResultType, 'UNSIGNED2');
    #UNIQUENAME(cppResultType);
    #SET(cppResultType, 'uint16_t');

    #UNIQUENAME(streamedFunctionDeclaration);
    LOCAL %streamedFunctionDeclaration% := DATASET
        (
            [
                %'eclResultType'% + ' ' + (STRING)functionNameStr + '(STREAMED DATASET(' + %'inputECLRecName'% + ') ' + (STRING)dsParameterNameStr + ') := EMBED(C++' + %'embedOptions'% + ')'
            ],
            %TextLayout%
        );

    // Any C++ includes we need
    #UNIQUENAME(headerIncludes);
    LOCAL %headerIncludes% := DATASET
        (
            [
                ''
                #IF(%headerNeedsStdString% = 1)
                    , '    #include <string>'
                #END
                #IF(%headerNeedsUTF% = 1)
                    , '    #define UCHAR_TYPE uint16_t'
                    , '    #include <unicode/unistr.h>'
                #END
                , ''
            ],
            %TextLayout%
        );

    #UNIQUENAME(rowPtr, 'rowPtr_$');

    // Code for reading each record's row from a streamed dataset
    #UNIQUENAME(bodyScalarResult);
    LOCAL %bodyScalarResult% := DATASET
        (
            [
                ''
                , '    ' + %'cppResultType'% + ' result;'
                , '    ' + %'inputECLRecName'% + ' ' + (STRING)cppRowVarNameStr + ';'
                , '    const byte* ' + %'rowPtr'% + ' = nullptr;'
                , ''
                , '    while ((' + %'rowPtr'% + ' = static_cast<const byte*>(' + (STRING)dsParameterNameStr + '->nextRow())))'
                , '    {'
                , '        // Populate struct ' + (STRING)cppRowVarNameStr
                , '        ' + %'rowExtractionFunction'% + '(' + %'rowPtr'% + ', ' + (STRING)cppRowVarNameStr + ');'
                , ''
                , '        // TODO: process data in struct ' + (STRING)cppRowVarNameStr
                , '    }'
                , ''
                , '    return result;'
                , 'ENDEMBED;'
            ],
            %TextLayout%
        );

    #UNIQUENAME(allDefs);
    LOCAL %allDefs% := %streamedFunctionDeclaration% + %headerIncludes% + %includeDefinitions% + %bodyScalarResult%;

    #UNIQUENAME(plainResult);
    LOCAL %plainResult% := ROLLUP
        (
            %allDefs%,
            TRUE,
            TRANSFORM
                (
                    RECORDOF(LEFT),
                    SELF.text := LEFT.text + '\n' + RIGHT.text
                )
        );

    #UNIQUENAME(escapedXML);
    LOCAL %escapedXML% := PROJECT
        (
            %allDefs%,
            TRANSFORM
                (
                    RECORDOF(LEFT),
                    SELF.text := REGEXREPLACE('<([^>]+)>', LEFT.text, '&lt;$1&gt;')
                )
        );

    #UNIQUENAME(rolledUp);
    LOCAL %rolledUp% := ROLLUP
        (
            %escapedXML%,
            TRUE,
            TRANSFORM
                (
                    RECORDOF(LEFT),
                    SELF.text := LEFT.text + '<br/>' + RIGHT.text
                )
        );

    #UNIQUENAME(htmlResult);
    LOCAL %htmlResult% := DATASET(['<pre>' + %rolledUp%[1].text + '</pre>'], {STRING result__html});

    RETURN #IF(eclWatchOutput) %htmlResult% #ELSE %plainResult% #END;
ENDMACRO;

//=============================================================================================

MatchingLayout := RECORD
    // UTF8            cpe;
    VARSTRING       cpe;
    BOOLEAN         did_match;
    UNSIGNED3       num_matches;
    DECIMAL32_6     r4;
    REAL8           r8;
END;

generatedCode := GenerateDatasetReader
    (
        MatchingLayout,
        eclWatchOutput := TRUE,
        embedOptionsStr := 'local,time'
    );

OUTPUT(generatedCode, ALL);
