/**
 * Hyperloop iOS-Core
 * Copyright (c) 2015-present by Appcelerator, Inc.
 */

#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "class.h"
#import "pointer.h"
#import "utils.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

@interface TestDispatch : XCTestCase

@end

@interface TestDispatchMock : NSObject
@end

@implementation TestDispatchMock
-(void)test:(int *)result {
	*result = 12;
}
-(int *)testWithIntPointerResult:(int)value {
	int *i = malloc(sizeof(int) * 2);
	i[0] = value + 1;
	i[1] = value + 2;
	return i;
}
-(int)testWithInt:(int)value {
	return value + 1;
}
-(float)testWithFloat:(float)value {
	return value + 1.1f;
}
-(long)testWithLong:(long)value {
	return value + 1;
}
-(short)testWithShort:(short)value {
	return value + 1;
}
-(double)testWithDouble:(double)value {
	return value + 1.02;
}
-(char)testWithChar:(char)value {
	return value;
}
-(unsigned char)testWithUnsignedChar:(unsigned char)value {
	return value;
}
-(char *)testWithCharStar:(char *)value {
	return "xyz";
}
-(bool)testWithBool:(bool)value {
	return !value;
}
-(long long)testWithLongLong:(long long)value {
	return value + 1;
}
-(unsigned int)testWithUnsignedInt:(unsigned int)value {
	return value + 1;
}
-(unsigned long)testWithUnsignedLong:(unsigned long)value {
	return value + 1;
}
-(unsigned short)testWithUnsignedShort:(unsigned short)value {
	return value + 1;
}
-(unsigned long long)testWithUnsignedLongLong:(unsigned long long)value {
	return value + 1;
}
-(CGRect)testWithCGRect:(CGRect)rect {
	rect.origin.x = 10;
	rect.origin.y = 10;
	return rect;
}
-(Class)testWithClass:(Class)cls {
	return cls;
}
-(SEL)testWithSEL:(SEL)value {
	return value;
}
-(id)testWithID: (id)value {
	return value;
}
@end

static const unsigned char TestPointerReturnStaticBytes[16] = {
	0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04,
	0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C
};

/**
 * Methods returning pointers the caller does not own: the bridge must wrap
 * the returned address and must never free it.
 */
@interface TestPointerReturnMock : NSObject
@end

@implementation TestPointerReturnMock
-(void *)staticVoidPointer {
	return (void *)TestPointerReturnStaticBytes;
}
-(void *)nullVoidPointer {
	return NULL;
}
@end

static unsigned char *TestPointerReturnBytePointerIMP(id self, SEL _cmd) {
	return (unsigned char *)TestPointerReturnStaticBytes;
}

/**
 * clang encodes every `char *` flavor (including `unsigned char *`) as `*`,
 * so a `^C` return is only produced by an explicit runtime type string.
 */
static SEL TestPointerReturnBytePointerSelector(void) {
	static dispatch_once_t once;
	SEL sel = NSSelectorFromString(@"staticBytePointer");
	dispatch_once(&once, ^{
		BOOL added = class_addMethod([TestPointerReturnMock class], sel, (IMP)TestPointerReturnBytePointerIMP, "^C@:");
		if (!added) {
			abort();
		}
	});
	return sel;
}

/**
 * Owns a single 4-byte int and returns it through a const-qualified pointer (encoded r^i).
 */
@interface TestQualifiedPointerReturnMock : NSObject
@property (nonatomic, readonly) int *storage;
@end

@implementation TestQualifiedPointerReturnMock
-(instancetype)init {
	if (self = [super init]) {
		_storage = malloc(sizeof(int));
		*_storage = 4242;
	}
	return self;
}
-(const int *)constIntPointer {
	return _storage;
}
-(void)dealloc {
	free(_storage);
}
@end

/**
 * Receives raw pointer arguments (NSValue or NSNumber, not HyperloopPointer) and
 * reports the address it was given.
 */
@interface TestPointerArgumentMock : NSObject
@property (nonatomic, assign) int receivedLeading;
@property (nonatomic, assign) int receivedTrailing;
@end

@implementation TestPointerArgumentMock
-(uintptr_t)addressOfPointer:(void *)pointer {
	return (uintptr_t)pointer;
}
-(uintptr_t)addressOfConstPointer:(const void *)pointer {
	return (uintptr_t)pointer;
}
-(void)writeInt:(int)value toPointer:(int *)pointer {
	*pointer = value;
}
-(uintptr_t)addressWithLeading:(int)leading pointer:(void *)pointer trailing:(int)trailing {
	_receivedLeading = leading;
	_receivedTrailing = trailing;
	return (uintptr_t)pointer;
}
@end

/**
 * Counts allocations and deallocations so tests can check that the bridge
 * neither leaks nor over-releases instances it constructs. Initializers follow
 * ARC init-family conventions: they consume self and return +1.
 */
static NSInteger TestInitOwnershipAllocs;
static NSInteger TestInitOwnershipDeallocs;
static NSInteger TestInitReplacementAllocs;
static NSInteger TestInitReplacementDeallocs;

static void TestInitOwnershipResetCounters(void) {
	TestInitOwnershipAllocs = 0;
	TestInitOwnershipDeallocs = 0;
	TestInitReplacementAllocs = 0;
	TestInitReplacementDeallocs = 0;
}

@interface TestInitReplacement : NSObject
@end

@implementation TestInitReplacement
+(instancetype)allocWithZone:(struct _NSZone *)zone {
	TestInitReplacementAllocs++;
	return [super allocWithZone:zone];
}
-(void)dealloc {
	TestInitReplacementDeallocs++;
}
@end

@interface TestInitOwnershipMock : NSObject
@property (nonatomic, assign) NSInteger value;
@end

