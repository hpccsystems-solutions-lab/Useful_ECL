/**
 * Module containing code for executing a compiled workunit by name.
 * The code will find the most recent workunit with the given jobname
 * that is in the compiled state, then execute that workunit with the
 * given arguments.  The workunit is cloned, so there will be a new workunit
 * with the same jobname in the workunit list.
 *
 * Note that Sasha archives workunits after a period of time (default one
 * week) and if the compiled workunit you are trying to execute has been
 * archived, this code will not be able to find it.  To prevent Sasha from
 * archiving those compiled workunits, mark them as "Protected".
 */
IMPORT Std;

EXPORT WorkunitExec := MODULE

    /**
     * Helper function for encoding special characters in strings that will
     * eventually make it into URLs.  The following characters are encoded:
     *      % -> %25
     *      @ -> %40
     *
     * @param   s                   The string to encode; REQUIRED
     *
     * @return  The argument, encoded.
     */
    SHARED EncodeString(STRING s) := FUNCTION
        s1 := REGEXREPLACE('%', s, '%25');
        s2 := REGEXREPLACE('@', s1, '%40');

        RETURN s2;
    END;

    /**
     * Helper function for creating a complete URL suitable for SOAPCALL
     *
     * @param   username            The user name to use when connecting
     *                              to the cluster; the special characters
     *                              '%' and '@' should not be encoded; REQUIRED
     * @param   userPW              The username password to use when
     *                              connecting to the cluster; the special
     *                              characters '%' and '@' should not be
     *                              encoded; REQUIRED
     * @param   espScheme           The scheme (http, https, etc) to use
     *                              when constructing the full URL to the
     *                              ESP service; REQUIRED
     * @param   espIPAddress        The IP address of the ESP service, as
     *                              a string; REQUIRED
     * @param   espPort             The port number to use when connecting
     *                              to the cluster; REQUIRED
     *
     * @return  A URL suitable for use in SOAPCALL invocations
     */
    SHARED CreateESPURL(STRING username,
                        STRING userPW,
                        STRING espScheme,
                        STRING espIPAddress,
                        UNSIGNED2 espPort) := FUNCTION
        fullUserInfo := MAP
            (
                username != '' AND userPW != '' => EncodeString(username) + ':' + EncodeString(userPW) + '@',
                username != ''  =>  EncodeString(username) + '@',
                ''
            );

        url := espScheme + '://' + TRIM(fullUserInfo, LEFT, RIGHT) + espIPAddress + ':' + (STRING)espPort + '/WsWorkunits/';

        RETURN url;
    END;

    /**
     * Record structure containing arguments to be passed to the workunit
     * that will be executed.  The 'name' attribute should match the
     * STORED argument for a attribute in the workunit to be executed;
     * the value will be passed in.
     */
    EXPORT RunArgLayout := RECORD
        STRING      name    {XPATH('Name')};
        STRING      value   {XPATH('Value')};
    END;

    /**
     * Record structure used to represent the results of running a
     * workunit.
     */
    EXPORT RunResultsLayout := RECORD
        STRING  wuid    {XPATH('Wuid')};
        STRING  state   {XPATH('State')};
        STRING  results {XPATH('Results')};
    END;

    /**
     * Finds the latest version of a workunit, by name, and executes it
     * with new arguments.  The arguments are mapped to the STORED
     * attributes in the workunit by name.
     *
     * Remember that Thor typically executes only a single workunit at
     * a time.  Unless you have a special cluster configuration that allows
     * you to run multiple Thor workunits simultaneously, you should avoid
     * trying to invoke a compiled Thor workunit from a Thor job.  The
     * result will be a hung Thor cluster, as the first job will be waiting
     * for the second job to complete, while the second job will be waiting for
     * the first to complete.
     *
     * @param   jobName             The jobname of the workunit to execute
     *                              as a string; REQUIRED
     * @param   espIPAddress        The IP address of the ESP service, as
     *                              a string; REQUIRED
     * @param   espScheme           The scheme (http, https, etc) to use
     *                              when constructing the full URL to the
     *                              ESP service; OPTIONAL, defaults
     *                              to 'http'
     * @param   espPort             The port number to use when connecting
     *                              to the cluster; OPTIONAL, defaults to
     *                              8010
     * @param   runArguments        Dataset in RunArgLayout format
     *                              containing key/value pairs of arguments
     *                              to pass to the workunit to execute;
     *                              the 'name' portion of this dataset will
     *                              be mapped to the STORED attributes in
     *                              the workunit; OPTIONAL, defaults to an
     *                              empty dataset
     * @param   waitForCompletion   Boolean indicating whether this function
     *                              should wait for the found workunit to
     *                              complete before continuing; OPTIONAL,
     *                              defaults to FALSE
     * @param   username            The user name to use when connecting
     *                              to the cluster; OPTIONAL, defaults to
     *                              an empty string
     * @param   userPW              The username password to use when
     *                              connecting to the cluster; OPTIONAL,
     *                              defaults to an empty string
     * @param   timeoutInSeconds    The number of seconds to wait for the
     *                              executed job to complete; use zero (0) to
     *                              wait forever; OPTIONAL, defaults to zero
     *
     * @return  A dataset in RunResultsLayout format containing run
     *          results.  If no workunit matching the given jobname can be
     *          found then an empty dataset will be returned.  Because
     *          this function returns a value, you should wrap a call to
     *          it in an EVALUATE() if you need to execute it in an
     *          action context.
     */
    EXPORT RunCompiledWorkunitByName(STRING jobName,
                                     STRING espIPAddress,
                                     STRING espScheme = 'http',
                                     UNSIGNED2 espPort = 8010,
                                     DATASET(RunArgLayout) runArguments = DATASET([], RunArgLayout),
                                     BOOLEAN waitForCompletion = FALSE,
                                     STRING username = '',
                                     STRING userPW = '',
                                     UNSIGNED2 timeoutInSeconds = 0) := FUNCTION
        espURL := CreateESPURL(username, userPW, espScheme, espIPAddress, espPort);

        QueryResultsLayout := RECORD
            STRING  rWUID       {XPATH('Wuid')};
            STRING  rCluster    {XPATH('Cluster')};
        END;

        // Find the latest compiled version of a workunit that matches the
        // given jobName
        queryResults := SOAPCALL
            (
                espURL,
                'WUQuery',
                {
                    STRING pJobname {XPATH('Jobname')} := jobName;
                    STRING pState {XPATH('State')} := 'compiled';
                },
                DATASET(QueryResultsLayout),
                XPATH('WUQueryResponse/Workunits/ECLWorkunit'),
                TIMEOUT(60), ONFAIL(SKIP)
            );
        latestWUID := TOPN(queryResults, 1, -rWUID)[1];

        // Call the found workunit with the arguments provided
        runResults := SOAPCALL
            (
                espURL,
                'WURun',
                {
                    STRING pWUID {XPATH('Wuid')} := latestWUID.rWUID;
                    STRING pCluster {XPATH('Cluster')} := latestWUID.rCluster;
                    STRING pWait {XPATH('Wait')} := IF(waitForCompletion, '-1', '0');
                    STRING pCloneWorkunit {XPATH('CloneWorkunit')} := '1';
                    DATASET(RunArgLayout) pRunArgs {XPATH('Variables/NamedValue')} := runArguments;
                },
                DATASET(RunResultsLayout),
                XPATH('WURunResponse'),
                TIMEOUT(timeoutInSeconds), ONFAIL(SKIP)
            );

        RETURN IF(EXISTS(queryResults), runResults, DATASET([], RunResultsLayout));
    END;

    /**
     * Finds the latest version of a running workunit, by name, and return
     * its workunit ID.
     *
     * @param   jobName             The jobname of the workunit to execute
     *                              as a string; REQUIRED
     * @param   espIPAddress        The IP address of the ESP service, as
     *                              a string; REQUIRED
     * @param   espScheme           The scheme (http, https, etc) to use
     *                              when constructing the full URL to the
     *                              ESP service; OPTIONAL, defaults
     *                              to 'http'
     * @param   espPort             The port number to use when connecting
     *                              to the cluster; OPTIONAL, defaults to
     *                              8010
     * @param   username            The user name to use when connecting
     *                              to the cluster; OPTIONAL, defaults to
     *                              an empty string
     * @param   userPW              The username password to use when
     *                              connecting to the cluster; OPTIONAL,
     *                              defaults to an empty string
     * @param   timeoutInSeconds    The number of seconds to wait for the
     *                              executed job to complete; use zero (0) to
     *                              wait forever; OPTIONAL, defaults to 60
     *
     * @return  The workunit ID of the found workunit or an empty string if
     *          a running workunit with that name cannot be found
     */
    EXPORT FindRunningWorkunitByName(STRING jobName,
                                     STRING espIPAddress,
                                     STRING espScheme = 'http',
                                     UNSIGNED2 espPort = 8010,
                                     STRING username = '',
                                     STRING userPW = '',
                                     UNSIGNED2 timeoutInSeconds = 60) := FUNCTION
        espURL := CreateESPURL(username, userPW, espScheme, espIPAddress, espPort);

        QueryResultsLayout := RECORD
            STRING  rWUID       {XPATH('Wuid')};
            STRING  rState      {XPATH('State')};
        END;

        // Find the latest running (or blocked) version of a workunit that
        // matches the given jobName
        queryResults := SOAPCALL
            (
                espURL,
                'WUQuery',
                {
                    STRING pJobname {XPATH('Jobname')} := jobName;
                },
                DATASET(QueryResultsLayout),
                XPATH('WUQueryResponse/Workunits/ECLWorkunit'),
                TIMEOUT(timeoutInSeconds), ONFAIL(SKIP)
            );
        latestWUID := TOPN(queryResults(rState IN ['running', 'blocked']), 1, -rWUID)[1];

        RETURN latestWUID.rWUID;
    END;

    /**
     * Finds all running or blocked workunits in a cluster and returns their
     * workunit IDs and state.
     *
     * @param   clusterName         The name of the cluster in which to look
     *                              for running jobs; REQUIRED
     * @param   espIPAddress        The IP address of the ESP service, as
     *                              a string; REQUIRED
     * @param   espScheme           The scheme (http, https, etc) to use
     *                              when constructing the full URL to the
     *                              ESP service; OPTIONAL, defaults
     *                              to 'http'
     * @param   espPort             The port number to use when connecting
     *                              to the cluster; OPTIONAL, defaults to
     *                              8010
     * @param   username            The user name to use when connecting
     *                              to the cluster; OPTIONAL, defaults to
     *                              an empty string
     * @param   userPW              The username password to use when
     *                              connecting to the cluster; OPTIONAL,
     *                              defaults to an empty string
     * @param   timeoutInSeconds    The number of seconds to wait for the
     *                              executed job to complete; use zero (0) to
     *                              wait forever; OPTIONAL, defaults to 60
     *
     * @return  A new DATASET({STRING rWUID, STRING rState, BOOLEAN thisWUI})
     *          of all running or blocked workunits; thisWU will be TRUE if
     *          the rWUID is the same one as is running this function; may
     *          return an empty dataset, indicating that none have been found
     */
    EXPORT FindRunningWorkunitsInCluster(STRING clusterName,
                                         STRING espIPAddress,
                                         STRING espScheme = 'http',
                                         UNSIGNED2 espPort = 8010,
                                         STRING username = '',
                                         STRING userPW = '',
                                         UNSIGNED2 timeoutInSeconds = 60) := FUNCTION
        espURL := CreateESPURL(username, userPW, espScheme, espIPAddress, espPort);

        QueryResultsLayout := RECORD
            STRING  rWUID       {XPATH('Wuid')};
            STRING  rState      {XPATH('State')};
            BOOLEAN thisWU := FALSE;
        END;

        // Find the latest running (or blocked) version of a workunit that
        // matches the given jobName
        queryResults0 := SOAPCALL
            (
                espURL,
                'WUQuery',
                {
                    STRING pClusterName {XPATH('Cluster')} := clusterName;
                },
                DATASET(QueryResultsLayout),
                XPATH('WUQueryResponse/Workunits/ECLWorkunit'),
                TIMEOUT(timeoutInSeconds), ONFAIL(SKIP)
            );

        queryResults := PROJECT
            (
                queryResults0(rState IN ['running', 'blocked']),
                TRANSFORM
                    (
                        RECORDOF(LEFT),
                        SELF.thisWU := LEFT.rWUID = Std.System.Job.WUID(),
                        SELF := LEFT
                    )
            );

        RETURN queryResults;
    END;

    /**
     * Extract, by name, one result stored within a workunit.  Because a
     * workunit result can be of any data type, the returned value will be a
     * STRING containing an XML document.
     *
     * Example PARSE for extracting a single string value from a result named
     * 'foo' from the results of this call:
     *
     * parsedData := PARSE
     *     (
     *         resultOfFunctionCall,
     *         rResultValue,
     *         TRANSFORM
     *             (
     *                 {
     *                     STRING  fooValue
     *                 },
     *                 SELF.fooValue := XMLTEXT('foo')
     *             ),
     *         XML('Dataset/Row')
     *     );
     *
     * @param   workunitID          The WUID of the workunit containing the
     *                              result; REQUIRED
     * @param   resultName          The name of the result to retrieve;
     *                              REQUIRED
     * @param   espIPAddress        The IP address of the ESP service, as
     *                              a string; REQUIRED
     * @param   espScheme           The scheme (http, https, etc) to use
     *                              when constructing the full URL to the
     *                              ESP service; OPTIONAL, defaults
     *                              to 'http'
     * @param   espPort             The port number to use when connecting
     *                              to the cluster; OPTIONAL, defaults to
     *                              8010
     * @param   username            The user name to use when connecting
     *                              to the cluster; OPTIONAL, defaults to
     *                              an empty string
     * @param   userPW              The username password to use when
     *                              connecting to the cluster; OPTIONAL,
     *                              defaults to an empty string
     * @param   timeoutInSeconds    The number of seconds to wait for the
     *                              executed job to complete; use zero (0) to
     *                              wait forever; OPTIONAL, defaults to 60
     *
     * @return  A new DATASET({STRING rWUID, STRING rResultname, STRING rResultVAlue})
     *          containing the results of the call.  If it is non-empty then
     *          the call was successful.  The rResultValue attribute will
     *          contain the workunit's result in XML format; this document
     *          will need to be parsed to extract the actual stored value.
     */
    ExtractWorkunitResultByName(STRING workunitID,
                                STRING resultName,
                                STRING espIPAddress,
                                STRING espScheme = 'http',
                                UNSIGNED2 espPort = 8010,
                                STRING username = '',
                                STRING userPW = '',
                                UNSIGNED2 timeoutInSeconds = 60) := FUNCTION
        espURL := CreateESPURL(username, userPW, espScheme, espIPAddress, espPort);

        QueryResultsLayout := RECORD
            STRING  rWUID           {XPATH('Wuid')};        // WUID of found workunit
            STRING  rResultName     {XPATH('Name')};        // Name of result
            STRING  rResultValue    {XPATH('Result')};      // Result in XML format
        END;

        queryResults := SOAPCALL
            (
                espURL,
                'WUResult',
                {
                    STRING pWUID {XPATH('Wuid')} := workunitID;
                    STRING pResultName {XPATH('ResultName')} := resultName;
                },
                DATASET(QueryResultsLayout),
                XPATH('WUResultResponse'),
                TIMEOUT(timeoutInSeconds), ONFAIL(SKIP)
            );

        RETURN queryResults;
    END;

END;
