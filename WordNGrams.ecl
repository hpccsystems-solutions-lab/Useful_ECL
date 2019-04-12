/**
 * Easy method for generate word n-grams (so-called "shingles") from a string.
 * The result is a dataset containing the n-grams as strings.  Multiple n-grams
 * (e.g. unigrams, bigrams, trigrams, etc) can be generated with one call.
 *
 * Note that this module requires HPCC Platform 7.2.0 or later, as it uses
 * C++11's regex functionality.
 *
 * Exported record definition:
 *
 *      WordNGramLayout
 *
 * Exported functions:
 *
 *      GenerateWordNGrams
 *      GenerateWordUnigrams
 *      GenerateWordBigrams
 *      GenerateWordTrigrams
 *
 * Sample calls shown at the end of the file.
 */
IMPORT Std;

EXPORT WordNGrams := MODULE

    /**
     * Record layout for datasets returned by exported functions
     */
    EXPORT WordNGramLayout := RECORD
        STRING  ngrams;
    END;

    /**
     * Generates word n-grams from an input string.  A word delimiter is defined
     * as any punctuation character other than an apostrophe.  Runs of word
     * delimiters are treated as a single delimiter.
     *
     * Multiple n-grams (e.g. unigrams, bigrams, etc) can be generated in the
     * same call by adjusting the min_gram and max_gram argument values.
     *
     * @param   s           The string to process; REQUIRED
     * @param   min_gram    The smallest n-gram to include in the output;
     *                      a zero value will be treated as a one value;
     *                      OPTIONAL, defaults to 1 (unigram)
     * @param   max_gram    The largest n-gram to include in the output;
     *                      if provided and less than the (possibly adjusted)
     *                      value of min_gram, will be set to min_gram;
     *                      OPTIONAL, defaults to 1 (unigram)
     *
     * @return  A dataset containing all n-grams generated from s.
     *
     * @see     GenerateWordUnigrams
     * @see     GenerateWordBigrams
     * @see     GenerateWordTrigrams
     */
    EXPORT STREAMED DATASET(WordNGramLayout) GenerateWordNGrams(CONST STRING s, UNSIGNED1 min_gram = 1, UNSIGNED1 max_gram = 1) := EMBED(C++)
        #option pure;

        // Requires C++11
        #include <regex>
        #include <string>
        #include <vector>

        class StreamDataset : public RtlCInterface, implements IRowStream
        {
            public:

                StreamDataset(IEngineRowAllocator* _resultAllocator, const char* _inputString, uint32_t _inputStringLen, uint32_t _minGram, uint32_t _maxGram)
                    : resultAllocator(_resultAllocator)
                {
                    // Populate word list
                    uint32_t                    myMinGram = (_minGram > 0 ? _minGram : 1);
                    uint32_t                    myMaxGram = (_maxGram >= _minGram ? _maxGram : _minGram);
                    std::string                 inputString(_inputString, _inputStringLen);
                    std::regex                  ws("((?!')[[:punct:]\\s])+"); // any punctuation other than apostrophe
                    std::sregex_token_iterator  wordIter(inputString.begin(), inputString.end(), ws, -1);

                    std::copy(wordIter, std::sregex_token_iterator(), std::back_inserter(wordList));

                    // Remove empty strings
                    wordList.erase(std::remove(wordList.begin(), wordList.end(), std::string()), wordList.end());

                    isStopped = (inputString.length() == 0 || wordList.size() == 0);
                    minGram = (_minGram > 0 ? _minGram : 1);
                    maxGram = (_maxGram >= _minGram ? _maxGram : _minGram);
                    currentWord = 0;
                    currentGram = minGram;
                }

                RTLIMPLEMENT_IINTERFACE

                virtual const void* nextRow()
                {
                    if (isStopped)
                    {
                        return NULL;
                    }

                    while (currentWord < wordList.size())
                    {
                        if (currentGram <= maxGram && currentWord + currentGram <= wordList.size())
                        {
                            std::string     buffer;

                            for (unsigned int x = 0; x < currentGram; x++)
                            {
                                if (x > 0)
                                    buffer += " ";
                                buffer += wordList[x + currentWord];
                            }

                            RtlDynamicRowBuilder    rowBuilder(resultAllocator);
                            uint32_t                len = buffer.length();
                            uint32_t                totalRowSize = sizeof(len) + len;
                            byte*                   row = rowBuilder.ensureCapacity(totalRowSize, NULL);

                            memcpy(row, &len, sizeof(len));
                            memcpy(row + sizeof(len), buffer.data(), len);

                            ++currentGram;

                            return rowBuilder.finalizeRowClear(totalRowSize);
                        }
                        else
                        {
                            ++currentWord;
                            currentGram = minGram;
                        }
                    }

                    isStopped = true;
                    return NULL;
                }
                virtual void stop()
                {
                    isStopped = true;
                }


            protected:

                Linked<IEngineRowAllocator> resultAllocator;

            private:

                bool                        isStopped;
                uint32_t                    minGram;
                uint32_t                    maxGram;
                uint32_t                    currentWord;
                uint32_t                    currentGram;
                std::vector<std::string>    wordList;
        };

        #body

        return new StreamDataset(_resultAllocator, s, lenS, min_gram, max_gram);
    ENDEMBED;

    /**
     * Helper function that simplifies the generation of unigrams.
     *
     * @param   s           The string to process; REQUIRED
     *
     * @return  A dataset containing all unigrams generated from s.
     *
     * @see     GenerateWordNGrams
     * @see     GenerateWordBigrams
     * @see     GenerateWordTrigrams
     */
    EXPORT STREAMED DATASET(WordNGramLayout) GenerateWordUnigrams(CONST STRING s) := GenerateWordNGrams(s, 1, 1);

    /**
     * Helper function that simplifies the generation of bigrams.
     *
     * @param   s           The string to process; REQUIRED
     *
     * @return  A dataset containing all bigrams generated from s.
     *
     * @see     GenerateWordNGrams
     * @see     GenerateWordUnigrams
     * @see     GenerateWordTrigrams
     */
    EXPORT STREAMED DATASET(WordNGramLayout) GenerateWordBigrams(CONST STRING s) := GenerateWordNGrams(s, 2, 2);

    /**
     * Helper function that simplifies the generation of trigrams.
     *
     * @param   s           The string to process; REQUIRED
     *
     * @return  A dataset containing all trigrams generated from s.
     *
     * @see     GenerateWordNGrams
     * @see     GenerateWordUnigrams
     * @see     GenerateWordBigrams
     */
    EXPORT STREAMED DATASET(WordNGramLayout) GenerateWordTrigrams(CONST STRING s) := GenerateWordNGrams(s, 3, 3);

