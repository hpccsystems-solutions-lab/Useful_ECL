/**
 * The BitSet module provides structures and algorithms for creating and
 * manipulating bit arrays (called bitsets here) of arbitrary size
 * (up to 4GB of RAM).  A bitset is stored in a compact manner, with
 * eight bits represented per byte.
 *
 * Bits within a bitset are referenced with a zero-based offset.  The first
 * bit is at position zero and, if the bitset was printed as a binary string
 * of zeros and ones, its position would be at the far right of the string.
 *
 * Attributes exported by this module (detailed descriptions are inlined with
 * each exported symbol):
 *
 *      // Typedefs
 *      BitSet_t := DATA;
 *      Footprint_t := UNSIGNED4;
 *      BitCapacity_t := UNSIGNED6;
 *      BitPosition_t := UNSIGNED6;
 *
 *      // Record definitions
 *      BitPositionsRec := {BitPosition_t bitPos};
 *
 *      // Max values
 *      MAX_FOOTPRINT := (Footprint_t)-1;
 *      MAX_BIT_CAPACITY := MAX_FOOTPRINT * 8;
 *      HIGHEST_BIT_POSITION := MAX_BIT_CAPACITY - 1;
 *      LOWEST_BIT_POSITION := 0;
 *
 *      // Sizes of a particular bitset
 *      Footprint_t Footprint(CONST BitSet_t b);
 *      BitCapacity_t Capacity(CONST BitSet_t b);
 *
 *      // Exporting a bitset as a different format
 *      STRING AsHexString(CONST BitSet_t b);
 *      STRING AsBinaryString(CONST BitSet_t b);
 *      LITTLE_ENDIAN UNSIGNED8 AsUnsigned(CONST BitSet_t b);
 *
 *      // Creating new bitsets
 *      BitSet_t New(BitCapacity_t bit_capacity);
 *      BitSet_t NewFromIntValue(LITTLE_ENDIAN UNSIGNED8 n, BitCapacity_t bit_capacity = 64);
 *      BitSet_t NewFromStrValue(STRING n, BitCapacity_t bit_capacity = 0);
 *      BitSet_t NewFromBitPositions(DATASET(BitPositionsRec) positions, BitCapacity_t bit_capacity = 0);
 *
 *      // Manipulating single bits
 *      BitSet_t SetAllBits(CONST BitSet_t b, BOOLEAN on);
 *      BitSet_t ResetBits(CONST BitSet_t b);
 *      BitSet_t SetBit(CONST BitSet_t b, BitPosition_t position, BOOLEAN on = TRUE);
 *      BitSet_t FlipBit(CONST BitSet_t b, BitPosition_t position);
 *
 *      // Bit shifting
 *      BitSet_t ShiftLeft(CONST BitSet_t b, BitCapacity_t num_bits = 1);
 *      BitSet_t ShiftRight(CONST BitSet_t b, BitCapacity_t num_bits = 1);
 *
 *      // Bitwise operations
 *      BitSet_t BitwiseAND(CONST BitSet_t b1, CONST BitSet_t b2);
 *      BitSet_t BitwiseOR(CONST BitSet_t b1, CONST BitSet_t b2);
 *      BitSet_t BitwiseXOR(CONST BitSet_t b1, CONST BitSet_t b2);
 *      BitSet_t BitwiseNOT(CONST BitSet_t b);
 *      BitSet_t BitwiseDIFF(CONST BitSet_t b1, CONST BitSet_t b2);
 *
 *      // Testing bits, individually and as a group
 *      BOOLEAN TestBit(CONST BitSet_t b, BitPosition_t position);
 *      BOOLEAN TestBits(CONST BitSet_t b1, CONST BitSet_t b2);
 *      BOOLEAN TestAnyBitsSet(CONST BitSet_t b);
 *      BOOLEAN TestNoBitsSet(CONST BitSet_t b);
 *      BOOLEAN TestAllBitsSet(CONST BitSet_t b);
 *      BOOLEAN TestBitSetsEqual(CONST BitSet_t b1, CONST BitSet_t b2);
 *
 *      // Inspection
 *      BitCapacity_t CountBitsSet(CONST BitSet_t b);
 *      DATASET(BitPositionsRec) BitsSetPositions(CONST BitSet_t b);
 *
 * Self tests are available.  To execute them, submit a job that contains
 * the following line:
 *
 *      BitSet._Tests.TestAll;
 *
 * All tests pass if the workunit completes successfully (there is no output).
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */

