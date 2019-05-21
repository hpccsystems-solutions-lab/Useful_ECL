/**
 * Code that examines a workunit looks for input files with "bad" data skews.
 * Such files may cause poor performance if the skew is not addressed by
 * ECL code.
 *
 * This code can either be run as a batch job under any of the HPCC engines
 * or it can be compiled and published as a Roxie or hThor query.
 *
 * If run as a batch job, you should supply values for the following
 * ECL attributes:
 *
 *      WORKUNIT_ID
 *      ESP_URL
 *      ESP_USER
 *      ESP_USER_PW
 *
 * If run as a query, these parameters can be supplied at run time.  The
 * descriptions for each are below.  Note that if run as a query, the default
 * values below are still in effect even though they will not appear on the
 * default query form.
 *
 * There are two results from this code:  Skew information on all of the files
 * that are used by the given workunit, and a subset of those files that may
 * have "bad" skew values (meaning, you should perhaps consider redistributing
 * their data or otherwise taking the skew into account).
 */
IMPORT Std;

#WORKUNIT('name', 'File Part Analyzer');

// The workunit ID to inspect; this code will find that workunit's input
// files and analyze them for skew
STRING WORKUNIT_ID := '' : STORED('Workunit_ID', FORMAT(SEQUENCE(100)));

// ESP (ECL Watch) information for the cluster you will be inspecting; defaults
// to the same ESP process this job is running on
STRING ESP_URL := Std.File.GetEspURL() : STORED('ESP_URL', FORMAT(SEQUENCE(200)));

// Any authentication needed to access the ESP process
STRING ESP_USER := '' : STORED('Username', FORMAT(SEQUENCE(300)));
STRING ESP_USER_PW := '' : STORED('User_Password', FORMAT(SEQUENCE(400), PASSWORD));

//==============================================================================

IF(WORKUNIT_ID = '', FAIL('A workunit ID must be supplied'));

// Authentication header for SOAPCALL
auth := IF
    (
        TRIM(ESP_USER, ALL) != '',
        'Basic ' + Std.Str.EncodeBase64((DATA)(TRIM(ESP_USER, ALL) + ':' + TRIM(ESP_USER_PW, ALL))),
        ''
    );

//------------------------------------------------------------------------------
// Get list of input files used by workunit
//------------------------------------------------------------------------------
FileNameInfo := RECORD
    STRING      name        {XPATH('Name')};
    BOOLEAN     isSuperFile {XPATH('IsSuperFile')};
END;

initialFilenameList := SOAPCALL
    (
        ESP_URL + '/WsWorkunits?ver_=1.62', // Verified with platform 6.2.20-1
        'WUInfo',
        {
            STRING      wuid                        {XPATH('Wuid')} := WORKUNIT_ID,
            BOOLEAN     includeExceptions           {XPATH('IncludeExceptions')} := FALSE,
            BOOLEAN     includeGraphs               {XPATH('IncludeGraphs')} := FALSE,
            BOOLEAN     includeSourceFiles          {XPATH('IncludeSourceFiles')} := TRUE,
            BOOLEAN     includeResults              {XPATH('IncludeResults')} := FALSE,
            BOOLEAN     includeVariables            {XPATH('IncludeVariables')} := FALSE,
            BOOLEAN     includeTimers               {XPATH('IncludeTimers')} := FALSE,
            BOOLEAN     includeDebugValues          {XPATH('IncludeDebugValues')} := FALSE,
            BOOLEAN     includeApplicationValues    {XPATH('IncludeApplicationValues')} := FALSE,
            BOOLEAN     includeWorkflows            {XPATH('IncludeWorkflows')} := FALSE
        },
        DATASET(FileNameInfo),
        XPATH('WUInfoResponse/Workunit/SourceFiles/ECLSourceFile'),
        HTTPHEADER('Authorization', auth)
    );

// initialFilenameList may contain superfiles; expand them if possible
expandedFilenameList := NOTHOR
    (
        PROJECT
            (
                GLOBAL(initialFilenameList, FEW),
                TRANSFORM
                    (
                        {
                            DATASET(Std.File.FsLogicalFileNameRecord)   logicalFiles
                        },
                        SELF.logicalFiles := IF(LEFT.isSuperFile, Std.File.SuperFileContents('~' + LEFT.name, TRUE), DATASET([LEFT.name], Std.File.FsLogicalFileNameRecord))
                    )
            )
    );

fullFilenameList := NORMALIZE
    (
        expandedFilenameList,
        LEFT.logicalFiles,
        TRANSFORM
            (
                FileNameInfo,
                SELF.name := RIGHT.name,
                SELF.isSuperFile := FALSE
            )
    );

