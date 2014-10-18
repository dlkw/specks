
"Generates a number of integers.

 The integers are not random and depend only on the value of count.
 The generated values are appropriate for tests - an attempt is made
 to include boundary values and uniformly distribute the values."
throws(`class Exception`, "if count is smaller than 1")
shared {Integer+} generateIntegers(
    "the number of integers to generate - must be positive"
    Integer count = 100,
    "the lower bound, or lowest value that should be generated"
    Integer lowerBound = - 1M,
    "the higher bound, or maximum value that should be generated"
    Integer higherBound = 1M) {
    if (count < 1) {
        throw Exception("Count must be positive");
    }
    if (count == 1) { return { 0 }; }
    
    class IntsIterator(Integer count) satisfies {Integer+} {
        value step = (higherBound - lowerBound) / (count - 1);
        
        variable Integer itemsLeft = count;
        variable Integer current = lowerBound;
        
        Integer|Finished increase() {
            if (itemsLeft == 0) {
                return finished;
            }
            value result = current;
            current += step;
            itemsLeft--;
            return result;
        }
        
        size = count;
        
        shared actual Iterator<Integer> iterator() => iter;
        
        object iter satisfies Iterator<Integer> {
            shared actual Integer|Finished next() => increase();
        }
    }
    
    return IntsIterator(count);
}
