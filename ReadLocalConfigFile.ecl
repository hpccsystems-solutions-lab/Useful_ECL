/**
 * Loads a local file containing configuration parameters and returns those
 * parameters as a dictionary.  Configuration parameters in the file should
 * be expressed in the following format:
 *
 *      key=value
 *      key=value
 *      ...
 *      key=value
 *
 * Blank lines in the file are skipped, as well as any line that has '#' as the
 * first non-blank character.  Empty values (e.g. 'key=') are allowed.
 * Whitespace surrounding both key and value is trimmed away.
 *
 * @param   fullPath        The full path to the configuration file
 *
 * @return  Parsed configuration parameters in the form of a DICTIONARY.
 *          The attributes within the dictionary are 'key' and 'value'.
 *          Both key and value are STRING data types.
 *          Example usage:  myParamValue := myConfig[key].value;
 */

IMPORT Std;

EXPORT ReadLocalConfigFile(STRING fullPath) := FUNCTION
    // Pull in file as a recordset composed of separate text lines
    fileLines := DATASET
        (
            DYNAMIC(Std.File.ExternalLogicalFileName('127.0.0.1', fullPath)),
            {STRING s},
            CSV(SEPARATOR(''))
        );

    filteredLines := fileLines(TRIM(s, LEFT)[1] != '#');

    params := PROJECT
        (
            filteredLines,
            TRANSFORM
                (
                    {
                        STRING  key,
                        STRING  value
                    },
                    SELF.key := TRIM(REGEXFIND('^([^=]+)=', LEFT.s, 1), LEFT, RIGHT),
                    SELF.value := IF(SELF.key != '', TRIM(REGEXFIND('=(.*)$', LEFT.s, 1), LEFT, RIGHT), SKIP)
                )
        );

    RETURN DICTIONARY(params, {key => value});
END;
