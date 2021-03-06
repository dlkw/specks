import ceylon.language.meta {
    type
}
import ceylon.language.meta.declaration {
    FunctionDeclaration
}
import ceylon.language.meta.model {
    Type,
    Generic
}
import ceylon.logging {
    logger,
    Logger
}
import ceylon.random {
    randomize
}

import com.athaydes.specks.assertion {
    AssertionResult
}

"The result of running a Specification case which fails or causes an error.
 A String represents a failure and describes the reason for the failure.
 An Exception means an unexpected error while running the Specification."
shared alias SpecCaseFailure => String|Exception;

"The result of running a successful Specification case or a successful assertion"
shared alias Success => Null;

"The single instance of type [[Success]]."
shared Success success = null;

"The result of running a Specification case.
 A Specification case is defined as an assertion on the result given by a when function
 (for each example, where applicable)."
shared alias SpecCaseResult => SpecCaseFailure|Success;

"The result of running all cases of a [[Block]] of a [[Specification]].
 The key in each entry of the stream represents a Tuple containing an example in the block and the block's description,
 whereas the value represents the lazily-obtained result of all assertions on that example."
shared alias BlockResult => {<[Anything[], String] -> {SpecCaseResult*}()>*};

"Final result of running a [[Specification]]."
shared alias SpecResult => BlockResult[];

"Annotation class for [[unroll]]"
shared final annotation class UnrollAnnotation()
        satisfies OptionalAnnotation<UnrollAnnotation, FunctionDeclaration> {}

"The unroll Annotation indicates that the results of a [[Specification]] should be split up into separate test results
 for each Specification case (or a combination of assertion/example),
 similar to ceylon.test [[ceylon.test::parameters]] annotated tests."
shared annotation UnrollAnnotation unroll()
        => UnrollAnnotation();

class Counter() {
    variable Integer count = 0;

    shared Integer currentValue() => count;

    shared void increment() {
        log.trace(() => "Incrementing counter from ``count``");
        count++;
    }
}

"Most generic kind of block which forms a [[Specification]].

 **specks** provides many different kinds of Blocks that can be created with functions
 such as [[feature]], [[expectations]], [[errorCheck]] and, to enable *property-based* tests,
 quickcheck style, [[forAll]], [[propertyCheck]]."
shared
interface Block {
    "Description of this block"
    shared formal String description;
    "Returns a lazy Stream which can be used to collect the results of running this [[Block]]."
    shared formal BlockResult runTests();
}

Logger log = logger(`module`);

"Top-level representation of a Specification in **specks**."
shared class Specification(
    "Blocks which are part of this [[Specification]]."
    {Block+} blocks) {

    BlockResult results(Block block) {
        log.info(() => "Running block ``block.description``");
        return block.runTests();
    }

    "Run this [[Specification]].

     This method is called by **specks** and usually users do not need to call it directly."
    shared SpecResult run() => blocks.collect(results);
}

Result|Exception apply<Result>(Result() fun) {
    try {
        return fun();
    } catch (e) {
        return e;
    }
}

"Calculate the result of running the when function on a single example for each assertion."
{SpecCaseResult*} applyAssertions<Result>(
    Result() when,
    {Callable<AssertionResult,Result>+} assertions,
    String description,
    Anything[] where,
    Integer maximumFailures,
    Counter failures = Counter())()
        given Result satisfies Anything[] {
    log.debug(() => "Assessing example ``where``");
    value whenResult = apply(when);

    if (is Exception whenResult) {
        return [ whenResult ];
    }

    return object satisfies {SpecCaseResult*} {

        value assertionsIterator = assertions.iterator();

        iterator() => object satisfies Iterator<SpecCaseResult> {
            shared actual SpecCaseResult|Finished next() {
                if (failures.currentValue() >= maximumFailures) {
                    return finished;
                } else if (!is Finished assertion = assertionsIterator.next()) {
                    value result = apply(() => assertion(*whenResult));
                    if (!is Success result) {
                        log.info(() => "Example '``where``' failed: ``result``");
                        failures.increment();
                        value whereString = where.empty then "" else " ``where``";
                        if (is Exception result) {
                            return result;
                        } else {
                            return "\n``description`` failed: ``result````whereString``";
                        }
                    } else {
                        log.debug(() => "Assertion passed for example '``where``'");
                        return success;
                    }
                } else {
                    return finished;
                }
            }
        };
    };
}

String blockDescription(String blockName, String simpleDescription)
        => blockName + (simpleDescription.empty then "" else " '``simpleDescription``'");

