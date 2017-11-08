/**
 * Provide delta copy functionality for files and superfiles that match
 * one or more filename patterns.
 *
 * This is strictly a "pull" copy scheme where the intention is to make the
 * local system (whatever is running this code) "mirror" the remote system,
 * strictly for those files that match one or more of the given filename
 * patterns.  Care should be taken when specifying filename patterns, especially
 * those with prefix and suffix wildcards (e.g. *fubar*).  Any local file or
 * superfile that matches a pattern is subject to modification or deletion,
 * depending on whether that file exists on the remote system or not.  It is
 * easy to lose local files that way, by inadvertently referencing them with
 * a filename pattern intended for something else.
 *
 * The full contents of superfiles will be copied as well, even if the subfiles
 * do not match any of the filename patterns.  Relatedly, superfile contents
 * are modified if necessary, such as when the remote system lists different
 * subfiles for a superfile that the local system already has.  In that case,
 * the code will copy any subfiles (if necessary) and alter the superfile
 * relationships so they match the remote system.
 *
 * Regular files are copied only if necessary.  If a file already exists in both
 * the systems, it is examined for change (size, content or metadata) and
 * copied only if a difference is found.
 *
 * Optional cluster name mapping is supported.  This covers the case where a
 * remote file may exist on a cluster with a name that doesn't exist on the
 * local system.  The most common example is probably 'thor' vs. 'mythor' --
 * two common Thor cluster names that seem to pop up in simple configurations.
 * The map indicates on which destination cluster to put a new or modified
 * file, given the name of the remote cluster.
 *
 * The code can be executed in "dry run" mode (which is the default).  In this
 * mode, every action that would normally be taken is compiled into a list of
 * commands and then displayed in a workunit result.  This gives you the
 * opportunity to see what the code would do if only given the chance.
 *
 * This code must be executed on the hthor HPCC engine.  If you try to execute
 * it on a different engine then it will fail with an informative error.
 *
 * KNOWN LIMITATION:  This code will not correctly process Roxie indexes that
 * are in use on the local system and need to be modified, nor will it update
 * local Roxie queries that need new data coming in from the remote system.
 *
 * Exported functions:
 *
 *  - CollectFileInfo:  Collects and analyzes file information
 *  - Go:               Executes information from CollectFileInfo()
 *
 * Example code is provided in a comment block at the end of this file.
 */
IMPORT Std;

