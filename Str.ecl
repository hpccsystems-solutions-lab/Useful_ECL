/**
 * Useful string-oriented utilities.  Exported functions:
 *
 *  URLDecode:  Decodes a URL-encoded string.
 *  URLEncode   Encodes a URL-encoded string.
 */
EXPORT Str := MODULE

    /**
     * Decodes a URL-encoded string.  Only strings with characters represented
     * by single bytes are valid.
     *
     * @param   s   The string to decode
     *
     * @return  The decoded string
     */
    EXPORT STRING URLDecode(STRING s) := EMBED(C++ : DISTRIBUTED)
        #include <string.h>
        #body
        const char HEX2DEC[256] =
            {
                /*       0  1  2  3   4  5  6  7   8  9  A  B   C  D  E  F */
                /* 0 */ -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1,
                /* 1 */ -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1,
                /* 2 */ -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1,
                /* 3 */  0, 1, 2, 3,  4, 5, 6, 7,  8, 9,-1,-1, -1,-1,-1,-1,

                /* 4 */ -1,10,11,12, 13,14,15,-1, -1,-1,-1,-1, -1,-1,-1,-1,
                /* 5 */ -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1,
                /* 6 */ -1,10,11,12, 13,14,15,-1, -1,-1,-1,-1, -1,-1,-1,-1,
                /* 7 */ -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1,

                /* 8 */ -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1,
                /* 9 */ -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1,
                /* A */ -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1,
                /* B */ -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1,

                /* C */ -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1,
                /* D */ -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1,
                /* E */ -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1,
                /* F */ -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1, -1,-1,-1,-1
            };
        const char*     beginInputPtr = s;
        const char*     endInputPtr = beginInputPtr + lenS;
        const char*     endCheckPtr = endInputPtr - 2;    // last decodable '%'
        char*           endOutputPtr = NULL;

        if (lenS > 0)
        {
            __result = reinterpret_cast<char*>(rtlMalloc(lenS));
            endOutputPtr = __result;

            while (beginInputPtr < endCheckPtr)
            {
                if (*beginInputPtr == '%')
                {
                    unsigned int    charPos1 = *(beginInputPtr + 1);
                    unsigned int    charPos2 = *(beginInputPtr + 2);
                    char dec1, dec2;
                    if (-1 != (dec1 = HEX2DEC[charPos1]) && -1 != (dec2 = HEX2DEC[charPos2]))
                    {
                        *endOutputPtr++ = (dec1 << 4) + dec2;
                        beginInputPtr += 3;
                        continue;
                    }
                }

                *endOutputPtr++ = *beginInputPtr++;
            }

            // the last 2- chars
            while (beginInputPtr < endInputPtr)
            {
                *endOutputPtr++ = *beginInputPtr++;
            }

            __lenResult = endOutputPtr - __result;
        }
        else
        {
            __lenResult = 0;
            __result = NULL;
        }
    ENDEMBED;

    /**
     * URL-encodes a string.  Only strings with characters represented
     * by single bytes are valid.
     *
     * @param   s   The string to encode
     *
     * @return  The encoded string
     */
    EXPORT STRING URLEncode(STRING s) := EMBED(C++ : DISTRIBUTED)
        #include <string.h>
        #body
        const char SAFE[256] =
            {
                /*      0 1 2 3  4 5 6 7  8 9 A B  C D E F */
                /* 0 */ 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
                /* 1 */ 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
                /* 2 */ 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
                /* 3 */ 1,1,1,1, 1,1,1,1, 1,1,0,0, 0,0,0,0,

                /* 4 */ 0,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1,
                /* 5 */ 1,1,1,1, 1,1,1,1, 1,1,1,0, 0,0,0,0,
                /* 6 */ 0,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1,
                /* 7 */ 1,1,1,1, 1,1,1,1, 1,1,1,0, 0,0,0,0,

                /* 8 */ 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
                /* 9 */ 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
                /* A */ 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
                /* B */ 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,

                /* C */ 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
                /* D */ 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
                /* E */ 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
                /* F */ 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0
            };
        const char      DEC2HEX[16 + 1] = "0123456789ABCDEF";
        const char*     beginInputPtr = s;
        const char*     endInputPtr = beginInputPtr + lenS;
        char*           endOutputPtr = NULL;

        if (lenS > 0)
        {
            __result = reinterpret_cast<char*>(rtlMalloc(lenS * 3));
            endOutputPtr = __result;

            for (; beginInputPtr < endInputPtr; ++beginInputPtr)
            {
                unsigned int    charPos = *beginInputPtr;

                if (SAFE[charPos])
                {
                    *endOutputPtr++ = *beginInputPtr;
                }
                else
                {
                    // escape this char
                    *endOutputPtr++ = '%';
                    *endOutputPtr++ = DEC2HEX[*beginInputPtr >> 4];
                    *endOutputPtr++ = DEC2HEX[*beginInputPtr & 0x0F];
                }
            }

            __lenResult = endOutputPtr - __result;
        }
        else
        {
            __lenResult = 0;
            __result = NULL;
        }
    ENDEMBED;

END;