filenameList := DEDUP(SORT(fullFilenameList, name), name);

//------------------------------------------------------------------------------
// Get topology information so we know what names are used for Thor clusters
//------------------------------------------------------------------------------
ClusterNameRec := RECORD
    STRING      cluster_name    {XPATH('Name')};
END;

TopologyRec := RECORD
    STRING                      cluster_type {XPATH('Type')};
    DATASET(ClusterNameRec)     clusters     {XPATH('TpClusters/TpCluster')};
END;

rawTopologyInfo := SOAPCALL
    (
        ESP_URL + '/WsTopology?ver_=1.25', // Verified with platform 6.2.20-1
        'TpTargetClusterQuery',
        {
            STRING  pType {XPATH('Type')} := ''
        },
        DATASET(TopologyRec),
        XPATH('TpTargetClusterQueryResponse/TpTargetClusters/TpTargetCluster'),
        HTTPHEADER('Authorization', auth),
        TRIM
    );

topologyInfo := NORMALIZE
    (
        rawTopologyInfo,
        LEFT.clusters,
        TRANSFORM
            (
                {
                    STRING      cluster_type,
                    STRING      cluster_name
                },
                SELF.cluster_type := IF(LEFT.cluster_type = 'ThorCluster', 'thor', SKIP),
                SELF.cluster_name := IF(RIGHT.cluster_name != '', RIGHT.cluster_name, SELF.cluster_type)
            )
    );

//------------------------------------------------------------------------------
// Get file part information for all files that matched the file name pattern
//------------------------------------------------------------------------------
RawFilePartRec := RECORD
    UNSIGNED1                   part_id             {XPATH('Id')};
    UNSIGNED1                   copy_num            {XPATH('Copy')};
    STRING                      ip_address          {XPATH('Ip')};
    STRING                      part_size_bytes     {XPATH('Partsize')};
END;

RawClusterInfoRec := RECORD
    STRING                      cluster_name        {XPATH('Cluster')};
    DATASET(RawFilePartRec)     file_parts          {XPATH('DFUFileParts/DFUPart')};
END;

RawResultRec := RECORD
    STRING                      file_name           {XPATH('Name')};
    STRING                      owner               {XPATH('Owner')};
    STRING                      file_size_bytes     {XPATH('Filesize')};
    STRING                      record_size_bytes   {XPATH('Recordsize')};
    STRING                      record_cnt          {XPATH('RecordCount')};
    DATASET(RawClusterInfoRec)  clusterInfo         {XPATH('DFUFilePartsOnClusters[1]/DFUFilePartsOnCluster')};
END;

DFUInfoParamRec := RECORD
    STRING  pfile_name {XPATH('Name')};
END;

dfuInfoRawResults := SOAPCALL
    (
        filenameList,
        ESP_URL + '/WsDFU?ver_=1.34', // Verified with platform 6.2.20-1
        'DFUInfo',
        DFUInfoParamRec,
        TRANSFORM
            (
                DFUInfoParamRec,
                SELF.pfile_name := LEFT.name
            ),
        DATASET(RawResultRec),
        XPATH('DFUInfoResponse/FileDetail'),
        HTTPHEADER('Authorization', auth),
        TRIM
    );

//------------------------------------------------------------------------------
// Normalize one level, hoisting the cluster name up to the file_name level
//------------------------------------------------------------------------------
DFUResultRec2 := RECORD
    STRING                      file_name;
    STRING                      owner;
    UNSIGNED8                   file_size_bytes;
    UNSIGNED8                   record_size_bytes;
    UNSIGNED8                   record_cnt;
    STRING                      cluster_name;
    DATASET(RawFilePartRec)     file_parts;
END;

normalizedDFUInfoResults := NORMALIZE
    (
        DISTRIBUTE(dfuInfoRawResults),
        LEFT.clusterInfo,
        TRANSFORM
            (
                DFUResultRec2,
                SELF.cluster_name := RIGHT.cluster_name,
                SELF.file_parts := RIGHT.file_parts,
                SELF.file_size_bytes := (UNSIGNED8)Std.Str.FilterOut(LEFT.file_size_bytes, ','),
                SELF.record_size_bytes := (UNSIGNED8)Std.Str.FilterOut(LEFT.record_size_bytes, ','),
                SELF.record_cnt := (UNSIGNED8)Std.Str.FilterOut(LEFT.record_cnt, ','),
                SELF := LEFT
            )
    );

