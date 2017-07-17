/**
 * Simple per-node key/value string cache with expiration.  The cache is
 * thread-aware.
 *
 * A per-node cache (in other words, a cache that is not used by an entire
 * HPCC cluster engine but used only by one node) can be very useful in some
 * circumstances.  For instance, a Roxie query can locally cache the results
 * of a web service call and thereby prevent any further network access for
 * the duration of the cache for that one node.  Other Roxie nodes would still
 * have to manage their own cache, but that may be acceptable if the cache
 * values do not have to be absolutely in sync or if the cached results change
 * only infrequently.
 *
 * Exported items:
 *
 *  - DEFAULT_EXPIRE_SECONDS
 *  - SetValue()
 *  - GetValue()
 *  - GetOrSetValue()
 *  - DeleteValue()
 *
 * This code requires a c++11 compiler.
 */
EXPORT StringCache := MODULE

    //==========================================================================
    // Internal Declarations
    //==========================================================================

    // Admittedly odd way of instantiating an #OPTION within a module;
    // see usage of this attribute below
    SHARED USE_CPP_11 := #OPTION('compileOptions', '-std=c++11');

    /**
     * INTERNAL
     *
     * Sets a value for a key in the cache.
     *
     * Implementation note:  Everything before the #body notation in this
     * function will be placed outside any function and can be considered
     * global to this module.  The other C++ functions within the module
     * rely on these global declarations.
     *
     * @see     SetValue
     */
    SHARED STRING _SetValue(STRING key, STRING value, UNSIGNED2 expire_seconds) := EMBED(C++ : DISTRIBUTED)
        #include <string>
        #include <map>
        #include <mutex>

        // Struct that contains stored value and expiration time
        struct StringCacheInfo
            {
                std::string     value;
                time_t          expireTime;

                // Basic constructor
                StringCacheInfo()
                {}

                // Initialization constructor
                StringCacheInfo(const std::string& _value, time_t _expireTime)
                    :   value(_value), expireTime(_expireTime)
                {}

                // Copy constructor
                StringCacheInfo(const StringCacheInfo& other)
                    :   value(other.value), expireTime(other.expireTime)
                {}
            };

        typedef std::map<std::string, StringCacheInfo> CacheMap;

        static CacheMap     gStringCacheMap;
        static std::mutex   gStringCacheMutex;

        // RAII class for mutex
        class StringCacheLock
        {
            public:

                StringCacheLock()
                {
                    gStringCacheMutex.lock();
                }

                ~StringCacheLock()
                {
                    gStringCacheMutex.unlock();
                }
        };

        #body
        #option action

        __lenResult = 0;
        __result = NULL;

        if (lenValue > 0)
        {
            {
                StringCacheLock     myLock;

                gStringCacheMap[key] = StringCacheInfo(value, time(NULL) + expire_seconds);
            }

            __lenResult = lenValue;
            __result = reinterpret_cast<char*>(rtlMalloc(__lenResult));
            memcpy(__result, value, __lenResult);
        }
    ENDEMBED;

    /**
     * INTERNAL
     *
     * Returns the value associated with given key.  If the value cannot
     * be found or has expired, an empty string will be returned.  Note that
     * it is not possible to tell the difference between a missing value and
     * an expired value.
     *
     * @see     GetValue
     */
    SHARED STRING _GetValue(STRING key) := EMBED(C++ : DISTRIBUTED)
        #option action

        time_t  timeNow = time(NULL);

        __lenResult = 0;
        __result = NULL;

        StringCacheLock     myLock;
        CacheMap::iterator  foundIter = gStringCacheMap.find(key);

        if (foundIter != gStringCacheMap.end())
        {
            if (foundIter->second.expireTime <= timeNow)
            {
                gStringCacheMap.erase(foundIter);
            }
            else if (foundIter->second.value.length() > 0)
            {
                __lenResult = foundIter->second.value.length();
                __result = reinterpret_cast<char*>(rtlMalloc(__lenResult));
                memcpy(__result, foundIter->second.value.data(), __lenResult);
            }
        }
    ENDEMBED;

    /**
     * INTERNAL
     *
     * Deletes the value associated with given key if it exists.
     *
     * @see     DeleteValue
     */
    SHARED BOOLEAN _DeleteValue(STRING key) := EMBED(C++ : DISTRIBUTED)
        #option action

        StringCacheLock     myLock;
        CacheMap::iterator  foundIter = gStringCacheMap.find(key);

        if (foundIter != gStringCacheMap.end())
        {
            gStringCacheMap.erase(foundIter);
            return true;
        }

        return false;
    ENDEMBED;

    //==========================================================================
    // Exported Declarations
    //==========================================================================

    // The default number of seconds to cache new values
    EXPORT DEFAULT_EXPIRE_SECONDS := 300;

    /**
     * Sets a value for a key in the cache.
     *
     * @param   key             The key to use to retrieve the value later;
     *                          REQUIRED
     * @param   value           The value to cache; REQUIRED
     * @param   expire_seconds  The number of seconds to cache the value;
     *                          OPTIONAL, defaults to DEFAULT_EXPIRE_SECONDS
     *
     * @return  The string value that was set.
     */
    EXPORT STRING SetValue(STRING key, STRING value, UNSIGNED2 expire_seconds = DEFAULT_EXPIRE_SECONDS) := WHEN(_SetValue(key, value, expire_seconds), USE_CPP_11);

    /**
     * Returns the value associated with given key.  If the value cannot
     * be found or has expired, an empty string will be returned.  Note that
     * it is not possible to tell the difference between a missing value and
     * an expired value.
     *
     * Cache expiry is performed during this function and only for the key
     * requested.  Other expired values may continue to exist in the cache
     * afterwards.
     *
     * @param   key             The key to use to retrieve the value; REQUIRED

     * @return  The string value associated with the given key or an empty
     *          string if there is no key/value cached or if the value is
     *          expired.
     */
    EXPORT STRING GetValue(STRING key) := WHEN(_GetValue(key), USE_CPP_11);

    /**
     * Returns the value associated with given key.  If the value cannot
     * be found or has expired and a valid (non-empty) default value is
     * provided, that default value will be inserted into the cache and
     * returned here.
     *
     * Cache expiry is performed during this function and only for the key
     * requested.  Other expired values may continue to exist in the cache
     * afterwards.
     *
     * @param   key             The key to use to retrieve the value; REQUIRED
     * @param   defaultValue    The value to cache and return if there is no
     *                          current value for the given key or if it is
     *                          expired; OPTIONAL, defaults to an empty string
     * @param   expire_seconds  The number of seconds to cache the value;
     *                          OPTIONAL, defaults to DEFAULT_EXPIRE_SECONDS

     * @return  The string value associated with the given key, the default
     *          value if there is no associated string value or if the value is
     *          expired, or an empty string if no default value is provided.
     */
    EXPORT GetOrSetValue(STRING key, STRING defaultValue = '', expSeconds = DEFAULT_EXPIRE_SECONDS) := FUNCTION
        getResult := GetValue(key);
        finalResult := IF(getResult != '', getResult, SetValue(key, defaultValue, expSeconds));

        RETURN finalResult;
    END;

    /**
     * Deletes the value associated with given key if it exists.
     *
     * @param   key             The key to use to find the value; REQUIRED

     * @return  TRUE if the value was found and deleted, FALSE otherwise.
     */
    EXPORT BOOLEAN DeleteValue(STRING key) := WHEN(_DeleteValue(key), USE_CPP_11);
END;
