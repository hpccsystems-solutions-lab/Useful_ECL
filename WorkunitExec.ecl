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
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
IMPORT Std;

EXPORT WorkunitExec := MODULE

    /**
     * Helper function for creating the Authorization header value for
     * authenticated SOAPCALL requests.
     *
     * @param   username            The user name to use when connecting
     *                              to the cluster; REQUIRED
     * @param   userPW              The username password to use when
     *                              connecting to the cluster; REQUIRED
     *
     * @return  Authorization header value, or an empty string if username
     *          is empty (SOAPCALL omits the header if the return value
     *          is an empty string).
     */
    SHARED CreateAuthHeaderValue(STRING username, STRING userPW) := IF
        (
            TRIM(username, ALL) != '',
            'Basic ' + Std.Str.EncodeBase64((DATA)(TRIM(username, ALL) + ':' + TRIM(userPW, LEFT, RIGHT))),
            ''
        );

    /**
     * Helper function for ensuring we're using the right URL to contact
     * the esp service.
     *
     * @param   espURL              The full URL for accessing the esp process
     *                              running on the HPCC Systems cluster (this
     *                              is typically the same URL as used to access
     *                              ECL Watch); set to an empty string to use
     *                              the URL of the current esp process;
     *                              REQUIRED
     *
     * @return  The full URL for accessing the proper esp service.
     */
    SHARED CreateESPURL(STRING explicitURL) := FUNCTION
        trimmedURL := TRIM(explicitURL, ALL);
        myESPURL := IF(trimmedURL != '', trimmedURL, Std.File.GetEspURL()) + '/WsWorkunits/ver_=1.74';

        RETURN myESPURL;
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
     * @param   espURL              The full URL for accessing the esp process
     *                              running on the HPCC Systems cluster (this
     *                              is typically the same URL as used to access
     *                              ECL Watch); set to an empty string to use
     *                              the URL of the current esp process;
     *                              OPTIONAL, defaults to an empty string
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
                                     STRING espURL = '',
                                     DATASET(RunArgLayout) runArguments = DATASET([], RunArgLayout),
                                     BOOLEAN waitForCompletion = FALSE,
                                     STRING username = '',
                                     STRING userPW = '',
                                     UNSIGNED2 timeoutInSeconds = 0) := FUNCTION
        myESPURL := CreateESPURL(espURL);
        auth := CreateAuthHeaderValue(username, userPW);

        QueryResultsLayout := RECORD
            STRING  rWUID       {XPATH('Wuid')};
            STRING  rCluster    {XPATH('Cluster')};
        END;

        // Find the latest compiled version of a workunit that matches the
        // given jobName
        queryResults := SOAPCALL
            (
                myESPURL,
                'WUQuery',
                {
                    STRING pJobname {XPATH('Jobname')} := jobName;
                    STRING pState {XPATH('State')} := 'compiled';
                },
                DATASET(QueryResultsLayout),
                XPATH('WUQueryResponse/Workunits/ECLWorkunit'),
                HTTPHEADER('Authorization', auth),
                TIMEOUT(60), ONFAIL(SKIP)
            );
        latestWUID := TOPN(queryResults, 1, -rWUID)[1];

        // Call the found workunit with the arguments provided
        runResults := SOAPCALL
            (
                myESPURL,
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
                HTTPHEADER('Authorization', auth),
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
     * @param   espURL              The full URL for accessing the esp process
     *                              running on the HPCC Systems cluster (this
     *                              is typically the same URL as used to access
     *                              ECL Watch); set to an empty string to use
     *                              the URL of the current esp process;
     *                              OPTIONAL, defaults to an empty string
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
                                     STRING espURL = '',
                                     STRING username = '',
                                     STRING userPW = '',
                                     UNSIGNED2 timeoutInSeconds = 60) := FUNCTION
        myESPURL := CreateESPURL(espURL);
        auth := CreateAuthHeaderValue(username, userPW);

        QueryResultsLayout := RECORD
            STRING  rWUID       {XPATH('Wuid')};
            STRING  rState      {XPATH('State')};
        END;

        // Find the latest running (or blocked) version of a workunit that
        // matches the given jobName; note that this is a lightweight query
        // that may return results from a cache, so we'll need to verify
        // the results with a follow-up call to WUInfo
        initialQueryResults := SOAPCALL
            (
                myESPURL,
                'WUQuery',
                {
                    STRING pJobname {XPATH('Jobname')} := jobName;
                },
                DATASET(QueryResultsLayout),
                XPATH('WUQueryResponse/Workunits/ECLWorkunit'),
                HTTPHEADER('Authorization', auth),
                TIMEOUT(timeoutInSeconds), ONFAIL(SKIP)
            );

        filteredInitialResults := initialQueryResults(rState IN ['running', 'blocked']);

        infoResults := PROJECT
            (
                filteredInitialResults,
                TRANSFORM
                    (
                        QueryResultsLayout,
                        info := SOAPCALL
                            (
                                myESPURL,
                                'WUInfo',
                                {
                                    STRING  pWuid                       {XPATH('Wuid')} := LEFT.rWUID;
                                    STRING  pTruncateEclTo64k           {XPATH('TruncateEclTo64k')} := '1';
                                    STRING  pIncludeExceptions          {XPATH('IncludeExceptions')} := '0';
                                    STRING  pIncludeGraphs              {XPATH('IncludeGraphs')} := '0';
                                    STRING  pIncludeSourceFiles         {XPATH('IncludeSourceFiles')} := '0';
                                    STRING  pIncludeResults             {XPATH('IncludeResults')} := '0';
                                    STRING  pIncludeResultsViewNames    {XPATH('IncludeResultsViewNames')} := '0';
                                    STRING  pIncludeVariables           {XPATH('IncludeVariables')} := '0';
                                    STRING  pIncludeTimers              {XPATH('IncludeTimers')} := '0';
                                    STRING  pIncludeDebugValues         {XPATH('IncludeDebugValues')} := '0';
                                    STRING  pIncludeApplicationValues   {XPATH('IncludeApplicationValues')} := '0';
                                    STRING  pIncludeWorkflows           {XPATH('IncludeWorkflows')} := '0';
                                    STRING  pIncludeXmlSchemas          {XPATH('IncludeXmlSchemas')} := '0';
                                    STRING  pIncludeResourceURLs        {XPATH('IncludeResourceURLs')} := '0';
                                    STRING  pIncludeECL                 {XPATH('IncludeECL')} := '0';
                                    STRING  pIncludeHelpers             {XPATH('IncludeHelpers')} := '0';
                                    STRING  pIncludeAllowedClusters     {XPATH('IncludeAllowedClusters')} := '0';
                                    STRING  pIncludeTotalClusterTime    {XPATH('IncludeTotalClusterTime')} := '0';
                                    STRING  pSuppressResultSchemas      {XPATH('SuppressResultSchemas')} := '0';
                                },
                                DATASET(QueryResultsLayout),
                                XPATH('WUInfoResponse/Workunit'),
                                HTTPHEADER('Authorization', auth),
                                TIMEOUT(timeoutInSeconds), ONFAIL(SKIP)
                            );
                        SELF := info[1]
                    )
            );

        latestWUID := TOPN(infoResults(rState IN ['running', 'blocked']), 1, -rWUID)[1];

        RETURN latestWUID.rWUID;
    END;

    /**
     * Finds all running or blocked workunits in a cluster and returns their
     * workunit IDs and state.
     *
     * @param   clusterName         The name of the cluster in which to look
     *                              for running jobs; REQUIRED
     * @param   espURL              The full URL for accessing the esp process
     *                              running on the HPCC Systems cluster (this
     *                              is typically the same URL as used to access
     *                              ECL Watch); set to an empty string to use
     *                              the URL of the current esp process;
     *                              OPTIONAL, defaults to an empty string
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
     * @return  A new DATASET of all running or blocked workunits; thisWU will
     *          be TRUE if the rWUID is the same one as is running this
     *          function; may return an empty dataset, indicating that none
     *          have been found
     */
    EXPORT FindRunningWorkunitsInCluster(STRING clusterName,
                                         STRING espURL = '',
                                         STRING username = '',
                                         STRING userPW = '',
                                         UNSIGNED2 timeoutInSeconds = 60) := FUNCTION
        myESPURL := CreateESPURL(espURL);
        auth := CreateAuthHeaderValue(username, userPW);

        QueryResultsLayout := RECORD
            STRING  rWUID           {XPATH('Wuid')};
            STRING  rState          {XPATH('State')};
            STRING  rClusterName    {XPATH('Cluster')};
            STRING  rJobname        {XPATH('Jobname')};
            STRING  rOwner          {XPATH('Owner')};
            BOOLEAN thisWU := FALSE;
        END;

        // Find the latest running (or blocked) version of a workunit that
        // matches the given jobName
        queryResults0 := SOAPCALL
            (
                myESPURL,
                'WUQuery',
                {
                    STRING pClusterName {XPATH('Cluster')} := clusterName;
                },
                DATASET(QueryResultsLayout),
                XPATH('WUQueryResponse/Workunits/ECLWorkunit'),
                HTTPHEADER('Authorization', auth),
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
     * @param   resultName          The name of the result to retrieve; use
     *                              an empty string to retrieve all results
     *                              from the workunit; REQUIRED
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
     *          Note that the format of the XML for the results will differ
     *          depending on whether or not you supply resultName value.
     */
    EXPORT ExtractWorkunitResultByName(STRING workunitID,
                                       STRING resultName,
                                       STRING espURL = '',
                                       STRING username = '',
                                       STRING userPW = '',
                                       UNSIGNED2 timeoutInSeconds = 60) := FUNCTION
        myESPURL := CreateESPURL(espURL);
        auth := CreateAuthHeaderValue(username, userPW);

        NamedQueryResultsLayout := RECORD
            STRING  rWUID           {XPATH('Wuid')};        // WUID of found workunit
            STRING  rResultName     {XPATH('Name')};        // Name of result
            STRING  rResultValue    {XPATH('Result')};      // Result in XML format
        END;

        namedQueryResults := SOAPCALL
            (
                myESPURL,
                'WUResult',
                {
                    STRING pWUID {XPATH('Wuid')} := workunitID;
                    STRING pResultName {XPATH('ResultName')} := resultName;
                },
                DATASET(NamedQueryResultsLayout),
                XPATH('WUResultResponse'),
                HTTPHEADER('Authorization', auth),
                TIMEOUT(timeoutInSeconds), ONFAIL(SKIP)
            );

        FullQueryResultsLayout := RECORD
            STRING  rWUID           {XPATH('Wuid')};        // WUID of found workunit
            STRING  rResults        {XPATH('Results')};     // All results in XML format
        END;

        fullQueryResults := SOAPCALL
            (
                myESPURL,
                'WUFullResult',
                {
                    STRING pWUID {XPATH('Wuid')} := workunitID;
                },
                DATASET(FullQueryResultsLayout),
                XPATH('WUFullResultResponse'),
                HTTPHEADER('Authorization', auth),
                TIMEOUT(timeoutInSeconds), ONFAIL(SKIP)
            );

        parsedFullQueryResults := PARSE
            (
                fullQueryResults,
                rResults,
                TRANSFORM
                    (
                        NamedQueryResultsLayout,
                        SELF.rWUID := LEFT.rWUID,
                        SELF.rResultName := XMLTEXT('@name'),
                        SELF.rResultValue := XMLTEXT('<>'),
                        SELF := []
                    ),
                XML('Result/Dataset')
            );

        RETURN IF(resultName != '', namedQueryResults, parsedFullQueryResults);
    END;

    /**
     * Finds all protected workunits and returns their workunit IDs;
     *
     * @param   espURL              The full URL for accessing the esp process
     *                              running on the HPCC Systems cluster (this
     *                              is typically the same URL as used to access
     *                              ECL Watch); set to an empty string to use
     *                              the URL of the current esp process;
     *                              OPTIONAL, defaults to an empty string
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
     * @return  A new DATASET of all protected workunits; may return an empty
     *          dataset, indicating that no protected workunits have been found
     */
    EXPORT AllProtectedWorkunits(STRING espURL = '',
                                 STRING username = '',
                                 STRING userPW = '',
                                 UNSIGNED2 timeoutInSeconds = 0) := FUNCTION
        myESPURL := CreateESPURL(espURL);
        auth := CreateAuthHeaderValue(username, userPW);

        QueryResultsLayout := RECORD
            STRING  rWUID       {XPATH('Wuid')};
            STRING  rCluster    {XPATH('Cluster')};
            BOOLEAN rProtected  {XPATH('Protected')};
        END;

        // All workunits; we will filter later
        queryResults := SOAPCALL
            (
                myESPURL,
                'WUQuery',
                {
                    UNSIGNED2   pCount {XPATH('Count')} := 32767;
                    UNSIGNED4   pStartFrom {XPATH('PageStartFrom')} := 0;
                    UNSIGNED4   pPageSize {XPATH('PageSize')} := 32767;
                },
                DATASET(QueryResultsLayout),
                XPATH('WUQueryResponse/Workunits/ECLWorkunit'),
                HTTPHEADER('Authorization', auth),
                TIMEOUT(60), ONFAIL(SKIP)
            );

        RETURN queryResults(rProtected);
    END;

END;
