# FuzzyMatching

## What Is This?

The code in this directory represents a complete example of implementing fuzzy search indexing and searching in ECL.  That is, given a dataset containing entity information (GUID, name, and alias), create ECL indexes that efficiently support fuzzy (non-exact) searching and also the queries that search those indexes and provide results.

An interesting feature of this example code is that two fuzzy search techniques are embodied in a single index/search step:  Retrieving similar words using both [Levenshtein Distance](https://en.wikipedia.org/wiki/Levenshtein_distance) and [Metaphone](https://en.wikipedia.org/wiki/Metaphone) matching.  Typically, this would require two different indexes and retrieval steps.  Here, both are combined into a single step.

Note that this code represents only one way to index and retrieve records with fuzzy matching, and it focuses entirely on fuzzy-matching words within strings.  There are many other techniques not shown here.

## Requirements

An embedded C++ function in this repo requires access to Unicode functions found in an external library.  HPCC Systems version 9.0 and later include both the library and header file in its distribution, but older versions rely on the operating system to provide those files.  If you receive an error indicating that the file ```unicode/unistr.h``` cannot be found, then you need to install a library package.  For either RHEL/CentOS or Debian operating systems, that package is ```libicu-dev```.  At minimum, you need to install it on the node that compiles your ECL code (the node running eclccserver).

## Repo Layout

```bash
├── Example_Business_Names/
├── Example_Person_Names/
├── Files.ecl
├── FuzzyNameMatch.ecl
└── README.md
```

The core of this fuzzy searching concept are embodied by the two files at the top level:

- [Files.ecl](Files.ecl): Contains record layouts, data type constants, and dataset/index definitions for files that will be created by this code.
- [FuzzyNameMatch.ecl](FuzzyNameMatch.ecl): The core code for index creation and searching.  Also contains function prototype definitions for functions that you will need to define in the calling code.

Two example implementations are included.  Both include a ``Queries`` directories containing Roxie-compatible search code, and a ``BWR`` directory containing code for creating the indexes needed for searching.

- [Example_Business_Names](Example_Business_Names): Supports the creation of a "stop word" dataset containing words that are too common to be useful in searching.
- [Example_Person_Names](Example_Person_Names): This is very similar to the business name example.  The main differences are combining individual name components (first, middle, family) at search time and the lack of stopword support.

## Raw Data Requirements

This code assumes the following structure for the raw data:

```ecl
RECORD
    STRING36  entity_guid;
    STRING36  name_guid;
    UTF8      name;
END
```

What those fields really mean:

- ``entity_guid``: A UUID (in string format) representing the global ID for an entity.  An entity can have multiple names (and hence, records in the dataset), so while a given value should refer to only one entity, it may be repeated if that entity has multiple names.  This is a required value.
- ``name_guid``:  A UUID (in string format) representing the global ID for a name for an entity.  If non-empty, this value should be unique within the dataset.  This is an optional value: if it is missing then it is assumed that there is only one name for the entity, and the entity_guid value is used for the name_guid.
- ``name``: A UTF-8 string representing one name for an entity.  This is a required value.

Odds are, your data will need to transformed into that structure.  The ECL definition for this record structure is ``CommonRawDataLayout`` within the [Files](Files.ecl) module.

## Usage

Create the search indexes using the ``Build()`` function within the [FuzzyNameMatch](FuzzyNameMatch.ecl) module. You will provide the raw data as well as some logical pathnames for the indexes that will be created.  In addition, the function wants a couple of function pointers:  One for cleaning a string and one for determining what edit distance to apply for a given word.  See the example code for ideas on how to write those functions.  The job that creates the index files should run in Thor.

Search queries use the indexes created in the prior step, and they are typically published to Roxie.  See the example code for ideas on how to write those queries.  Searching is performed via the ``BestMatches()`` function found in the [FuzzyNameMatch](FuzzyNameMatch.ecl) module.  Note that the example queries also support a pagination technique.

### Example: Business Names

A business name is typically a single string composed of multiple words. The name typically contains extremely common words such as "company", "inc", "limited", "the" and so on.  Searching for those words is usually not productive because they return too many possible matches, and indexing those words can lead to much larger indexes. Those words can be put onto a "stopword list" and, if found within the corpus or within a user's query, they can be ignored.

The Business Name example code provides a BWR that examines the raw data source and creates a stop list logical file.  That file is consulted by both the indexing code and the searching code.

See [Example_Business_Names](Example_Business_Names) for more information.

### Example: Person Names

Person names, in this example, are assumed to be a single string as well. This is admittedly a simplification, as most implementations would at least split family name out in order to correctly sort records.

The example code is much like the Business Name example code, with only a few differences:

- The values are cleaned using different rules.
- Stopwords are not supported (all words of sufficient length are indexed).
- The search form requests first, middle, and last names but concatenates those values for processing.

See [Example_Person_Names](Example_Person_Names) for more information.
