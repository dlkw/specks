import com.athaydes.specks.assertion {
    expect,
    expectCondition,
    AssertionResult,
    expectToThrow
}
import com.athaydes.specks.matcher {
    equalTo,
    Matcher,
    sameAs,
	toBe
}



"Run the module `com.athaydes.specks`."
shared void run() {
    
    void myFunction(Integer i, Integer j) {
        if (i <= 0 || j <= 0) {
            throw Exception();
        }
    }
    
    "Example custom matcher"
    function sorted<Item>(Boolean ascending) 
            given Item satisfies Comparable<Item>
            => object satisfies Matcher<{Item*}> {
        
        value compare = ascending
                then ((Item i, Item prev) => i <= prev)
                else ((Item i, Item prev) => i > prev);
        
        shared actual AssertionResult matches({Item*} actual) {
            if (is {Item+} actual, actual.size > 1) {
                variable value prev = actual.first;
                for (pair in zipPairs(1..actual.size, actual.rest)) {
                    value [index, item] = pair;
                    if (compare(item, prev)) {
                        return "Not sorted at index ``index``: [``item``]";
                    }
                    prev = item;
                }
            }
            return success;
        }
    };
    
    [Specification {
        feature {
            description = "== operator should be symmetric";
            examples = { ["a", "a"], ["", ""] };
            when(String s1, String s2) => [s1, s2];
            (String s1, String s2) => expect(s1, equalTo<String>(s2)),
            (String s1, String s2) => expect(s2, toBe(equalTo<String>(s1)))
        }
    },
    Specification {
        feature {
            description = "Ceylon operators to work";
            when() => [];
            () => expectCondition(2 + 2 == 4),
            () => expectCondition(2 < 4)
        },
        feature {
            description = "Bad expressions to fail";
            when() => [];
            () => expectCondition(2 + 2 == 8),
            () => expectCondition(2 > 4)
        },
        feature {
            description = "More examples";
            when(Integer a, Integer b) => [a, b];
            examples = { [1, 2], [5, 10], [25, 50] };
            (Integer a, Integer b) => expect(2 * a, equalTo<Integer>(b))
        },
        feature {
            description = "Using generated examples";
            examples = { generateIntegers().sequence() };
            when(Integer* ints) => sort(ints);
            (Integer* ints) => expect(ints, sorted<Integer>(true))
        },
        errorCheck {
            description = "when we call throw";
            function when() { throw; }
            expectToThrow(`Exception`)
        },
        errorCheck {
            description = "Error when not given at least one positive integer";
            examples = { [-4, 0], [0, -1], [-2, -3], [0, 0] };
            when = myFunction;
            expectToThrow(`Exception`)
        }
    }, Specification {
        expectations {
            description = "Iterable.first expectations";
            expect([].first, sameAs(null)),
            expect([1].first, equalTo<Integer>(1)),
            expect([5, 4, 3, 2, 1, 0].first, equalTo<Integer>(5)),
            expect(('x'..'z').first, equalTo<Character>('x')),
            expect(['a', 'b'].cycled.first, equalTo<Character>('a'))
        },
        feature {
            description = "Ceylon [*].first should return either the first element or null for empty Sequences";
            when() => [];
            () => expect([1].first, equalTo<Integer>(1)),
            () => expect([5, 4, 3, 2, 1, 0].first, equalTo<Integer>(5)),
            () => expect([1, 2, 3].first, equalTo<Integer>(1))
        },
        feature {
            examples = [[[], null], [[1], 1], [[1,2,3], 1], [["A"], "A"]];
            when(Object[] sequence, Object? expected) => [sequence.first, expected];
            (Object? first, Object? expected) => expect(first, sameAs(expected))
        }
    },
    Specification {
        feature {
            description = "BankAccounts support deposits and withdrawals";
            function when(Float toDeposit, Float toWithdraw, Float finalBalance) {
                value account = BankAccount();
                account.deposit(toDeposit);
                value afterDepositBalance = account.balance;
                account.withdraw(toWithdraw);
                return [toDeposit, afterDepositBalance, account.balance, finalBalance];
            }
            examples = [[100.0, 20.0, 80.0], [33.0k, 31.5k, 1.5k]];
            (Float toDeposit, Float afterDeposit, Float afterWithdrawal, Float finalBalance)
                    => expect(afterDeposit, equalTo<Float>(toDeposit)),
            (Float toDeposit, Float afterDeposit, Float afterWithdrawal, Float finalBalance)
                    => expect(afterWithdrawal, equalTo<Float>(finalBalance)) 
        }
    }
    ].collect((Specification speck) => print(speck.run()));
    
    
    
}

class BankAccount() {
    
    shared void deposit(Float amount) {}

    shared void withdraw(Float amount) {}
    
    shared Float balance = 2.0;
    
}