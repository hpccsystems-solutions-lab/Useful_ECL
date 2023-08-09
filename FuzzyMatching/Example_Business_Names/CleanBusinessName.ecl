IMPORT Useful_ECL;

EXPORT UTF8 CleanBusinessName(UTF8 s) := FUNCTION
    cleanedName := Useful_ECL.CleanBusinessName(s);
    removeKeywords := REGEXREPLACE(u'\\b(?:SELECT)|(?:FROM)|(?:WHERE)|(?:TABLE)|(?:DELETE)|(?:CREATE)|(?:UPDATE)|(?:DROP)\\b', cleanedName, '');
    RETURN removeKeywords;
END;