Block assertionsWithoutExamplesBlock<Result>(
    String internalDescription,
    Result() applyWhenFunction,
    "Assertions to verify the result of running the 'when' function."
    {Callable<AssertionResult, Result>+} assertions,
    Integer maxFailuresAllowed)
        given Result satisfies Anything[] {

    return object satisfies Block {
        description = internalDescription;

        runTests() => { [[], description] -> applyAssertions(applyWhenFunction, assertions, description, [], maxFailuresAllowed) };
    };
}

Block assertionsWithExamplesBlock<Where, Result>(
    String internalDescription,
    Result(Where) applyWhenFunction,
    "Assertions to verify the result of running the 'when' function."
    {Callable<AssertionResult,Result>+} assertions,
    {Where*} examples,
    Integer maxFailuresAllowed)
        given Where satisfies Anything[]
        given Result satisfies Anything[] {

    [Where, String]->{SpecCaseResult*}() applyExample(Counter failures)(Where example) {
        if (failures.currentValue() >= maxFailuresAllowed) {
            return [example, internalDescription] -> (() => {});
        }
        value assertionResults = applyAssertions(
            () => applyWhenFunction(example),
            assertions, internalDescription, example,
            maxFailuresAllowed,
            failures);

         return [example, internalDescription] -> assertionResults;
    }

    return object satisfies Block {
        description = internalDescription;

        runTests() => examples.map(applyExample(Counter()));

        string = "[``description``]";
    };
}

"A [[Block]] that consists of a series of one or more [[com.athaydes.specks.assertion::expect]] statements which
 verify the behaviour of a system."
shared Block expectations(
    "Assertions that verify the behaviour of a system."
    {AssertionResult+} assertions,
    "Description of this group of expectations."
    String description = "")
        => feature(() => [], assertions.map((a) => () => a), description);

"A feature block allows the description of how a software functionality is expected to work."
shared Block feature<out Where = [], in Result = Where>(
    "The action being tested in this feature."
    Callable<Result, Where> when,
    "Assertions to verify the result of running the 'when' function."
    {Callable<AssertionResult, Result>+} assertions,
    "Description of this feature."
    String description = "",
    "Input examples.<p/>
     Each example will be passed to each assertion function in the order it is declared."
    {Where*} examples = [],
    "Maximum number of failures to allow before stopping running more examples/assertions."
    Integer maxFailuresAllowed = 10)
        given Where satisfies Anything[]
        given Result satisfies Anything[] {

    String internalDescription = blockDescription("Feature", description);

    if (examples.empty) {
        "If you do not provide any examples, your 'when' function must not take any parameters."
        assert (is Callable<Result,[]> when);
        return assertionsWithoutExamplesBlock(
            internalDescription, when, assertions, maxFailuresAllowed);
    } else {
        return assertionsWithExamplesBlock(
            internalDescription,
            (Where example) => when(*example),
            assertions, examples, maxFailuresAllowed);
    }
}

"The errorCheck block makes it possible to verify that an error condition produces the expected
 error or [[Throwable]]."
shared Block errorCheck<Where = []>(
    "The action being tested in this feature."
    Callable<Anything, Where> when,
    {AssertionResult(Throwable?)+} assertions,
    String description = "",
    "Input examples.<p/>
     Each example will be passed to each assertion function in the order it is declared."
    {Where*} examples = [],
    "Maximum number of failures to allow before stopping running more examples/assertions."
    Integer maxFailuresAllowed = 10)
        given Where satisfies Anything[] {

    [Throwable?] apply(void fun())() {
        try {
            fun();
            return [success];
        } catch (Throwable t) {
            return [t];
        }
    }

    String internalDescription = blockDescription("ErrorCheck", description);

    if (examples.empty) {
        "If you do not provide any examples, your 'when' function must not take any parameters."
        assert (is Callable<Anything,[]> when);

        return assertionsWithoutExamplesBlock(
            internalDescription,
            apply(when), assertions, maxFailuresAllowed);
    } else {
        return assertionsWithExamplesBlock(
            internalDescription,
            (Where example) => apply(() => when(*example))(),
            assertions, examples, maxFailuresAllowed);
    }
}

"Creates a [[Block]] for quick-check style (or property-based) testing.

 Examples are generated automatically (or using the provided generators) and passed to the provided
 [[assertion]] function, which should assert that some invariant condition holds for all examples."
