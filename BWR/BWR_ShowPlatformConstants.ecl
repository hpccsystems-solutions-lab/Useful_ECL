/**
 * Shows the current value of some internal attributes that you can access
 * from ECL.  Some of them are hard-coded (like the ECL version numbers) while
 * others are determined when the HPCC platform starts up.
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
OUTPUT(__ecl_legacy_mode__, NAMED('__ecl_legacy_mode__'));
OUTPUT(__ecl_version__, NAMED('__ecl_version__'));
OUTPUT(__ecl_version_major__, NAMED('__ecl_version_major__'));
OUTPUT(__ecl_version_minor__, NAMED('__ecl_version_minor__'));
OUTPUT(__ecl_version_subminor__, NAMED('__ecl_version_subminor__'));
OUTPUT(__line__, NAMED('__line__'));
OUTPUT(__os__, NAMED('__os__'));
OUTPUT(__platform__, NAMED('__platform__'));
OUTPUT(__stand_alone__, NAMED('__stand_alone__'));
