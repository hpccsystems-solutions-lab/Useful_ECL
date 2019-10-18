/**
 * Function concatenates the values within a field from every record in the
 * input dataset.  This is similar to using the standard library function
 * Std.Str.CombineWords(SET(inFile, inField), delim) but is not confined to
 * only STRING input and output.
 *
 * Callers can mandate the result datatype, and care should be taken that the
 * result datatype is string- or data-like (in other words, a datatype that
 * actually allows concatenation).  In addition, input values are cast to
 * that datatype so callers should be aware of type casting rules.
 *
 * Obviously, some care should be taken with very large datasets.  It is
 * entirely possible to run out of memory if there are many inFile records.
 *
 * @param   inFile          The dataset to process; REQUIRED
 * @param   outFieldType    The datatype of the result; this is not a string;
 *                          REQUIRED
 * @param   inField         The name of the field within inFile whose values
 *                          will be concatenated; this is not a string;
 *                          REQUIRED
 * @param   delim           The delimiter to use between values in the final
 *                          result; will be type cast to outFieldType;
 *                          OPTIONAL, defaults to an empty STRING
 * @param   doTrim          If TRUE, perform a TRIM(LEFT, RIGHT) on the inField
 *                          values; note that inField's datatype needs to be
 *                          able to support a TRIM() call -- so, a STRING,
 *                          UNICODE, or UTF8 type; OPTIONAL, defaults to FALSE
 *
 * @return  A scalar value of type outFieldType containing all of the values
 *          from the inFile.inField, with the value of delim as a separator,
 *          in record order.
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
ConcatFieldValues(inFile, outFieldType, inField, delim = '\'\'', doTrim = FALSE) := FUNCTIONMACRO
    #UNIQUENAME(outField);
    LOCAL onlyFieldData := PROJECT
        (
            inFile,
            TRANSFORM
                (
                    {
                        outFieldType    %outField%
                    },
                    #IF((BOOLEAN)doTrim)
                        SELF.%outField% := TRIM((outFieldType)LEFT.inField, LEFT, RIGHT)
                    #ELSE
                        SELF.%outField% := (outFieldType)LEFT.inField
                    #END
                )
        );

    LOCAL rolledUpData := ROLLUP
        (
            onlyFieldData,
            TRUE,
            TRANSFORM
                (
                    RECORDOF(LEFT),
                    SELF.%outField% := LEFT.%outField% + (outFieldType)delim + RIGHT.%outField%
                )
        );

    RETURN rolledUpData[1].%outField%;
ENDMACRO;