EXPORT DataPull := MODULE

    // Action indicators
    EXPORT SYNC_ACTION := ENUM
        (
            UNSIGNED1,
                UNKNOWN = 0,
                ADD = 1,
                MODIFY = 2,
                DELETE_FILE = 3,
                DELETE_SUPERFILE = 4
        );

    // Map from one cluster to another, used to place a file on a local cluster
    // when the local cluster's name does not match the remote cluster's name
    EXPORT ClusterMapRec := RECORD
        STRING          remoteCluster;
        STRING          localCluster;
    END;

    // Collected information about files
    EXPORT FileInfoRec := RECORD
        UNSIGNED2       level;
        Std.File.FsLogicalFileInfoRecord;
        STRING          fileCRC;
        STRING          formatCRC;
    END;

    // Collected information about superfile/subfile relationships
    EXPORT SuperfileRelationshipRec := RECORD
        STRING          superFilePath;
        STRING          subFilePath;
        BOOLEAN         subFileIsSuperfile;
        UNSIGNED2       level;
    END;

    // Information regarding a file that must be modified
    EXPORT FileActionRec := RECORD
        STRING          path;
        STRING          sourceCluster;
        BOOLEAN         isSuperFile;
        SYNC_ACTION     syncAction;
    END;

    // Information regarding a superfile relationship that must be modified
    EXPORT SuperFileActionRec := RECORD
        STRING          superFilePath;
        STRING          subFilePath;
        SYNC_ACTION     syncAction;
    END;

    // Summarization of actions compiled by processing FileActionRec and
    // SuperFileActionRec data
    EXPORT ActionSummaryRec := RECORD
        STRING          actionDescription;
        UNSIGNED4       fileCount;
    END;

    //--------------------------------------------------------------------------

    /**
     * Default values used in exported function arguments
     */
    SHARED DEFAULT_FILENAME_PATTERNS := ['*'];

    /**
     * Remove any prefixing tilde character from a path
     *
     * @param   path    An HPCC path
     *
     * @return  Cleaned path.
     */
    SHARED NoAbsPath(STRING path) := REGEXREPLACE('^~', path, '');

    /**
     * Ensure that a given path is absolute (contains a prefixing tilde).
     *
     * @param   path    An HPCC path
     *
     * @return  Cleaned path.
     */
    SHARED AbsPath(STRING path) := '~' + NoAbsPath(path);

    /**
     * Wrap the given string in apostrophes.
     *
     * @param   s       String to wrap.
     *
     * @return  Wrapped string value.
     */
    SHARED Quoted(STRING s) := '\'' + s + '\'';

    /**
     * Given a path, ensure it is absolute and then wrap it in apostrophes.
     * Useful for displaying an absolute path.
     *
     * @param   path    An HPCC path
     *
     * @return  Cleaned and quoted path.
     */
    SHARED QuotedAbsPath(STRING path) := Quoted(AbsPath(path));

    /**
     * Test whether the given Dali address is the same as the local Dali
     * address.
     *
     * @param   dali    The IP address of a Dali system as a string
     *
     * @return  TRUE if the given Dali is the local Dali, FALSE otherwise.
     */
    SHARED DaliIsRemote(STRING dali) := dali != Std.System.Thorlib.DaliServer();

    /**
     * Create a 'foreign' prefix that can be prepended to a path to make the
     * path reference a file on another HPCC system.
     *
     * @param   dali    The IP address of a Dali system as a string
     *
     * @return  The prefix needed to convert a local path to a foreign path.
     */
    SHARED ForeignPrefix(STRING dali) := 'foreign::' + dali + '::';

    /**
     * Convert a local path to a foreign path to the given Dali.
     *
     * @param   path        An HPCC logical path
     * @param   dali        The IP address of the remote Dali system
     *
     * @return  The prefixed path.
     */
    SHARED ForeignPath(STRING path, STRING dali) := '~' + ForeignPrefix(dali) + REGEXREPLACE('^~', path, '');

    /**
     * Ensure that the given path is foreign.  If necessary, a foreign prefix
     * will be prepended to path (if the given Dali is the local Dali then
     * the path is merely converted to an absolute path)
     *
     * @param   path        An HPCC logical path
     * @param   dali        The IP address of the remote Dali system
     *
     * @return  The foreign path.
     */
    SHARED EnsureForeignPath(STRING path, STRING dali) := MAP
        (
            DaliIsRemote(dali) AND Std.Str.StartsWith(path, '~foreign::')   =>  path,
            DaliIsRemote(dali)                                              =>  ForeignPath(path, dali),
            AbsPath(path)
        );

    /**
     * Gather information on files and superfiles that match the given set of
     * filename patterns.
     *
     * @param   dali        The IP address of the Dali to check for files
     * @param   patterns    A set of filename patterns to match
     *
     * @return  A DATASET(FileInfoRec) containing the information.  Note that
     *          both files and superfiles are gathered.
     */
    SHARED GetInfoForFilesMatchingPatterns(STRING dali, SET OF STRING patterns) := FUNCTION
        // Gather files that match each given pattern; matched files will be
        // in a child recordset
        embeddedResults := PROJECT
            (
                NOFOLD(DATASET(patterns, {STRING aPattern})),
                TRANSFORM
                    (
                        {
                            STRING      foundWithPattern,
                            DATASET(Std.File.FsLogicalFileInfoRecord)   infoList
                        },

                        thePattern := TRIM(LEFT.aPattern, LEFT, RIGHT);

                        SELF.foundWithPattern := thePattern,
                        SELF.infoList := Std.File.LogicalFileList
                            (
                                thePattern,
                                includenormal := TRUE,
                                includesuper := TRUE,
                                foreigndali := dali
                            )
                    )
            );

        // Flatten the results and append additional CRC information
        flatResults := NORMALIZE
            (
                embeddedResults,
                LEFT.infoList,
                TRANSFORM
                    (
                        FileInfoRec,
                        SELF.level := 1,
                        SELF.fileCRC := IF(~RIGHT.superfile, Std.File.GetLogicalFileAttribute(EnsureForeignPath(RIGHT.name, dali), 'fileCrc'), ''),
                        SELF.formatCRC := IF(~RIGHT.superfile, Std.File.GetLogicalFileAttribute(EnsureForeignPath(RIGHT.name, dali), 'formatCrc'), ''),
                        SELF := RIGHT
                    )
            );

        // A file can match more than one pattern, so dedup on name
        dedupedResults := DEDUP(SORT(flatResults, name), name);

        RETURN dedupedResults;
    END;

    /**
     * Gather information on all subfiles referenced by superfiles.  This is a
     * recursive function and will drill down as far as it needs to go.
     *
     * @param   fileInfoList    A dataset containing previously-derived file
     *                          info, as from GetInfoForFilesMatchingPatterns()
     * @param   dali        The IP address of the Dali to check for files
     *
     * @return  A DATASET(FileInfoRec) containing the information.  Note that
     *          both files and superfiles are gathered.
     *
     * @see     GetInfoForFilesMatchingPatterns
     */
    SHARED GetAllSubFiles(DATASET(FileInfoRec) fileInfoList, STRING dali) := FUNCTION
        // Loop that gathers information on the immediate children of superfiles;
        // note that the ds argument will contain only superfiles
        GetImmediateChildren(DATASET(SuperfileRelationshipRec) ds, UNSIGNED2 c) := FUNCTION
            EmbeddedSubFileRec := RECORD
                UNSIGNED2       level;
                STRING          superFilePath;
                DATASET(Std.File.FsLogicalFileNameRecord)   subFileNames;
            END;

            dedupedDS := DEDUP(SORT(ds, subFilePath), subFilePath);

            // For each superfile, immediate children are stored in a child
            // recordset
            embeddedSubFileNames := PROJECT
                (
                    dedupedDS,
                    TRANSFORM
                        (
                            EmbeddedSubFileRec,
                            SELF.level := c + 1,
                            SELF.superFilePath := LEFT.subFilePath,
                            SELF.subFileNames := Std.File.SuperFileContents(EnsureForeignPath(LEFT.subFilePath, dali), FALSE),
                            SELF := LEFT
                        )
                );

            FlatSubFileRec := RECORD
                UNSIGNED2       level;
                STRING          superFilePath;
                Std.File.FsLogicalFileNameRecord;
            END;

            // Flatten the results and remove the foreign path prefix (if any)
            // from the name
            flattenedSubFileNames := NORMALIZE
                (
                    embeddedSubFileNames,
                    LEFT.subFileNames,
                    TRANSFORM
                        (
                            FlatSubFileRec,
                            SELF.name := REGEXREPLACE('^foreign::.+?::', RIGHT.name, ''),
                            SELF := LEFT
                        )
                );

            SubFileInfoRec := RECORD
                UNSIGNED2               level;
                STRING                  superFilePath;
                DATASET(FileInfoRec)    subFileInfo;
            END;

            // Collect the detailed information for each child path; note that
            // are treating the full name as a "pattern" here
            subFileInfoResults := PROJECT
                (
                    flattenedSubFileNames,
                    TRANSFORM
                        (
                            SubFileInfoRec,
                            SELF.subFileInfo := GetInfoForFilesMatchingPatterns(dali, [LEFT.name]),
                            SELF := LEFT
                        )
                );

            // Flatten those results and bang them into the same data structure
            // as our ds argument
            flatContentResults := NORMALIZE
                (
                    subFileInfoResults,
                    LEFT.subFileInfo,
                    TRANSFORM
                        (
                            SuperfileRelationshipRec,
                            SELF.superFilePath := LEFT.superFilePath,
                            SELF.subFilePath := RIGHT.name,
                            SELF.subFileIsSuperfile := RIGHT.superfile,
                            SELF.level := LEFT.level
                        )
                );

            RETURN ds + flatContentResults;
        END;

        // Convert initial data into a structure our loop can use
        initialDS := PROJECT
            (
                fileInfoList(superfile = TRUE),
                TRANSFORM
                    (
                        SuperfileRelationshipRec,
                        SELF.superFilePath := '',
                        SELF.subFilePath := LEFT.name,
                        SELF.subFileIsSuperfile := LEFT.superfile,
                        SELF.level := 1
                    )
            );

        // Iteratively gather immediate children
        loopResults := LOOP
            (
                initialDS,
                LEFT.subFileIsSuperfile = TRUE AND LEFT.level = COUNTER,
                GetImmediateChildren(ROWS(LEFT), COUNTER)
            );

        // Remove those results that have empty superfile paths (those from
        // the initial loop dataset) and dedup the results
        dedupedResults := DEDUP(SORT(loopResults(superFilePath != ''), superFilePath, subFilePath), superFilePath, subFilePath);

        RETURN dedupedResults;
    END;

    /**
     * Gather all information files referenced by the given Dali and matching
     * at least one of the given filename patterns.  If superfiles are
     * gathered, their subfiles will also be (recursively) gathered.  Note that
     * gathered subfiles may not necessarily match any of the given filename
     * patterns.
     *
     * @param   dali        The IP address of the Dali to check for files
     * @param   patterns    A set of filename patterns to match
     *
     * @return  A MODULE containing file and superfile information
     *          within a DATASET(FileInfoRec) dataset, as well as
     *          superfile/subfile relationship data in a
     *          DATASET(SuperfileRelationshipRec) dataset.
     */
    SHARED CollectFileInfoFromSystem(STRING dali, SET OF STRING patterns) := FUNCTION
        initialPatternResult := GetInfoForFilesMatchingPatterns(dali, patterns);
        superSubResult := GetAllSubFiles(initialPatternResult, dali) : INDEPENDENT;

        // We need to add file information for files found while gathering
        // subfiles but were not included in the initial pattern match
        unreportedSubFileNames := JOIN
            (
                superSubResult,
                initialPatternResult,
                LEFT.subFilePath = RIGHT.name,
                TRANSFORM
                    (
                        {STRING subFilePath},
                        SELF.subFilePath := LEFT.subFilePath
                    ),
                LEFT ONLY
            );
        unreportedNameSet := NOTHOR(SET(unreportedSubFileNames, subFilePath));
        unreportedSubFileInfo := GetInfoForFilesMatchingPatterns(dali, unreportedNameSet);

        // Concatenate the additional files with the initial pattern result
        allFileInfo := initialPatternResult + unreportedSubFileInfo : INDEPENDENT;

        RETURN MODULE
            EXPORT DATASET(FileInfoRec)                 files := allFileInfo;
            EXPORT DATASET(SuperfileRelationshipRec)    superFileRelationships := superSubResult;
        END;
    END;

    /**
     * Given file information gathered from both remote and local systems,
     * create a single dataset describing the changes that need to be made to
     * the local system in order to make the local system a mirror of the
     * remote system.
     *
     * @param   remoteFiles     Dataset containing remote file information
     * @param   localFiles      Dataset containing local file information
     *
     * @return  DATASET(FileActionRec) containing information that inform
     *          actions to be taken.
     *
     * @see     GenerateSuperFileActions
     */
    SHARED GenerateFileActions(DATASET(FileInfoRec) remoteFiles, DATASET(FileInfoRec) localFiles) := FUNCTION
        // Files and superfiles that exist only on the remote system; these
        // will be added to the local system
        onlyRemote := JOIN
            (
                remoteFiles,
                localFiles,
                LEFT.name = RIGHT.name,
                TRANSFORM
                    (
                        FileActionRec,
                        SELF.path := LEFT.name,
                        SELF.sourceCluster := Std.Str.SplitWords(LEFT.cluster, ',')[1],
                        SELF.isSuperFile := LEFT.superfile,
                        SELF.syncAction := SYNC_ACTION.ADD
                    ),
                LEFT ONLY
            );

        // Files and superfiles that exist only on the local system; these will
        // be deleted from the local system
        onlyLocal := JOIN
            (
                remoteFiles,
                localFiles,
                LEFT.name = RIGHT.name,
                TRANSFORM
                    (
                        FileActionRec,
                        SELF.path := RIGHT.name,
                        SELF.sourceCluster := '',
                        SELF.isSuperFile := RIGHT.superfile,
                        SELF.syncAction := SYNC_ACTION.DELETE_FILE
                    ),
                RIGHT ONLY
            );

        // Regular files that exist on both systems that also appear to have
        // different content; these will need to be copied from the remote
        // system
        common := JOIN
            (
                remoteFiles,
                localFiles,
                LEFT.name = RIGHT.name
                    AND (LEFT.size != RIGHT.size OR (LEFT.fileCRC != '' AND LEFT.fileCRC != RIGHT.fileCRC) OR (LEFT.formatCRC != '' AND LEFT.formatCRC != RIGHT.formatCRC))
                    AND LEFT.superfile = FALSE
                    AND RIGHT.superfile = FALSE,
                TRANSFORM
                    (
                        FileActionRec,
                        SELF.path := LEFT.name,
                        SELF.sourceCluster := Std.Str.SplitWords(LEFT.cluster, ',')[1],
                        SELF.isSuperFile := LEFT.superfile,
                        SELF.syncAction := SYNC_ACTION.MODIFY
                    )
            );

        // Find cases where a particular path references a regular file on the
        // remote system and a superfile on the local system; these files
        // need to have two actions, one to copy the regular remote file and
        // the second to delete the local superfile
        commonSuperBecomesRegular1 := JOIN
            (
                remoteFiles,
                localFiles,
                LEFT.name = RIGHT.name
                    AND LEFT.superfile = FALSE
                    AND RIGHT.superfile = TRUE,
                TRANSFORM
                    (
                        FileActionRec,
                        SELF.path := LEFT.name,
                        SELF.sourceCluster := Std.Str.SplitWords(LEFT.cluster, ',')[1],
                        SELF.isSuperFile := FALSE,
                        SELF.syncAction := SYNC_ACTION.ADD
                    )
            );

        commonSuperBecomesRegular2 := PROJECT
            (
                commonSuperBecomesRegular1,
                TRANSFORM
                    (
                        RECORDOF(LEFT),
                        SELF.syncAction := SYNC_ACTION.DELETE_SUPERFILE,
                        SELF.isSuperFile := TRUE,
                        SELF := LEFT
                    )
            );

        // Find cases where a particular path references a superfile on the
        // remote system and a regular file on the local system; these files
        // need to have two actions, one to delete the regular local file and
        // the second to add a local superfile
        commonRegularBecomesSuper1 := JOIN
            (
                remoteFiles,
                localFiles,
                LEFT.name = RIGHT.name
                    AND LEFT.superfile = TRUE
                    AND RIGHT.superfile = FALSE,
                TRANSFORM
                    (
                        FileActionRec,
                        SELF.path := LEFT.name,
                        SELF.sourceCluster := '',
                        SELF.isSuperFile := FALSE,
                        SELF.syncAction := SYNC_ACTION.DELETE_FILE
                    )
            );

        commonRegularBecomesSuper2 := PROJECT
            (
                commonRegularBecomesSuper1,
                TRANSFORM
                    (
                        RECORDOF(LEFT),
                        SELF.syncAction := SYNC_ACTION.ADD,
                        SELF.isSuperFile := TRUE,
                        SELF := LEFT
                    )
            );

        RETURN onlyRemote + onlyLocal + common + commonSuperBecomesRegular1 + commonSuperBecomesRegular2 + commonRegularBecomesSuper1 + commonRegularBecomesSuper2;
    END;

    /**
     * Given superfile relationship information gathered from both remote and
     * local systems, create a single dataset describing the changes that need
     * to be made to the local system in order to make the local system a
     * mirror of the remote system.
     *
     * @param   remoteFiles     Dataset containing remote superfile information
     * @param   localFiles      Dataset containing local superfile information
     * @param   fileActions     A dataset describing the changes that will be
     *                          applied at the file level, which is needed
     *                          in order to find files that will be modified
     *                          that are part of a superfile/subfile
     *                          relationship (those files need to removed from
     *                          their superfile prior to copy, then restored
     *                          afterwards); OPTIONAL, defaults to an empty
     *                          dataset
     *
     * @return  DATASET(SuperFileActionRec) containing information that inform
     *          actions to be taken.
     *
     * @see     GenerateFileActions
     */
    SHARED GenerateSuperFileActions(DATASET(SuperfileRelationshipRec) remoteFiles,
                                    DATASET(SuperfileRelationshipRec) localFiles,
                                    DATASET(FileActionRec) fileActions = DATASET([], FileActionRec)) := FUNCTION
        // Superfile/subfile relationships that exist only on the remote
        // system; these will need to be instantiated on the local system
        onlyRemote := JOIN
            (
                remoteFiles,
                localFiles,
                LEFT.superFilePath = RIGHT.superFilePath
                    AND LEFT.subFilePath = RIGHT.subFilePath,
                TRANSFORM
                    (
                        SuperFileActionRec,
                        SELF.syncAction := SYNC_ACTION.ADD,
                        SELF := LEFT
                    ),
                LEFT ONLY
            );

        // Superfile/subfile relationships that exist only on the local
        // system; these will need to be unlinked on the local system
        onlyLocal := JOIN
            (
                remoteFiles,
                localFiles,
                LEFT.superFilePath = RIGHT.superFilePath
                    AND LEFT.subFilePath = RIGHT.subFilePath,
                TRANSFORM
                    (
                        SuperFileActionRec,
                        SELF.syncAction := SYNC_ACTION.DELETE_SUPERFILE,
                        SELF := RIGHT
                    ),
                RIGHT ONLY
            );

        // Files that will be replaced that are part of a superfile
        // relationship must be removed from the relationship before the
        // copy, then added back after the copy
        commonFiles := JOIN
            (
                remoteFiles,
                localFiles,
                LEFT.superFilePath = RIGHT.superFilePath
                    AND LEFT.subFilePath = RIGHT.subFilePath,
                TRANSFORM
                    (
                        SuperFileActionRec,
                        SELF.syncAction := SYNC_ACTION.UNKNOWN, // Will be overridden
                        SELF := LEFT
                    )
            );

        toBeModifiedDelete := JOIN
            (
                commonFiles,
                fileActions,
                LEFT.subFilePath = RIGHT.path
                    AND RIGHT.syncAction = SYNC_ACTION.MODIFY,
                TRANSFORM
                    (
                        SuperFileActionRec,
                        SELF.syncAction := SYNC_ACTION.DELETE_SUPERFILE,
                        SELF := LEFT
                    )
            );

        toBeModifiedAdd := PROJECT
            (
                toBeModifiedDelete,
                TRANSFORM
                    (
                        RECORDOF(LEFT),
                        SELF.syncAction := SYNC_ACTION.ADD,
                        SELF := LEFT
                    )
            );

        allResults := onlyRemote + onlyLocal + toBeModifiedDelete + toBeModifiedAdd;

        dedupedResults := DEDUP(SORT(allResults, superFilePath, subFilePath, syncAction), superFilePath, subFilePath, syncAction);

        RETURN dedupedResults;
    END;

    /**
     * Collect and analyze information from both remote and local systems,
     * determine what changes are needed to make the local system mirror the
     * remote system, and provide summarized results of those changes.
     *
     * @param   dali        The IP address of the remote Dali to check
     * @param   patterns    A set of filename patterns to match; OPTIONAL,
     *                      defaults to ['*'] which indicates all files
     *
     * @return  MODULE containing multiple attributes:
     *              engine                          The HPCC engine that is
     *                                              currently being used
     *              remoteFiles                     Remote files matching the
     *                                              filename patterns (plus any
     *                                              subfiles)
     *              remoteSuperFileRelationships    Superfile/subfile relationships
     *                                              found on the remote system
     *              localFiles                      Local files matching the
     *                                              filename patterns (plus any
     *                                              subfiles)
     *              localSuperFileRelationships     Superfile/subfile relationships
     *                                              found on the local system
     *              fileActions                     Dataset containing indicators
     *                                              of the actions that need to
     *                                              be taken on the local system
     *                                              for files
     *              fileActionSummary               Human-readable summary of
     *                                              fileActions
     *              superFileActions                Dataset containing indicators
     *                                              of the actions that need to
     *                                              be taken on the local system
     *                                              for superfile/subfile
     *                                              management
     *              superFileActionSummary          Human-readable summary of
     *                                              superFileActions
     *
     * @see     Go
     */
    EXPORT CollectFileInfo(STRING dali, SET OF STRING patterns = DEFAULT_FILENAME_PATTERNS) := FUNCTION
        remoteResults := CollectFileInfoFromSystem(dali, patterns);
        localResults := CollectFileInfoFromSystem(Std.System.Thorlib.DaliServer(), patterns);
        fileActionResults := GenerateFileActions(remoteResults.files, localResults.files);
        fileActionSummaryStats := TABLE
            (
                fileActionResults,
                {
                    syncAction,
                    UNSIGNED4   numFiles := COUNT(GROUP)
                },
                syncAction
            );
        fileActionSummary := PROJECT
            (
                fileActionSummaryStats,
                TRANSFORM
                    (
                        ActionSummaryRec,
                        SELF.actionDescription := CASE
                            (
                                LEFT.syncAction,
                                    SYNC_ACTION.ADD                 =>  'Copy new file from remote (new)',
                                    SYNC_ACTION.MODIFY              =>  'Copy modified file from remote',
                                    SYNC_ACTION.DELETE_FILE         =>  'Delete local file',
                                    SYNC_ACTION.DELETE_SUPERFILE    =>  'Delete local superfile',
                                    ERROR('Unable to determine file action')
                            ),
                        SELF.fileCount := LEFT.numFiles
                    )
            );
        superFileActionResults := GenerateSuperFileActions(remoteResults.superFileRelationships, localResults.superFileRelationships, fileActionResults);
        superFileActionSummaryStats := TABLE
            (
                superFileActionResults,
                {
                    syncAction,
                    UNSIGNED4   numFiles := COUNT(GROUP)
                },
                syncAction
            );
        superFileActionSummary := PROJECT
            (
                superFileActionSummaryStats,
                TRANSFORM
                    (
                        ActionSummaryRec,
                        SELF.actionDescription := CASE
                            (
                                LEFT.syncAction,
                                    SYNC_ACTION.ADD                 =>  'Create new local superfile',
                                    SYNC_ACTION.DELETE_SUPERFILE    =>  'Delete local superfile',
                                    ERROR('Unable to determine superfile action')
                            ),
                        SELF.fileCount := LEFT.numFiles
                    )
            );

        executionEngine := Std.Str.ToUpperCase(Std.System.Job.Platform());

        RETURN MODULE
            EXPORT STRING                               engine := IF(executionEngine = 'HTHOR', executionEngine, ERROR('This code must be run on hthor'));
            EXPORT DATASET(FileInfoRec)                 remoteFiles := remoteResults.files;
            EXPORT DATASET(SuperfileRelationshipRec)    remoteSuperFileRelationships := remoteResults.superFileRelationships;
            EXPORT DATASET(FileInfoRec)                 localFiles := localResults.files;
            EXPORT DATASET(SuperfileRelationshipRec)    localSuperFileRelationships := localResults.superFileRelationships;
            EXPORT DATASET(FileActionRec)               fileActions := fileActionResults;
            EXPORT DATASET(ActionSummaryRec)            fileActionSummary := fileActionSummary;
            EXPORT DATASET(SuperFileActionRec)          superFileActions := superFileActionResults;
            EXPORT DATASET(ActionSummaryRec)            superFileActionSummary := superFileActionSummary;
        END;
    END;

    /**
     * Using file analytics data provided by CollectFileInfo(), either
     * execute the actions necessary to make the local system mirror the remote
     * system or just output the commands that will be executed for review
     * purposes.
     *
     * @param   dali            The IP address of the remote Dali
     * @param   patterns        Set of filename patterns that will be used
     *                          to gather files to analyze; OPTIONAL, defaults
     *                          to ['*'] which indicates all files
     * @param   clusterMap      DATASET(ClusterMapRec) containing remote and
     *                          local cluster names; this is used when a remote
     *                          file needs to be copied but the cluster on
     *                          which the remote file lives is named differently
     *                          than the destination cluster (e.g. 'thor' versus
     *                          'mythor'); OPTIONAL, defaults to an empty
     *                          dataset
     * @param   isDryRun        If TRUE, only information about the analysis
     *                          and commands that would be executed are shown
     *                          as results; if FALSE then the commands are also
     *                          executed; defaults to TRUE for safety
     *
     * @return  An action that performs the analysis and, if isDryRun is TRUE,
     *          also performs the actions required to bring the data into sync
     *
     * @see     CollectFileInfo
     */
    EXPORT Go(STRING dali,
              SET OF STRING patterns = DEFAULT_FILENAME_PATTERNS,
              DATASET(ClusterMapRec) clusterMap = DATASET([], ClusterMapRec),
              BOOLEAN isDryRun = TRUE) := FUNCTION

        clusterMapDict := DICTIONARY(clusterMap, {remoteCluster => localCluster});
        MappedCluster(STRING clusterName) := FUNCTION
            newName := clusterMapDict[clusterName].localCluster;
            RETURN IF(newName != '', newName, clusterName);
        END;

        ActionDescRec := RECORD
            STRING      cmd;
        END;

        actionCountLabel := IF(isDryRun, 'DryRun', '') + 'ActionCount';
        actionLabel := IF(isDryRun, 'DryRun', '') + 'Actions';

        info := CollectFileInfo(dali, patterns);

        // Remove local superfile relations
        removeLocalSuperFileRelations := GLOBAL(info.superFileActions(syncAction = SYNC_ACTION.DELETE_FILE), FEW);
        removeLocalSuperFileRelationsDryRun := PROJECT
            (
                removeLocalSuperFileRelations,
                TRANSFORM
                    (
                        ActionDescRec,
                        SELF.cmd := 'Std.File.RemoveSuperFile(' + QuotedAbsPath(LEFT.superFilePath) + ', ' + QuotedAbsPath(LEFT.subFilePath) + ');'
                    )
            );
        removeLocalSuperFileRelationsAction := PARALLEL
            (
                OUTPUT(removeLocalSuperFileRelationsDryRun, NAMED(actionLabel), ALL, EXTEND);
                IF(~isDryRun, NOTHOR(APPLY(removeLocalSuperFileRelations, Std.File.RemoveSuperFile(AbsPath(superFilePath), AbsPath(subFilePath)))));
            );

        // Delete unneeded local superfiles
        removeLocalUneededSuperFiles := GLOBAL(info.fileActions(syncAction = SYNC_ACTION.DELETE_SUPERFILE), FEW);
        removeLocalUneededSuperFilesDryRun := PROJECT
            (
                removeLocalUneededSuperFiles,
                TRANSFORM
                    (
                        ActionDescRec,
                        SELF.cmd := 'Std.File.DeleteSuperFile(' + QuotedAbsPath(LEFT.path) + ');'
                    )
            );
        removeLocalUneededSuperFilesAction := PARALLEL
            (
                OUTPUT(removeLocalUneededSuperFilesDryRun, NAMED(actionLabel), ALL, EXTEND);
                IF(~isDryRun, NOTHOR(APPLY(removeLocalUneededSuperFiles, Std.File.DeleteSuperFile(AbsPath(path)))));
            );

        // Delete unneeded local files
        removeLocalUneededFiles := GLOBAL(info.fileActions(~isSuperFile AND syncAction = SYNC_ACTION.DELETE_FILE), FEW);
        removeLocalUneededFilesDryRun := PROJECT
            (
                removeLocalUneededFiles,
                TRANSFORM
                    (
                        ActionDescRec,
                        SELF.cmd := 'Std.File.DeleteLogicalFile(' + QuotedAbsPath(LEFT.path) + ');'
                    )
            );
        removeLocalUneededFilesAction := PARALLEL
            (
                OUTPUT(removeLocalUneededFilesDryRun, NAMED(actionLabel), ALL, EXTEND);
                IF(~isDryRun, NOTHOR(APPLY(removeLocalUneededFiles, Std.File.DeleteLogicalFile(AbsPath(path)))));
            );

        // Create new local superfiles
        createLocalNewSuperFiles := GLOBAL(info.fileActions(isSuperFile AND syncAction = SYNC_ACTION.ADD), FEW);
        createLocalNewSuperFilesDryRun := PROJECT
            (
                createLocalNewSuperFiles,
                TRANSFORM
                    (
                        ActionDescRec,
                        SELF.cmd := 'Std.File.CreateSuperFile(' + QuotedAbsPath(LEFT.path) + ');'
                    )
            );
        createLocalNewSuperFilesAction := PARALLEL
            (
                OUTPUT(createLocalNewSuperFilesDryRun, NAMED(actionLabel), ALL, EXTEND);
                IF(~isDryRun, NOTHOR(APPLY(createLocalNewSuperFiles, Std.File.CreateSuperFile(AbsPath(path)))));
            );

        // Copy modified and new files
        copyFiles := GLOBAL(info.fileActions(~isSuperFile AND syncAction IN [SYNC_ACTION.ADD, SYNC_ACTION.MODIFY]), FEW);
        copyFilesDryRun := PROJECT
            (
                copyFiles,
                TRANSFORM
                    (
                        ActionDescRec,
                        SELF.cmd := 'Std.File.Copy(' + QuotedAbsPath(LEFT.path) + ', ' + Quoted(MappedCluster(LEFT.sourceCluster)) + ', ' + QuotedAbsPath(LEFT.path) + ', ' + Quoted(dali) + ', allowoverwrite := TRUE, compress := TRUE);'
                    )
            );
        copyFilesAction := PARALLEL
            (
                OUTPUT(copyFilesDryRun, NAMED(actionLabel), ALL, EXTEND);
                IF(~isDryRun, NOTHOR(APPLY(copyFiles, Std.File.Copy(AbsPath(path), MappedCluster(sourceCluster), AbsPath(path), dali, allowoverwrite := TRUE, compress := TRUE))));
            );

        // Add new local superfile relations
        addLocalSuperFileRelations := GLOBAL(info.superFileActions(syncAction = SYNC_ACTION.ADD), FEW);
        addLocalSuperFileRelationsDryRun := PROJECT
            (
                addLocalSuperFileRelations,
                TRANSFORM
                    (
                        ActionDescRec,
                        SELF.cmd := 'Std.File.AddSuperFile(' + QuotedAbsPath(LEFT.superFilePath) + ', ' + QuotedAbsPath(LEFT.subFilePath) + ');'
                    )
            );
        addLocalSuperFileRelationsAction := PARALLEL
            (
                OUTPUT(addLocalSuperFileRelationsDryRun, NAMED(actionLabel), ALL, EXTEND);
                IF(~isDryRun, NOTHOR(APPLY(addLocalSuperFileRelations, Std.File.AddSuperfile(AbsPath(superFilePath), AbsPath(subFilePath)))));
            );

        commandCount := COUNT(removeLocalSuperFileRelations)
                            + COUNT(removeLocalUneededSuperFiles)
                            + COUNT(removeLocalUneededFiles)
                            + COUNT(createLocalNewSuperFiles)
                            + COUNT(copyFiles)
                            + COUNT(addLocalSuperFileRelations);

        allActions := SEQUENTIAL
            (
                OUTPUT(isDryRun, NAMED('WasDryRun'));
                OUTPUT(COUNT(info.remoteFiles), NAMED('RemoteFilesExaminedCount'));
                OUTPUT(COUNT(info.localFiles), NAMED('LocalFilesExaminedCount'));
                OUTPUT(commandCount, NAMED(actionCountLabel));
                IF(~isDryRun, Std.File.StartSuperFileTransaction());
                removeLocalSuperFileRelationsAction;
                removeLocalUneededSuperFilesAction;
                IF(~isDryRun, Std.File.FinishSuperFileTransaction());
                removeLocalUneededFilesAction;
                copyFilesAction;
                IF(~isDryRun, Std.File.StartSuperFileTransaction());
                createLocalNewSuperFilesAction;
                addLocalSuperFileRelationsAction;
                IF(~isDryRun, Std.File.FinishSuperFileTransaction());
            );

        // Forcing this check of info.engine could result in an intentional
        // error message if the code is being executed on a different engine
        RETURN IF(info.engine = 'HTHOR', allActions);
    END;

END;

/*******************************************************************************

Example code:

// Mirror all of my files and any file or superfile with 'search' in the name
FILE_PATTERNS := ['dcamper::*', '*search*'];
REMOTE_DALI := '10.173.147.1';

// Make sure that any remote files existing on the 'hthor__myeclagent' cluster
// are copied to the local 'hthor' cluster
clusters := DATASET
    (
        [
            {'hthor__myeclagent', 'hthor'}
        ],
        DataPull.ClusterMapRec
    );

DataPull.Go
    (
        REMOTE_DALI,
        FILE_PATTERNS,
        clusterMap := clusters,
        isDryRun := TRUE
    );

*******************************************************************************/
