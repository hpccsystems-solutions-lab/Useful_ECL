/**
 * Returns a random string composed of lowercase letters and numbers.  The
 * first character in the returned value is always a letter.
 *
 * @param   len     The length of the string to return; must be greater than
 *                  zero; REQUIRED
 *
 * @return  A string
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
EXPORT STRING RandomFilename(UNSIGNED2 len) := EMBED(C++)
    #option volatile

    const char  letters[] = "abcdefghijklmnopqrstuvwxyz0123456789";

    __result = reinterpret_cast<char*>(rtlMalloc(len));
    __lenResult = len;

    __result[0] = letters[rand() % 26];

    for (unsigned int x = 1; x < len; x++)
        __result[x] = letters[rand() % 36];
ENDEMBED;
