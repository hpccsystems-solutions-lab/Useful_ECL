/**
 * A single macro that accepts a dataset and creates a .zip archive
 * from the contents.  This means you skip the following steps:
 *
 *      1) Write the data to Thor in the format you need (e.g.
 *         tab-delimited).
 *      2) Despray the file to the landing zone.
 *      3) Compress the landing zone file to a new archive.
 *
 * For large files, the time and space savings are considerable.
 *
 * To create something that looks like a .csv file, use:
 *      separator := ','
 *      quote := '"'
 *
 * The default values represent the task of "create a tab-delimited
 * zip file of the data."
 *
 * See the end of this file for an example execution.
 *
 * @param   outData         The dataset to process; neither child
 *                          datasets nor embedded records are supported;
 *                          REQUIRED
 * @param   outPath         A STRING representing the full path
 *                          of the file to create; note that ".zip"
 *                          will be appended to the path, and the
 *                          file that will be extracted will be name
 *                          given here; REQUIRED
 * @param   separator       The field delimiter, as a STRING; OPTIONAL,
 *                          defaults to a tab character
 * @param   quote           The character used to quote string values that
 *                          contain the SEPARATOR value; OPTIONAL,
 *                          defaults to an empty string
 * @param   includeHeader   If TRUE, the first line of the output will
 *                          contain the name of the fields delimited by
 *                          'separator'; OPTIONAL, defaults to TRUE
 *
 * Origin:  https://github.com/hpccsystems-solutions-lab/Useful_ECL
 */
EXPORT ExportZipArchive(outData,
                        outPath,
                        separator = '\'\t\'',
                        quote = '\'\'',
                        includeHeader = TRUE) := MACRO
    IMPORT Std;
    LOADXML('<xml/>');
    #EXPORTXML(outDataFields, RECORDOF(outData));
    #UNIQUENAME(needsDelim);
    #SET(needsDelim, 0);

    #UNIQUENAME(myOutPath);
    LOCAL %myOutPath% := TRIM((STRING)outPath, LEFT, RIGHT);

    #UNIQUENAME(outLayout);
    LOCAL %outLayout% := {STRING rec};

    #UNIQUENAME(AsQuoted);
    LOCAL %AsQuoted%(STRING s) := IF(quote = '' OR separator = '' OR Std.Str.Find(s, separator, 1) = 0, s, quote + s + quote);

    #SET(needsDelim, 0);
    #UNIQUENAME(headerStr);
    LOCAL %headerStr% := IF
        (
            includeHeader,
                #FOR(outDataFields)
                    #FOR(Field)
                        #IF(%needsDelim% = 1) + separator + #END
                        %AsQuoted%(%'@name'%)
                        #SET(needsDelim, 1)
                    #END
                #END
                + '\n',
            ''
        );

    #SET(needsDelim, 0);
    #UNIQUENAME(rewrittenDataDS);
    LOCAL %rewrittenDataDS% := PROJECT
        (
            outData,
            TRANSFORM
                (
                    %outLayout%,
                    SELF.rec := #FOR(outDataFields)
                                    #FOR(Field)
                                        #IF(%{@isRecord}% = 1 OR %{@isDataset}% = 1)
                                            #ERROR('Only flat datasets are supported')
                                        #END
                                        #IF(%needsDelim% = 1) + separator + #END
                                        %AsQuoted%(#EXPAND('(STRING)LEFT.' + %'@name'%))
                                        #SET(needsDelim, 1)
                                    #END
                                #END
                                + '\n'
                )
        );

    #UNIQUENAME(WriteFunc);
    LOCAL %WriteFunc%(STREAMED DATASET(%outLayout%) ds, VARSTRING path, VARSTRING header) := EMBED(C++)
        #option library archive

        #include "archive.h"
        #include "archive_entry.h"
        #include <cstdio>
        #include <string>

        #body

        std::string givenPath(path);
        std::string destPath = givenPath + ".zip";
        std::string destFilename(givenPath.substr(givenPath.find_last_of("/\\") + 1));
        int errNum = 0;

        // Try to remove any existing file
        if (std::remove(destPath.c_str()) != 0)
        {
            if (errno != ENOENT)
            {
                rtlFail(errno, "While trying to delete preexisting archive file");
            }
        }

        struct archive* archivePtr = archive_write_new();
        archive_write_set_format_zip(archivePtr);
        errNum = archive_write_open_filename(archivePtr, destPath.c_str());
        if (errNum != ARCHIVE_OK)
        {
            rtlFail(archive_errno(archivePtr), archive_error_string(archivePtr));
        }

        struct archive_entry* entryPtr = archive_entry_new();
        archive_entry_set_pathname(entryPtr, destFilename.c_str());
        archive_entry_set_filetype(entryPtr, AE_IFREG);
        archive_entry_set_perm(entryPtr, 0644);
        archive_write_header(archivePtr, entryPtr);

        if (header && header[0])
        {
            if (archive_write_data(archivePtr, header, strlen(header)) < 0)
            {
                rtlFail(archive_errno(archivePtr), archive_error_string(archivePtr));
            }
        }

        while(true)
        {
            const byte*     oneRow = static_cast<const byte*>(ds->nextRow());

            if (!oneRow)
            {
                oneRow = static_cast<const byte*>(ds->nextRow());
                if (!oneRow)
                {
                    break;
                }
            }

            const size32_t  rowSize = *(reinterpret_cast<const size32_t*>(oneRow));
            const char*     rowBuffer = reinterpret_cast<const char*>(oneRow + sizeof(rowSize));

            if (archive_write_data(archivePtr, rowBuffer, rowSize) < 0)
            {
                rtlFail(archive_errno(archivePtr), archive_error_string(archivePtr));
            }

            rtlReleaseRow(oneRow);
        }

        errNum = archive_write_finish_entry(archivePtr);
        if (errNum != ARCHIVE_OK)
        {
            rtlFail(archive_errno(archivePtr), archive_error_string(archivePtr));
        }

        archive_entry_free(entryPtr);

        errNum = archive_write_close(archivePtr);
        if (errNum != ARCHIVE_OK)
        {
            rtlFail(archive_errno(archivePtr), archive_error_string(archivePtr));
        }

        archive_write_free(archivePtr);
    ENDEMBED;

    %WriteFunc%(%rewrittenDataDS%, %myOutPath%, %headerStr%);
ENDMACRO;

/*=====================================================================================

// Example call

ds := DATASET
    (
        10000,
        TRANSFORM
            (
                {
                    UNSIGNED4 id,
                    UNSIGNED4 n
                },
                SELF.id := COUNTER,
                SELF.n := RANDOM()
            ),
        DISTRIBUTED
    );

LZ_DIR := '/var/lib/HPCCSystems/mydropzone';
DEST_FILE := LZ_DIR + '/test.txt';

// Archive will be named 'test.txt.zip'; the uncompressed file will
// be named 'test.txt'.

ExportZipArchive(ds, DEST_FILE);

*/
