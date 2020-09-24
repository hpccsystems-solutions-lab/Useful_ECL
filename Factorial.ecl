/**
 * Simple function to compute the factorial of a non-negative integer.  See
 * https://en.wikipedia.org/wiki/Factorial for more information.
 *
 * @param   n   The non-negative integer to find the factorial of; maximum
 *              allowed value is 65, as any higher number results in a value
 *              that will not fit into an UNSIGNED8
 * 
 * @return  The factorial of argument, or zero if it cannot be computed.
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */
EXPORT UNSIGNED8 Factorial(UNSIGNED1 n) := EMBED(C++)
    #option pure;
    unsigned __int64 result = 0;

    if (n <= 65)
    {
        result = 1;

        for (unsigned int x = 2; x <= n; x++)
        {
            result *= x;
        }
    }
    
    return result;
ENDEMBED;
