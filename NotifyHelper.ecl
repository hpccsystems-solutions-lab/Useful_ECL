/**
 * This module provides an easy way to use ECL's NOTIFY() function to pass
 * data between a running job and a waiting job.  For more information on
 * creating jobs that wait for events, see NOTIFY(), EVENT(), WHEN() and WAIT()
 * within the ECL language reference manual.
 *
 * This module focuses more on the parameter-passing aspect of NOTIFY() than
 * anything else, with the goal of being able to pass much richer data between
 * jobs than usual.  It is possible, with functions defined here, to pass
 * arbitrary datasets and sets between jobs as well as simple string values.
 *
 * There are three submodules within this module, each encompassing separate
 * aspects of encoding values to pass, decoding them, and actually
 * triggering the NOTIFY():
 *
 *  Encode
 *      AnyDataset()
 *      SetOfString()
 *      SimpleString()
 *  Decode
 *      AsAnyDataset()
 *      AsSetOfString()
 *      AsSimpleString()
 *  NotifyWith
 *      AnyDataset()
 *      SetOfString()
 *      SimpleString()
 *
 * This module has been designed to work together.  Specifically, the values
 * are coded and decoded with tags that the module knows about.  Everything
 * works best if you pair the writer and reader using the functions here
 * (for instance, if you use NotifyWith.SetOfString() to send off the
 * notification, the recipient should use Decode.AsSetOfString() to read the
 * data).
 *
 * Documentation on the specific functions can be found inline.  Example
 * BWRs (one that would wait for a notification, and one that triggers it) can
 * be found at the end of the file in comment blocks.
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */

IMPORT Std;

EXPORT NotifyHelper := MODULE

    /**
     * The Encode module contains functions for encoding data and preparing
     * it for use with the NOTIFY() ECL function.  The module is intended to be
     * used by running ECL jobs that need to send data to waiting jobs.
     *
     * Note that you can use the NotifyWith module functions to both encode
     * the data and send the notification in one step.  If those functions
     * are used then the Encode functions do not need to be used separately.
     */
    EXPORT Encode := MODULE

        /**
         * Converts a dataset into a string parameter suitable to be used
         * as the second argument of the NOTIFY() ECL command, so the data
         * can be passed to an ECL job waiting for it.
         *
         * The dataset should not be too large.  If you want to pass a large
         * amount of data, if would probably be better to write the data to
         * a file and then pass the logical filename of that file instead.
         *
         * @param   inDS        A dataset to encode
         *
         * @return  A string containing the encoded data.
         *
         * @see     Decode.AsAnyDataset()
         */
        EXPORT AnyDataset(inDS) := FUNCTIONMACRO
            #UNIQUENAME(jsonDS);
            LOCAL %jsonDS% := PROJECT
                (
                    inDS,
                    TRANSFORM
                        (
                            {STRING s},
                            SELF.s := '{' + (STRING)TOJSON(LEFT) + '}'
                        )
                );

            #UNIQUENAME(rolledUpJSON);
            LOCAL %rolledUpJSON% := ROLLUP
                (
                    %jsonDS%,
                    TRUE,
                    TRANSFORM
                        (
                            RECORDOF(LEFT),
                            SELF.s := LEFT.s + IF(LEFT.s != '', ', ', '') + RIGHT.s
                        ),
                    STABLE, ORDERED(TRUE)
                );

            #UNIQUENAME(finalJSON);
            LOCAL %finalJSON% := '{"d": [' + %rolledUpJSON%[1].s + ']}';

            #UNIQUENAME(xmlEncodedValue);
            LOCAL %xmlEncodedValue% := '<JSON_DATA>' + %finalJSON% + '</JSON_DATA>';

            #UNIQUENAME(result);
            LOCAL %result% := '<Event>' + %xmlEncodedValue% + '</Event>';

            RETURN %result%;
        ENDMACRO;

        /**
         * Converts a SET OF STRING value into a string parameter suitable to
         * be used  as the second argument of the NOTIFY() ECL command, so the
         * data can be passed to an ECL job waiting for it.
         *
         * @param   inSet       A SET OF STRING to encode
         *
         * @return  A string containing the encoded data.
         *
         * @see     Decode.AsSetOfString()
         */
        EXPORT SetOfString(SET OF STRING inSet) := FUNCTION
            RETURN AnyDataset(DATASET(inSet, {STRING s}));
        END;

        /**
         * Encodes a simple string in a format suitable to be used  as the
         * second argument of the NOTIFY() ECL command, so the string can be
         * passed to an ECL job waiting for it.
         *
         * @param   inString    A STRING to encode
         *
         * @return  A string containing the encoded data.
         *
         * @see     Decode.AsSimpleString()
         */
        EXPORT SimpleString(STRING inString) := FUNCTION
            xmlEncodedValue := '<SIMPLE_STRING>' + inString + '</SIMPLE_STRING>';
            result := '<Event>' + xmlEncodedValue + '</Event>';

            RETURN result;
        END;

    END;

    /**
     * The Decode module contains functions for decoding data previously
     * created by functions within the Encode module.  The module is intended to
     * be used by waiting ECL jobs that have just awakened by a notification
     * and need to extract passed-in data from the event.
     */
    EXPORT Decode := MODULE

        /**
         * Reads the data originally posted to an event by Encode.AnyDataset()
         * and creates a new dataset using the record definition provided.
         *
         * @param   datasetLayout   The RECORD definition describing the
         *                          data; it is helpful to explicitly tag
         *                          attributes within the definition with
         *                          {XPATH()} options
         *
         * @return  A new dataset in datasetLayout format containing the
         *          passed data
         *
         * @see     Encode.AnyDataset()
         */
        EXPORT AsAnyDataset(datasetLayout) := FUNCTIONMACRO
            #UNIQUENAME(dataAsJSON);
            LOCAL %dataAsJSON% := EVENTEXTRA('JSON_DATA') : GLOBAL;

            #UNIQUENAME(TempLayout);
            LOCAL %TempLayout% := RECORD
                DATASET(datasetLayout) d {XPATH('d')};
            END;

            #UNIQUENAME(parsedRow);
            LOCAL %parsedRow% := FROMJSON
                (
                    %TempLayout%,
                    %dataAsJSON%,
                    ONFAIL(TRANSFORM(%TempLayout%, SELF := []))
                );

            #UNIQUENAME(parsedParams);
            LOCAL %parsedParams% := NORMALIZE
                (
                    DATASET(%parsedRow%),
                    LEFT.d,
                    TRANSFORM
                        (
                            datasetLayout,
                            SELF := RIGHT
                        )
                );

            RETURN %parsedParams%;
        ENDMACRO;

        /**
         * Reads the data originally posted to an event by Encode.SetOfString()
         * and creates a new SET OF STRING value from it.
         *
         * @return  A new SET OF STRING value containing the passed data
         *
         * @see     Encode.SetOfString()
         */
        EXPORT AsSetOfString() := FUNCTION
            dsValue := AsAnyDataset({STRING s});

            RETURN SET(dsValue, s);
        END;

        /**
         * Reads the data originally posted to an event by Encode.SimpleString()
         * and creates a new STRING value from it.
         *
         * @return  A new STRING value containing the passed data
         *
         * @see     Encode.SimpleString()
         */
        EXPORT AsSimpleString() := FUNCTION
            RETURN GLOBAL(EVENTEXTRA('SIMPLE_STRING'));
        END;

    END;

    /**
     * The NotifyWith module contains convenience methods for both encoding
     * data to be passed to a waiting ECL job and then sending the notification
     * in one step.  The module is intended to be used by running ECL jobs that
     * need to send data to waiting jobs.
     */
    EXPORT NotifyWith := MODULE

        /**
         * Encodes a dataset and sends it as an event argument in a NOTIFY()
         * call.
         *
         * @param   name    The name of the event; this name should match
         *                  the name the waiting ECL job is using to watch
         *                  for events within its WHEN() or WAIT() calls
         * @param   inDS    The dataset to send to the waiting ECL job
         *
         * @return  A NOTIFY() action
         *
         * @see     Encode.AnyDataset()
         */
        EXPORT AnyDataset(name, inDS) := FUNCTIONMACRO
            RETURN NOTIFY((STRING)name, Useful_ECL.NotifyHelper.Encode.AnyDataset(inDS));
        ENDMACRO;

        /**
         * Encodes a set of strings and sends it as an event argument in a
         * NOTIFY() call.
         *
         * @param   name    The name of the event; this name should match
         *                  the name the waiting ECL job is using to watch
         *                  for events within its WHEN() or WAIT() calls
         * @param   inSet   The SET OF STRING value to send to the waiting
         *                   ECL job
         *
         * @return  A NOTIFY() action
         *
         * @see     Encode.SetOfString()
         */
        EXPORT SetOfString(STRING name, SET OF STRING inSet) := FUNCTION
            RETURN NOTIFY((STRING)name, Encode.SetOfString(inSet));
        END;

        /**
         * Encodes a string and sends it as an event argument in a
         * NOTIFY() call.
         *
         * @param   name    The name of the event; this name should match
         *                  the name the waiting ECL job is using to watch
         *                  for events within its WHEN() or WAIT() calls
         * @param   inStr   The string value to send to the waiting ECL job
         *
         * @return  A NOTIFY() action
         *
         * @see     Encode.SetOfString()
         */
        EXPORT SimpleString(STRING name, STRING inStr) := FUNCTION
            RETURN NOTIFY(name, Encode.SimpleString(inStr));
        END;

    END;

