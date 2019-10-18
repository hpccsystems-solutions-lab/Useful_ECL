/**
 * Hack for loading a file local to a Thor, Roxie or hThor node.
 *
 * @param   fullPath        The full path to the file; REQUIRED
 * @param   ipAddress       The IP address of the system that hosts the file
 *                          at fullPath; use '127.0.0.1' to specify the local
 *                          system; OPTIONAL, defaults to '127.0.0.1'
 *
 * @return  The contents of the file as a string
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */

IMPORT Std;

EXPORT ReadLocalFile(STRING fullPath, STRING ipAddress = '127.0.0.1') := FUNCTION
    // Pull in file as a recordset composed of separate text lines
    fileLines := DATASET
        (
            DYNAMIC(Std.File.ExternalLogicalFileName(ipAddress, fullPath)),
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
