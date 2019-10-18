/**
 * Examines the plugin definitions and files installed on the cluster and
 * determines which ones are actually available.  This BWR can be run on each
 * HPCC engine to ensure that a plugin is installed where it is needed.
 *
 * Three results are returned:
 *  -   PlatformVersion:  The version of HPCC we are running on
 *  -   Engine:  The name of the HPCC engine (hthor, Thor, Roxie)
 *  -   IPAddress:  The IP address of the engine executing the workunit
 *      (inaccurate when run on a Thor cluster)
 *  -   InstalledPluginsByNodeNum:  The names of installed plugins and which
 *      node they were found on
 *  -   InstalledPluginsNodeCount:  For each plugin, the number of nodes that
 *      had that plugin installed
 *  -   PluginsNotInstalledEverywhere:  Names of plugins that were installed
 *      on only some nodes; this should be an empty result if everything
 *      was installed correctly
 *
 * Reporting on Roxie is problematical.  The code will execute and report on
 * only one of the nodes, and you don't really know which one.  If Roxie is
 * quiet (not processing any other requests) then you can execute this query
 * once for every Roxie node in the cluster.  The ESP's software-based round-
 * robin action will dispatch the query to each node in turn and you can
 * compare the results from the individual runs.
 *
 * This code assumes that the platform is running on a Linux operating system.
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
IMPORT Std;

#OPTION('pickBestEngine', FALSE);
#WORKUNIT('name', 'Show Installed Plugins');

PLUGINS_DIR := '/opt/HPCCSystems/plugins';
LIB_DIR := '/opt/HPCCSystems/lib';

//------------------------------------------------------------------------------

PluginNameFromPath(STRING path) := FUNCTION
    ContentRec := RECORD
        STRING      line;
    END;

    ds := DATASET(DYNAMIC(Std.File.ExternalLogicalFileName('127.0.0.1', path)), ContentRec, CSV(SEPARATOR('')));
    filteredContent := ds(REGEXFIND('plugin\\(\'.+?\'\\)', line, NOCASE));
    onlyPluginNames := PROJECT
        (
            filteredContent,
            TRANSFORM
                (
                    RECORDOF(LEFT),
                    SELF.line := REGEXFIND('plugin\\(\'(.+?)\'\\)', LEFT.line, 1, NOCASE)
                )
        );

    RETURN onlyPluginNames[1].line;
END;

//------------------------------------------------------------------------------

ECLLibPluginInfoRec := RECORD
    STRING      pluginName;
    STRING      sharedLibName;
END;

NodeRec := RECORD
    UNSIGNED4   nodeNum;
    DATASET(Std.File.FsFilenameRecord)  ecllibFileList;
    DATASET(Std.File.FsFilenameRecord)  sharedLibFileList;
END;

FileNameWithNodeNumRec := RECORD
    UNSIGNED4   nodeNum;
    STRING      filename;
END;

PluginNameRec := RECORD
    UNSIGNED4   nodeNum;
    STRING      pluginName;
END;

//------------------------------------------------------------------------------

// Create a dataset containing node numbers, then distribute the records
// such that each node receives its particular record
nodes0 := DATASET
    (
        Std.System.Thorlib.Nodes(),
        TRANSFORM
            (
                NodeRec,
                SELF.nodeNum := COUNTER - 1,
                SELF := []
            )
    );
nodes := DISTRIBUTE(nodes0, nodeNum);

// Grab a list of *.ecllib and *.so files from the plugins directory
nodesWithFileLists := PROJECT
    (
        nodes,
        TRANSFORM
            (
                RECORDOF(LEFT),
                SELF.ecllibFileList := NOTHOR(Std.File.RemoteDirectory('127.0.0.1', PLUGINS_DIR, '*.ecllib')),
                SELF.sharedLibFileList := DEDUP(NOTHOR(Std.File.RemoteDirectory('127.0.0.1', PLUGINS_DIR, '*.so')) + NOTHOR(Std.File.RemoteDirectory('127.0.0.1', LIB_DIR, '*.so')), ALL),
                SELF := LEFT
            ),
        LOCAL
    );

// Flatten the *.ecllib results and pick out some interesting names for later
// Note that a *.ecllib file will exist for every possible plugin, but that
// does not mean that that plugin is actually installed
ecllibFileList := NORMALIZE
    (
        nodesWithFileLists,
        LEFT.ecllibFileList,
        TRANSFORM
            (
                {
                    FileNameWithNodeNumRec,
                    STRING      pluginName;
                    STRING      sharedLibName;
                },
                SELF.nodeNum := LEFT.nodeNum,
                SELF.filename := RIGHT.name,
                SELF.pluginName := PluginNameFromPath(PLUGINS_DIR + '/' + SELF.filename),
                SELF.sharedLibName := IF(SELF.pluginName != '', 'lib' + SELF.pluginName + '.so', '')
            )
    );

// Flatten the *.so results
sharedLibFileList := NORMALIZE
    (
        nodesWithFileLists,
        LEFT.sharedLibFileList,
        TRANSFORM
            (
                FileNameWithNodeNumRec,
                SELF.nodeNum := LEFT.nodeNum,
                SELF.filename := RIGHT.name
            )
    );

// Filter the *.ecllib list by found *.so files
ecllibPluginsWithSharedLibs := JOIN
    (
        ecllibFileList(sharedLibName != ''),
        sharedLibFileList,
        LEFT.nodeNum = RIGHT.nodeNum
            AND Std.Str.ToLowerCase(LEFT.sharedLibName) = Std.Str.ToLowerCase(RIGHT.filename),
        TRANSFORM(LEFT),
        LOCAL
    );

// Filter the result down to only those items we want to show
finalResult := PROJECT
    (
        ecllibPluginsWithSharedLibs,
        TRANSFORM
            (
                PluginNameRec,
                SELF := LEFT
            )
    );

OUTPUT((STRING)__ecl_version_major__ + '.' + (STRING)__ecl_version_minor__ + '.' + (STRING)__ecl_version_subminor__, NAMED('PlatformVersion'));

OUTPUT(Std.Str.ToUpperCase(Std.System.Job.Platform()), NAMED('Engine'));

OUTPUT(Std.System.Util.ResolveHostName('.'), NAMED('IPAddress'));

OUTPUT(SORT(finalResult, nodeNum, pluginName, FEW), NAMED('InstalledPluginsByNodeNum'));

nodeCountByPlugin := TABLE
    (
        finalResult,
        {
            pluginName,
            UNSIGNED4   nodeCount := COUNT(GROUP)
        },
        pluginName,
        FEW
    );

OUTPUT(SORT(nodeCountByPlugin, pluginName, FEW), NAMED('InstalledPluginsNodeCount'));

OUTPUT(nodeCountByPlugin(nodeCount != Std.System.Thorlib.Nodes()), NAMED('PluginsNotInstalledEverywhere'));
