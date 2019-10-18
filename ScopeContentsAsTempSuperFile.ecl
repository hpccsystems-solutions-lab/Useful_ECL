/**
 * Function constructs a list of files sharing the given scope and creates
 * a temporary superfile path out of the results.  The resulting path may
 * used within a DATASET or INDEX function to reference the contents of
 * multiple files as if they were one file.  Note that, if the results
 * point to logical files (or index files) then their record structures
 * and file types must be identical.
 *
 * @param   fileScope               A string citing the path scope (prefix)
 *                                  to in which to search on the local
 *                                  cluster; the scope may end with '::'
 *                                  but that is not a requirement; REQUIRED
 * @param   includeLogicalFiles     If TRUE, logical files are included
 *                                  in the output; either
 *                                  includeLogicalFiles or
 *                                  includeSuperFiles must be set to TRUE;
 *                                  OPTIONAL, defaults to TRUE
 * @param   includeSuperFiles       If TRUE, superfiles are included
 *                                  in the output; either
 *                                  includeLogicalFiles or
 *                                  includeSuperFiles must be set to TRUE;
 *                                  OPTIONAL, defaults to FALSE
 *
 * @return  A single string in the format of '~{path1, path2, path3, ...}'
 *          representing a temporary superfile path.  This result can be
 *          used in a DATASET or INDEX function.  If no matching regular
 *          files can be found, an empty string is returned instead.
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
EXPORT ScopeContentsAsTempSuperFile(STRING fileScope
                                    BOOLEAN includeLogicalFiles = TRUE,
                                    BOOLEAN includeSuperFiles = FALSE) := FUNCTION
    IMPORT Std;

    myScope := REGEXREPLACE('([^:]+)$', fileScope, '$1::');
    filePattern := myScope + '*';

    files := NOTHOR
        (
            Std.File.LogicalFileList
                (
                    filePattern,
                    includeNormal := includeLogicalFiles,
                    includeSuper := includeSuperFiles
                )
        );

    onlyNames := TABLE(files, {name});

    combinedNames := ROLLUP
        (
            onlyNames,
            TRUE,
            TRANSFORM
                (
                    RECORDOF(LEFT),
                    SELF.name := LEFT.name + IF(LEFT.name != '', ',', '') + RIGHT.name
                )
        );

    result := IF(EXISTS(onlyNames), '~{' + combinedNames[1].name + '}', '');

    RETURN result;
END;