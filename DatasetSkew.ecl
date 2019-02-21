/**
 * Simple function that computes the skew of a recordset.  This may be useful
 * in determining how skewed an interim dataset is in a workflow, which in
 * term can affect performance of a job.
 *
 * While this function can be executed on any of HPCC System's engines, it
 * is really useful only on Thor.
 *
 * @param   inFile      The recordset to examine
 *
 * @return  A new recordset showing the number of records currently hosted on
 *          each Thor slave process, along with a skew value in the same
 *          format as the skew shown in workunit graphs (a percentage value,
 *          ranging from -100 to (100 * (number of Thor slaves - 1)))
 */
EXPORT DatasetSkew(VIRTUAL DATASET inFile) := FUNCTION
    IMPORT Std;

    // Calculate the perfect distribution of records for a Thor slave
    perfectDist := COUNT(inFile) / Std.System.Thorlib.Nodes();

    // Get the number of records stored on each node
    nodeCounts := TABLE
        (
            inFile,
            {
                UNSIGNED4   recordCount := COUNT(GROUP),
                UNSIGNED4   nodeNum := Std.System.Thorlib.Node()
            },
            LOCAL
        );

    // Add the skew value calculation to the result
    skewStats := PROJECT
        (
            nodeCounts,
            TRANSFORM
                (
                    {
                        RECORDOF(LEFT),
                        INTEGER2    skewValue
                    },
                    SELF.skewvalue := (LEFT.recordCount - perfectDist) / (perfectDist) * 100,
                    SELF := LEFT
                )
        );

    RETURN skewStats;
END;
