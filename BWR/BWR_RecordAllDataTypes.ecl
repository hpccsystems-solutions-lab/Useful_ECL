/**
 * Simple BWR that shows the output from the #EXPORT() template function when
 * presented with a record structure that contains almost every data type.
 * The output is actually captured within a comment section after the code.
 *
 * This is most useful for a macro programmer, as it shows what kind of XML
 * structure is returned as well as some of the possible values.
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
S := {INTEGER n};

R := RECORD
    BOOLEAN f_boolean;
    INTEGER f_integer;
    UNSIGNED f_unsigned;
    UNSIGNED INTEGER f_unsigned_integer;
    BIG_ENDIAN INTEGER f_big_endian_integer;
    BIG_ENDIAN UNSIGNED f_big_endian_unsigned;
    BIG_ENDIAN UNSIGNED INTEGER f_big_endian_unsigned_integer;
    LITTLE_ENDIAN INTEGER f_little_endian_integer;
    LITTLE_ENDIAN UNSIGNED f_little_endian_unsigned;
    LITTLE_ENDIAN UNSIGNED INTEGER f_little_endian_unsigned_integer;
    REAL f_real;
    DECIMAL32 f_decimal32;
    DECIMAL32_6 f_decimal32_6;
    UDECIMAL32 f_udecimal32;
    UDECIMAL32_6 f_udecimal32_6;
    UNSIGNED DECIMAL32 f_unsigned_decimal32;
    UNSIGNED DECIMAL32_6 f_unsigned_decimal32_6;
    STRING f_string;
    STRING256 f_string256;
    ASCII STRING f_ascii_string;
    ASCII STRING256 f_ascii_string256;
    EBCDIC STRING f_ebcdic_string;
    EBCDIC STRING256 f_ebcdic_string256;
    QSTRING f_qstring;
    QSTRING256 f_qstring256;
    UNICODE f_unicode;
    UNICODE_de f_unicode_de;
    UNICODE256 f_unicode256;
    UNICODE_de256 f_unicode_de256;
    UTF8 f_utf8;
    UTF8_de f_utf8_de;
    DATA f_data;
    DATA256 f_data256;
    VARSTRING f_varstring;
    VARSTRING256 f_varstring256;
    VARUNICODE f_varunicode;
    VARUNICODE_de f_varunicode_de;
    VARUNICODE256 f_varunicode256;
    VARUNICODE_de256 f_varunicode_de256;
    SET OF INTEGER f_set_of_integer;
    SET OF UNSIGNED f_set_of_unsigned;
    SET OF UNSIGNED INTEGER f_set_of_unsigned_integer;
    SET OF BIG_ENDIAN INTEGER f_set_of_big_endian_integer;
    SET OF BIG_ENDIAN UNSIGNED f_set_of_big_endian_unsigned;
    SET OF BIG_ENDIAN UNSIGNED INTEGER f_set_of_big_endian_unsigned_integer;
    SET OF LITTLE_ENDIAN INTEGER f_set_of_little_endian_integer;
    SET OF LITTLE_ENDIAN UNSIGNED f_set_of_little_endian_unsigned;
    SET OF LITTLE_ENDIAN UNSIGNED INTEGER f_set_of_little_endian_unsigned_integer;
    SET OF REAL f_set_of_real;
    SET OF BOOLEAN f_set_of_boolean;
    SET OF STRING f_set_of_string;
    SET OF STRING256 f_set_of_string256;
    SET OF ASCII STRING f_set_of_ascii_string;
    SET OF ASCII STRING256 f_set_of_ascii_string256;
    SET OF EBCDIC STRING f_set_of_ebcdic_string;
    SET OF EBCDIC STRING256 f_set_of_ebcdic_string256;
    SET OF UNICODE f_set_of_unicode;
    SET OF UNICODE_de f_set_of_unicode_de;
    SET OF UNICODE256 f_set_of_unicode256;
    SET OF UNICODE_de256 f_set_of_unicode_de256;
    SET OF DATA f_set_of_data;
    SET OF DATA256 f_set_of_data256;
    SET OF DATASET(S) f_set_of_dataset;
    S f_record;
    DATASET(S) f_child_dataset;
END;

#UNIQUENAME(recordDetails);
#EXPORT(recordDetails, R);
OUTPUT(%'recordDetails'%);

/*
<Data>
 <Field ecltype="boolean"
        label="f_boolean"
        name="f_boolean"
        position="0"
        rawtype="65536"
        size="1"
        type="boolean"/>
 <Field ecltype="integer8"
        label="f_integer"
        name="f_integer"
        position="1"
        rawtype="524289"
        size="8"
        type="integer"/>
 <Field ecltype="unsigned8"
        label="f_unsigned"
        name="f_unsigned"
        position="2"
        rawtype="524545"
        size="8"
        type="unsigned"/>
 <Field ecltype="unsigned8"
        label="f_unsigned_integer"
        name="f_unsigned_integer"
        position="3"
        rawtype="524545"
        size="8"
        type="unsigned"/>
 <Field ecltype="big_endian integer8"
        label="f_big_endian_integer"
        name="f_big_endian_integer"
        position="4"
        rawtype="524314"
        size="8"
        type="big_endian integer"/>
 <Field ecltype="big_endian unsigned integer8"
        label="f_big_endian_unsigned"
        name="f_big_endian_unsigned"
        position="5"
        rawtype="524570"
        size="8"
        type="big_endian unsigned integer"/>
 <Field ecltype="big_endian unsigned integer8"
        label="f_big_endian_unsigned_integer"
        name="f_big_endian_unsigned_integer"
        position="6"
        rawtype="524570"
        size="8"
        type="big_endian unsigned integer"/>
 <Field ecltype="integer8"
        label="f_little_endian_integer"
        name="f_little_endian_integer"
        position="7"
        rawtype="524289"
        size="8"
        type="integer"/>
 <Field ecltype="unsigned8"
        label="f_little_endian_unsigned"
        name="f_little_endian_unsigned"
        position="8"
        rawtype="524545"
        size="8"
        type="unsigned"/>
 <Field ecltype="unsigned8"
        label="f_little_endian_unsigned_integer"
        name="f_little_endian_unsigned_integer"
        position="9"
        rawtype="524545"
        size="8"
        type="unsigned"/>
 <Field ecltype="real8"
        label="f_real"
        name="f_real"
        position="10"
        rawtype="524290"
        size="8"
        type="real"/>
 <Field ecltype="decimal32"
        label="f_decimal32"
        name="f_decimal32"
        position="11"
        rawtype="1114115"
        size="17"
        type="decimal"/>
 <Field ecltype="decimal32_6"
        label="f_decimal32_6"
        name="f_decimal32_6"
        position="12"
        rawtype="1114115"
        size="17"
        type="decimal"/>
 <Field ecltype="udecimal32"
        label="f_udecimal32"
        name="f_udecimal32"
        position="13"
        rawtype="1048579"
        size="16"
        type="udecimal"/>
 <Field ecltype="udecimal32_6"
        label="f_udecimal32_6"
        name="f_udecimal32_6"
        position="14"
        rawtype="1048579"
        size="16"
        type="udecimal"/>
 <Field ecltype="udecimal32"
        label="f_unsigned_decimal32"
        name="f_unsigned_decimal32"
        position="15"
        rawtype="1048579"
        size="16"
        type="udecimal"/>
 <Field ecltype="udecimal32_6"
        label="f_unsigned_decimal32_6"
        name="f_unsigned_decimal32_6"
        position="16"
        rawtype="1048579"
        size="16"
        type="udecimal"/>
 <Field ecltype="string"
        label="f_string"
        name="f_string"
        position="17"
        rawtype="-983036"
        size="-15"
        type="string"/>
 <Field ecltype="string256"
        label="f_string256"
        name="f_string256"
        position="18"
        rawtype="16777220"
        size="256"
        type="string"/>
 <Field ecltype="string"
        label="f_ascii_string"
        name="f_ascii_string"
        position="19"
        rawtype="-983036"
        size="-15"
        type="string"/>
 <Field ecltype="string256"
        label="f_ascii_string256"
        name="f_ascii_string256"
        position="20"
        rawtype="16777220"
        size="256"
        type="string"/>
 <Field ecltype="EBCDIC string"
        label="f_ebcdic_string"
        name="f_ebcdic_string"
        position="21"
        rawtype="-982524"
        size="-15"
        type="EBCDIC string"/>
 <Field ecltype="EBCDIC string256"
        label="f_ebcdic_string256"
        name="f_ebcdic_string256"
        position="22"
        rawtype="16777732"
        size="256"
        type="EBCDIC string"/>
 <Field ecltype="qstring"
        label="f_qstring"
        name="f_qstring"
        position="23"
        rawtype="-983010"
        size="-15"
        type="qstring"/>
 <Field ecltype="qstring256"
        label="f_qstring256"
        name="f_qstring256"
        position="24"
        rawtype="12582942"
        size="192"
        type="qstring"/>
 <Field ecltype="unicode"
        label="f_unicode"
        name="f_unicode"
        position="25"
        rawtype="-983009"
        size="-15"
        type="unicode"/>
 <Field ecltype="unicode_de"
        label="f_unicode_de"
        name="f_unicode_de"
        position="26"
        rawtype="-983009"
        size="-15"
        type="unicode_de"/>
 <Field ecltype="unicode256"
        label="f_unicode256"
        name="f_unicode256"
        position="27"
        rawtype="33554463"
        size="512"
        type="unicode"/>
 <Field ecltype="unicode_de256"
        label="f_unicode_de256"
        name="f_unicode_de256"
        position="28"
        rawtype="33554463"
        size="512"
        type="unicode_de"/>
 <Field ecltype="utf8"
        label="f_utf8"
        name="f_utf8"
        position="29"
        rawtype="-982999"
        size="-15"
        type="utf"/>
 <Field ecltype="utf8_de"
        label="f_utf8_de"
        name="f_utf8_de"
        position="30"
        rawtype="-982999"
        size="-15"
        type="utf8_de"/>
 <Field ecltype="data"
        label="f_data"
        name="f_data"
        position="31"
        rawtype="-983024"
        size="-15"
        type="data"/>
 <Field ecltype="data256"
        label="f_data256"
        name="f_data256"
        position="32"
        rawtype="16777232"
        size="256"
        type="data"/>
 <Field ecltype="varstring"
        label="f_varstring"
        name="f_varstring"
        position="33"
        rawtype="-983026"
        size="-15"
        type="varstring"/>
 <Field ecltype="varstring256"
        label="f_varstring256"
        name="f_varstring256"
        position="34"
        rawtype="16842766"
        size="257"
        type="varstring"/>
 <Field ecltype="varunicode"
        label="f_varunicode"
        name="f_varunicode"
        position="35"
        rawtype="-983007"
        size="-15"
        type="varunicode"/>
 <Field ecltype="varunicode_de"
        label="f_varunicode_de"
        name="f_varunicode_de"
        position="36"
        rawtype="-983007"
        size="-15"
        type="varunicode_de"/>
 <Field ecltype="varunicode256"
        label="f_varunicode256"
        name="f_varunicode256"
        position="37"
        rawtype="33685537"
        size="514"
        type="varunicode"/>
 <Field ecltype="varunicode_de256"
        label="f_varunicode_de256"
        name="f_varunicode_de256"
        position="38"
        rawtype="33685537"
        size="514"
        type="varunicode_de"/>
 <Field ecltype="set of integer8"
        label="f_set_of_integer"
        name="f_set_of_integer"
        position="39"
        rawtype="-983019"
        size="-15"
        type="set of integer"/>
 <Field ecltype="set of unsigned8"
        label="f_set_of_unsigned"
        name="f_set_of_unsigned"
        position="40"
        rawtype="-983019"
        size="-15"
        type="set of unsigned"/>
 <Field ecltype="set of unsigned8"
        label="f_set_of_unsigned_integer"
        name="f_set_of_unsigned_integer"
        position="41"
        rawtype="-983019"
        size="-15"
        type="set of unsigned"/>
 <Field ecltype="set of big_endian integer8"
        label="f_set_of_big_endian_integer"
        name="f_set_of_big_endian_integer"
        position="42"
        rawtype="-983019"
        size="-15"
        type="set of big_endian integer"/>
 <Field ecltype="set of big_endian unsigned integer8"
        label="f_set_of_big_endian_unsigned"
        name="f_set_of_big_endian_unsigned"
        position="43"
        rawtype="-983019"
        size="-15"
        type="set of big_endian unsigned integer"/>
 <Field ecltype="set of big_endian unsigned integer8"
        label="f_set_of_big_endian_unsigned_integer"
        name="f_set_of_big_endian_unsigned_integer"
        position="44"
        rawtype="-983019"
        size="-15"
        type="set of big_endian unsigned integer"/>
 <Field ecltype="set of integer8"
        label="f_set_of_little_endian_integer"
        name="f_set_of_little_endian_integer"
        position="45"
        rawtype="-983019"
        size="-15"
        type="set of integer"/>
 <Field ecltype="set of unsigned8"
        label="f_set_of_little_endian_unsigned"
        name="f_set_of_little_endian_unsigned"
        position="46"
        rawtype="-983019"
        size="-15"
        type="set of unsigned"/>
 <Field ecltype="set of unsigned8"
        label="f_set_of_little_endian_unsigned_integer"
        name="f_set_of_little_endian_unsigned_integer"
        position="47"
        rawtype="-983019"
        size="-15"
        type="set of unsigned"/>
 <Field ecltype="set of real8"
        label="f_set_of_real"
        name="f_set_of_real"
        position="48"
        rawtype="-983019"
        size="-15"
        type="set of real"/>
 <Field ecltype="set of boolean"
        label="f_set_of_boolean"
        name="f_set_of_boolean"
        position="49"
        rawtype="-983019"
        size="-15"
        type="set of boolean"/>
 <Field ecltype="set of string"
        label="f_set_of_string"
        name="f_set_of_string"
        position="50"
        rawtype="-983019"
        size="-15"
        type="set of string"/>
 <Field ecltype="set of string256"
        label="f_set_of_string256"
        name="f_set_of_string256"
        position="51"
        rawtype="-983019"
        size="-15"
        type="set of string"/>
 <Field ecltype="set of string"
        label="f_set_of_ascii_string"
        name="f_set_of_ascii_string"
        position="52"
        rawtype="-983019"
        size="-15"
        type="set of string"/>
 <Field ecltype="set of string256"
        label="f_set_of_ascii_string256"
        name="f_set_of_ascii_string256"
        position="53"
        rawtype="-983019"
        size="-15"
        type="set of string"/>
 <Field ecltype="set of EBCDIC string"
        label="f_set_of_ebcdic_string"
        name="f_set_of_ebcdic_string"
        position="54"
        rawtype="-983019"
        size="-15"
        type="set of EBCDIC string"/>
 <Field ecltype="set of EBCDIC string256"
        label="f_set_of_ebcdic_string256"
        name="f_set_of_ebcdic_string256"
        position="55"
        rawtype="-983019"
        size="-15"
        type="set of EBCDIC string"/>
 <Field ecltype="set of unicode"
        label="f_set_of_unicode"
        name="f_set_of_unicode"
        position="56"
        rawtype="-983019"
        size="-15"
        type="set of unicode"/>
 <Field ecltype="set of unicode_de"
        label="f_set_of_unicode_de"
        name="f_set_of_unicode_de"
        position="57"
        rawtype="-983019"
        size="-15"
        type="set of unicode_de"/>
 <Field ecltype="set of unicode256"
        label="f_set_of_unicode256"
        name="f_set_of_unicode256"
        position="58"
        rawtype="-983019"
        size="-15"
        type="set of unicode"/>
 <Field ecltype="set of unicode_de256"
        label="f_set_of_unicode_de256"
        name="f_set_of_unicode_de256"
        position="59"
        rawtype="-983019"
        size="-15"
        type="set of unicode_de"/>
 <Field ecltype="set of data"
        label="f_set_of_data"
        name="f_set_of_data"
        position="60"
        rawtype="-983019"
        size="-15"
        type="set of data"/>
 <Field ecltype="set of data256"
        label="f_set_of_data256"
        name="f_set_of_data256"
        position="61"
        rawtype="-983019"
        size="-15"
        type="set of data"/>
 <Field ecltype="set of table of &lt;unnamed&gt;"
        label="f_set_of_dataset"
        name="f_set_of_dataset"
        position="62"
        rawtype="-983019"
        size="8"
        type="set of table of &lt;unnamed&gt;"/>
 <Field ecltype="integer8"
        label="n"
        name="n"
        position="63"
        rawtype="524289"
        size="8"
        type="integer"/>
 <Field isEnd="1" name="f_set_of_dataset"/>
 <Field ecltype="s"
        isRecord="1"
        label="f_record"
        name="f_record"
        position="64"
        rawtype="13"
        size="8"
        type="s"/>
 <Field ecltype="integer8"
        label="n"
        name="n"
        position="65"
        rawtype="524289"
        size="8"
        type="integer"/>
 <Field isEnd="1" name="f_record"/>
 <Field ecltype="table of &lt;unnamed&gt;"
        isDataset="1"
        label="f_child_dataset"
        name="f_child_dataset"
        position="66"
        rawtype="-983020"
        size="8"
        type="table of &lt;unnamed&gt;"/>
 <Field ecltype="integer8"
        label="n"
        name="n"
        position="67"
        rawtype="524289"
        size="8"
        type="integer"/>
 <Field isEnd="1" name="f_child_dataset"/>
</Data>
*/