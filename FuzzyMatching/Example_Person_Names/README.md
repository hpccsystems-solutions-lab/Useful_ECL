# Fuzzy Searching for Person Names

## What Is This?

The code in this directory is a complete example of one way to fuzzy search for peoples' names.  It demonstrates the following techniques:

- Normalizing and cleaning names
- Passing a function for name cleaning to the underlying library code (a method of factoring the code to make it more flexible)
- Passing a function to dynamically choose a Levenshtein edit distance to use for an individual word, making it somewhat adaptive
- Creating fuzzy search indexes for individual words within a name, runnable under Thor so it can handle large datasets
- Creating a search query, runnable under Roxie, to search the indexes and score the results, supporting paginated results

## Code Layout

```bash
├── BWRs
│   └── 01_CreateIndexes.ecl
├── CleanPersonName.ecl
├── Constants.ecl
├── Queries
│   └── Search.ecl
└── README.md
```

The two files at the top level are used by other code:

- [CleanPersonName.ecl](CleanPersonName.ecl): A function that accepts a UTF-8 string representing a full person name and then returns a normalized and "cleaned" version of that same string.  The function is used when both indexing and querying.
- [Constants.ecl](Constants.ecl): Constants used in other parts of the code. In this example, all of the exported values are logical pathname declarations.

## Building the search index

[BWRs/01_CreateIndexes.ecl](BWRs/01_CreateIndexes.ecl) is the code that actually creates the indexes.  That file loads the raw data using these two lines near the top:

```ecl
RAW_DATA_PATH := Home.Constants.PATH_PREFIX + '::person_namelist.csv';
rawData := DATASET(RAW_DATA_PATH, Root.Files.CommonRawDataLayout, CSV(UNICODE));
```

This example code assumes that the file has already been sprayed and has the full logical filename of ``~fuzzy_match:: person_namelist.csv `` (definitions from [Constants.ecl](Constants.ecl) come into play, here).  The raw file's first three fields are what we need, in the right order, and the first line of the data does not contain field names.  For your own data, the easiest thing to do is to read it in and project it to the right format, then make sure the result is assigned to the attribute ``rawData`` at that same location; the rest of the code should Just Work.

This file contains a function that will be passed to the index-building code.  ``AdaptedDistance()`` returns an edit distance that should be used, given a string.  This allows you to specify different "fuzziness" for different-length words, which is a handy feature.

The bulk of the work is performed by the toplevel ``Build()`` function.  This BWR should run under Thor for performance reasons (and to handle actual big data scenarios).

## Creating and publishing the search query

[Queries/Search.ecl](Queries/Search.ecl) is the code for searching against the indexes created by [BWRs/01_CreateIndexes.ecl](BWRs/01_CreateIndexes.ecl).  The search code should be compiled -- not executed -- under Roxie, then published.

Most of the search code is related to handling the query parameters or echoing things back to the caller via multiple results.  Result pagination is also supported.

This query prompts for first, middle, and last names individually but then it combines them into a single string for cleaning and further processing.  This makes the code function very similar to the business name example.  You may want to consider using separate processing of those name components, for finer-grained cleaning and normalization if nothing else.

Note that an ``AdaptedDistance()`` function is defined here, like it was when creating the index.  It is not necessary to use the exactly same function for index creation and searching (as is shown in this example).  If both the original data is indexed with an edit distance of 1, then a user's query is also fuzzed with an edit distance of 1, the net effect could be retrieving data that is actually an edit distance of 2 away from the query.  Some experimentation may be needed to determine which values best meet the needs of your use case.