EXPORT BitSet := MODULE, FORWARD

    // Typedefs
    EXPORT BitSet_t := DATA;
    EXPORT Footprint_t := UNSIGNED4;
    EXPORT BitCapacity_t := UNSIGNED6;
    EXPORT BitPosition_t := UNSIGNED6;

    // Record defining bit positions
    EXPORT BitPositionsRec := RECORD
        BitPosition_t   bitPos;
    END;

    // Maximum number of bytes a single bitset can consume
    EXPORT MAX_FOOTPRINT := (Footprint_t)-1;

    // The maximum number of bits that can be referenced within one bitset
    EXPORT MAX_BIT_CAPACITY := MAX_FOOTPRINT * 8;

    // The highest-numbered bit position that can be referenced
    EXPORT HIGHEST_BIT_POSITION := MAX_BIT_CAPACITY - 1;

    // The lowest-numbered bit position that can be referenced
    EXPORT LOWEST_BIT_POSITION := 0;

    //--------------------------------------------------------------------------

    /**
     * Return the amount of memory used by a bitset.
     *
     * @param   b           A bitset; REQUIRED
     *
     * @return  A non-negative integer representing the number of bytes
     *          used by the given bitset
     *
     * @see     Capacity
     */
    EXPORT Footprint_t Footprint(CONST BitSet_t b) := (Footprint_t)LENGTH(b);

    /**
     * Return the maximum number of bits that can be referenced within a
     * bitset.  This number may be up to seven bits higher than the number of
     * bits originally requested due to memory allocation.
     *
     * @param   b           A bitset; REQUIRED
     *
     * @return  A non-negative integer representing the number of bits that
     *          can be referenced by the given bitset
     *
     * @see     Footprint
     */
    EXPORT BitCapacity_t Capacity(CONST BitSet_t b) := (BitCapacity_t)(Footprint(b) * 8);

    /**
     * Return a hexadecimal representation of a bitset as a string.  Basically,
     * every byte used by the bitset is returned as its hexadecimal number and
     * all such numbers are concatenated.
     *
     * @param   b           A bitset; REQUIRED
     *
     * @return  A new STRING containing the hexadecimal representation of the
     *          given bitset.  The returned value will consume twice the
     *          RAM of the bitset, as defined by Footprint(b), so care should
     *          taken when calling this function with extremely large bitsets.
     *
     * @see     AsBinaryString
     * @see     AsUnsigned
     */
    EXPORT STRING AsHexString(CONST BitSet_t b) := EMBED(C++)
        #option pure;

        __lenResult = lenB * 2;
        __result = static_cast<char*>(rtlMalloc(__lenResult));

        char*           outPtr = __result;
        const byte*     inData = static_cast<const byte*>(b);
        const char      hexchar[] = "0123456789ABCDEF";

        for (__int64 x = lenB - 1; x >= 0; x--)
        {
            *outPtr++ = hexchar[inData[x] >> 4];
            *outPtr++ = hexchar[inData[x] & 0x0F];
        }
    ENDEMBED;

    /**
     * Return a binary representation of a bitset as a string of ones and
     * zeros.  Note that the result's length will always be a multiple of
     * eight, rounded up from the number of bits requested for the bitset if
     * necessary.
     *
     * @param   b           A bitset; REQUIRED
     *
     * @return  A new STRING containing the binary representation of the
     *          given bitset.  The returned value will consume eight times the
     *          RAM of the bitset, as defined by Footprint(b), so care should
     *          taken when calling this function with extremely large bitsets.
     *
     * @see     AsHexString
     * @see     AsUnsigned
     */
    EXPORT STRING AsBinaryString(CONST BitSet_t b) := EMBED(C++)
        #option pure;

        __lenResult = lenB * 8;
        __result = static_cast<char*>(rtlMalloc(__lenResult));

        char*   outPtr = __result;

        for (uint32_t x = lenB; x > 0; x--)
        {
            const byte  sourceByte = static_cast<const byte*>(b)[x - 1];

            for (uint32_t position = 8; position > 0; position--)
            {
                const byte  testValue = 1 << (position - 1);

                *outPtr++ = ((sourceByte & testValue) == testValue ? '1' : '0');
            }
        }
    ENDEMBED;

    /**
     * Return the unsigned integer representation of the bitset.  Note that
     * only the first 64 bits of a bitset can be accurately represented this
     * way; any bits beyond the first 64 will be ignored.
     *
     * @param   b           A bitset; REQUIRED
     *
     * @return  An UNSIGNED8 value containing the integer representation of the
     *          given bitset.  Only the first 64 bits of the bitset are used
     *          to build the returned value.
     *
     * @see     AsHexString
     * @see     AsBinaryString
     */
    EXPORT LITTLE_ENDIAN UNSIGNED8 AsUnsigned(CONST BitSet_t b) := EMBED(C++)
        #option pure;

        unsigned __int64    result = 0;
        const uint32_t      numBytesToCopy = (lenB < 8 ? lenB : 8);

        memcpy(&result, b, numBytesToCopy);

        return result;
    ENDEMBED;

    /**
     * Create a new bitset.
     *
     * @param   bit_capacity    The maximum number of bits needed in the new
     *                          bitset; REQUIRED
     *
     * @return  A new BitSet_t value that can track at least the number of bits
     *          cited in the argument.  The actual number of bits within the
     *          bitset may be slightly higher due to the use of bytes to pack
     *          the bits.  All bits within the new bitset will be set to zero.
     *
     * @see     NewFromIntValue
     * @see     NewFromStrValue
     * @see     NewFromBitPositions
     */
    EXPORT BitSet_t New(BitCapacity_t bit_capacity) := FUNCTION
        BitSet_t _New(BitCapacity_t _bit_capacity, BitCapacity_t _max_capacity = MAX_BIT_CAPACITY) := EMBED(C++)
            #option pure;

            const unsigned __int64  bitsRequested = (_bit_capacity < _max_capacity ? _bit_capacity : _max_capacity);
            const uint32_t          bytesNeeded = bitsRequested / 8 + (bitsRequested % 8 != 0 ? 1 : 0);

            // Create empty result bitset
            __lenResult = bytesNeeded;
            __result = rtlMalloc(__lenResult);
            memset(__result, 0, __lenResult);
        ENDEMBED;

        RETURN _New(bit_capacity);
    END;

    /**
     * Create a new bitset initialized with an integer value.  The optional
     * <bit_capacity> argument provides control over how many bits are actually
     * allocated in the bitset.
     *
     * @param   n               The integer value containing the bits that will
     *                          be copied into the new bitset; REQUIRED
     * @param   bit_capacity    The maximum number of bits needed in the new
     *                          bitset; OPTIONAL, defaults to 64
     *
     * @return  A new BitSet_t value preinitialized with the bits taken from
     *          the <n> argument.  If <bit_capacity> is smaller the number of
     *          bits needed to represent <n> then only first few bytes of <n>
     *          will be used to seed the new bitset.
     *
     * @see     New
     * @see     NewFromStrValue
     * @see     NewFromBitPositions
     */
    EXPORT BitSet_t NewFromIntValue(LITTLE_ENDIAN UNSIGNED8 n, BitCapacity_t bit_capacity = 64) := EMBED(C++)
        #option pure;

        const uint32_t  bytesNeeded = bit_capacity / 8 + (bit_capacity % 8 != 0 ? 1 : 0);
        const uint32_t  numBytesToCopy = (bytesNeeded < sizeof(n) ? bytesNeeded : sizeof(n));

        // Create empty result bitset
        __lenResult = bytesNeeded;
        __result = rtlMalloc(__lenResult);
        memset(__result, 0, __lenResult);

        // Little endian integers have the same binary pattern that we are
        // using, so a simple byte-wise copy is sufficient
        memcpy(__result, &n, numBytesToCopy);
    ENDEMBED;

    /**
     * Create a new bitset initialized with a binary string value.  The optional
     * <bit_capacity> argument provides control over how many bits are actually
     * allocated in the bitset.
     *
     * @param   s               A STRING containing only ones and zeros; REQUIRED
     * @param   bit_capacity    The minimum number of bits needed in the new
     *                          bitset; use zero to indicate the number of bits
     *                          should be derived from the length of <s>;
     *                          OPTIONAL, defaults to zero
     *
     * @return  A new BitSet_t value preinitialized with the characters read
     *          from the <s> argument.  If <bit_capacity> is smaller than the
     *          number of characters in <s> then <bit_capacity> will be ignored.
     *
     * @see     New
     * @see     NewFromIntValue
     * @see     NewFromBitPositions
     */
    EXPORT BitSet_t NewFromStrValue(STRING s, BitCapacity_t bit_capacity = 0) := FUNCTION
        BitSet_t _NewFromStrValue(STRING _s, BitCapacity_t _bit_capacity, BitCapacity_t _max_capacity = MAX_BIT_CAPACITY) := EMBED(C++)
            #option pure;

            const unsigned __int64  bitsRequested = (len_s > _bit_capacity ? len_s : _bit_capacity);
            const unsigned __int64  actualBitCount = (bitsRequested < _max_capacity ? bitsRequested : _max_capacity);
            const uint32_t          bytesToAllocate = actualBitCount / 8 + (actualBitCount % 8 != 0 ? 1 : 0);

            // Create empty result bitset
            __lenResult = bytesToAllocate;
            __result = rtlMalloc(__lenResult);
            memset(__result, 0, __lenResult);

            for (uint32_t resultBytePos = 0; resultBytePos < bytesToAllocate && resultBytePos * 8 < len_s; resultBytePos++)
            {
                __int64 incomingCharOffset = static_cast<__int64>(len_s) - static_cast<__int64>((resultBytePos + 1) * 8);

                for (int x = 7; x >= 0; x--)
                {
                    if (incomingCharOffset >= 0)
                    {
                        static_cast<byte*>(__result)[resultBytePos] |= ((_s[incomingCharOffset] == '0' ? 0 : 1) << x);
                    }
                    ++incomingCharOffset;
                }
            }
        ENDEMBED;

        RETURN _NewFromStrValue(s, bit_capacity);
    END;

    /**
     * Create a new bitset initialized from a list of bit positions.  The
     * <bit_capacity> argument provides control over how many bits are actually
     * allocated in the bitset.
     *
     * @param   positions       A DATASET(BitPositionsRec) containing the
     *                          zero-based bit positions to set in the
     *                          new bitset; REQUIRED
     * @param   bit_capacity    The minimum number of bits needed in the new
     *                          bitset; use zero to indicate the number of bits
     *                          should be derived from the highest bit position
     *                          found within <positions>; OPTIONAL,
     *                          defaults to zero
     *
     * @return  A new BitSet_t value with bits set from the positions cited
     *          with the <positions> argument.  If <bit_capacity> is smaller than
     *          highest position referenced in <positions> then it will be
     *          ignored.
     *
     * @see     New
     * @see     NewFromIntValue
     * @see     NewFromStrValue
     * @see     BitsSetPositions
     */
    EXPORT BitSet_t NewFromBitPositions(DATASET(BitPositionsRec) positions, BitCapacity_t bit_capacity = 0) := FUNCTION
        BitSet_t _NewFromBitPositions(DATASET(BitPositionsRec) _positions, BitCapacity_t _bit_capacity, BitCapacity_t _max_capacity = MAX_BIT_CAPACITY, UNSIGNED1 _element_size = SIZEOF(bit_capacity)) := EMBED(C++)
            #option pure;

            const uint32_t          numElements = len_positions / _element_size;
            unsigned __int64        aPosition = 0;
            unsigned __int64        highestPosition = 0;

            // Find the highest referenced position
            for (uint32_t x = 0; x < numElements; x++)
            {
                memcpy(&aPosition, static_cast<const byte*>(_positions) + (x * _element_size), _element_size);

                if (aPosition > highestPosition)
                {
                    highestPosition = aPosition;
                }
            }

            const unsigned __int64  bitsRequested = (highestPosition > _bit_capacity ? highestPosition : _bit_capacity);
            const unsigned __int64  actualBitCount = (bitsRequested < _max_capacity ? bitsRequested : _max_capacity);
            const uint32_t          bytesToAllocate = actualBitCount / 8 + (actualBitCount % 8 != 0 ? 1 : 0);

            // Create empty result bitset
            __lenResult = bytesToAllocate;
            __result = rtlMalloc(__lenResult);
            memset(__result, 0, __lenResult);

            for (uint32_t x = 0; x < numElements; x++)
            {
                memcpy(&aPosition, static_cast<const byte*>(_positions) + (x * _element_size), _element_size);

                uint32_t    bytePos = aPosition / 8;
                uint32_t    bitPos = aPosition % 8;
                byte        newValue = 1 << bitPos;

                static_cast<byte*>(__result)[bytePos] |= newValue;
            }
        ENDEMBED;

        RETURN _NewFromBitPositions(positions, bit_capacity);
    END;


    /**
     * Makes sure the given bitset can hold <bit_capacity> bits.  A new bitset
     * is always returned, even if the given bitset is large enough.
     *
     * @param   b               A bitset; REQUIRED
     * @param   bit_capacity    The minimum number of bits needed in the
     *                          bitset; REQUIRED
     *
     * @return  A new BitSet_t value of at least size <bit_capacity>, with the
     *          bits from <b> copied over.
     */
    EXPORT BitSet_t ReserveCapacity(CONST BitSet_t b, BitCapacity_t bit_capacity) := FUNCTION
        BitSet_t _ReserveCapacity(CONST BitSet_t _b, BitCapacity_t _bit_capacity, BitCapacity_t _max_capacity = MAX_BIT_CAPACITY) := EMBED(C++)
            #option pure;

            const unsigned __int64  bitsRequested = (_bit_capacity < _max_capacity ? _bit_capacity : _max_capacity);
            const uint32_t          bytesNeeded = bitsRequested / 8 + (bitsRequested % 8 != 0 ? 1 : 0);
            const uint32_t          bytesToAllocate = (bytesNeeded > len_b ? bytesNeeded : len_b);

            __lenResult = bytesToAllocate;
            __result = rtlMalloc(__lenResult);
            memcpy(__result, _b, len_b);
            if (__lenResult > len_b)
            {
                memset(&(static_cast<byte*>(__result)[len_b]), 0, __lenResult - len_b);
            }
        ENDEMBED;

        RETURN _ReserveCapacity(b, bit_capacity);
    END;

    /**
     * Set every bit in a bitset to zero or one.
     *
     * @param   b           A bitset; REQUIRED
     * @param   on          If TRUE, set every bit to one; if FALSE, set every
     *                      bit to zero; REQUIRED
     *
     * @return  A new BitSet_t, of the same size as <b>, with all bits set
     *          as indicated by the <on> argument.
     *
     * @see     ResetBits
     */
    EXPORT BitSet_t SetAllBits(CONST BitSet_t b, BOOLEAN on) := EMBED(C++)
        #option pure;

        // Create empty result bitset
        __lenResult = lenB;
        __result = rtlMalloc(__lenResult);

        // Determine byte value to copy everywhere
        const byte  byteValue = (on ? 255 : 0);

        // Copy byte value to result
        memset(__result, byteValue, __lenResult);
    ENDEMBED;

    /**
     * Set every bit in a bitset to zero.
     *
     * @param   b           A bitset; REQUIRED
     *
     * @return  A new BitSet_t, of the same size as <b>, with all bits set
     *          to zero.
     *
     * @see     SetAllBits
     */
    EXPORT BitSet_t ResetBits(CONST BitSet_t b) := SetAllBits(b, FALSE);

    /**
     * Set a bit in a bitset to either zero or one.
     *
     * @param   b           A bitset; REQUIRED
     * @param   position    The zero-based position of the bit to set; REQUIRED
     * @param   on          If TRUE, set the bit to one; if FALSE, set the
     *                      bit to zero; OPTIONAL, defaults to TRUE
     *
     * @return  A new BitSet_t containing the bits from <b> and with bit
     *          <position> set as indicated by the <on> argument.  If <position>
     *          is greater than the number of bits referenced by the bitset,
     *          an unchanged copy of <b> is returned.
     */
    EXPORT BitSet_t SetBit(CONST BitSet_t b, BitPosition_t position, BOOLEAN on = TRUE) := FUNCTION
        BitSet_t _SetBit(CONST BitSet_t b, BitPosition_t position, BOOLEAN on, BitPosition_t _max_position = HIGHEST_BIT_POSITION) := EMBED(C++)
            #option pure;

            // Create a copy of our bitset
            __lenResult = lenB;
            __result = rtlMalloc(__lenResult);
            memcpy(__result, b, lenB);

            const unsigned __int64  requestedPosition = (position < _max_position ? position : _max_position);
            const uint32_t          bytePos = requestedPosition / 8;

            if (bytePos < lenB)
            {
                const byte  bitValue = 1 << (requestedPosition % 8);

                if (on)
                {
                    static_cast<byte*>(__result)[bytePos] |= bitValue;
                }
                else
                {
                    static_cast<byte*>(__result)[bytePos] &= ~bitValue;
                }
            }
        ENDEMBED;

        RETURN _SetBit(b, position, on);
    END;

    /**
     * Flip a single bit from one to zero, or zero to one, depending on its
     * original value.
     *
     * @param   b           A bitset; REQUIRED
     * @param   position    The zero-based position of the bit to flip; REQUIRED
     *
     * @return  A new BitSet_t containing the bits from <b> and with bit
     *          <position> flipped from zero to one or one to zero.  If
     *          <position> is greater than the number of bits referenced by the
     *          bitset, an unchanged copy of <b> is returned.
     */
    EXPORT BitSet_t FlipBit(CONST BitSet_t b, BitPosition_t position) := EMBED(C++)
        #option pure;

        // Create a copy of our bitset
        __lenResult = lenB;
        __result = rtlMalloc(__lenResult);
        memcpy(__result, b, lenB);

        const uint32_t  bytePos = position / 8;

        if (bytePos < lenB)
        {
            const byte  bitValue = 1 << (position % 8);

            static_cast<byte*>(__result)[bytePos] ^= bitValue;
        }
    ENDEMBED;

    /**
     * Return a boolean indicating if a single bit within a bitset is one or
     * not.  This is the equivalent of this test:
     *
     *      (b >> position) & 1 == 1
     *
     * @param   b           A bitset; REQUIRED
     * @param   position    The zero-based position of the bit to test; REQUIRED
     *
     * @return  TRUE if the indicated bit's value is one, FALSE otherwise.  If
     *          <position> is greater than the number of bits referenced by the
     *          bitset, FALSE is returned.
     *
     * @see     TestBits
     * @see     TestAnyBitsSet
     * @see     TestNoBitsSet
     * @see     TestAllBitsSet
     * @see     TestBitSetsEqual
     */
    EXPORT BOOLEAN TestBit(CONST BitSet_t b, BitPosition_t position) := EMBED(C++)
        #option pure;

        bool            isSet = false;
        const uint32_t  bytePos = position / 8;

        if (bytePos < lenB)
        {
            const byte  testValue = 1 << (position % 8);

            isSet = ((static_cast<const byte*>(b)[bytePos] & testValue) == testValue);
        }

        return isSet;
    ENDEMBED;

    /**
     * Return a boolean indicating if every set bit in one bitset is also set
     * in another bitset.  This is the equivalent of this test:
     *
     *      (b1 & b2) == b2
     *
     * @param   b1          A bitset that you want to test against; REQUIRED
     * @param   b2          A bitset containing the bits to test; REQUIRED
     *
     * @return  TRUE if every set bit in <b2> is also set in <b1>, FALSE
     *          otherwise.
     *
     * @see     TestBit
     * @see     TestAnyBitsSet
     * @see     TestNoBitsSet
     * @see     TestAllBitsSet
     * @see     TestBitSetsEqual
     */
    EXPORT BOOLEAN TestBits(CONST BitSet_t b1, CONST BitSet_t b2) := EMBED(C++)
        #option pure;

        for (uint32_t x = 0; x < lenB2; x++)
        {
            if ((x < lenB1 && ((static_cast<const byte*>(b1)[x] & static_cast<const byte*>(b2)[x]) != static_cast<const byte*>(b2)[x]))
                || (x >= lenB1 && (static_cast<const byte*>(b2)[x]) != 0))
            {
                return false;
            }
        }

        return true;
    ENDEMBED;

    /**
     * Return a boolean indicating if any bit in a bitset is set to one.
     *
     * @param   b           A bitset; REQUIRED
     *
     * @return  TRUE if any bit in <b> is set to one, FALSE otherwise.
     *
     * @see     TestBit
     * @see     TestBits
     * @see     TestNoBitsSet
     * @see     TestAllBitsSet
     * @see     TestBitSetsEqual
     */
    EXPORT BOOLEAN TestAnyBitsSet(CONST BitSet_t b) := EMBED(C++)
        #option pure;

        for (uint32_t bytePos = 0; bytePos < lenB; bytePos++)
        {
            const byte  val = static_cast<const byte*>(b)[bytePos];

            if (val > 0)
            {
                return true;
            }
        }

        return false;
    ENDEMBED;

    /**
     * Return a boolean indicating if no bit in a bitset is set to one.
     *
     * @param   b           A bitset; REQUIRED
     *
     * @return  TRUE if no bit in <b> is set to one, FALSE otherwise.
     *
     * @see     TestBit
     * @see     TestBits
     * @see     TestAnyBitsSet
     * @see     TestAllBitsSet
     * @see     TestBitSetsEqual
     */
    EXPORT BOOLEAN TestNoBitsSet(CONST BitSet_t b) := EMBED(C++)
        #option pure;

        for (uint32_t bytePos = 0; bytePos < lenB; bytePos++)
        {
            const byte  val = static_cast<const byte*>(b)[bytePos];

            if (val > 0)
            {
                return false;
            }
        }

        return true;
    ENDEMBED;

    /**
     * Return a boolean indicating if every bit in a bitset is set to one.
     *
     * @param   b           A bitset; REQUIRED
     *
     * @return  TRUE if every bit in <b> is set to one, FALSE otherwise.
     *
     * @see     TestBit
     * @see     TestBits
     * @see     TestAnyBitsSet
     * @see     TestNoBitsSet
     * @see     TestBitSetsEqual
     */
    EXPORT BOOLEAN TestAllBitsSet(CONST BitSet_t b) := EMBED(C++)
        #option pure;

        for (uint32_t bytePos = 0; bytePos < lenB; bytePos++)
        {
            const byte  val = static_cast<const byte*>(b)[bytePos];

            if (val != 255)
            {
                return false;
            }
        }

        return true;
    ENDEMBED;

    /**
     * Return a boolean indicating if two bitsets are completely identical.
     *
     * @param   b1          A bitset; REQUIRED
     * @param   b2          Another bitset; REQUIRED
     *
     * @return  TRUE <b1> and <b2> have both the same size and combination of
     *          set and unset bits, FALSE otherwise.
     *
     * @see     TestBit
     * @see     TestBits
     */
    EXPORT BOOLEAN TestBitSetsEqual(CONST BitSet_t b1, CONST BitSet_t b2) := EMBED(C++)
        #option pure;

        return lenB1 == lenB2 && memcmp(b1, b2, lenB1) == 0;
    ENDEMBED;

    /**
     * Count the number of set bits within a bitset.
     *
     * @param   b           A bitset; REQUIRED
     *
     * @return  A non-negative integer representing the number of set bits
     *          within <b>.
     */
    EXPORT BitCapacity_t CountBitsSet(CONST BitSet_t b) := EMBED(C++)
        #option pure;

        unsigned __int64    numBitsSet = 0;

        for (uint32_t bytePos = 0; bytePos < lenB; bytePos++)
        {
            byte    val = static_cast<const byte*>(b)[bytePos];

            while (val > 0)
            {
                if ((val & 1) == 1)
                {
                    ++numBitsSet;
                }
                val >>= 1;
            }
        }

        return numBitsSet;
    ENDEMBED;

    /**
     * Collect the positions of all set bits within a bitset.
     *
     * @param   b           A bitset; REQUIRED
     *
     * @return  A new DATASET(BitPositionsRec) containing the zero-based
     *          positions of all set bits within the bitset.  If no bits are
     *          set then the resulting dataset will be empty.
     *
     * @see     NewFromBitPositions
     */
    EXPORT STREAMED DATASET(BitPositionsRec) BitsSetPositions(CONST BitSet_t b) := EMBED(C++)
        #option pure;

        class StreamDataset : public RtlCInterface, implements IRowStream
        {
            public:

                StreamDataset(IEngineRowAllocator* _resultAllocator, size32_t _dataLength, const void* _dataPtr)
                    : resultAllocator(_resultAllocator), dataLength(_dataLength), dataPtr(static_cast<const byte*>(_dataPtr))
                {
                    isStopped = false;
                    currentByte = 0;
                    currentBit = 0;
                }

                RTLIMPLEMENT_IINTERFACE

                virtual const void* nextRow()
                {
                    if (isStopped)
                    {
                        return NULL;
                    }

                    // Find next set bit
                    while (currentByte < dataLength)
                    {
                        while (currentBit < 8)
                        {
                            byte    testValue = 1 << currentBit;

                            if ((dataPtr[currentByte] & testValue) == testValue)
                            {
                                RtlDynamicRowBuilder    rowBuilder(resultAllocator);
                                unsigned int            len = 6;
                                byte*                   row = rowBuilder.ensureCapacity(len, NULL);
                                unsigned __int64        position = currentByte * 8 + currentBit;

                                // Copy the position to the output record
                                memcpy(row, &position, len);

                                // Increment bit position for next call
                                ++currentBit;

                                return rowBuilder.finalizeRowClear(len);
                            }
                            else
                            {
                                ++currentBit;
                            }
                        }

                        currentBit = 0;
                        ++currentByte;
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

                size32_t                    dataLength;
                const byte*                 dataPtr;
                bool                        isStopped;
                size32_t                    currentByte;
                size32_t                    currentBit;
        };

        #body

        return new StreamDataset(_resultAllocator, lenB, b);
    ENDEMBED;

    /**
     * Shift all bits in a bitset left a given number of positions.  This is
     * the equivalent of:
     *
     *      b << num_bits
     *
     * @param   b           A bitset; REQUIRED
     * @param   num_bits    The number of positions to shift all bits to the
     *                      left; OPTIONAL, defaults to one.
     *
     * @return  A new BitSet_t bitset with the contents of <b> left-shifted by
     *          the number of positions indicated by <num_bits>.  The bit
     *          positions that have been vacated by the shift operation are
     *          zero-filled.  Bits that are shifted off the end are discarded.
     */
    EXPORT BitSet_t ShiftLeft(CONST BitSet_t b, BitCapacity_t num_bits = 1) := EMBED(C++)
        #option pure;

        // Create empty result bitset
        __lenResult = lenB;
        __result = rtlMalloc(__lenResult);

        if (num_bits > 0)
        {
            const uint32_t  shift = num_bits / 8;
            const uint32_t  offset = num_bits % 8;

            memset(__result, 0, __lenResult);

            if (shift < lenB)
            {
                if (offset == 0)
                {
                    for (size_t x = lenB - 1; x >= shift; x--)
                    {
                        static_cast<byte*>(__result)[x] = static_cast<const byte*>(b)[x - shift];
                    }
                }
                else
                {
                    const size_t    subOffset = (8 - offset);

                    for (size_t x = lenB - 1; x > shift; x--)
                    {
                        static_cast<byte*>(__result)[x] = ((static_cast<const byte*>(b)[x - shift] << offset) | (static_cast<const byte*>(b)[x - shift - 1] >> subOffset));
                    }

                    static_cast<byte*>(__result)[shift] = static_cast<const byte*>(b)[0] << offset;
                }
            }
        }
        else
        {
            // No shifting, so just copy
            memcpy(__result, b, __lenResult);
        }
    ENDEMBED;

    /**
     * Shift all bits in a bitset right a given number of positions.  This is
     * the equivalent of:
     *
     *      b >> num_bits
     *
     * @param   b           A bitset; REQUIRED
     * @param   num_bits    The number of positions to shift all bits to the
     *                      right; OPTIONAL, defaults to one.
     *
     * @return  A new BitSet_t bitset with the contents of <b> right-shifted by
     *          the number of positions indicated by <num_bits>.  The bit
     *          positions that have been vacated by the shift operation are
     *          zero-filled.  Bits that are shifted off the end are discarded.
     */
    EXPORT BitSet_t ShiftRight(CONST BitSet_t b, BitCapacity_t num_bits) := EMBED(C++)
        #option pure;

        // Create empty result bitset
        __lenResult = lenB;
        __result = rtlMalloc(__lenResult);

        if (num_bits > 0)
        {
            const uint32_t  shift = num_bits / 8;
            const uint32_t  offset = num_bits % 8;
            const size_t    limit = lenB - shift - 1;

            memset(__result, 0, __lenResult);

            if (shift < lenB)
            {
                if (offset == 0)
                {
                    for (size_t x = 0; x <= limit; x++)
                    {
                        static_cast<byte*>(__result)[x] = static_cast<const byte*>(b)[x + shift];
                    }
                }
                else
                {
                    const size_t    subOffset = (8 - offset);

                    for (size_t x = 0; x < limit; x++)
                    {
                        static_cast<byte*>(__result)[x] = ((static_cast<const byte*>(b)[x + shift] >> offset) | (static_cast<const byte*>(b)[x + shift + 1] << subOffset));
                    }

                    static_cast<byte*>(__result)[limit] = static_cast<const byte*>(b)[lenB - 1] >> offset;
                }
            }
        }
        else
        {
            // No shifting, so just copy
            memcpy(__result, b, __lenResult);
        }
    ENDEMBED;

    /**
     * Perform a bitwise AND operation on two bitsets.  This is the equivalent
     * of this function:
     *
     *      b1 & b2
     *
     * @param   b1          A bitset; REQUIRED
     * @param   b2          A bitset; REQUIRED
     *
     * @return  A new BitSet_t containing the result of a bitwise AND operation
     *          between <b1> and <b2>.  The new bitset will be as large as the
     *          larger of <b1> and <b2>.
     *
     * @see     BitwiseOR
     * @see     BitwiseXOR
     * @see     BitwiseNOT
     */
    EXPORT BitSet_t BitwiseAND(CONST BitSet_t b1, CONST BitSet_t b2) := EMBED(C++)
        #option pure;

        const bool  b1Receives = (lenB1 >= lenB2);
        uint32_t    largerNumBytes = 0;
        uint32_t    smallerNumBytes = 0;
        const byte* largerPtr = NULL;
        const byte* smallerPtr = NULL;

        if (b1Receives)
        {
            largerNumBytes = lenB1;
            smallerNumBytes = lenB2;
            largerPtr = static_cast<const byte*>(b1);
            smallerPtr = static_cast<const byte*>(b2);
        }
        else
        {
            largerNumBytes = lenB2;
            smallerNumBytes = lenB1;
            largerPtr = static_cast<const byte*>(b2);
            smallerPtr = static_cast<const byte*>(b1);
        }

        __lenResult = largerNumBytes;
        __result = rtlMalloc(__lenResult);

        byte*   outPtr = static_cast<byte*>(__result);

        for (uint32_t x = 0; x < largerNumBytes; x++)
        {
            if (x < smallerNumBytes)
            {
                *outPtr++ = largerPtr[x] & smallerPtr[x];
            }
            else
            {
                *outPtr++ = 0;
            }
        }
    ENDEMBED;

    /**
     * Perform a bitwise OR operation on two bitsets.  This is the equivalent
     * of this function:
     *
     *      b1 | b2
     *
     * @param   b1          A bitset; REQUIRED
     * @param   b2          A bitset; REQUIRED
     *
     * @return  A new BitSet_t containing the result of a bitwise OR operation
     *          between <b1> and <b2>.  The new bitset will be as large as the
     *          larger of <b1> and <b2>.
     *
     * @see     BitwiseAND
     * @see     BitwiseXOR
     * @see     BitwiseNOT
     */
    EXPORT BitSet_t BitwiseOR(CONST BitSet_t b1, CONST BitSet_t b2) := EMBED(C++)
        #option pure;

        const bool  b1Receives = (lenB1 >= lenB2);
        uint32_t    largerNumBytes = 0;
        uint32_t    smallerNumBytes = 0;
        const byte* largerPtr = NULL;
        const byte* smallerPtr = NULL;

        if (b1Receives)
        {
            largerNumBytes = lenB1;
            smallerNumBytes = lenB2;
            largerPtr = static_cast<const byte*>(b1);
            smallerPtr = static_cast<const byte*>(b2);
        }
        else
        {
            largerNumBytes = lenB2;
            smallerNumBytes = lenB1;
            largerPtr = static_cast<const byte*>(b2);
            smallerPtr = static_cast<const byte*>(b1);
        }

        __lenResult = largerNumBytes;
        __result = rtlMalloc(__lenResult);

        byte*   outPtr = static_cast<byte*>(__result);

        for (uint32_t x = 0; x < largerNumBytes; x++)
        {
            if (x < smallerNumBytes)
            {
                *outPtr++ = largerPtr[x] | smallerPtr[x];
            }
            else
            {
                *outPtr++ = largerPtr[x];
            }
        }
    ENDEMBED;

    /**
     * Perform a bitwise XOR operation on two bitsets.  This is the equivalent
     * of this function:
     *
     *      b1 ^ b2
     *
     * @param   b1          A bitset; REQUIRED
     * @param   b2          A bitset; REQUIRED
     *
     * @return  A new BitSet_t containing the result of a bitwise XOR operation
     *          between <b1> and <b2>.  The new bitset will be as large as the
     *          larger of <b1> and <b2>.
     *
     * @see     BitwiseAND
     * @see     BitwiseOR
     * @see     BitwiseNOT
     */
    EXPORT BitSet_t BitwiseXOR(CONST BitSet_t b1, CONST BitSet_t b2) := EMBED(C++)
        #option pure;

        const bool  b1Receives = (lenB1 >= lenB2);
        uint32_t    largerNumBytes = 0;
        uint32_t    smallerNumBytes = 0;
        const byte* largerPtr = NULL;
        const byte* smallerPtr = NULL;

        if (b1Receives)
        {
            largerNumBytes = lenB1;
            smallerNumBytes = lenB2;
            largerPtr = static_cast<const byte*>(b1);
            smallerPtr = static_cast<const byte*>(b2);
        }
        else
        {
            largerNumBytes = lenB2;
            smallerNumBytes = lenB1;
            largerPtr = static_cast<const byte*>(b2);
            smallerPtr = static_cast<const byte*>(b1);
        }

        __lenResult = largerNumBytes;
        __result = rtlMalloc(__lenResult);

        byte*   outPtr = static_cast<byte*>(__result);

        for (uint32_t x = 0; x < largerNumBytes; x++)
        {
            if (x < smallerNumBytes)
            {
                *outPtr++ = largerPtr[x] ^ smallerPtr[x];
            }
            else
            {
                *outPtr++ = largerPtr[x]; // a ^ 0 == a
            }
        }
    ENDEMBED;

    /**
     * Perform a bitwise NOT operation on a bitset.  This is the equivalent
     * of this function:
     *
     *      ~b
     *
     * @param   b           A bitset; REQUIRED
     *
     * @return  A new BitSet_t containing the result of a bitwise NOT operation
     *          on <b> and <b2>.  The new bitset will be the same size as <b>.
     *
     * @see     BitwiseAND
     * @see     BitwiseOR
     * @see     BitwiseXOR
     */
    EXPORT BitSet_t BitwiseNOT(CONST BitSet_t b) := EMBED(C++)
        #option pure;

        __lenResult = lenB;
        __result = rtlMalloc(__lenResult);

        byte*   outPtr = static_cast<byte*>(__result);

        for (uint32_t x = 0; x < lenB; x++)
        {
            *outPtr++ = ~(static_cast<const byte*>(b)[x]);
        }
    ENDEMBED;

    /**
     * Perform a bitwise difference operation on two bitsets.  The resulting
     * bitset will contain set bits that correspond to bits that are set in
     * <b1> but not set in <b2>.  This is the equivalent of this function:
     *
     *      b1 & ~b2
     *
     * Example:  1101 & ~1011 = 0100
     *
     * @param   b1          A bitset; REQUIRED
     * @param   b2          A bitset; REQUIRED
     *
     * @return  A new BitSet_t containing the result of a bitwise difference
     *          operation between <b1> and <b2>.  The result will be as large
     *          as the larger of <b1> and <b2>.
     *
     * @see     BitwiseAND
     * @see     BitwiseOR
     * @see     BitwiseNOT
     */
    EXPORT BitSet_t BitwiseDIFF(CONST BitSet_t b1, CONST BitSet_t b2) := BitwiseAND(b1, BitwiseNOT(b2));

    EXPORT _Tests := MODULE

        SHARED smallBitset := New(23);
        SHARED grownSmallBitSet := ReserveCapacity(smallBitset, 39);
        SHARED intBitset := NewFromIntValue(5, 4);
        SHARED strBitset := NewFromStrValue('0101', 4);
        SHARED bitPositions := DATASET([0, 2], BitPositionsRec);
        SHARED bitPosBitset := NewFromBitPositions(bitPositions, 4);
        SHARED allIntBitsSetOn := SetAllBits(intBitset, TRUE);
        SHARED allIntBitsSetOff := SetAllBits(intBitset, FALSE);
        SHARED intBitsetSet4 := SetBit(intBitset, 4, TRUE);
        SHARED intBitsetCleared4 := SetBit(intBitsetSet4, 4, FALSE);
        SHARED intFlipped1 := FlipBit(intBitset, 4);
        SHARED intFlipped2 := FlipBit(intFlipped1, 4);
        SHARED intReserved := ReserveCapacity(intBitset, 17);

        SHARED AreBitSetPositionsSame(DATASET(BitPositionsRec) s1, DATASET(BitPositionsRec) s2) := FUNCTION
            sameLength := COUNT(s1) = COUNT(s2);
            sortedS1 := SORT(s1, bitPos);
            sortedS2 := SORT(s2, bitPos);
            sameTest := DATASET
                (
                    COUNT(sortedS1),
                    TRANSFORM
                        (
                            {BOOLEAN isSame},
                            SELF.isSame := sortedS1[COUNTER].bitPos = sortedS2[COUNTER].bitPos
                        )
                );
            allSameDS := ROLLUP
                (
                    sameTest,
                    TRUE,
                    TRANSFORM
                        (
                            RECORDOF(LEFT),
                            SELF.isSame := LEFT.isSame = RIGHT.isSame
                        )
                );

            RETURN sameLength AND allSameDS[1].isSame;
        END;

        EXPORT TestSimple := [
                ASSERT(Capacity(smallBitset) = 24, FAIL);
                ASSERT(Footprint(smallBitset) = 3, FAIL);

                ASSERT(Capacity(grownSmallBitSet) = 40, FAIL);
                ASSERT(Footprint(grownSmallBitSet) = 5, FAIL);

                ASSERT(AsHexString(intBitset) = '05', FAIL);
                ASSERT(AsBinaryString(intBitset) = '00000101', FAIL);
                ASSERT(AsUnsigned(intBitset) = 5, FAIL);

                ASSERT(Capacity(intBitset) = 8, FAIL);
                ASSERT(Footprint(intBitset) = 1, FAIL);
                ASSERT(TestBit(intBitset, 0) = TRUE, FAIL);
                ASSERT(TestBit(intBitset, 1) = FALSE, FAIL);
                ASSERT(TestBit(intBitset, 2) = TRUE, FAIL);
                ASSERT(TestBit(intBitset, 3) = FALSE, FAIL);
                ASSERT(TestBit(intBitset, 4) = FALSE, FAIL);
                ASSERT(TestBit(intBitset, 5) = FALSE, FAIL);
                ASSERT(TestBit(intBitset, 6) = FALSE, FAIL);
                ASSERT(TestBit(intBitset, 7) = FALSE, FAIL);

                ASSERT(Capacity(strBitset) = 8, FAIL);
                ASSERT(Footprint(strBitset) = 1, FAIL);
                ASSERT(TestBit(strBitset, 0) = TRUE, FAIL);
                ASSERT(TestBit(strBitset, 1) = FALSE, FAIL);
                ASSERT(TestBit(strBitset, 2) = TRUE, FAIL);
                ASSERT(TestBit(strBitset, 3) = FALSE, FAIL);
                ASSERT(TestBit(strBitset, 4) = FALSE, FAIL);
                ASSERT(TestBit(strBitset, 5) = FALSE, FAIL);
                ASSERT(TestBit(strBitset, 6) = FALSE, FAIL);
                ASSERT(TestBit(strBitset, 7) = FALSE, FAIL);

                ASSERT(Capacity(bitPosBitset) = 8, FAIL);
                ASSERT(Footprint(bitPosBitset) = 1, FAIL);
                ASSERT(TestBit(bitPosBitset, 0) = TRUE, FAIL);
                ASSERT(TestBit(bitPosBitset, 1) = FALSE, FAIL);
                ASSERT(TestBit(bitPosBitset, 2) = TRUE, FAIL);
                ASSERT(TestBit(bitPosBitset, 3) = FALSE, FAIL);
                ASSERT(TestBit(bitPosBitset, 4) = FALSE, FAIL);
                ASSERT(TestBit(bitPosBitset, 5) = FALSE, FAIL);
                ASSERT(TestBit(bitPosBitset, 6) = FALSE, FAIL);
                ASSERT(TestBit(bitPosBitset, 7) = FALSE, FAIL);

                ASSERT(TestBit(allIntBitsSetOn, 0) = TRUE, FAIL);
                ASSERT(TestBit(allIntBitsSetOn, 1) = TRUE, FAIL);
                ASSERT(TestBit(allIntBitsSetOn, 2) = TRUE, FAIL);
                ASSERT(TestBit(allIntBitsSetOn, 3) = TRUE, FAIL);
                ASSERT(TestBit(allIntBitsSetOn, 4) = TRUE, FAIL);
                ASSERT(TestBit(allIntBitsSetOn, 5) = TRUE, FAIL);
                ASSERT(TestBit(allIntBitsSetOn, 6) = TRUE, FAIL);
                ASSERT(TestBit(allIntBitsSetOn, 7) = TRUE, FAIL);

                ASSERT(TestBit(allIntBitsSetOff, 0) = FALSE, FAIL);
                ASSERT(TestBit(allIntBitsSetOff, 1) = FALSE, FAIL);
                ASSERT(TestBit(allIntBitsSetOff, 2) = FALSE, FAIL);
                ASSERT(TestBit(allIntBitsSetOff, 3) = FALSE, FAIL);
                ASSERT(TestBit(allIntBitsSetOff, 4) = FALSE, FAIL);
                ASSERT(TestBit(allIntBitsSetOff, 5) = FALSE, FAIL);
                ASSERT(TestBit(allIntBitsSetOff, 6) = FALSE, FAIL);
                ASSERT(TestBit(allIntBitsSetOff, 7) = FALSE, FAIL);

                ASSERT(TestBit(intBitsetSet4, 4) = TRUE, FAIL);
                ASSERT(TestBit(intBitsetCleared4, 4) = FALSE, FAIL);

                ASSERT(TestBit(intFlipped1, 4) = TRUE, FAIL);
                ASSERT(TestBit(intFlipped2, 4) = FALSE, FAIL);

                ASSERT(AsHexString(intReserved) = '000005', FAIL);
                ASSERT(AsBinaryString(intReserved) = '000000000000000000000101', FAIL);
                ASSERT(AsUnsigned(intReserved) = 5, FAIL);

                ASSERT(TestBits(intBitset, intReserved) = TRUE, FAIL);
                ASSERT(TestBits(intReserved, intBitset) = TRUE, FAIL);
                ASSERT(TestBits(intBitset, smallBitset) = TRUE, FAIL);
                ASSERT(TestBits(smallBitset, intBitset) = FALSE, FAIL);

                ASSERT(TestAnyBitsSet(intBitset) = TRUE, FAIL);
                ASSERT(TestAnyBitsSet(smallBitset) = FALSE, FAIL);

                ASSERT(TestNoBitsSet(intBitset) = FALSE, FAIL);
                ASSERT(TestNoBitsSet(smallBitset) = TRUE, FAIL);

                ASSERT(TestAllBitsSet(allIntBitsSetOn) = TRUE, FAIL);
                ASSERT(TestAllBitsSet(allIntBitsSetOff) = FALSE, FAIL);

                ASSERT(TestBitSetsEqual(intBitSet, strBitSet) = TRUE, FAIL);

                ASSERT(CountBitsSet(intReserved) = 2, FAIL);

                ASSERT(AreBitSetPositionsSame(BitsSetPositions(intBitset), bitPositions) = TRUE, FAIL);

                ASSERT(TRUE)
            ];

        EXPORT TestAll := [EVALUATE(TestSimple)];

    END;

END;
