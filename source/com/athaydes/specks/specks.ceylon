import ceylon.language.meta {
    type
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
    AssertionResult,
    AssertionFailure
}

"The result of running a Specification which fails or causes an error.
 A String represents a failure and describes the reason for the failure.
 An Exception means an unexpected error which occurred when trying to run the Specification."
shared alias SpecFailure => String|Exception;

"Successfull Specification"
shared alias SpecSuccess => Null;

"The result of running a Specification."
shared alias SpecResult => SpecFailure|SpecSuccess;

"The result of running a Specification which is successful."
shared SpecSuccess success = null;

Logger log = logger(`module`);

"Most generic kind of block which forms a [[Specification]]."
shared
interface Block {
    shared formal String description;
    shared formal {SpecResult*} runTests();
}

"Top-level representation of a Specification in **specks**."
shared class Specification(
    "block which describe this [[Specification]]."
    {Block+} blocks) {

    {SpecResult*} results(Block block) {
        log.info(() => "Running block ``block.description``");
        return block.runTests();
    }

    "Run this [[Specification]]. This method is called by **specks** to run this Specification
     and usually users do not need to call it directly."
    shared {SpecResult*}[] run() => blocks.collect(results);
}

{SpecResult*} assertSpecResultsExist(SpecResult[]? result) {
    if (exists result, !result.empty) {
        return result;
    }
    throw Exception("Did not find any tests to run.");
}

alias FullSpecResult => [SpecResult[], Integer];

Result|Exception apply<Result>(Result() fun) {
    try {
        return fun();
    } catch (e) {
        return e;
    }
}

"Calculate the result of running the when function on an example for each assertion.
 The [[previousResults]] parameter may be null, indicating that more than the alowed number of failures has
 already occurred, which means no further assertions should be made."
FullSpecResult? specResult<Result>(
    Result() when,
    {Callable<AssertionResult,Result>+} assertions,
    String description,
    {Anything*} where,
    Integer maximumFailures,
    FullSpecResult? previousResults = [[], 0])
        given Result satisfies Anything[] {

    if (is Null previousResults) {
        return null;
    }

    FullSpecResult fail(FullSpecResult acc, AssertionFailure|Exception result) {
        value whereString = where.empty then "" else " ``where``";
        value [results, failures] = acc;

        value error = (switch (result)
            case (is Exception) result
            else "\n``description`` failed: ``result````whereString``");

        log.info(() => "Example failed: ``where`` - ``error``");

        return [results.withTrailing(error), failures + 1];
    }

    value whenResult = apply(when);

    return assertions.scan<FullSpecResult>(previousResults)((acc, assertion) =>
        if (is Exception whenResult) then fail(acc, whenResult)
        else let (failures = acc[1],
                  result = apply(() => assertion(*whenResult)))
            (switch (result)
                case (is AssertionFailure|Exception) fail(acc, result)
                else let (ignore = log.debug(() => "Assertion passed for example ``whenResult``"))
                  [acc[0].withTrailing(success), failures]))
            .takeWhile((item) => item[1] <= maximumFailures)
            .last;
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

        runTests() => assertSpecResultsExist(
            specResult(applyWhenFunction, assertions, description, [], maxFailuresAllowed)?.first);
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

    FullSpecResult? applyExample(FullSpecResult? previousResults, Where example) =>
            specResult(
                () => applyWhenFunction(example),
                assertions, internalDescription, example,
                maxFailuresAllowed, previousResults);

    return object satisfies Block {
        description = internalDescription;

        runTests() => assertSpecResultsExist(
            examples.scan<FullSpecResult?>([[], 0])(applyExample).coalesced.last?.first else null);

        string = "[``description``]";
    };
}

"A block that consists of a series of one or more `expect` statements which
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

    shared actual {SpecResult*} runTests()
            => feature(when, assertions, description,
                examples, maxFailuresAllowed).runTests();

};