//------------------------------------------------------------------------------
// Filter so that only file_names belonging to a Thor cluster remain
//------------------------------------------------------------------------------
onlyThorData := JOIN
    (
        normalizedDFUInfoResults,
        topologyInfo,
        LEFT.cluster_name = RIGHT.cluster_name,
        TRANSFORM(LEFT),
        LOOKUP
    );

//------------------------------------------------------------------------------
// Normalize file part information; we'll wind up with one record per file
// part
//------------------------------------------------------------------------------
FilePartRec := RECORD
    UNSIGNED1                   part_id;
    UNSIGNED8                   part_size_bytes;
    DECIMAL9_2                  part_skew_pct;
END;

DFUResultRec3 := RECORD
    STRING                      file_name;
    STRING                      owner;
    UNSIGNED8                   file_size_bytes;
    UNSIGNED8                   record_size_bytes;
    UNSIGNED8                   record_cnt;
    STRING                      cluster_name;
    FilePartRec;
END;

flattenedResults := NORMALIZE
    (
        onlyThorData,
        LEFT.file_parts(copy_num = 1), // Look at only the first copy of a file
        TRANSFORM
            (
                DFUResultRec3,

                REAL idealpart_size_bytes := LEFT.file_size_bytes / MAX(LEFT.file_parts, part_id);

                SELF.part_size_bytes := (UNSIGNED8)Std.Str.FilterOut(RIGHT.part_size_bytes, ','),
                SELF.part_skew_pct := ((REAL)SELF.part_size_bytes - idealpart_size_bytes) / idealpart_size_bytes * 100,
                SELF := RIGHT,
                SELF := LEFT
            )
    );

//------------------------------------------------------------------------------
// Simple analysis of the flattened results
//------------------------------------------------------------------------------
analysis := TABLE
    (
        flattenedResults,
        {
            file_name,
            owner,
            cluster_name,
            file_size_bytes,
            record_cnt,
            UNSIGNED2   file_part_cnt := COUNT(GROUP),
            DECIMAL9_2  min_part_skew_pct := MIN(GROUP, part_skew_pct),
            DECIMAL9_2  max_part_skew_pct := MAX(GROUP, part_skew_pct),
            UNSIGNED2   num_high_skew := SUM(GROUP, IF(part_skew_pct >= 100, 1, 0)),
            UNSIGNED2   num_low_skew := SUM(GROUP, IF(part_skew_pct <= -70, 1, 0)),
            UNSIGNED2   num_index_parts := SUM(GROUP, IF(part_size_bytes = 32768, 1, 0)) // Kind of a hack
        },
        file_name, owner, cluster_name, file_size_bytes, record_cnt,
        LOCAL
    );

maxFilePartCnt := MAX(analysis, file_part_cnt);

flaggedAnalysis := PROJECT
    (
        analysis,
        TRANSFORM
            (
                {
                    BOOLEAN     flagged,
                    RECORDOF(LEFT)
                },
                SELF.flagged := MAP
                    (
                        LEFT.num_index_parts = 1                                =>  FALSE, // Don't flag index files stored on Thor
                        LEFT.file_size_bytes < 2000000                          =>  FALSE, // Don't flag small (<2MB) files
                        LEFT.max_part_skew_pct >= (90 * (maxFilePartCnt - 1))   =>  TRUE,
                        LEFT.num_high_skew > 1                                  =>  TRUE,
                        LEFT.num_low_skew > 1                                   =>  TRUE,
                        LEFT.min_part_skew_pct = -100                           =>  TRUE,
                        FALSE
                    ),
                SELF := LEFT
            )
    );

//------------------------------------------------------------------------------
// Attach detailed part information to each file
//------------------------------------------------------------------------------
summary := DENORMALIZE
    (
        flaggedAnalysis,
        flattenedResults,
        LEFT.file_name = RIGHT.file_name
            AND LEFT.cluster_name = RIGHT.cluster_name,
        GROUP,
        TRANSFORM
            (
                {
                    RECORDOF(LEFT) - [file_part_cnt, num_high_skew, num_low_skew, num_index_parts],
                    DATASET(FilePartRec)    partInfo
                },
                SELF.partInfo := PROJECT(ROWS(RIGHT), TRANSFORM(FilePartRec, SELF := LEFT)),
                SELF := LEFT
            )
    );

//------------------------------------------------------------------------------
// Output final results
//------------------------------------------------------------------------------
sortedSummary := SORT(summary, -max_part_skew_pct, min_part_skew_pct);

OUTPUT(sortedSummary, NAMED('AllFiles'), NOXPATH);
OUTPUT(sortedSummary(flagged), NAMED('FlaggedFiles'), NOXPATH);
