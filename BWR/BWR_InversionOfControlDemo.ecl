/**
 * This executable code demonstrates inversion of control (IoC) in the
 * ECL language.  More information on IoC can be found in Wikipedia:
 *
 * https://en.wikipedia.org/wiki/Inversion_of_control
 *
 * The idea with IoC is that you have a generic framework of execution that
 * should use some custom code to perform (as opposed to writing custom code
 * that calls into generic framework code).  This kind of software design is
 * more easily maintained in many use cases.
 *
 * Follows is a very small demonstration of IoC.  The generic task is to
 * return a set of unsigned integers.  The custom part of the task is
 * generating those integers:  Sometimes you might want only odd numbers,
 * sometimes you want only even numbers.  This code happens to do both,
 * sequentially.  The general concept can easily be extended in more complex
 * (and useful) directions.
 *
 * The underlying ECL concepts are the INTERFACE and the MODULE.  An INTERFACE,
 * here, is used to define the interface that a MODULE will expose.  A MODULE
 * will be the worker (the custom code).
 *
 * Origin:  https://github.com/dcamper/Useful_ECL
 */

// Define the record structure of the data we'll be working with
NumberRec := RECORD
    UNSIGNED4   num;
END;

//------------------------------------------------------------------------------

// Define the interface that our workers will implement
IWorker := INTERFACE
    // This is a function declaration, not an actual function
    EXPORT DATASET(NumberRec) MakeNumbers(UNSIGNED4 cnt);
END;

//------------------------------------------------------------------------------

// The worker that produces even numbers; note that it inherits from
// the INTERFACE
Worker_EvenNumbers := MODULE(IWorker)
    // Function must match the signature within the INTERFACE
    EXPORT DATASET(NumberRec) MakeNumbers(UNSIGNED4 cnt) := FUNCTION
        RETURN DATASET
            (
                cnt,
                TRANSFORM
                    (
                        NumberRec,
                        SELF.num := COUNTER * 2
                    )
            );
    END;
END;

// The worker that produces odd numbers; note that it inherits from
// the INTERFACE
Worker_OddNumbers := MODULE(IWorker)
    // Function must match the signature within the INTERFACE
    EXPORT DATASET(NumberRec) MakeNumbers(UNSIGNED4 cnt) := FUNCTION
        RETURN DATASET
            (
                cnt,
                TRANSFORM
                    (
                        NumberRec,
                        SELF.num := COUNTER * 2 - 1
                    )
            );
    END;
END;

//------------------------------------------------------------------------------

// The generic function that invokes the custom bits.  All it does is return
// the output from the worker code.  Note that the first argument's datatype
// is the INTERFACE but you will be passing in the MODULE that adheres to that
// INTERFACE.
ShowNumbers(IWorker worker, UNSIGNED4 cnt = 10) := FUNCTION
    RETURN worker.MakeNumbers(cnt);
END;

// Call our generic function twice, once with each worker
OUTPUT(ShowNumbers(Worker_EvenNumbers, 5), NAMED('Even1'));
OUTPUT(ShowNumbers(Worker_OddNumbers, 5), NAMED('Odd1'));

//------------------------------------------------------------------------------

// You can group related custom code together by passing the custom bits
// into a MODULE and then referencing the argument names within that module
MyGenericModule(IWorker worker) := MODULE
    EXPORT myData := worker.MakeNumbers(5);
    EXPORT myDataCount := COUNT(myData);
END;

mEven := MyGenericModule(Worker_EvenNumbers);
OUTPUT(mEven.myData, NAMED('Even2'));
OUTPUT(mEven.myDataCount, NAMED('Even2Count'));

mOdd := MyGenericModule(Worker_OddNumbers);
OUTPUT(mOdd.myData, NAMED('Odd2'));
OUTPUT(mOdd.myDataCount, NAMED('Odd2Count'));
