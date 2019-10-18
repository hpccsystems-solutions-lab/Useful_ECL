/**
 * Convert one or more attributes within a dataset to dictionary lookup values.
 * Macro accepts an optional old mapping (as if created from a previous
 * execution run) can be passed in; if it is provided then those mappings will
 * be reused.
 *
 * The goal here is to create nominal integer values for every unique value
 * of interest, and also to provide a way to update an old nominal map with
 * new data.
 *
 * This macro updates two attributes that you supply, one for the rewritten
 * input dataset and one that will contain the mapping.  The mapping will have
 * the structure:
 *      RECORD
 *          STRING      fieldName;      // Name of attribute
 *          STRING      valueAsString;  // Value converted to a string
 *          UNSIGNED4   nom;            // Nominal value
 *      END;
 *
 * The actual datatype used for the 'nom' mapping attribute can be easily
 * changed; look for '%NomType%' in the code below.
 *
 * @param   inFile          IN, REQUIRED    The dataset to process
 * @param   attrListStr     IN, REQUIRED    A comma-delimited list of
 *                                          attributes within the dataset to
 *                                          convert; the string should be
 *                                          in lowercase
 * @param   outFile         OUT, REQUIRED   The attribute that will contain
 *                                          the result of converting inFile
 * @param   outMap          OUT, REQUIRED   The attribute that will contain
 *                                          the new/updated mappings
 * @param   oldMap          IN, OPTIONAL    A dataset containing mappings
 *                                          from a previous execution; must have
 *                                          the record structure described above
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
EXPORT CreateNominalValues(inFile, attrListStr, outFile, outMap, oldMap = '') := MACRO
    LOADXML('<xml/>');
    #EXPORTXML(inFileFields, RECORDOF(inFile));

    #UNIQUENAME(NomType);
    %NomType% := UNSIGNED4;

    #UNIQUENAME(MapRec);
    %MapRec% := RECORD
        STRING      fieldName;
        STRING      valueAsString;
        %NomType%   nom;
    END;

    #UNIQUENAME(trimmedAttrList);
    %trimmedAttrList% := TRIM((STRING)attrListStr, ALL);

    #UNIQUENAME(CanProcessAttribute);
    %CanProcessAttribute%(STRING attrName, STRING attrType) := (REGEXFIND('(^|,)' + attrName + '(,|$)', %trimmedAttrList%, NOCASE));

    #UNIQUENAME(OutFileLayout);
    %OutFileLayout% := RECORD
        #FOR(inFileFields)
            #FOR(field)
                #IF(%{@isRecord}% = 1 OR %{@isDataset}% = 1 OR %{@isEnd}% = 1)
                    #ERROR('Datasets with embedded records or child datasets not supported')
                #ELSE
                    #IF(%CanProcessAttribute%(%'@name'%, %'@type'%))
                        %NomType% %@name%;
                    #ELSE
                        %@type% %@name%;
                    #END
                #END
            #END
        #END
    END;

    // Find maximum nominal values for each field for an old mapping
    #UNIQUENAME(oldMapMaximums);
    %oldMapMaximums% :=
        #IF(#TEXT(oldMap) != '')
            TABLE(oldMap, {fieldName, %NomType% nom := MAX(GROUP, nom)}, fieldName, FEW)
        #ELSE
            DATASET([], {STRING fieldName, %NomType% nom})
        #END;
    #UNIQUENAME(oldMapDict);
    %oldMapDict% := DICTIONARY(%oldMapMaximums%, {fieldName => nom});

    #UNIQUENAME(needsDelim);
    #SET(needsDelim, 0);
    #UNIQUENAME(corrNamePosX);
    #UNIQUENAME(fieldX);
    #SET(corrNamePosX, 1);

    // Create nominal values for each unique value in our dataset
    #UNIQUENAME(localMap);
    %localMap% :=
        #LOOP
            #SET(fieldX, REGEXFIND('^([^,]+)', %trimmedAttrList%[%corrNamePosX%..], 1))
            #IF(%'fieldX'% != '')
                #IF(%needsDelim% = 1) + #END
                PROJECT
                    (
                        TABLE(inFile, {%fieldX%}, %fieldX%, MERGE),
                        TRANSFORM
                            (
                                %MapRec%,
                                SELF.fieldName := %'fieldX'%,
                                SELF.valueAsString := (STRING)LEFT.%fieldX%,
                                SELF.nom := COUNTER + %oldMapDict%[%'fieldX'%].nom
                            )
                    )
                #SET(needsDelim, 1)
                #SET(corrNamePosX, %corrNamePosX% + LENGTH(%'fieldX'%) + 1)
            #ELSE
                #BREAK
            #END
        #END;

    // Merge the old and new mappings if needed
    outMap :=
        #IF(#TEXT(oldMap) != '')
            ROLLUP
                (
                    SORT(%localMap% + oldMap, fieldName, valueAsString),
                    TRANSFORM
                        (
                            RECORDOF(LEFT),
                            SELF.nom := MIN(LEFT.nom, RIGHT.nom),
                            SELF := LEFT
                        ),
                    fieldName, valueAsString
                )
        #ELSE
            %localMap%
        #END;

    #UNIQUENAME(dict);
    %dict% := DICTIONARY(outMap, {fieldName, valueAsString => nom});

    // Rewrite data to use the mappings
    outFile := PROJECT
        (
            inFile,
            TRANSFORM
                (
                    %OutFileLayout%,
                    #FOR(inFileFields)
                        #FOR(field)
                            #IF(%CanProcessAttribute%(%'@name'%, %'@type'%))
                                SELF.%@name% := %dict%[%'@name'%, (STRING)LEFT.%@name%].nom,
                            #END
                        #END
                    #END
                    SELF := LEFT
                )
        );
ENDMACRO;
