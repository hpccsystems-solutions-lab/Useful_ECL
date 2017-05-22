/***************************************************************************

Replace the definition of R with a reference to a record structure, then
run this code to see the structure details; eg:

IMPORT SomeModule;

R := SomeModule.MyRecordStructure;

// or:  R := RECORDOF(SomeModule.myDataSet);

The output will be a scalar string containing XML.

***************************************************************************/

R := RECORD
	STRING s;
END;

//-----------------------------------

#DECLARE(recordDetails);
#EXPORT(recordDetails, R);
OUTPUT(%'recordDetails'%);
