/**
 * Geocode an address or geographical place that is presented in string format.
 * The work is performed by a free service; see https://geocode.maps.co.
 * Note that this service is likely NOT suitable for Big Data geocoding work,
 * or extremely high volume.  The code here should probably be used for
 * something like translating input within a Roxie query, rather than
 * geocoding an huge dataset's worth of records.
 *
 * This code is presented as a module.  There are a couple of EXPORTed
 * attributes of interest:
 *
 *      CoordinatesRec      Record definition of the dataset returned by a
 *                          geocoding call.
 *      GeocodeAddress()    Function that actually makes the geocoding
 *                          call.  It returns a DATASET(CoordinatesRec)
 *                          dataset.
 *
 * Example calls are located at the end of this file.
 *
 * Origin:  https://github.com/hpccsystems-solutions-lab/Useful_ECL
 */
EXPORT Geo := MODULE

    // We use Str.URLEncode()
    IMPORT #$.Str;

    // Result's record definition
    EXPORT CoordinatesRec := RECORD
        UNSIGNED4   placeID;
        UTF8        name;
        STRING      placeType;
        STRING      placeClass;
        STRING      osmType;
        UNSIGNED4   osmID;
        REAL4       importance;
        DECIMAL9_6  centroidLat;
        DECIMAL9_6  centroidLon;
        DECIMAL9_6  northLat;
        DECIMAL9_6  southLat;
        DECIMAL9_6  eastLon;
        DECIMAL9_6  westLon;
    END;

    EXPORT CoordinatesRec GeocodeAddress(STRING address) := FUNCTION
        // Record structure for values we extract from reply; this is
        // the same as the final result, but with XPATH's defined
        ReplyRec := RECORD
            DECIMAL9_6      southLat    {XPATH('boundingbox[1]')};
            DECIMAL9_6      northLat    {XPATH('boundingbox[2]')};
            DECIMAL9_6      westLon     {XPATH('boundingbox[3]')};
            DECIMAL9_6      eastLon     {XPATH('boundingbox[4]')};
            DECIMAL9_6      centroidLat {XPATH('lat')};
            DECIMAL9_6      centroidLon {XPATH('lon')};
            UNSIGNED4       placeID     {XPATH('place_id')};
            UTF8            name        {XPATH('display_name')};
            STRING          placeType   {XPATH('type')};
            STRING          placeClass  {XPATH('class')};
            STRING          osmType     {XPATH('osm_type')};
            UNSIGNED4       osmID       {XPATH('osm_id')};
            REAL4           importance  {XPATH('importance')};
        END;

        // Wrapper for reply values, so we can capture a dataset
        // rather than just a row with FROMJSON
        ReplyWrapper := RECORD
            DATASET(ReplyRec)   d       {XPATH('d')};
        END;

        // Temp structure that pulls in entire reply as a string
        ReplyStrRec := RECORD
            UTF8                s       {XPATH('<>')};
        END;

        // Full URL we'll be calling
        url := 'https://geocode.maps.co/search?q=' + Str.URLEncode(address);

        // Call the URL and extract the results as a string
        replyAsString := HTTPCALL(url, 'GET', 'application/json', ReplyStrRec, XPATH('/'), TRIM);

        // Parse the JSON string
        parsedReply := FROMJSON
            (
                ReplyWrapper,
                '{"d": [' + replyAsString.s + ']}',
                ONFAIL(TRANSFORM(ReplyWrapper, SELF := []))
            );

        // Create final result
        coercedReply := PROJECT(parsedReply.d, CoordinatesRec);

        RETURN coercedReply;
    END;
END; // MODULE

/******************************************************************************

IMPORT Useful_ECL;

TestAddress(addr) := FUNCTIONMACRO
    #UNIQUENAME(name);
    %name% := REGEXREPLACE('^([^a-z])', REGEXREPLACE('[^[:alnum:]]+', #TEXT(addr), '_'), 'z_$1', NOCASE);
    RETURN OUTPUT(Useful_ECL.Geo.GeocodeAddress(addr), NAMED(%name%));
ENDMACRO;

TestAddress('Alpharetta, GA');
TestAddress('California');
TestAddress('Japan');
TestAddress('1 Infinite Loop, Cupertino, CA 95014-2084');

*/
