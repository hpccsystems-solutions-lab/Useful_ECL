IMPORT Std;

/**
 * IsDaylightSavingsInEffect
 *
 * Returns TRUE if Daylight Saving Time (DST) is considered in effect for the given
 * date under U.S. federal DST schedules (where they existed), otherwise FALSE.
 *
 * This function intentionally uses a date-only approximation:
 *  - DST is treated as active starting on the start-transition Sunday (inclusive)
 *  - and inactive starting on the end-transition Sunday (exclusive).
 *
 * This avoids ambiguity around the local 02:00 transition time (and the midnight–02:00
 * window on the “fall back” day). If you need hour-level correctness, use a
 * timestamp + timezone rules (e.g., IANA tzdata) instead.
 *
 * Historical notes / limitations:
 *  - 1967+ follows the Uniform Time Act schedules (with the 1974–1975 exceptions and
 *    the 1987 and 2007 rule changes).
 *  - 1942–1945 models WWII “War Time” as continuous DST (starting 1942-02-09, ending 1945-09-30).
 *  - 1920–1941 and 1946–1966 return FALSE because DST was not federally standardized
 *    and varied by state/locality.
 *  - This does NOT account for state/local exemptions (e.g., areas that do not observe DST).
 *
 * @param   date    The date in question, in YYYYMMDD format;
 *                  OPTIONAL, defaults to the current date.
 *
 * @return  TRUE if daylight saving time was in effect on that date, FALSE otherwise.
 */
EXPORT BOOLEAN IsDaylightSavingsInEffect(Std.Date.Date_t date = Std.Date.Today()) := FUNCTION
    // Helper functions
    Std.Date.Date_t SundayDateBefore(Std.Date.Date_t d, UNSIGNED1 nthSunday = 1) := FUNCTION
        delta := (Std.Date.DayOfWeek(d) - 1) + ((nthSunday - 1) * 7);
        RETURN Std.Date.AdjustDate(d, day_delta := -delta);
    END;
    Std.Date.Date_t SundayDateAfter(Std.Date.Date_t d, UNSIGNED1 nthSunday = 1) := FUNCTION
        delta := ((8 - Std.Date.DayOfWeek(d)) % 7) + ((nthSunday - 1) * 7);
        RETURN Std.Date.AdjustDate(d, day_delta := delta);
    END;

    year := Std.Date.Year(date);

    RETURN MAP
        (
            year >= 2007 => (date >= SundayDateAfter(Std.Date.DateFromParts(year, 3, 1), 2) AND date < SundayDateAfter(Std.Date.DateFromParts(year, 11, 1))),
            year >= 1987 => (date >= SundayDateAfter(Std.Date.DateFromParts(year, 4, 1)) AND date < SundayDateBefore(Std.Date.DateFromParts(year, 10, 31))),
            year >= 1976 => (date >= SundayDateBefore(Std.Date.DateFromParts(year, 4, 30)) AND date < SundayDateBefore(Std.Date.DateFromParts(year, 10, 31))),
            year =  1975 => (date >= SundayDateBefore(Std.Date.DateFromParts(year, 2, 28)) AND date < SundayDateBefore(Std.Date.DateFromParts(year, 10, 31))),
            year =  1974 => (date >= SundayDateAfter(Std.Date.DateFromParts(year, 1, 1)) AND date < SundayDateBefore(Std.Date.DateFromParts(year, 10, 31))),
            year >= 1967 => (date >= SundayDateBefore(Std.Date.DateFromParts(year, 4, 30)) AND date < SundayDateBefore(Std.Date.DateFromParts(year, 10, 31))),
            year >= 1946 => FALSE, // DST not federally mandated (varied by locality)
            year =  1945 => (date < SundayDateBefore(Std.Date.DateFromParts(year, 9, 30))),
            year >= 1943 => TRUE, // "war time" (continuous DST)
            year =  1942 => (date >= SundayDateAfter(Std.Date.DateFromParts(year, 2, 1), 2)),
            year >= 1920 => FALSE, // DST not federally mandated (varied by locality)
            year >= 1918 => (date >= SundayDateBefore(Std.Date.DateFromParts(year, 3, 31)) AND date < SundayDateBefore(Std.Date.DateFromParts(year, 10, 31))),
            FALSE
        );
END;
