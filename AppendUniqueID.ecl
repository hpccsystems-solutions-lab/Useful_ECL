/**
 * Append a unique numeric record identifier to a dataset.  The new dataset
 * is returned.
 *
 * @param inFile                The dataset to process; REQUIRED.
 * @param startingID            The minimum record identifier to assign;
 *                              OPTIONAL; defaults to 1.
 * @param strictlySequential    If TRUE, the assigned IDs will be in numerically
 *                              increasing order; if FALSE, the assigned IDs
 *                              will be unique but there may be gaps,
 *                              depending on how the records are distributed;
 *                              OPTIONAL; defaults to FALSE.
 * @param idAttr                The name of the unique ID attribute to add to
 *                              the dataset; this is a bare keyword, not a
 *                              string; OPTIONAL, defaults to uid
 *
 * @return                      A new dataset with the appended unique identifer
 *                              field.
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */

EXPORT AppendUniqueID(inFile, startingID = 1, strictlySequential = FALSE, idAttr = 'uid') := FUNCTIONMACRO
    IMPORT Std;

    // Definition of %result% layout
    #UNIQUENAME(ResultRec);
    LOCAL %ResultRec% := RECORD
        UNSIGNED6   idAttr;
        RECORDOF(inFile);
    END;

    //--------------------------------------------------------------------------
    // Assign sequential values for only a few records
    //--------------------------------------------------------------------------

    #UNIQUENAME(seqFew);
    LOCAL %seqFew% := PROJECT
        (
            inFile,
            TRANSFORM
                (
                    %ResultRec%,
                    SELF.idAttr := startingID + COUNTER - 1,
                    SELF := LEFT
                )
        );

    //--------------------------------------------------------------------------
    // Assign sequential values for many records
    //--------------------------------------------------------------------------

    #UNIQUENAME(nodeNum);
    #UNIQUENAME(nodeCount);
    #UNIQUENAME(nodeOffset);

    #UNIQUENAME(ResultRecWithNode);
    LOCAL %ResultRecWithNode% := RECORD
        %ResultRec%;
        UNSIGNED4   %nodeNum%;
    END;

    // Append zero-value RecID value and the Thor node number to each record
    #UNIQUENAME(inFileWithNodeNum);
    LOCAL %inFileWithNodeNum% := PROJECT
        (
            inFile,
            TRANSFORM
                (
                    %ResultRecWithNode%,
                    SELF.idAttr := 0,
                    SELF.%nodeNum% := Std.System.Thorlib.Node(),
                    SELF := LEFT
                ),
            LOCAL
        );

    // Count the number of records on each node
    #UNIQUENAME(recCountsPerNode);
    LOCAL %recCountsPerNode% := TABLE
        (
            %inFileWithNodeNum%,
            {
                UNSIGNED4   %nodeNum% := Std.System.Thorlib.Node(),
                UNSIGNED6   %nodeCount% := COUNT(GROUP),
                UNSIGNED6   %nodeOffset% := 0
            },
            LOCAL
        );

    // Compute the node offset, which is the minimum RecID value for any
    // record on that node
    #UNIQUENAME(nodeOffsets);
    LOCAL %nodeOffsets% := ITERATE
        (
            %recCountsPerNode%,
            TRANSFORM
                (
                    RECORDOF(%recCountsPerNode%),
                    SELF.%nodeOffset% := IF(COUNTER = 1, startingID, LEFT.%nodeOffset% + LEFT.%nodeCount%),
                    SELF:=RIGHT
                )
        );

    // Append the node offset to the data
    #UNIQUENAME(inFileWithOffsets);
    LOCAL %inFileWithOffsets% := JOIN
        (
            %inFileWithNodeNum%,
            %nodeOffsets%,
            LEFT.%nodeNum% = RIGHT.%nodeNum%,
            MANY LOOKUP
        );

    // Iterate through the records on each node, computing the RecID value
    #UNIQUENAME(inFileSequenced);
    LOCAL %inFileSequenced% := ITERATE
        (
            %inFileWithOffsets%,
            TRANSFORM
                (
                    RECORDOF(%inFileWithOffsets%),
                    SELF.idAttr := IF(LEFT.%nodeNum% = RIGHT.%nodeNum%, LEFT.idAttr + 1, RIGHT.%nodeOffset%),
                    SELF := RIGHT
                ),
            LOCAL
        );

    // Put the data in its final form
    #UNIQUENAME(seqMany);
    LOCAL %seqMany% := PROJECT
        (
            %inFileSequenced%,
            TRANSFORM
                (
                    %ResultRec%,
                    SELF := LEFT
                ),
            LOCAL);

    //--------------------------------------------------------------------------
    // Assign unique values, not necessarily sequential
    //--------------------------------------------------------------------------

    #UNIQUENAME(uniq);
    LOCAL %uniq% := PROJECT
        (
            inFile,
            TRANSFORM
                (
                    %ResultRec%,
                    SELF.idAttr := ((COUNTER - 1) * Std.System.Thorlib.Nodes()) + Std.System.Thorlib.Node() + startingID + COUNTER - 1,
                    SELF := LEFT
                ),
            LOCAL
        );

    //--------------------------------------------------------------------------
    // Create resulting dataset using a method dependent on the strictness
    // of the RecID value and the size of the input
    //--------------------------------------------------------------------------

    #UNIQUENAME(result);
    LOCAL %result% := MAP
        (
            strictlySequential and COUNT(inFile) >= 1000000 =>  %seqMany%,
            strictlySequential                              =>  %seqFew%,
            %uniq%
        );

    RETURN %result%;
ENDMACRO;
