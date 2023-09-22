# Fuzzy Searching for Business Names

## What Is This?

The code in this directory is a complete example of one way to fuzzy search for business names.  It demonstrates the following techniques:

- Normalizing and cleaning business names
- Passing a function for name cleaning to the underlying library code (a method of factoring the code to make it more flexible)
- Passing a function to dynamically choose a Levenshtein edit distance to use for an individual word, making it somewhat adaptive
- Creating fuzzy search indexes for individual words within a name, runnable under Thor so it can handle large datasets
- Creating a search query, runnable under Roxie, to search the indexes and score the results, supporting paginated results

## Code Layout

```bash
├── BWRs
│   ├── 01_CreateStopwords.ecl
│   └── 02_CreateIndexes.ecl
├── CleanBusinessName.ecl
├── Constants.ecl
├── Queries
│   └── Search.ecl
└── README.md
```

The two files at the top level are used by other code:

- [CleanBusinessName.ecl](CleanBusinessName.ecl): A function that accepts a UTF-8 string representing a business name and then returns a normalized and "cleaned" version of that same string.  The function is used when both indexing and querying.  Note that the heavy lifting is performed by an external function found in the [Useful_ECL](https://github.com/hpccsystems-solutions-lab/Useful_ECL) repo.
- [Constants.ecl](Constants.ecl): Constants used in other parts of the code. Most of them have to do with file naming, but one -- ``INDEX_STOPWORD_WORD_FREQ_CUTOFF`` -- is crucial to creating the stopword dataset. The idea behind that constant is basically, "if a user searched for a single common word and it returned too many results, what number is 'too many results'?"  The example code uses 5000, but it should be adjusted for your use case.  The ``INDEX_STOPWORD_WORD_FREQ_CUTOFF`` is used to create the final stopword list that is loaded by the index build code.  The implication here is that if you modify the constant then that will change the contents of the stopword list, which further means that you will have to rebuild the search index as well.

## Creating a stopword list

Support for a stopword list is provided by the toplevel code, but it should be noted that the stopword list is optional.  In that toplevel code, if the logical pathname for the stopword list is not provided, or if the pathname is provided but no data is found, then the stopword functionality is simply ignored.

To create the stopword list, you will want to execute [BWRs/01_CreateStopwords.ecl](BWRs/01_CreateStopwords.ecl) in Thor.  That file loads the raw data using these two lines near the top:

```ecl
RAW_DATA_PATH := Home.Constants.PATH_PREFIX + '::business_namelist.csv';
rawData := DATASET(RAW_DATA_PATH, Root.Files.CommonRawDataLayout, CSV(UNICODE));
```

This example code assumes that the file has already been sprayed and has the full logical filename of ``~fuzzy_match::business_namelist.csv`` (definitions from [Constants.ecl](Constants.ecl) come into play, here).  The raw file's first three fields are what we need, in the right order, and the first line of the data does not contain field names.  For your own data, the easiest thing to do is to read it in and project it to the right format, then make sure the result is assigned to the attribute ``rawData`` at that same location; the rest of the code should Just Work.

The stopword dataset that is created is defined by the ``STOPWORD_PATH`` constant, defined within [Constants.ecl](Constants.ecl).  The workunit creates some other outputs as well, such as the number of words processed and a sample of words *not* included in the stopword list but were close to the cutoff.

## Building the search index

[BWRs/02_CreateIndexes.ecl](BWRs/02_CreateIndexes.ecl) is the code that actually creates the indexes.  It uses the same raw data file declaration as when building the stopword list, so you will have to make the same changes here to reference your own data.

This file contains a function that will be passed to the index-building code.  ``AdaptedDistance()`` returns an edit distance that should be used, given a string.  This allows you to specify different "fuzziness" for different-length words, which is a handy feature.

The bulk of the work is performed by the toplevel ``Build()`` function.  This BWR should run under Thor for performance reasons (and to handle actual big data scenarios).

## Creating and publishing the search query

[Queries/Search.ecl](Queries/Search.ecl) is the code for searching against the indexes created by [BWRs/02_CreateIndexes.ecl](BWRs/02_CreateIndexes.ecl).  The search code should be compiled -- not executed -- under Roxie, then published.

Most of the search code is related to handling the query parameters or echoing things back to the caller via multiple results.  Result pagination is also supported.

Note that an ``AdaptedDistance()`` function is defined here, like it was when creating the index.  It is not necessary to use the exactly same function for index creation and searching (as is shown in this example).  If both the original data is indexed with an edit distance of 1, then a user's query is also fuzzed with an edit distance of 1, the net effect could be retrieving data that is actually an edit distance of 2 away from the query.  Some experimentation may be needed to determine which values best meet the needs of your use case.
