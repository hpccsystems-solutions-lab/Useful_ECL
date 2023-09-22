IMPORT Std;

/***
 * Removes all logical subfiles from a superfile, leaving any
 * sub-superfiles intact.
 *
 * @param   superfilePath   The path to the superfile
 * @param   delete          If TRUE, physically delete the logical subfiles;
 *                          should not be TRUE if dealing with foreign subfiles
 *                          or files that are owned by more than one superfile;
 *                          OPTIONAL, defaults to FALSE
 *
 * @return  An action that performs the removal
 *
 * Origin:  https://github.com/hpccsystems-solutions-lab/Useful_ECL
 */
EXPORT RemoveAllSuperFileLogicalFiles(STRING superfilePath, BOOLEAN delete = FALSE) := FUNCTION
    subfilesToDelete := PROJECT
        (
            NOTHOR(Std.File.SuperFileContents(superfilePath, TRUE)),
            TRANSFORM
                (
                    {
                        STRING  owner,
                        STRING  subfile
                    },
                    SELF.subfile := '~' + LEFT.name,
                    SELF.owner := '~' + Std.File.LogicalFileSuperOwners(SELF.subfile)[1].name
                )
        );
    removeSubfilesAction := NOTHOR(APPLY(subfilesToDelete, Std.File.RemoveSuperFile(owner, subfile, del := delete)));

    RETURN removeSubfilesAction;
END;
