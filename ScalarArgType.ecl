/**
 * Function macro that returns a string indicating the general data type of the
 * scalar argument.  The argument cannot be a dataset or row.
 *
 * @param   value   The scalar argument to test
 *
 * @return  A string value indicating the general data type of the argument.
 *          If the general type cannot be determined then the exact type
 *          (as determined by #GETDATATYPE()) will be returned.
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
EXPORT ScalarArgType(value) := FUNCTIONMACRO
    #UNIQUENAME(outType);
    #SET(outType, '');
    #UNIQUENAME(inType);
    #SET(inType, #GETDATATYPE(value));

    #IF(%'inType'%[..6] = 'string')
        #SET(outType, 'string')
    #ELSEIF(%'inType'%[..7] = 'unicode')
        #SET(outType, 'unicode')
    #ELSEIF(%'inType'%[..4] = 'utf8')
        #SET(outType, 'utf8')
    #ELSEIF(%'inType'%[..8] = 'unsigned')
        #SET(outType, 'unsigned')
    #ELSEIF(%'inType'%[..7] = 'integer')
        #SET(outType, 'integer')
    #ELSEIF(%'inType'%[..4] = 'real')
        #SET(outType, 'real')
    #ELSEIF(%'inType'%[..7] = 'decimal')
        #SET(outType, 'decimal')
    #ELSEIF(%'inType'%[..4] = 'data')
        #SET(outType, 'data')
    #ELSE
        #SET(outType, %'inType'%)
    #END

    RETURN %'outType'%;
ENDMACRO;
