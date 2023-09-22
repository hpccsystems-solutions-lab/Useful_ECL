/**
 * Function for determining if a string contains UTF-8 characters or not.
 * Note that if you are processing an ECL STRING value then this function
 * will always return FALSE because the value has already been converted
 * to an ECL STRING (high ASCII, at best).  For an accurate assessment,
 * the argument should be a UTF8 or DATA value from the caller's
 * perspective.
 *
 * @param   str         The string to check; REQUIRED
 * @param   validate    If TRUE, check/validate the entire string; if FALSE,
 *                      abort scan at first valid UTF-8 character found and
 *                      return TRUE; OPTIONAL, defaults to TRUE
 *
 * @return  If validate argument is TRUE, the value of str is scanned in its
 *          entirety and TRUE is returned only if at least one UTF-8 character
 *          is found and the entire string is correctly encoded; if validate
 *          is FALSE, the function stops scanning when the first valid UTF-8
 *          character is found.  If the value of str is found to be invalid
 *          then FALSE will be returned.
 *
 *          If an empty string is passed to the function, TRUE will be returned
 *          if validate is FALSE, and FALSE will be returned if validate is TRUE.
 *
 * Origin:  https://github.com/hpccsystems-solutions-lab/Useful_ECL
 */
EXPORT BOOLEAN IsUTF8(UTF8 str, BOOLEAN validate = TRUE) := EMBED(C++)
    if (lenStr == 0)
        return !validate;

    const unsigned char*    bytes = reinterpret_cast<const unsigned char*>(str);
    const unsigned char*    endPtr = bytes + lenStr;
    bool                    foundAnyUTF8 = false;

    while (bytes < endPtr)
    {
        if (bytes[0] == 0x09 || bytes[0] == 0x0A || bytes[0] == 0x0D || (0x20 <= bytes[0] && bytes[0] <= 0x7E))
        {
            // ASCII; continue scan
            bytes += 1;
        }
        else if ((0xC2 <= bytes[0] && bytes[0] <= 0xDF) && (0x80 <= bytes[1] && bytes[1] <= 0xBF))
        {
            // Valid non-overlong 2-byte
            if (validate)
            {
                bytes += 2;
                foundAnyUTF8 = true;
            }
            else
            {
                return true;
            }
        }
        else if (bytes[0] == 0xE0 && (0xA0 <= bytes[1] && bytes[1] <= 0xBF) && (0x80 <= bytes[2] && bytes[2] <= 0xBF))
        {
            // Valid excluding overlongs
            if (validate)
            {
                bytes += 3;
                foundAnyUTF8 = true;
            }
            else
            {
                return true;
            }
        }
        else if (((0xE1 <= bytes[0] && bytes[0] <= 0xEC) || bytes[0] == 0xEE || bytes[0] == 0xEF) && (0x80 <= bytes[1] && bytes[1] <= 0xBF) && (0x80 <= bytes[2] && bytes[2] <= 0xBF))
        {
            // Valid straight 3-byte
            if (validate)
            {
                bytes += 3;
                foundAnyUTF8 = true;
            }
            else
            {
                return true;
            }
        }
        else if (bytes[0] == 0xED && (0x80 <= bytes[1] && bytes[1] <= 0x9F) && (0x80 <= bytes[2] && bytes[2] <= 0xBF))
        {
            // Valid excluding surrogates
            if (validate)
            {
                bytes += 3;
                foundAnyUTF8 = true;
            }
            else
            {
                return true;
            }
        }
        else if (bytes[0] == 0xF0 && (0x90 <= bytes[1] && bytes[1] <= 0xBF) && (0x80 <= bytes[2] && bytes[2] <= 0xBF) && (0x80 <= bytes[3] && bytes[3] <= 0xBF))
        {
            // Valid planes 1-3
            if (validate)
            {
                bytes += 4;
                foundAnyUTF8 = true;
            }
            else
            {
                return true;
            }
        }
        else if ((0xF1 <= bytes[0] && bytes[0] <= 0xF3) && (0x80 <= bytes[1] && bytes[1] <= 0xBF) && (0x80 <= bytes[2] && bytes[2] <= 0xBF) && (0x80 <= bytes[3] && bytes[3] <= 0xBF))
        {
            // Valid planes 4-15
            if (validate)
            {
                bytes += 4;
                foundAnyUTF8 = true;
            }
            else
            {
                return true;
            }
        }
        else if (bytes[0] == 0xF4 && (0x80 <= bytes[1] && bytes[1] <= 0x8F) && (0x80 <= bytes[2] && bytes[2] <= 0xBF) && (0x80 <= bytes[3] && bytes[3] <= 0xBF))
        {
            // Valid plane 16
            if (validate)
            {
                bytes += 4;
                foundAnyUTF8 = true;
            }
            else
            {
                return true;
            }
        }
        else
        {
            // Invalid; abort
            return false;
        }
    }

    return foundAnyUTF8;
ENDEMBED;
