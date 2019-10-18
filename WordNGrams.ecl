/**
 * Easy method for generate word n-grams (so-called "shingles") from a string.
 * The result is a dataset containing the n-grams as strings.  Multiple n-grams
 * (e.g. unigrams, bigrams, trigrams, etc) can be generated with one call.
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
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
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
     * as a space or any punctuation character other than an apostrophe.  Runs
     * of word delimiters are treated as a single delimiter.
     *
     * Multiple n-grams (e.g. unigrams, bigrams, etc) can be generated in the
     * same call by adjusting the min_gram and max_gram argument values.
     *
     * @param   s               The string to process; REQUIRED
     * @param   min_gram        The smallest n-gram to include in the output;
     *                          a zero value will be treated as a one value;
     *                          OPTIONAL, defaults to 1 (unigram)
     * @param   max_gram        The largest n-gram to include in the output;
     *                          if provided and less than the (possibly
     *                          adjusted) value of min_gram, will be set to
     *                          min_gram; OPTIONAL, defaults to 1 (unigram)
     * @param   min_word_len    The minimum length of a word that will be
     *                          processed; words less than this length will be
     *                          ignored when creating the ngrams; OPTIONAL,
     *                          defaults to 1
     *
     * @return  A dataset containing all n-grams generated from s.
     *
     * @see     GenerateWordUnigrams
     * @see     GenerateWordBigrams
     * @see     GenerateWordTrigrams
     */
    EXPORT STREAMED DATASET(WordNGramLayout) GenerateWordNGrams(CONST STRING s, UNSIGNED1 min_gram = 1, UNSIGNED1 max_gram = 1, UNSIGNED1 min_word_len = 1) := EMBED(C++)
        #option pure;

        #include <string>
        #include <vector>

        #define IS_DELIMITER(x) ((::ispunct(x) != 0 && x != '\'') || ::isspace(x))

        class StreamDataset : public RtlCInterface, implements IRowStream
        {
            public:

                StreamDataset(IEngineRowAllocator* _resultAllocator, const char* _inputString, uint32_t _inputStringLen, uint32_t _minGram, uint32_t _maxGram, uint32_t _minWordLen)
                    : resultAllocator(_resultAllocator)
                {
                    int32_t     startPos = -1;

                    for (uint32_t pos = 0; pos < _inputStringLen; pos++)
                    {
                        if (!IS_DELIMITER(_inputString[pos]))
                        {
                            startPos = pos;
                            break;
                        }
                    }

                    if (startPos >= 0)
                    {
                        uint32_t    wordPos = startPos;
                        bool        lastCharWasDelim = false;

                        for (uint32_t pos = startPos + 1; pos < _inputStringLen; pos++)
                        {
                            if (IS_DELIMITER(_inputString[pos]))
                            {
                                if (!lastCharWasDelim && pos-wordPos >= _minWordLen)
                                {
                                    wordList.push_back(std::string(&_inputString[wordPos], pos-wordPos));
                                }
                                lastCharWasDelim = true;
                            }
                            else
                            {
                                if (lastCharWasDelim)
                                {
                                    wordPos = pos;
                                    lastCharWasDelim = false;
                                }
                            }
                        }

                        if (!lastCharWasDelim && wordPos < _inputStringLen && _inputStringLen-wordPos >= _minWordLen)
                        {
                            wordList.push_back(std::string(&_inputString[wordPos], _inputStringLen-wordPos));
                        }
                    }

                    isStopped = (_inputStringLen == 0 || wordList.size() == 0);
                    minGram = (_minGram > 0 ? _minGram : 1);
                    maxGram = (_maxGram >= _minGram ? _maxGram : _minGram);
                    minWordLen = _minWordLen;
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
                uint32_t                    minWordLen;
                uint32_t                    currentWord;
                uint32_t                    currentGram;
                std::vector<std::string>    wordList;
        };

        #body

        return new StreamDataset(_resultAllocator, s, lenS, min_gram, max_gram, min_word_len);
    ENDEMBED;

    /**
     * Helper function that simplifies the generation of unigrams.
     *
     * @param   s               The string to process; REQUIRED
     * @param   min_word_len    The minimum length of a word that will be
     *                          processed; words less than this length will be
     *                          ignored when creating the ngrams; OPTIONAL,
     *                          defaults to 1
     *
     * @return  A dataset containing all unigrams generated from s.
     *
     * @see     GenerateWordNGrams
     * @see     GenerateWordBigrams
     * @see     GenerateWordTrigrams
     */
    EXPORT STREAMED DATASET(WordNGramLayout) GenerateWordUnigrams(CONST STRING s, UNSIGNED1 min_word_len = 1) := GenerateWordNGrams(s, 1, 1, min_word_len);

    /**
     * Helper function that simplifies the generation of bigrams.
     *
     * @param   s               The string to process; REQUIRED
     * @param   min_word_len    The minimum length of a word that will be
     *                          processed; words less than this length will be
     *                          ignored when creating the ngrams; OPTIONAL,
     *                          defaults to 1
     *
     * @return  A dataset containing all bigrams generated from s.
     *
     * @see     GenerateWordNGrams
     * @see     GenerateWordUnigrams
     * @see     GenerateWordTrigrams
     */
    EXPORT STREAMED DATASET(WordNGramLayout) GenerateWordBigrams(CONST STRING s, UNSIGNED1 min_word_len = 1) := GenerateWordNGrams(s, 2, 2, min_word_len);

    /**
     * Helper function that simplifies the generation of trigrams.
     *
     * @param   s               The string to process; REQUIRED
     * @param   min_word_len    The minimum length of a word that will be
     *                          processed; words less than this length will be
     *                          ignored when creating the ngrams; OPTIONAL,
     *                          defaults to 1
     *
     * @return  A dataset containing all trigrams generated from s.
     *
     * @see     GenerateWordNGrams
     * @see     GenerateWordUnigrams
     * @see     GenerateWordBigrams
     */
    EXPORT STREAMED DATASET(WordNGramLayout) GenerateWordTrigrams(CONST STRING s, UNSIGNED1 min_word_len = 1) := GenerateWordNGrams(s, 3, 3, min_word_len);

END;

/**
 * Sample calls:
 *
 * res1 := WordNGrams.GenerateWordNGrams('The quick brown fox jumped over the lazy dog.', 1, 9);
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
 * res2 := WordNGrams.GenerateWordBigrams('The quick brown fox jumped over the lazy dog.');
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