@implementation TestInitOwnershipMock
+(instancetype)allocWithZone:(struct _NSZone *)zone {
	TestInitOwnershipAllocs++;
	return [super allocWithZone:zone];
}
+(id)nilFactory {
	return nil;
}
-(instancetype)initReturningNil {
	// ARC releases the consumed self here, like a failing Foundation initializer.
	self = [super init];
	return nil;
}
-(instancetype)initWithValue:(NSInteger)value {
	if (self = [super init]) {
		_value = value;
	}
	return self;
}
-(id)initReturningReplacement {
	// ARC releases the consumed self and returns the replacement at +1.
	return [[TestInitReplacement alloc] init];
}
-(instancetype)initThrowing {
	@throw [NSException exceptionWithName:@"TestInitFailure" reason:@"initializer failed" userInfo:nil];
}
-(id)nilObject {
	return nil;
}
-(void)dealloc {
	TestInitOwnershipDeallocs++;
}
@end

@interface TestArrayArgumentMock : NSObject
+(void)reset;
+(id)receivedValue;
+(int)receivedBefore;
+(int)receivedAfter;
+(int)enteredCount;
@end

typedef NS_ENUM(int, TestArrayArgumentKind) {
	TestArrayArgumentKindNil = 0,
	TestArrayArgumentKindEmptyArray = 1,
	TestArrayArgumentKindNonEmptyArray = 2,
	TestArrayArgumentKindOther = 3
};

static id TestArrayArgumentValue;
static int TestArrayArgumentBefore;
static int TestArrayArgumentAfter;
static int TestArrayArgumentEntered;

@implementation TestArrayArgumentMock
+(void)reset {
	TestArrayArgumentValue = nil;
	TestArrayArgumentBefore = 0;
	TestArrayArgumentAfter = 0;
	TestArrayArgumentEntered = 0;
}
+(int)enteredCount {
	return TestArrayArgumentEntered;
}
+(id)receivedValue {
	return TestArrayArgumentValue;
}
+(int)receivedBefore {
	return TestArrayArgumentBefore;
}
+(int)receivedAfter {
	return TestArrayArgumentAfter;
}
+(int)kindOf:(id)value {
	if (value == nil) {
		return TestArrayArgumentKindNil;
	}
	if (![value isKindOfClass:[NSArray class]]) {
		return TestArrayArgumentKindOther;
	}
	return [value count] == 0 ? TestArrayArgumentKindEmptyArray : TestArrayArgumentKindNonEmptyArray;
}
+(int)takeArray:(NSArray *)value {
	TestArrayArgumentValue = value;
	return [self kindOf:value];
}
+(int)takeInt:(int)before array:(NSArray *)value int:(int)after {
	TestArrayArgumentBefore = before;
	TestArrayArgumentValue = value;
	TestArrayArgumentAfter = after;
	return [self kindOf:value];
}
+(int)takeBlock:(void (^)(void))block {
	TestArrayArgumentValue = block;
	return block == nil ? TestArrayArgumentKindNil : TestArrayArgumentKindOther;
}
// Parameters an array cannot be converted to. Each only records that it was entered and
// never reads its argument, so a bogus value cannot make the fixture itself unsafe.
+(int)takeIntValue:(int)value {
	TestArrayArgumentEntered++;
	return 0;
}
+(int)takeDoubleValue:(double)value {
	TestArrayArgumentEntered++;
	return 0;
}
+(int)takeBoolValue:(BOOL)value {
	TestArrayArgumentEntered++;
	return 0;
}
+(int)takeClassValue:(Class)value {
	TestArrayArgumentEntered++;
	return 0;
}
+(int)takeSelectorValue:(SEL)value {
	TestArrayArgumentEntered++;
	return 0;
}
+(int)takeCString:(const char *)value {
	TestArrayArgumentEntered++;
	return 0;
}
+(int)takeRect:(CGRect)value {
	TestArrayArgumentEntered++;
	return 0;
}
+(int)takeObjectPointer:(const id *)value {
	TestArrayArgumentEntered++;
	return 0;
}
// Records only whether the pointer is NULL; it is never dereferenced.
+(int)takePointer:(void *)value {
	TestArrayArgumentEntered++;
	return value == NULL ? TestArrayArgumentKindNil : TestArrayArgumentKindOther;
}
// Only compares the block with nil: an invalid value is never called, copied or stored.
+(int)takeBlockValue:(void (^)(void))block {
	TestArrayArgumentEntered++;
	return block == nil ? TestArrayArgumentKindNil : TestArrayArgumentKindOther;
}
+(int)takeInt:(int)before block:(void (^)(void))block {
	TestArrayArgumentEntered++;
	TestArrayArgumentBefore = before;
	return 0;
}
+(int)takeInt:(int)before pointer:(void *)value {
	TestArrayArgumentEntered++;
	TestArrayArgumentBefore = before;
	return 0;
}
// The runtime encodes this parameter as "nO@": an object parameter behind two qualifiers.
+(int)takeQualifiedArray:(in bycopy NSArray *)value {
	TestArrayArgumentValue = value;
	return [self kindOf:value];
}
@end

@implementation TestDispatch

-(void)tearDown {
	[TestArrayArgumentMock reset];
#ifdef HYPERLOOP_MEMORY_TRACKING
	HyperloopTrackDumpAll();
#endif
}

- (void)testNoArgDispatch {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"NSString" alloc:YES init:@selector(initWithString:) args:@[@"hello"]];
	id result = [HyperloopUtils invokeSelector:@selector(description) args:nil target:cls instance:YES];
	XCTAssertEqualObjects(result, @"hello");
}

- (void)testNoArgDispatchWithClassMethod {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"NSString" alloc:YES init:@selector(initWithString:) args:@[@"hello"]];
	id result = [HyperloopUtils invokeSelector:@selector(class) args:nil target:cls instance:NO];
	XCTAssertEqualObjects([result stringValue], NSStringFromClass([@"hello" class]));
}