see(`function propertyCheck`)
shared Block forAll<Where>(
    "Single assertion which should hold for all possible inputs of a given function"
    Callable<AssertionResult, Where> assertion,
    "Description of this feature."
    String description = "",
    "Number of sample inputs to run tests with"
    Integer sampleCount = 100,
    "Input data generator functions. If not given, uses default generators."
    [Anything()+]? generators = null,
    "Maximum number of failures to allow before stopping running more examples/assertions."
    Integer maxFailuresAllowed = 10)
        given Where satisfies Anything[]
        => propertyCheck(flatten((Where where) => [assertion(*where)]),
                { identity<AssertionResult> },
                    description, sampleCount, generators, maxFailuresAllowed);

[Anything()+] defaultGenerators {
	function collectionSize() => 1 + defaultRandom.nextInteger(100);
	value forStrings = () => randomStrings(collectionSize());
	value forIntegers = () => randomIntegers(collectionSize());
	value forFloats = () => randomFloats(collectionSize());
	value forBooleans = () => randomBooleans(collectionSize());
	return [forStrings, forIntegers, forFloats, forBooleans];
}

"Creates a [[Block]] for more advanced quick-check style (or property-based) testing.

 Examples are generated automatically (or using the provided generators) and passed to the provided
 [[when]] function, which then returns a [[Tuple]] whose elements are passed to the given [[assertions]]
 to verify that certain conditions hold for all examples that can be generated.

 This Block is similar to a [[feature]], except that examples are automatically generated rather than hand-picked."
see(`function forAll`, `function feature`)
shared Block propertyCheck<Result, Where>(
    "The action being tested in this feature."
    Callable<Result, Where> when,
    "Assertions to verify the result of running the 'when' function."
    {Callable<AssertionResult,Result>+} assertions,
    "Description of this feature."
    String description = "",
    "Number of sample inputs to run tests with"
    Integer sampleCount = 100,
    "Input data generator functions. If not given, uses default generators."
    [Anything()+]? generators = null,
    "Maximum number of failures to allow before stopping running more examples/assertions."
    Integer maxFailuresAllowed = 10)
        given Where satisfies Anything[]
        given Result satisfies Anything[]
        => let (desc = description) object satisfies Block {

    description = desc;

    Anything()? iterableToInstanceGeneratorFor(
        Type<Anything> requiredType,
        Type<Anything> genReturnType,
        Anything() generator) {
        if (genReturnType.subtypeOf(`Iterable<>`)) {
            "Specks currently only supports generators that produce Iterables whose
             elements type argument is the first one, such as [[List<Element>]]."
            assert(is Generic genReturnType);
            Type<Anything>? elementsType = genReturnType.typeArgumentList[0];

            if (exists elementsType, elementsType.subtypeOf(requiredType)) {
                assert(is {Anything*}() generator);
                {{Anything*}+} infiniteGenerator = { generator() }.cycled;
                return infiniteGenerator.flatMap(identity).iterator().next;
            }
        }
        return null;
    }

    value gens = generators else defaultGenerators;

    if (exists generators) {
        log.debug("Using custom generator functions");
    } else {
        log.debug("Using default generator functions");
    }

    Where exampleOf([Type<Anything>+] types) {
        {Anything()+} typeGenerators = types.map((requiredType) {
            [Anything()*] acceptableGenerators = gens.map((gen) {
                Type<Anything>? genReturnType = type(gen).typeArgumentList.first;
                if (exists genReturnType) {
                    return if (genReturnType.subtypeOf(requiredType))
                    then gen
                    else iterableToInstanceGeneratorFor(requiredType, genReturnType, gen);
                }
                return null;
            }).coalesced.sequence();

            if (acceptableGenerators.empty) {
                throw Exception("No generator exists for type: ``requiredType``.
                                 Add a generator function for the required type.");
            }
            Anything()? result = randomize(acceptableGenerators).first;
            assert(exists result);
            return result;
        });

        Tuple<Anything, Anything, Anything> typedTuple({Anything+} array) {
            if (exists second = array.rest.first) {
                return Tuple(array.first,
                    typedTuple({ second }.chain(array.rest.rest)));
            }
            else {
                return Tuple(array.first, []);
            }
        }

        [Anything+] instance = [ for (Anything() generate in typeGenerators) generate() ];

        Tuple<Anything,Anything,Anything> tuple = typedTuple(instance);

        "Tuple must be an instance of Where because Where was introspected to create it.
         If you ever see this error, please report a bug on GitHub!"
        assert(is Where tuple);
        return tuple;
    }

    [Type<Anything>+] argTypes = TypeArgumentsChecker().argumentTypes(when);

    {Where*} examples = (0:sampleCount).map((it)
        => exampleOf(argTypes));

    shared actual BlockResult runTests()
            => feature(when, assertions, description,
                examples, maxFailuresAllowed).runTests();

};
