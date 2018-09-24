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

    // For each record in the input recordset, determine which Thor slave
    // is hosting it
    recordLocation := PROJECT
        (
            inFile,
            TRANSFORM
                (
                    {UNSIGNED2 nodeNum},
                    SELF.nodeNum := Std.System.Thorlib.Node()
                ),
            LOCAL
        );

    // Count the records per Thor slave
    nodeCounts0 := TABLE
        (
            recordLocation,
            {
                nodeNum,
                UNSIGNED4   recordCount := COUNT(GROUP)
            },
            nodeNum,
            FEW
        );

    // Not all slaves will have records, which means there will be "holes" in
    // the previous result; we need to fill in those holes with zero-count
    // records; construct a small recordset containing zero-count records
    // for all Thor slaves
    zeroCounts := DATASET
        (
            Std.System.Thorlib.Nodes(),
            TRANSFORM
                (
                    RECORDOF(nodeCounts0),
                    SELF.nodeNum := COUNTER - 1,
                    SELF.recordCount := 0
                )
        );

    // Join the zero-count recordset with the calculated result; the net
    // effect is to fill in any holes in the per-slave record counts
    nodeCounts := JOIN
        (
            zeroCounts,
            nodeCounts0,
            LEFT.nodeNum = RIGHT.nodeNum,
            TRANSFORM
                (
                    RECORDOF(LEFT),
                    SELF.nodeNum := LEFT.nodeNum,
                    SELF.recordCount := MAX(LEFT.recordCount, RIGHT.recordCount)
                ),
            LEFT OUTER
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