//// Variadic methods don't work with NSInvocation
//- (void)testWithArguments {
//	HyperloopClass *cls = [Hyperloop newClass:@"NSMutableString" alloc:YES init:@selector(initWithString:) args:@[@""]];
//	NSArray *args = @[
//		@"appendFormat:",
//		@[
//			@"hello %@",
//			@"world"
//		]
//	];
//	[cls dispatch:args];
//	id result = [cls dispatch:@[@"description"]];
//	XCTAssertEqualObjects(result, @"hello world");
//}

- (void)testWithArguments {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"NSMutableString" alloc:YES init:@selector(initWithString:) args:@[@""]];
	id result = [HyperloopUtils invokeSelector:@selector(appendString:) args:@[@"hello world"] target:cls instance:YES];
	XCTAssertNil(result);
	result = [HyperloopUtils invokeSelector:@selector(description) args:nil target:cls instance:YES];
	XCTAssertEqualObjects(result, @"hello world");
}

- (void)testWithIntPointer {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestDispatchMock" alloc:YES init:@selector(init) args:nil];
	HyperloopPointer *ptr = [HyperloopPointer encoding:@encode(int *)];
	id result = [HyperloopUtils invokeSelector:@selector(test:) args:@[ptr] target:cls instance:YES];
	XCTAssertNil(result);
	id value = [ptr valueAtIndex:0];
	XCTAssertEqual([value intValue], 12);
}

- (void)testPointerArgumentFixtureEncoding {
	XCTAssertEqual(strcmp([[TestPointerArgumentMock instanceMethodSignatureForSelector:@selector(addressOfPointer:)] getArgumentTypeAtIndex:2], "^v"), 0);
	XCTAssertEqual(strcmp([[TestPointerArgumentMock instanceMethodSignatureForSelector:@selector(addressOfConstPointer:)] getArgumentTypeAtIndex:2], "r^v"), 0);
	XCTAssertEqual(strcmp([[TestPointerArgumentMock instanceMethodSignatureForSelector:@selector(writeInt:toPointer:)] getArgumentTypeAtIndex:3], "^i"), 0);
	NSMethodSignature *sig = [TestPointerArgumentMock instanceMethodSignatureForSelector:@selector(addressWithLeading:pointer:trailing:)];
	XCTAssertEqual(strcmp([sig getArgumentTypeAtIndex:2], "i"), 0);
	XCTAssertEqual(strcmp([sig getArgumentTypeAtIndex:3], "^v"), 0);
	XCTAssertEqual(strcmp([sig getArgumentTypeAtIndex:4], "i"), 0);
}

// the native method must receive the address held by the NSValue, not the bytes stored at it
- (void)testPointerArgumentFromValue {
	TestPointerArgumentMock *mock = [[TestPointerArgumentMock alloc] init];
	uint64_t pointee = 0x1122334455667788ULL;
	NSValue *value = [NSValue valueWithPointer:&pointee];
	id result = [HyperloopUtils invokeSelector:@selector(addressOfPointer:) args:@[value] target:mock instance:YES];
	XCTAssertEqual([result unsignedLongValue], (uintptr_t)&pointee);
	result = [HyperloopUtils invokeSelector:@selector(addressOfConstPointer:) args:@[value] target:mock instance:YES];
	XCTAssertEqual([result unsignedLongValue], (uintptr_t)&pointee);
	XCTAssertEqual(pointee, 0x1122334455667788ULL);
}

- (void)testPointerArgumentFromNullValue {
	TestPointerArgumentMock *mock = [[TestPointerArgumentMock alloc] init];
	id result = [HyperloopUtils invokeSelector:@selector(addressOfPointer:) args:@[ [NSValue valueWithPointer:NULL] ] target:mock instance:YES];
	XCTAssertEqual([result unsignedLongValue], 0ul);
	// a JS 0 arrives as a double-backed NSNumber
	result = [HyperloopUtils invokeSelector:@selector(addressOfPointer:) args:@[ [NSNumber numberWithDouble:0] ] target:mock instance:YES];
	XCTAssertEqual([result unsignedLongValue], 0ul);
}

- (void)testPointerArgumentWritesThroughValue {
	TestPointerArgumentMock *mock = [[TestPointerArgumentMock alloc] init];
	int *storage = calloc(2, sizeof(int));
	[HyperloopUtils invokeSelector:@selector(writeInt:toPointer:) args:@[ @77, [NSValue valueWithPointer:storage] ] target:mock instance:YES];
	XCTAssertEqual(storage[0], 77);
	XCTAssertEqual(storage[1], 0);
	free(storage);
}

- (void)testPointerArgumentBetweenArguments {
	TestPointerArgumentMock *mock = [[TestPointerArgumentMock alloc] init];
	uint64_t pointee = 0x1122334455667788ULL;
	NSArray *args = @[ @(-7), [NSValue valueWithPointer:&pointee], @(INT_MIN) ];
	id result = [HyperloopUtils invokeSelector:@selector(addressWithLeading:pointer:trailing:) args:args target:mock instance:YES];
	XCTAssertEqual([result unsignedLongValue], (uintptr_t)&pointee);
	XCTAssertEqual(mock.receivedLeading, -7);
	XCTAssertEqual(mock.receivedTrailing, INT_MIN);
}

- (void)testWithIntPointerResult {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestDispatchMock" alloc:YES init:@selector(init) args:nil];
	HyperloopPointer *ptr = [HyperloopPointer encoding:@encode(int)];
	HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(testWithIntPointerResult:) args:@[ptr] target:cls instance:YES];
	XCTAssertEqual([[result valueAtIndex:0] intValue], 1);
	XCTAssertEqual([[result valueAtIndex:1] intValue], 2);
}

