EXPORT DatasetAsHTMLTable(inFile) := FUNCTIONMACRO
    LOADXML('<xml/>');
    #EXPORTXML(inFileFields, RECORDOF(inFile));

    #UNIQUENAME(scalarFields);
    #UNIQUENAME(fieldCount);
    #UNIQUENAME(recLevel);
    #UNIQUENAME(fieldStack);
    #UNIQUENAME(childDSFields);
    #UNIQUENAME(namePrefix);
    #UNIQUENAME(fullName);
    #UNIQUENAME(explicitScalarFields);

    #SET(scalarFields, '');
    #SET(fieldCount, 0);
    #SET(recLevel, 0);
    #SET(fieldStack, '');
    #SET(childDSFields, '');
    #SET(namePrefix, '');
    #SET(fullName, '');
    #FOR(inFileFields)
        #FOR(Field)
            #SET(fieldCount, %fieldCount% + 1)
            #IF(%{@isEnd}% != 1)
                // Adjust full name
                #SET(fullName, %'namePrefix'% + %'@name'%)
            #END
            #IF(%{@isRecord}% = 1)
                // Push record onto stack so we know what we're popping when we see @isEnd
                #SET(fieldStack, 'r' + %'fieldStack'%)
                #APPEND(namePrefix, %'@name'% + '.')
            #ELSEIF(%{@isDataset}% = 1)
                // Push dataset onto stack so we know what we're popping when we see @isEnd
                #SET(fieldStack, 'd' + %'fieldStack'%)
                #APPEND(namePrefix, %'@name'% + '.')
                #SET(recLevel, %recLevel% + 1)
                // Note the field index and field name so we can process it separately
                #IF(%'childDSFields'% != '')
                    #APPEND(childDSFields, ',')
                #END
                #APPEND(childDSFields, %'fieldCount'% + ':' + %'fullName'%)
            #ELSEIF(%{@isEnd}% = 1)
                #SET(namePrefix, REGEXREPLACE('\\w+\\.$', %'namePrefix'%, ''))
                #IF(%'fieldStack'%[1] = 'd')
                    #SET(recLevel, %recLevel% - 1)
                #END
                #SET(fieldStack, %'fieldStack'%[2..])
            #ELSEIF(%recLevel% = 0)
                // Note the field index and full name of the attribute so we can process it
                #IF(%'scalarFields'% != '')
                    #APPEND(scalarFields, ',')
                #END
                #APPEND(scalarFields, %'fieldCount'% + ':' + %'fullName'%)
            #END
        #END
    #END

    // Collect the gathered full attribute names so we can walk them later
    #SET(explicitScalarFields, REGEXREPLACE('\\d+:', %'scalarFields'%, ''));
ENDMACRO;
