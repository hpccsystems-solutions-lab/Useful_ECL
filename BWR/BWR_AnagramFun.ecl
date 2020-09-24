/**
 * This is a fun example involving finding anagrams within a list of words
 * using ECL.  Several ECL techniques are demonstrated, including embedded
 * C++ code, reading a "plain" text file from disk, explicit data distribution
 * (with local execution), deduplication, sorting, and computing some simple
 * statistics.
 *
 * The code uses Linux's built-in dictionary file, located at
 * /usr/share/dict/words.  The assumption is that there will be one word per
 * line.  You can use a different file by changing the value of the
 * WORD_FILE_PATH attribute.
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
IMPORT Std;

/**
 * Helper function for computing a 'prime factor product' of a text string.
 * The idea here is to map letters to prime numbers, then multiply all prime
 * numbers together to create a unique unsigned integer value representing
 * the string.  The order in which the letters appear in the string do not
 * change the result, which makes this an effective way of grouping anagrams
 * together.
 *
 * @param   s   The word to convert to a prime factor product
 *
 * @return  An UNSIGNED8 value.  Will return zero if the string does not
 *          contain any ASCII characters.
 */
UNSIGNED8 StringToPrimeFactorProduct(CONST VARSTRING s) := EMBED(C++)
    #option pure;
    __uint64    res = 1;

    while (*s)
    {
        switch (toupper(*s))
        {
            case 'E': res *= 2; break;
            case 'A': res *= 3; break;
            case 'R': res *= 5; break;
            case 'I': res *= 7; break;
            case 'O': res *= 11; break;
            case 'T': res *= 13; break;
            case 'N': res *= 17; break;
            case 'S': res *= 19; break;
            case 'L': res *= 23; break;
            case 'C': res *= 29; break;
            case 'U': res *= 31; break;
            case 'D': res *= 37; break;
            case 'P': res *= 41; break;
            case 'M': res *= 43; break;
            case 'H': res *= 47; break;
            case 'G': res *= 53; break;
            case 'B': res *= 59; break;
            case 'F': res *= 61; break;
            case 'Y': res *= 67; break;
            case 'W': res *= 71; break;
            case 'K': res *= 73; break;
            case 'V': res *= 79; break;
            case 'X': res *= 83; break;
            case 'Z': res *= 89; break;
            case 'J': res *= 97; break;
            case 'Q': res *= 101; break;
        }

        ++s;
    }

    return res > 1 ? res : 0;
ENDEMBED;

//------------------------------------------------------------------------------

// We will use the dictionary supplied with Linux
WORD_FILE_PATH := '/usr/share/dict/words';

WordRec := RECORD
    STRING  word;
END;

// Reads the file, mapping one line of input to its own record
words0 := DATASET
    (
        Std.File.ExternalLogicalFileName('127.0.0.1', WORD_FILE_PATH),
        WordRec,
        CSV(QUOTE(''), SEPARATOR(''))
    );

OUTPUT(COUNT(words0), NAMED('original_word_count'));

// Convert each word to uppercase and remove apostrophes (found via inspection);
// while we don't have to convert to uppercase for the prime factor product
// computation, we do need to do that in order to deduplicate the words (a
// necessary step since we remove some characters)
words1 := PROJECT
    (
        words0,
        TRANSFORM
            (
                RECORDOF(LEFT),
                SELF.word := Std.Str.ToUpperCase(Std.Str.FilterOut(LEFT.word, '\''))
            )
    );

// Make sure we have at least two characters in each word
words2 := words1(LENGTH(word) > 1);

// Remove the duplicates
words3 := DEDUP(SORT(words2, word), word);

words := words3;

OUTPUT(COUNT(words), NAMED('final_word_count'));

// Compute the prime factor product (PFP) for each word
wordsWithPrimeFactorProduct := PROJECT
    (
        words,
        TRANSFORM
            (
                {
                    UNSIGNED8   pfp,
                    WordRec
                },

                myPFP := StringToPrimeFactorProduct(LEFT.word);

                SELF.pfp := IF(myPFP > 0, myPFP, SKIP),
                SELF := LEFT
            )
    );

// Redistribute our data so that words with the same PFP wind up on the same
// Thor nodes
distributedWords := DISTRIBUTE(wordsWithPrimeFactorProduct, pfp);

// Create dataset containing unique PFP values
uniquePFPs := TABLE(distributedWords, {pfp}, pfp, LOCAL);

AnagramRec := RECORD
    UNSIGNED8           pfp;
    UNSIGNED2           word_count;
    DATASET(WordRec)    anagrams;
END;

// Group words with the same PFP value together -- by definition, they will be
// anagrams; skip records that contain only one word in the word list
groupedAnagrams := DENORMALIZE
    (
        uniquePFPs,
        distributedWords,
        LEFT.pfp = RIGHT.pfp,
        GROUP,
        TRANSFORM
            (
                AnagramRec,

                wordList := SORT(PROJECT(ROWS(RIGHT), TRANSFORM(WordRec, SELF := LEFT)), word);

                SELF.pfp := LEFT.pfp,
                SELF.word_count := IF(COUNT(ROWS(RIGHT)) > 1, COUNT(ROWS(RIGHT)), SKIP),
                SELF.anagrams := wordList
            ),
        LOCAL
    );

// Show the found anagrams; explicitly sort by word count, the length of the
// anagram, and the PFP value (the last item is merely to make the result
// stable)
OUTPUT(SORT(groupedAnagrams, -word_count, -LENGTH(anagrams[1].word), pfp), NAMED('anagram_sample'));

// Compute some stats about the anagrams we found
anagramStats := TABLE
    (
        groupedAnagrams,
        {
            UNSIGNED4       num_words_within_anagram := word_count,
            UNSIGNED4       occurs := COUNT(GROUP)
        },
        word_count,
        MERGE
    );

// Show the computed stats, sorting (descending) by the number of words in
// an anagram group
OUTPUT(SORT(anagramStats, -num_words_within_anagram), NAMED('anagram_stats'));

numOfWordsInAnagrams := SUM(anagramStats, num_words_within_anagram * occurs);

OUTPUT(numOfWordsInAnagrams, NAMED('words_that_form_anagrams_count'));