- (void)testStaticVoidPointerResultIsBorrowed {
	TestPointerReturnMock *mock = [[TestPointerReturnMock alloc] init];
	XCTAssertEqual(strcmp([[mock methodSignatureForSelector:@selector(staticVoidPointer)] methodReturnType], @encode(void *)), 0);
	__weak HyperloopPointer *weakResult = nil;
	@autoreleasepool {
		HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(staticVoidPointer) args:nil target:mock instance:YES];
		XCTAssertTrue([result isKindOfClass:[HyperloopPointer class]]);
		XCTAssertEqualObjects([result encoding], @"^v");
		XCTAssertEqual([result pointerValue], (void *)TestPointerReturnStaticBytes);
		XCTAssertEqual(memcmp([result pointerValue], TestPointerReturnStaticBytes, sizeof(TestPointerReturnStaticBytes)), 0);
		weakResult = result;
		result = nil;
	}
	XCTAssertNil(weakResult);
	// static storage must be untouched by dispatch and wrapper cleanup
	const unsigned char expected[16] = { 0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C };
	XCTAssertEqual(memcmp(TestPointerReturnStaticBytes, expected, sizeof(expected)), 0);
}

- (void)testNSDataBytesResultIsBorrowed {
	const NSUInteger length = 4096;
	unsigned char *expected = malloc(length);
	for (NSUInteger i = 0; i < length; i++) {
		expected[i] = (unsigned char)(i * 31 + 7);
	}
	NSData *owner = nil;
	@autoreleasepool {
		owner = [[NSData alloc] initWithBytes:expected length:length];
	}
	const void *ownerBytes = owner.bytes;
	__weak HyperloopPointer *weakResult = nil;
	@autoreleasepool {
		HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(bytes) args:nil target:owner instance:YES];
		XCTAssertTrue([result isKindOfClass:[HyperloopPointer class]]);
		XCTAssertEqual([result pointerValue], ownerBytes);
		XCTAssertEqual(memcmp([result pointerValue], expected, length), 0);
		XCTAssertEqual(memcmp(owner.bytes, expected, length), 0);
		weakResult = result;
		result = nil;
	}
	XCTAssertNil(weakResult);
	// the live owner's buffer survives wrapper cleanup unchanged
	XCTAssertEqual(owner.bytes, ownerBytes);
	XCTAssertEqual(memcmp(owner.bytes, expected, length), 0);
	@autoreleasepool {
		owner = nil;
	}
	free(expected);
}

- (void)testUnsignedCharPointerResultIsBorrowed {
	SEL sel = TestPointerReturnBytePointerSelector();
	TestPointerReturnMock *mock = [[TestPointerReturnMock alloc] init];
	XCTAssertEqual(strcmp([[mock methodSignatureForSelector:sel] methodReturnType], "^C"), 0);
	__weak HyperloopPointer *weakResult = nil;
	@autoreleasepool {
		HyperloopPointer *result = [HyperloopUtils invokeSelector:sel args:nil target:mock instance:YES];
		XCTAssertTrue([result isKindOfClass:[HyperloopPointer class]]);
		XCTAssertEqualObjects([result encoding], @"^C");
		XCTAssertEqual([result pointerValue], (void *)TestPointerReturnStaticBytes);
		for (NSUInteger i = 0; i < sizeof(TestPointerReturnStaticBytes); i++) {
			XCTAssertEqual([[result valueAtIndex:i] unsignedCharValue], TestPointerReturnStaticBytes[i]);
		}
		weakResult = result;
		result = nil;
	}
	XCTAssertNil(weakResult);
	XCTAssertEqual(TestPointerReturnStaticBytes[0], 0xDE);
	XCTAssertEqual(TestPointerReturnStaticBytes[15], 0x0C);
}

- (void)testNullVoidPointerResult {
	TestPointerReturnMock *mock = [[TestPointerReturnMock alloc] init];
	__weak HyperloopPointer *weakResult = nil;
	@autoreleasepool {
		HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(nullVoidPointer) args:nil target:mock instance:YES];
		// a NULL pointer return is still wrapped (not nil), as for any other pointer return
		XCTAssertNotNil(result);
		XCTAssertTrue([result isKindOfClass:[HyperloopPointer class]]);
		XCTAssertEqualObjects([result encoding], @"^v");
		XCTAssertTrue([result pointerValue] == NULL);
		weakResult = result;
		result = nil;
	}
	XCTAssertNil(weakResult);
}

// a const-qualified pointer return (r^i) goes through the real signature parser: it is borrowed,
// keeps the native address of the 4-byte pointee, drops the qualifier and is not freed on cleanup
- (void)testQualifiedIntPointerResultIsBorrowed {
	TestQualifiedPointerReturnMock *mock = [[TestQualifiedPointerReturnMock alloc] init];
	XCTAssertEqual(strcmp([[mock methodSignatureForSelector:@selector(constIntPointer)] methodReturnType], "r^i"), 0);
	__weak HyperloopPointer *weakResult = nil;
	@autoreleasepool {
		HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(constIntPointer) args:nil target:mock instance:YES];
		XCTAssertTrue([result isKindOfClass:[HyperloopPointer class]]);
		XCTAssertEqualObjects([result encoding], @"^i");
		XCTAssertEqual([result pointerValue], (void *)mock.storage);
		XCTAssertEqual([[result valueAtIndex:0] intValue], 4242);
		weakResult = result;
		result = nil;
	}
	XCTAssertNil(weakResult);
	// still owned (and later freed) by the mock
	XCTAssertEqual(*mock.storage, 4242);
}

- (void)testWithIntValue {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestDispatchMock" alloc:YES init:@selector(init) args:nil];
	HyperloopPointer *ptr = [HyperloopPointer encoding:@encode(int)];
	[ptr setValue:@1 atIndex:0];
	HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(testWithInt:) args:@[ptr] target:cls instance:YES];
	XCTAssertNotNil(result);
	XCTAssertEqual([result intValue], 2);
}

