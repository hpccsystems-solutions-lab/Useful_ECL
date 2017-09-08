/**
 * Hack for loading a file local to a Thor, Roxie or hThor node.
 *
 * @param   fullPath        The full path to the file
 *
 * @return  The contents of the file as a string
 */

IMPORT Std;

EXPORT ReadLocalFile(STRING fullPath) := FUNCTION
    // Pull in file as a recordset composed of separate text lines
    fileLines := DATASET
        (
            DYNAMIC(Std.File.ExternalLogicalFileName('127.0.0.1', fullPath)),
            {STRING s},
            CSV(SEPARATOR('')),
            OPT
        );

    // Combine lines into a single string
    singleLine := ROLLUP
        (
            fileLines,
            TRUE,
            TRANSFORM
                (
                    RECORDOF(LEFT),
                    SELF.s := LEFT.s + RIGHT.s
                ),
            STABLE, ORDERED(TRUE)
        );

    RETURN singleLine[1].s;
END;