END;

//------------------------------------------------------------------------------
// Sample code (passing full datasets between ECL jobs)
//------------------------------------------------------------------------------

/*******************************************************************************
// Sample 'task runner' BWR that waits for a single notification, reads the
// passed parameters that are expected in specific format, then outputs those
// parameters.  This code should be submitted first, so that it is waiting
// for events that the 'task starter' BWR will emit.  This BWR will sit in
// wait mode until the event is received, then terminate.

IMPORT Useful_ECL;

#WORKUNIT('name', 'TaskRunner');

EVENT_NAME := 'RunTestProcess'; // Must match sender

RunProcess() := FUNCTION
    DataRec := RECORD
        STRING  a {XPATH('a')};
        STRING  b {XPATH('b')};
    END;

    paramInfo := Useful_ECL.NotifyHelper.Decode.AsAnyDataset(DataRec);

    RETURN OUTPUT(paramInfo, NAMED('RetrievedParameter'));
END;

RunProcess() : WHEN(EVENT_NAME, COUNT(1));
*******************************************************************************/

/*******************************************************************************
// Sample 'task starter' BWR that creates a sample inline dataset in the
// format that the task runner BWR expects, then emits a notification with
// that data as a parameter.

IMPORT Useful_ECL;

#WORKUNIT('name', 'TaskStarter');

EVENT_NAME := 'RunTestProcess'; // Must match receiver

DataRec := RECORD
    STRING  a;
    STRING  b;
END;

ds := DATASET
    (
        [
            {'1', '2'},
            {'3', '4'},
            {'5', '6'}
        ],
        DataRec
    );

Useful_ECL.NotifyHelper.NotifyWith.AnyDataset(EVENT_NAME, ds);
*******************************************************************************/
