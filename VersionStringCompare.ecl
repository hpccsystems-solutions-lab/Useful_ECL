/**
 * Function for comparing two version strings, returning {-1, 0, 1}
 * to indicate that the first argument is less than, equal to, or
 * greater than the second argument.
 *
 * Versions are roughly delimited by decimal points and compared in "chunks",
 * but alpha strings are compared separately and do not need to be delimited
 * (example: 1.5b2 is compared in chunks of '1', '5', 'b' and '2').  Any
 * number of chunks can be included in a version string.
 *
 * Various exceptions to standard numeric or lexigraphical comparisons:
 *
 *      - Trailing decimals and zeros are ignored, so for instance
 *        '1.2' == '1.2.0'
 *      - Versions that match up to an alphacharacter will be sorted
 *        reversed (e.g. 1.5 > 1.5b1)
 *      - Alpha characters are compared case-insensitive (1.1a1 == 1.1A1)
 *      - Versions that begin with a decimal point will have a zero
 *        zero prepended prior to testing
 *      - An empty version string is less than a non-empty string
 *        (e.g. '' < '1.2')
 *      - Two empty strings are equal ('' == '')
 *
 * @param   v1      First version string to compare
 * @param   v2      Second version string to compare
 *
 * @return  -1 if v1 < v2
 *          0 if v1 == v2
 *          1 if v1 > v2
 *
 * Example code can be found at the bottom of this file.
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
EXPORT INTEGER1 VersionStringCompare(STRING v1, STRING v2) := EMBED(C++)
    #option pure;
    #include <string>

    #body

    // Check empty string cases
    if (lenV1 == 0 && lenV2 > 0)
        return -1;
    if (lenV2 == 0 && lenV1 > 0)
        return 1;
    if (lenV1 == 0 && lenV2 == 0)
        return 0;

    std::string     version1(v1, lenV1);
    std::string     bin1;
    unsigned int    pos1 = 0;
    std::string     version2(v2, lenV2);
    std::string     bin2;
    unsigned int    pos2 = 0;

    // Prepend zeros if necessary
    if (version1[0] == '.')
        version1 = '0' + version1;
    if (version2[0] == '.')
        version2 = '0' + version2;

    while (pos1 < version1.length() && pos2 < version2.length())
    {
        bool    parsingNum1 = isdigit(version1[pos1]);
        bool    parsingNum2 = isdigit(version2[pos2]);

        if (parsingNum1 && !parsingNum2)
            return 1;
        else if (!parsingNum1 && parsingNum2)
            return -1;

        // Grab chunk from version1
        while (pos1 < version1.length())
        {
            char    ch = version1[pos1];

            if (parsingNum1 && ch >= '0' && ch <= '9')
            {
                bin1 += ch;
                ++pos1;
            }
            else if (!parsingNum1 && !ispunct(ch))
            {
                bin1 += tolower(ch);
                ++pos1;
            }
            else
            {
                if (ispunct(ch))
                    ++pos1;
                break;
            }
        }

        // Grab chunk from version2
        while (pos2 < version2.length())
        {
            char    ch = version2[pos2];

            if (parsingNum1 && ch >= '0' && ch <= '9')
            {
                bin2 += ch;
                ++pos2;
            }
            else if (!parsingNum1 && !ispunct(ch))
            {
                bin2 += tolower(ch);
                ++pos2;
            }
            else
            {
                if (ispunct(ch))
                    ++pos2;
                break;
            }
        }

        // Compare chunks
        if (parsingNum1)
        {
            int     n1 = std::stoi(bin1);
            int     n2 = std::stoi(bin2);

            if (n1 < n2)
                return -1;
            else if (n1 > n2)
                return 1;
        }
        else
        {
            if (bin1 < bin2)
                return -1;
            else if (bin1 > bin2)
                return 1;
        }

        bin1.erase();
        bin2.erase();
    }

    // If we get to here then we have matched until the end
    // of one of the strings; if the remaining version string
    // starts with a letter then we assume that it is 'prior' to
    // shorter string (e.g. 1.5 vs 1.5b1, so 1.5b1 should be prior);
    // if the remaining version string does not start with a letter
    // then check for trailing [.0] characters
    if (version1.length() < version2.length())
    {
        if (isalpha(version2[pos2]))
        {
            return 1;
        }
        else
        {
            // Make sure the trailing string is not composed of
            // only decimal points and zeros
            for (unsigned int x = pos2; x < version2.length(); x++)
            {
                if (version2[x] != '.' && version2[x] != '0')
                {
                    return -1;
                }
            }
        }
    }
    else if (version1.length() > version2.length())
    {
        if (isalpha(version1[pos1]))
        {
            return -1;
        }
        else
        {
            // Make sure the trailing string is not composed of
            // only decimal points and zeros
            for (unsigned int x = pos1; x < version1.length(); x++)
            {
                if (version1[x] != '.' && version1[x] != '0')
                {
                    return 1;
                }
            }
        }
    }

    return 0;
ENDEMBED;

//=============================================================================
// Testing
//=============================================================================

/*
DataRec := RECORD
    STRING      vers1;
    STRING      vers2;
    INTEGER1    compare := 0;
END;

ds := DATASET
    (
        [
            {'1.2.3', '2.3.4'}
            , {'1.2.3', '1.2.3'}
            , {'1.2.3', '1.2'}
            , {'1.2', '1.2.3'}
            , {'1.2', '.2.3'}
            , {'.2.4', '.2.3'}
            , {'10.4', '2.3'}
            , {'10.4b2', '10.4b1'}
            , {'10.4', '10.4b1'}
            , {'10.4a5', '10.4b1'}
            , {'10.4a5-2', '10.4a5-1'}
            , {'10.4a5-2', '10.4a5-10'}
            , {'7.00', '7.0.0'}
            , {'7', '7.0.0'}
            , {'7.', '7'}
            , {'5A1', '5a1'}
            , {'6.2-1a4', '6.2-1'}
            , {'6.2-1-4', '6.2-1'}
            , {'6.2-1.0', '6.2-1'}
            , {'1.2.3', ''}
            , {'', '1.2.3'}
            , {'', ''}
        ],
        DataRec
    );

res := PROJECT
    (
        NOFOLD(ds),
        TRANSFORM
            (
                RECORDOF(LEFT),
                SELF.compare := VersionStringCompare(LEFT.vers1, LEFT.vers2),
                SELF := LEFT
            )
    );

OUTPUT(res);
*/
