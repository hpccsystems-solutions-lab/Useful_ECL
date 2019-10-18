/**
 * Simple function that tests a full version string against the individual
 * platform version constants to determine if the platform's version is at
 * least as high as the argument.
 *
 * Note that this function will be evaluated at compile-time if the argument
 * is a constant.  This makes it useful for embedding in #IF() declarations:
 *
 *      #IF(PlatformVersionCheck('6.2.0-1'))
 *          OUTPUT('Platform check TRUE');
 *      #ELSE
 *          OUTPUT('Platform check FALSE');
 *      #END
 *
 * This function can be found in the standard library as of version 7.2.0
 * (Std.System.Util.PlatformVersionCheck).
 *
 * @param   v       The minimum platform version in either xx.xx.xx, xx.xx,
 *                  or xx format (where xx is an integer and does not need
 *                  to be zero-padded)
 *
 * @return  If TRUE, the platform's current version is equal to or higher than
 *          the argument.
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
EXPORT PlatformVersionCheck(STRING v) := FUNCTION
    major := (INTEGER)REGEXFIND('^(\\d+)', v, 1);
    minor := (INTEGER)REGEXFIND('^\\d+\\.(\\d+)', v, 1);
    subminor := (INTEGER)REGEXFIND('^\\d+\\.\\d+\\.(\\d+)', v, 1);

    RETURN MAP
        (
            __ecl_version_major__ > major                                                                               =>  TRUE,
            __ecl_version_major__ = major AND __ecl_version_minor__ > minor                                             =>  TRUE,
            __ecl_version_major__ = major AND __ecl_version_minor__ = minor AND __ecl_version_subminor__ >= subminor    =>  TRUE,
            FALSE
        );
END;