- (void)testWithFloatValue {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestDispatchMock" alloc:YES init:@selector(init) args:nil];
	HyperloopPointer *ptr = [HyperloopPointer encoding:@encode(float)];
	[ptr setValue:@1.0f atIndex:0];
	HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(testWithFloat:) args:@[ptr] target:cls instance:YES];
	XCTAssertNotNil(result);
	XCTAssertEqual([result floatValue], 2.1f);
}

- (void)testWithDoubleValue {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestDispatchMock" alloc:YES init:@selector(init) args:nil];
	HyperloopPointer *ptr = [HyperloopPointer encoding:@encode(double)];
	[ptr setValue:@1.0f atIndex:0];
	HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(testWithDouble:) args:@[ptr] target:cls instance:YES];
	XCTAssertNotNil(result);
	XCTAssertEqual([result doubleValue], 2.0200000);
}

- (void)testWithShortValue {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestDispatchMock" alloc:YES init:@selector(init) args:nil];
	HyperloopPointer *ptr = [HyperloopPointer encoding:@encode(short)];
	[ptr setValue:@1 atIndex:0];
	HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(testWithShort:) args:@[ptr] target:cls instance:YES];
	XCTAssertNotNil(result);
	XCTAssertEqual([result shortValue], 2);
}

- (void)testWithLongValue {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestDispatchMock" alloc:YES init:@selector(init) args:nil];
	HyperloopPointer *ptr = [HyperloopPointer encoding:@encode(long)];
	[ptr setValue:@1 atIndex:0];
	HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(testWithLong:) args:@[ptr] target:cls instance:YES];
	XCTAssertNotNil(result);
	XCTAssertEqual([result longValue], 2);
}

- (void)testWithLongLongValue {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestDispatchMock" alloc:YES init:@selector(init) args:nil];
	HyperloopPointer *ptr = [HyperloopPointer encoding:@encode(long long)];
	[ptr setValue:@1 atIndex:0];
	HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(testWithLongLong:) args:@[ptr] target:cls instance:YES];
	XCTAssertNotNil(result);
	XCTAssertEqual([result longLongValue], 2);
}

- (void)testWithUnsignedIntValue {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestDispatchMock" alloc:YES init:@selector(init) args:nil];
	HyperloopPointer *ptr = [HyperloopPointer encoding:@encode(unsigned int)];
	[ptr setValue:@1 atIndex:0];
	HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(testWithUnsignedInt:) args:@[ptr] target:cls instance:YES];
	XCTAssertNotNil(result);
	XCTAssertEqual([result unsignedIntValue], 2);
}

- (void)testWithUnsignedShortValue {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestDispatchMock" alloc:YES init:@selector(init) args:nil];
	HyperloopPointer *ptr = [HyperloopPointer encoding:@encode(unsigned short)];
	[ptr setValue:@1 atIndex:0];
	HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(testWithUnsignedShort:) args:@[ptr] target:cls instance:YES];
	XCTAssertNotNil(result);
	XCTAssertEqual([result unsignedShortValue], 2);
}

- (void)testWithUnsignedLongLongValue {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestDispatchMock" alloc:YES init:@selector(init) args:nil];
	HyperloopPointer *ptr = [HyperloopPointer encoding:@encode(unsigned long long)];
	[ptr setValue:@1 atIndex:0];
	HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(testWithUnsignedLongLong:) args:@[ptr] target:cls instance:YES];
	XCTAssertNotNil(result);
	XCTAssertEqual([result unsignedLongLongValue], 2);
}

- (void)testWithBoolValue {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestDispatchMock" alloc:YES init:@selector(init) args:nil];
	HyperloopPointer *ptr = [HyperloopPointer encoding:@encode(bool)];
	[ptr setValue:@1 atIndex:0];
	HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(testWithBool:) args:@[ptr] target:cls instance:YES];
	XCTAssertNotNil(result);
	XCTAssertEqual([result boolValue], false);
}

- (void)testWithCharValue {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestDispatchMock" alloc:YES init:@selector(init) args:nil];
	HyperloopPointer *ptr = [HyperloopPointer encoding:@encode(char)];
	[ptr setValue:@'a' atIndex:0];
	HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(testWithChar:) args:@[ptr] target:cls instance:YES];
	XCTAssertNotNil(result);
	XCTAssertEqual([result charValue], 'a');
}

- (void)testWithUnsignedCharValue {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestDispatchMock" alloc:YES init:@selector(init) args:nil];
	HyperloopPointer *ptr = [HyperloopPointer encoding:@encode(unsigned char)];
	[ptr setValue:@'a' atIndex:0];
	HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(testWithUnsignedChar:) args:@[ptr] target:cls instance:YES];
	XCTAssertNotNil(result);
	XCTAssertEqual([result unsignedCharValue], 'a');
}

- (void)testWithCharStarValue {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestDispatchMock" alloc:YES init:@selector(init) args:nil];
	HyperloopPointer *ptr = [HyperloopPointer encoding:@encode(char *)];
	[ptr setValue:@"abc" atIndex:0];
	HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(testWithCharStar:) args:@[ptr] target:cls instance:YES];
	XCTAssertNotNil(result);
	XCTAssertEqualObjects([result stringValue], @"xyz");
}

- (void)testWithStruct {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestDispatchMock" alloc:YES init:@selector(init) args:nil];
	HyperloopPointer *ptr = [HyperloopPointer encoding:@encode(CGRect)];
	HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(testWithCGRect:) args:@[ptr] target:cls instance:YES];
	XCTAssertNotNil(result);
	XCTAssertEqualObjects([result valueAtIndex:0], @10);
	XCTAssertEqualObjects([result valueAtIndex:1], @10);
}

- (void)testWithSelector {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestDispatchMock" alloc:YES init:@selector(init) args:nil];
	SEL sel = @selector(foo:bar:);
	HyperloopPointer *ptr = [HyperloopPointer pointer:sel encoding:@encode(SEL)];
	HyperloopPointer *result = [HyperloopUtils invokeSelector:@selector(testWithSEL:) args:@[ptr] target:cls instance:YES];
	XCTAssertNotNil(result);
	XCTAssertEqualObjects([result selectorValue], NSStringFromSelector(sel));
}

