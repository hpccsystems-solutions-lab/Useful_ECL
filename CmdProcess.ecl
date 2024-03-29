/**
 * Basic replacement for Std.System.Util.CmdProcess(), which was an ECL
 * function provided in the ECL Standard Library up until HPCC Systems
 * version 8.4.0, when it removed due to security concerns.
 *
 * If your use case does not require you to supply data to the program
 * via stdin, you should probably investigate using the built-in ECL
 * function PIPE() instead.
 *
 * @param   prog            A null-terminated string containing the name
 *                          of the program to execute. This may include
 *                          command-line parameters.
 * @param   progInput       A string containing the text to pipe into the
 *                          program through stdin.  If you have no data
 *                          to pass, set this to an empty string.
 *
 * @return  Any output generated by the executed program via its
 *          stdout pipe.
 *
 * Origin:  https://github.com/hpccsystems-solutions-lab/Useful_ECL
 */
EXPORT STRING CmdProcess(VARSTRING prog, STRING progInput) := EMBED(C++ : action)
    #include <stdio.h>
    #include <string>
    #include <vector>

    typedef std::vector<char*> CharPtrList;

    void SplitArgs(const std::string& command, CharPtrList& outArgs)
    {
        int     len = command.length();
        bool    foundQuote = false;
        bool    foundApostrophe = false;
        int     arglen = 0;

        for (int i = 0; i < len; i++)
        {
            int start = i;

            if (command[i] == '"')
            {
                foundQuote = true;
            }
            else if (command[i] == '\'')
            {
                foundApostrophe = true;
            }

            if (foundQuote)
            {
                i++;
                start++;
                while (i < len && command[i] != '"')
                    i++;
                if (i < len)
                    foundQuote = false;
                arglen = i - start;
                i++;
            }
            else if (foundApostrophe)
            {
                i++;
                start++;
                while (i < len && command[i] != '\'')
                    i++;
                if (i < len)
                    foundApostrophe = false;
                arglen = i - start;
                i++;
            }
            else
            {
                while (i < len && command[i] != ' ')
                    i++;
                arglen = i - start;
            }

            char* tmpPtr = reinterpret_cast<char*>(rtlMalloc(arglen + 1));
            memcpy(tmpPtr, &command[start], arglen);
            tmpPtr[arglen] = 0;
            outArgs.push_back(tmpPtr);
        }

        outArgs.push_back(static_cast<char*>(nullptr));
    }

    #body

    std::string     resultStr;
    CharPtrList     args;

    if (prog && prog[0])
    {
        try
        {
            int     writePipe[2]; // parent -> child
            int     readPipe[2];  // child -> parent

            if (pipe(readPipe) < 0 || pipe(writePipe) < 0)
            {
                // Failure -- cannot create pipes
                resultStr = "pipe creation failure";
            }

            #define PARENT_READ     readPipe[0]
            #define CHILD_WRITE     readPipe[1]
            #define CHILD_READ      writePipe[0]
            #define PARENT_WRITE    writePipe[1]

            // Split command into executable and arguments
            SplitArgs(prog, args);

            // Fork!
            pid_t childPID = fork();

            if (childPID < 0)
            {
                // Failure -- cannot fork
                resultStr = "fork failure";
            }
            else if (childPID == 0)
            {
                // Child process

                // Redirect our parent pipes to stdin and stdout
                dup2(CHILD_READ, STDIN_FILENO);
                dup2(CHILD_WRITE, STDOUT_FILENO);

                // Close pipe ends we don't need
                close(PARENT_READ);
                close(PARENT_WRITE);
                close(CHILD_READ);
                close(CHILD_WRITE);

                // Execute external program
                execvp(args[0], &args[0]);

                // We should never get here
                exit(EXIT_FAILURE);
            }
            else
            {
                // Parent process

                // Close pipe ends we don't need
                close(CHILD_READ);
                close(CHILD_WRITE);

                ssize_t         numBytes = 0;
                ssize_t         bytesWritten = 0;

                // Send data to child's stdin, if any
                while (bytesWritten < lenProginput)
                {
                    numBytes = write(PARENT_WRITE, &proginput[bytesWritten], lenProginput - bytesWritten);
                    if (numBytes == -1)
                    {
                        // error
                        break;
                    }
                    else
                    {
                        bytesWritten += numBytes;
                    }
                }

                // Close that pipe
                close(PARENT_WRITE);

                // Wait for child to produce output on its stdout
                fd_set          descriptors;
                struct timeval  timeout;

                FD_ZERO(&descriptors);
                FD_SET(PARENT_READ, &descriptors);
                timeout.tv_sec = 10;
                timeout.tv_usec = 0;

                if (select(PARENT_READ + 1, &descriptors, nullptr, nullptr, &timeout) > 0)
                {
                    unsigned int    bufferSize = 10240;
                    char            readBuffer[bufferSize];

                    // Capture output
                    while (true)
                    {
                        numBytes = read(PARENT_READ, readBuffer, bufferSize-1);

                        if (numBytes == -1)
                        {
                            // error
                            break;
                        }
                        else if (numBytes > 0)
                        {
                            resultStr.append(readBuffer, numBytes);
                        }
                        else
                        {
                            break;
                        }
                    }
                }

                // Close last pipe
                close(PARENT_READ);

                // Kill child if it is still running
                kill(childPID, SIGTERM);
            }
        }
        catch (...)
        {
            // Ignore errors
        }
    }

    // Clear the vector of char* we created
    while (!args.empty())
    {
        rtlFree(args.back());
        args.pop_back();
    }

    // Copy result that will be returned
    __lenResult = resultStr.length();

    if (__lenResult > 0)
    {
        __result = reinterpret_cast<char*>(rtlMalloc(__lenResult));
        memcpy(__result, resultStr.data(), __lenResult);
    }
    else
    {
        __result = nullptr;
    }
ENDEMBED;