END;

/**
 * Sample calls:
 *
 * res1 := GenerateWordNGrams('The quick brown fox jumped over the lazy dog.', 1, 9);
 * OUTPUT(res1);
 *
 * Result:
 *
 * The
 * The quick
 * The quick brown
 * The quick brown fox
 * The quick brown fox jumped
 * The quick brown fox jumped over
 * The quick brown fox jumped over the
 * The quick brown fox jumped over the lazy
 * The quick brown fox jumped over the lazy dog
 * quick
 * quick brown
 * quick brown fox
 * quick brown fox jumped
 * quick brown fox jumped over
 * quick brown fox jumped over the
 * quick brown fox jumped over the lazy
 * quick brown fox jumped over the lazy dog
 * brown
 * brown fox
 * brown fox jumped
 * brown fox jumped over
 * brown fox jumped over the
 * brown fox jumped over the lazy
 * brown fox jumped over the lazy dog
 * fox
 * fox jumped
 * fox jumped over
 * fox jumped over the
 * fox jumped over the lazy
 * fox jumped over the lazy dog
 * jumped
 * jumped over
 * jumped over the
 * jumped over the lazy
 * jumped over the lazy dog
 * over
 * over the
 * over the lazy
 * over the lazy dog
 * the
 * the lazy
 * the lazy dog
 * lazy
 * lazy dog
 * dog
 *
 * res2 := GenerateWordBigrams('The quick brown fox jumped over the lazy dog.');
 * OUTPUT(res2);
 *
 * Result:
 *
 * The quick
 * quick brown
 * brown fox
 * fox jumped
 * jumped over
 * over the
 * the lazy
 * lazy dog
 */