- (void)testNewString {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"NSString" alloc:NO init:@selector(stringWithString:) args:@[@"hello"]];
	XCTAssertNotNil(cls);
	HyperloopPointer *description = [HyperloopUtils invokeSelector:@selector(description) args:nil target:cls instance:YES];
	XCTAssertNotNil(description);
	XCTAssertEqualObjects(description, @"hello");
	HyperloopPointer *hash = [HyperloopUtils invokeSelector:@selector(hash) args:nil target:cls instance:YES];
	XCTAssertNotNil(hash);
	HyperloopPointer *uppercaseString = [HyperloopUtils invokeSelector:@selector(uppercaseString) args:nil target:cls instance:YES];
	XCTAssertNotNil(uppercaseString);
	XCTAssertEqualObjects(uppercaseString, @"HELLO");
	HyperloopPointer *append = [HyperloopUtils invokeSelector:@selector(stringByAppendingString:) args:@[@" world"] target:cls instance:YES];
	XCTAssertNotNil(append);
	XCTAssertEqualObjects(append, @"hello world");
}

- (void)testCFDictionaryRetain {
	@autoreleasepool {
		CFMutableDictionaryRef registeredProxies = CFDictionaryCreateMutable(NULL, 10, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		HyperloopClass *proxy = [[HyperloopClass alloc] initWithClassName:@"UIView" alloc:NO init:@selector(class) args:nil];
		id result = (id)CFDictionaryGetValue(registeredProxies, (__bridge const void *)(proxy));
		XCTAssertNil(result);
		CFDictionaryAddValue(registeredProxies,(__bridge const void *)(proxy),(__bridge const void *)(proxy));
		result = (id)CFDictionaryGetValue(registeredProxies, (__bridge const void *)(proxy));
		XCTAssertNotNil(result);
		CFDictionaryRemoveAllValues(registeredProxies);
		CFRelease(registeredProxies);
		proxy = nil;
	}
}

- (void)testInitializerReturningNil {
	TestInitOwnershipResetCounters();
	@autoreleasepool {
		HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestInitOwnershipMock" alloc:YES init:@selector(initReturningNil) args:nil];
		XCTAssertNotNil(cls);
		XCTAssertNil(cls.nativeObject);
		XCTAssertNil([cls target]);
	}
	XCTAssertEqual(TestInitOwnershipAllocs, 1);
	XCTAssertEqual(TestInitOwnershipDeallocs, 1);
}

- (void)testInitializerReturningSelf {
	TestInitOwnershipResetCounters();
	HyperloopClass *cls = nil;
	__weak id weakNative = nil;
	@autoreleasepool {
		cls = [[HyperloopClass alloc] initWithClassName:@"TestInitOwnershipMock" alloc:YES init:@selector(initWithValue:) args:@[@42]];
		XCTAssertTrue([cls.nativeObject isKindOfClass:[TestInitOwnershipMock class]]);
		weakNative = cls.nativeObject;
		HyperloopPointer *value = [HyperloopUtils invokeSelector:@selector(value) args:nil target:cls instance:YES];
		XCTAssertEqualObjects(value, @42);
	}
	XCTAssertEqual(TestInitOwnershipAllocs, 1);
	XCTAssertEqual(TestInitOwnershipDeallocs, 0);
	XCTAssertNotNil(weakNative);
	@autoreleasepool {
		cls = nil;
	}
	XCTAssertNil(weakNative);
	XCTAssertEqual(TestInitOwnershipDeallocs, 1);
}

- (void)testInitializerReturningReplacement {
	TestInitOwnershipResetCounters();
	HyperloopClass *cls = nil;
	__weak id weakNative = nil;
	@autoreleasepool {
		cls = [[HyperloopClass alloc] initWithClassName:@"TestInitOwnershipMock" alloc:YES init:@selector(initReturningReplacement) args:nil];
		XCTAssertTrue([cls.nativeObject isKindOfClass:[TestInitReplacement class]]);
		weakNative = cls.nativeObject;
	}
	XCTAssertEqual(TestInitOwnershipAllocs, 1);
	XCTAssertEqual(TestInitOwnershipDeallocs, 1);
	XCTAssertEqual(TestInitReplacementAllocs, 1);
	XCTAssertEqual(TestInitReplacementDeallocs, 0);
	XCTAssertNotNil(weakNative);
	@autoreleasepool {
		cls = nil;
	}
	XCTAssertNil(weakNative);
	XCTAssertEqual(TestInitReplacementDeallocs, 1);
}

- (void)testInitializerThrowing {
	TestInitOwnershipResetCounters();
	@autoreleasepool {
		XCTAssertThrowsSpecificNamed([[HyperloopClass alloc] initWithClassName:@"TestInitOwnershipMock" alloc:YES init:@selector(initThrowing) args:nil], NSException, @"TestInitFailure");
	}
	XCTAssertEqual(TestInitOwnershipAllocs, 1);
	// Only guards against over-release: the allocation currently leaks on this path
	// (0 deallocs) because ARC does not release references during exception unwinding.
	XCTAssertLessThanOrEqual(TestInitOwnershipDeallocs, 1);
}

- (void)testOrdinaryMethodReturningNil {
	TestInitOwnershipResetCounters();
	HyperloopClass *cls = nil;
	@autoreleasepool {
		cls = [[HyperloopClass alloc] initWithClassName:@"TestInitOwnershipMock" alloc:YES init:@selector(initWithValue:) args:@[@1]];
		id result = [HyperloopUtils invokeSelector:@selector(nilObject) args:nil target:cls instance:YES];
		XCTAssertNil(result);
	}
	XCTAssertEqual(TestInitOwnershipDeallocs, 0);
	XCTAssertNotNil(cls.nativeObject);
	@autoreleasepool {
		cls = nil;
	}
	XCTAssertEqual(TestInitOwnershipAllocs, 1);
	XCTAssertEqual(TestInitOwnershipDeallocs, 1);
}

- (void)testClassFactoryReturningNil {
	TestInitOwnershipResetCounters();
	@autoreleasepool {
		HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestInitOwnershipMock" alloc:NO init:@selector(nilFactory) args:nil];
		XCTAssertNotNil(cls);
		XCTAssertNil(cls.nativeObject);
	}
	XCTAssertEqual(TestInitOwnershipAllocs, 0);
	XCTAssertEqual(TestInitOwnershipDeallocs, 0);
}

- (void)testRegularExpressionInitializerFailure {
	__weak id weakNative = nil;
	@autoreleasepool {
		// NSNull marshals to a nil NSError ** so no out-parameter storage is involved.
		HyperloopClass *invalid = [[HyperloopClass alloc] initWithClassName:@"NSRegularExpression" alloc:YES init:@selector(initWithPattern:options:error:) args:@[@"(", @0, [NSNull null]]];
		XCTAssertNotNil(invalid);
		XCTAssertNil(invalid.nativeObject);

		HyperloopClass *valid = [[HyperloopClass alloc] initWithClassName:@"NSRegularExpression" alloc:YES init:@selector(initWithPattern:options:error:) args:@[@"a+", @0, [NSNull null]]];
		XCTAssertTrue([valid.nativeObject isKindOfClass:[NSRegularExpression class]]);
		XCTAssertEqualObjects([(NSRegularExpression *)valid.nativeObject pattern], @"a+");
		weakNative = valid.nativeObject;
	}
	XCTAssertNil(weakNative);
}


- (void)testEmptyArrayObjectArgument {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestArrayArgumentMock" alloc:NO init:@selector(class) args:nil];
	NSArray *empty = @[];
	// The outer array is the invocation argument list; the inner empty array is the one argument.
	id result = [HyperloopUtils invokeSelector:@selector(takeArray:) args:@[empty] target:cls instance:NO];
	XCTAssertEqualObjects(result, @(TestArrayArgumentKindEmptyArray));
	id received = [TestArrayArgumentMock receivedValue];
	XCTAssertNotNil(received);
	XCTAssertTrue([received isKindOfClass:[NSArray class]]);
	XCTAssertEqual([received count], 0);
}

- (void)testEmptyArgumentListIsNotAnEmptyArrayArgument {
	// Control: an empty argument list means zero method arguments, not one empty array.
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestArrayArgumentMock" alloc:NO init:@selector(class) args:nil];
	XCTAssertThrowsSpecificNamed([HyperloopUtils invokeSelector:@selector(takeArray:) args:@[] target:cls instance:NO], NSException, @"WrongArgumentCount");
}

- (void)testNonEmptyArrayObjectArgument {
	// Control: unchanged non-empty conversion path.
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestArrayArgumentMock" alloc:NO init:@selector(class) args:nil];
	NSArray *value = @[@1, @"two", @[@3]];
	id result = [HyperloopUtils invokeSelector:@selector(takeArray:) args:@[value] target:cls instance:NO];
	XCTAssertEqualObjects(result, @(TestArrayArgumentKindNonEmptyArray));
	XCTAssertEqualObjects([TestArrayArgumentMock receivedValue], value);
}

- (void)testEmptyArrayObjectArgumentBetweenScalars {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestArrayArgumentMock" alloc:NO init:@selector(class) args:nil];
	id result = [HyperloopUtils invokeSelector:@selector(takeInt:array:int:) args:@[@7, @[], @9] target:cls instance:NO];
	XCTAssertEqualObjects(result, @(TestArrayArgumentKindEmptyArray));
	id received = [TestArrayArgumentMock receivedValue];
	XCTAssertNotNil(received);
	XCTAssertTrue([received isKindOfClass:[NSArray class]]);
	XCTAssertEqual([received count], 0);
	XCTAssertEqual([TestArrayArgumentMock receivedBefore], 7);
	XCTAssertEqual([TestArrayArgumentMock receivedAfter], 9);
}

- (void)testEmptyArrayBlockArgumentStaysNil {
	// Control: a block parameter (@?) is not an array parameter; [] keeps arriving as nil.
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestArrayArgumentMock" alloc:NO init:@selector(class) args:nil];
	id result = [HyperloopUtils invokeSelector:@selector(takeBlock:) args:@[@[]] target:cls instance:NO];
	XCTAssertEqualObjects(result, @(TestArrayArgumentKindNil));
	XCTAssertNil([TestArrayArgumentMock receivedValue]);
}

// Asserts that passing array as the only argument of selector raises InvalidArgumentType
// naming argument 0 and encoding, without entering the native method.
- (void)assertArray:(NSArray *)array rejectedBy:(SEL)selector encoding:(NSString *)encoding {
	[TestArrayArgumentMock reset];
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestArrayArgumentMock" alloc:NO init:@selector(class) args:nil];
	NSException *caught = nil;
	@try {
		[HyperloopUtils invokeSelector:selector args:@[array] target:cls instance:NO];
	} @catch (NSException *e) {
		caught = e;
	}
	NSString *name = NSStringFromSelector(selector);
	XCTAssertNotNil(caught, @"%@ accepted %@", name, array);
	XCTAssertEqualObjects(caught.name, @"InvalidArgumentType", @"%@", name);
	NSString *expected = [NSString stringWithFormat:@"at argument 0 (%@)", encoding];
	XCTAssertTrue([caught.reason hasSuffix:expected], @"%@: reason \"%@\" does not end with \"%@\"", name, caught.reason, expected);
	XCTAssertEqual([TestArrayArgumentMock enteredCount], 0, @"%@ was entered", name);
}

- (void)assertArrayRejectedByNonObjectParameters:(NSArray *)array {
	[self assertArray:array rejectedBy:@selector(takeIntValue:) encoding:@"i"];
	[self assertArray:array rejectedBy:@selector(takeDoubleValue:) encoding:@"d"];
	[self assertArray:array rejectedBy:@selector(takeBoolValue:) encoding:@(@encode(BOOL))];
	[self assertArray:array rejectedBy:@selector(takeClassValue:) encoding:@"#"];
	[self assertArray:array rejectedBy:@selector(takeSelectorValue:) encoding:@":"];
	[self assertArray:array rejectedBy:@selector(takePointer:) encoding:@"^v"];
	// Qualified encodings ("r^@", "r*") are reported without their qualifier.
	[self assertArray:array rejectedBy:@selector(takeObjectPointer:) encoding:@"^@"];
	[self assertArray:array rejectedBy:@selector(takeCString:) encoding:@"*"];
	[self assertArray:array rejectedBy:@selector(takeRect:) encoding:@(@encode(CGRect))];
}

- (void)testEmptyArrayRejectedForNonObjectParameters {
	[self assertArrayRejectedByNonObjectParameters:@[]];
}

- (void)testNonEmptyArrayRejectedForNonObjectParameters {
	[self assertArrayRejectedByNonObjectParameters:@[@1, @"two"]];
}

- (void)testArrayRejectionNamesArgumentIndex {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestArrayArgumentMock" alloc:NO init:@selector(class) args:nil];
	NSException *caught = nil;
	@try {
		[HyperloopUtils invokeSelector:@selector(takeInt:pointer:) args:@[@7, @[]] target:cls instance:NO];
	} @catch (NSException *e) {
		caught = e;
	}
	XCTAssertEqualObjects(caught.name, @"InvalidArgumentType");
	XCTAssertTrue([caught.reason hasSuffix:@"at argument 1 (^v)"], @"%@", caught.reason);
	XCTAssertEqual([TestArrayArgumentMock enteredCount], 0);
	XCTAssertEqual([TestArrayArgumentMock receivedBefore], 0);
}

- (void)testBlockFixtureHasBlockEncoding {
	for (NSString *name in @[@"takeBlockValue:", @"takeBlock:"]) {
		NSMethodSignature *sig = [TestArrayArgumentMock methodSignatureForSelector:NSSelectorFromString(name)];
		XCTAssertEqualObjects(@([sig getArgumentTypeAtIndex:2]), @"@?", @"%@", name);
	}
}

- (void)testNonEmptyArrayRejectedForBlockParameter {
	[self assertArray:@[@1, @"two"] rejectedBy:@selector(takeBlockValue:) encoding:@"@?"];
}

- (void)testBlockRejectionNamesArgumentIndex {
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestArrayArgumentMock" alloc:NO init:@selector(class) args:nil];
	NSException *caught = nil;
	@try {
		[HyperloopUtils invokeSelector:@selector(takeInt:block:) args:@[@7, @[@1]] target:cls instance:NO];
	} @catch (NSException *e) {
		caught = e;
	}
	XCTAssertEqualObjects(caught.name, @"InvalidArgumentType");
	XCTAssertTrue([caught.reason hasSuffix:@"at argument 1 (@?)"], @"%@", caught.reason);
	XCTAssertEqual([TestArrayArgumentMock enteredCount], 0);
	XCTAssertEqual([TestArrayArgumentMock receivedBefore], 0);
}

- (void)testEmptyArrayBlockValueStaysNil {
	// Unchanged compatibility control: an empty array to a block parameter still arrives as nil.
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestArrayArgumentMock" alloc:NO init:@selector(class) args:nil];
	id result = [HyperloopUtils invokeSelector:@selector(takeBlockValue:) args:@[@[]] target:cls instance:NO];
	XCTAssertEqualObjects(result, @(TestArrayArgumentKindNil));
	XCTAssertEqual([TestArrayArgumentMock enteredCount], 1);
}

- (void)testNullPointerArgumentStillAccepted {
	// Control: NSNull to a pointer parameter is not an array and still arrives as NULL.
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestArrayArgumentMock" alloc:NO init:@selector(class) args:nil];
	id result = [HyperloopUtils invokeSelector:@selector(takePointer:) args:@[[NSNull null]] target:cls instance:NO];
	XCTAssertEqualObjects(result, @(TestArrayArgumentKindNil));
	XCTAssertEqual([TestArrayArgumentMock enteredCount], 1);
}

- (void)testEmptyArrayDoublyQualifiedObjectArgument {
	// "nO@" is an object parameter; skipping only one qualifier would misclassify it.
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestArrayArgumentMock" alloc:NO init:@selector(class) args:nil];
	id result = [HyperloopUtils invokeSelector:@selector(takeQualifiedArray:) args:@[@[]] target:cls instance:NO];
	XCTAssertEqualObjects(result, @(TestArrayArgumentKindEmptyArray));
	id received = [TestArrayArgumentMock receivedValue];
	XCTAssertTrue([received isKindOfClass:[NSArray class]]);
	XCTAssertEqual([received count], 0);
}

- (void)testNonEmptyArrayDoublyQualifiedObjectArgument {
	// Control: the non-empty path to a qualified object parameter keeps its contents and order.
	HyperloopClass *cls = [[HyperloopClass alloc] initWithClassName:@"TestArrayArgumentMock" alloc:NO init:@selector(class) args:nil];
	NSArray *value = @[@1, @"two", @[@3]];
	id result = [HyperloopUtils invokeSelector:@selector(takeQualifiedArray:) args:@[value] target:cls instance:NO];
	XCTAssertEqualObjects(result, @(TestArrayArgumentKindNonEmptyArray));
	XCTAssertEqualObjects([TestArrayArgumentMock receivedValue], value);
}

@end

#pragma clang diagnostic pop
