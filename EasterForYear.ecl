IMPORT Std;

/**
 * Function returns a date in Std.Date.Date_t format
 * representing the date Easter falls on for the
 * given year.
 *
 * @param	year	Four-digit year; REQUIRED
 * 
 * @return	The date Easter falls on in the given
 *			year, in Std.Date.Date_t format.
 */
EXPORT EasterForYear(INTEGER2 year) := FUNCTION
    c := year DIV 100;
    g := year % 19;
    h := ((c - (c DIV 4) - ((8 * c + 13) DIV 25) + (19 * g) + 15) % 30);
    i := (h - (h DIV 28) * (1 - (29 DIV (h + 1)) * ((21-g) DIV 11)));
    j := ((year + (year DIV 4) + i + 2 - c + (c DIV 4)) % 7);
    l := i - j;
    month := (3 + ((l + 40) DIV 44));
    day := (l + 28 - 31 * (month DIV 4));

    RETURN Std.Date.DateFromParts(year, month, day);
END;

/*
OUTPUT(EasterForYear(2022), NAMED('easter_2022'));   // 20220417
OUTPUT(EasterForYear(2023), NAMED('easter_2023'));   // 20230409
OUTPUT(EasterForYear(2024), NAMED('easter_2024'));   // 20240331
*/
